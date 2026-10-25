# ============================================================================
# Fratuci Labs — GCP Data Foundation & FinOps ($100/month Guardrail)
# Author: Anderson (@fratuci) — Data & Cloud Architect
# Modules: GoogleCloudPlatform/cloud-foundation-fabric
# ============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.20"
    }
  }
}

variable "project_id" {
  description = "ID do projeto GCP da Fratuci Labs"
  type        = string
  default     = "fratuci-labs-prod"
}

variable "billing_account_id" {
  description = "ID da conta de faturamento GCP monitorada pelo FinOps"
  type        = string
}

variable "region" {
  description = "Região primária (baixo custo de rede e suporte a ARM t2a)"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zona com disponibilidade de processadores Ampere Altra ARM64 (Tau T2A)"
  type        = string
  default     = "us-central1-a"
}

# ----------------------------------------------------------------------------
# 1. Projeto e APIs Essenciais (Cloud Foundation Fabric)
# ----------------------------------------------------------------------------
module "project" {
  source          = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=v31.0.0"
  name            = var.project_id
  billing_account = var.billing_account_id

  services = [
    "run.googleapis.com",
    "compute.googleapis.com",
    "bigquery.googleapis.com",
    "billingbudgets.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "aiplatform.googleapis.com",
    "secretmanager.googleapis.com"
  ]

  labels = {
    environment = "production"
    governance  = "family-board"
    finops_cap  = "usd-100"
  }
}

# ----------------------------------------------------------------------------
# 2. Segurança Zero-Trust: Workload Identity Federation (Sem Chaves JSON)
# Restrito exclusivamente à organização GitHub: fratuci-labs
# ----------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github_pool" {
  project                   = module.project.project_id
  workload_identity_pool_id = "fratuci-labs-github-pool"
  display_name              = "Fratuci Labs GitHub Actions Pool"
  description               = "Autenticação OIDC sem chaves estáticas para repositórios da fratuci-labs"
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  project                            = module.project.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC Provider (fratuci-labs only)"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  # Trava Inviolável de Perímetro: apenas repositórios da organização fratuci-labs
  attribute_condition = "assertion.repository_owner == 'fratuci-labs'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ----------------------------------------------------------------------------
# 3. Cloud Run Serverless: Ponte Automática Gemini-to-GitHub (Escala a Zero)
# ----------------------------------------------------------------------------
module "gemini_webhook_service" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloud-run-v2?ref=v31.0.0"
  project_id = module.project.project_id
  name       = "gemini-webhook-ingest"
  region     = var.region

  containers = {
    ingest = {
      image = "us-central1-docker.pkg.dev/${module.project.project_id}/containers/gemini-webhook-ingest:v1.0.0"
      resources = {
        limits = {
          cpu    = "1000m"
          memory = "256Mi"
        }
        cpu_idle = true # Throttling de CPU fora de requisições (FinOps)
      }
      env = {
        GITHUB_ALLOWED_ORG = "fratuci-labs"
        CLICKHOUSE_ENABLED = "true"
      }
    }
  }

  revision = {
    max_instance_count = 2
    min_instance_count = 0 # Scale-to-zero obrigatório para preservar a cota de US$ 100
  }
}

# ----------------------------------------------------------------------------
# 4. Motor Analítico: ClickHouse 26.x em ARM64 (Ampere Altra t2a-standard-2)
# Sob demanda / Spot com vetorização SIMD ARM64 dentro do teto de US$ 45/mês
# ----------------------------------------------------------------------------
module "clickhouse_arm64_node" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/compute-vm?ref=v31.0.0"
  project_id    = module.project.project_id
  zone          = var.zone
  name          = "ch-analytics-arm64-01"
  instance_type = "t2a-standard-2" # 2 vCPUs Ampere Altra ARM64, 8 GB RAM

  boot_disk = {
    initialize_params = {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-arm64"
      type  = "pd-balanced"
      size  = 50
    }
  }

  options = {
    spot               = true
    termination_action = "STOP"
  }

  labels = {
    engine     = "clickhouse-26x-arm64"
    role       = "healthtech-audit-telemetry"
    finops_cap = "usd-45-allocation"
  }
}

# ----------------------------------------------------------------------------
# 5. BigQuery Dataset: Exportação FinOps & Auditoria Fria de Longo Prazo
# ----------------------------------------------------------------------------
module "finops_audit_dataset" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/bigquery-dataset?ref=v31.0.0"
  project_id = module.project.project_id
  id         = "fratuci_finops_and_legal_audit"
  location   = "US"

  options = {
    default_table_expiration_ms     = null
    default_partition_expiration_ms = null
    delete_contents_on_destroy      = false
  }
}

# ----------------------------------------------------------------------------
# 6. Governança FinOps: Alerta e Trava de Orçamento Mensal de US$ 100.00
# ----------------------------------------------------------------------------
resource "google_billing_budget" "monthly_100_usd_cap" {
  billing_account = var.billing_account_id
  display_name    = "Fratuci Labs — Cota Mensal Rigorosa US$ 100"

  budget_filter {
    projects               = ["projects/${module.project.number}"]
    calendar_period        = "MONTH"
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = "100"
    }
  }

  threshold_rules {
    threshold_percent = 0.50
    spend_basis       = "CURRENT_SPEND"
  }
  threshold_rules {
    threshold_percent = 0.80
    spend_basis       = "CURRENT_SPEND"
  }
  threshold_rules {
    threshold_percent = 0.95
    spend_basis       = "CURRENT_SPEND"
  }
  threshold_rules {
    threshold_percent = 1.00
    spend_basis       = "FORECASTED_SPEND"
  }
}
