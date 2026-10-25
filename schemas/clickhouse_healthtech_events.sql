-- ============================================================================
-- Fratuci Labs — ClickHouse 26.x HealthTech & AI Governance Telemetry Schema
-- Author: Anderson (@fratuci) — Data & Cloud Architect
-- Co-Reviewers: Antônio (AI), Adriana (Pharma/Anvisa), André (Legal/LGPD)
-- Target Engine: ClickHouse 26.x on ARM64 (Ampere Altra t2a-standard-2)
-- ============================================================================
-- DIRETRIZES ARQUITETURAIS APLICADAS (ClickHouse 26.x Best Practices):
-- 1. Vetorização SIMD ARM64 sobre colunas LowCardinality(String) sem índices
--    desnecessários em colunas de baixa cardinalidade (< 50 valores).
-- 2. Índices invertidos nativos TYPE text(tokenizer = 'array' / 'splitByNonAlpha')
--    para ativar Direct Read (query_plan_direct_read_from_text_index = 1).
-- 3. Rastreabilidade Criptográfica (SHA-256) exigida pelo POP-001 (Anvisa/Adriana)
--    e pela Matriz de Risco LGPD Art. 20 (André).
-- 4. Materialized Views SEMPRE com cláusula explícita `TO target_table`.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS fratuci_audit;

-- ----------------------------------------------------------------------------
-- 1. Tabela Fato Principal: Telemetria de Agentes e Auditoria Farmacológica
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fratuci_audit.healthtech_agent_events
(
    -- Identificadores e Particionamento Temporal
    event_date                  Date DEFAULT toDate(event_timestamp),
    event_timestamp             DateTime64(3, 'America/Sao_Paulo'),
    trace_id                    UUID,
    session_id                  String,

    -- Governança de IA & Rastreabilidade Criptográfica (Antônio + André)
    agent_name                  LowCardinality(String),   -- Ex: 'pharma-triage-agent', 'legal-contract-auditor'
    model_version               LowCardinality(String),   -- Ex: 'gemini-2.5-flash', 'gemini-2.5-pro'
    prompt_version              LowCardinality(String),   -- Ex: '1.1.0'
    prompt_sha256               FixedString(64),          -- Hash SHA-256 imutável do arquivo Markdown no GitHub
    legal_disclaimer_injected   UInt8,                    -- 1 = Aviso de responsabilidade civil do André exibido
    lgpd_art20_review_flag      UInt8,                    -- 1 = Decisão sinalizada para revisão humana (Art. 20 LGPD)

    -- Curadoria Clínica & Conformidade Anvisa (Adriana - POP-001)
    pharma_dataset_version      LowCardinality(String),   -- Versão do JSON interacoes-medicamentosas-criticas.json
    pharma_dataset_sha256       FixedString(64),          -- Hash SHA-256 da base clínica usada no RAG
    queried_dcb_substances      Array(String),            -- Lista de princípios ativos (DCB/DCI) consultados
    interaction_severity        LowCardinality(String),   -- 'NENHUMA', 'LEVE', 'MODERADA', 'ALTA', 'CONTRAINDICADA'
    requires_pharmacist_signoff UInt8,                    -- 1 = Exige confirmação humana de Farmacêutico/Médico
    clinical_guidance_summary   String,                   -- Resumo da conduta recomendada baseada na fonte regulatória

    -- Métricas de Performance & FinOps (Anderson - Quota US$ 100/mês)
    latency_ms                  UInt32,
    input_tokens                UInt32,
    output_tokens               UInt32,
    estimated_cost_micros_usd   UInt64,                   -- Custo em milionésimos de USD (1 USD = 1_000_000 micros)

    -- Assinatura de Integridade do Registro (Cadeia de Custódia)
    record_hmac_sha256          FixedString(64),

    -- ========================================================================
    -- ÍNDICES DE SALTO E ÍNDICES INVERTIDOS NATIVOS (ClickHouse 26.x)
    -- Nota: NÃO indexamos LowCardinality (agent_name, interaction_severity)
    -- pois o scan SIMD ARM64 varre dicionários de 1 byte a >15 GB/s por core.
    -- ========================================================================
    INDEX idx_trace_id trace_id TYPE bloom_filter(0.001) GRANULARITY 1,
    INDEX idx_prompt_sha256 prompt_sha256 TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_pharmacist_signoff requires_pharmacist_signoff TYPE set(2) GRANULARITY 1,
    INDEX idx_dcb_substances queried_dcb_substances TYPE text(tokenizer = 'array') GRANULARITY 1,
    INDEX idx_clinical_guidance clinical_guidance_summary TYPE text(tokenizer = 'splitByNonAlpha') GRANULARITY 1
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, agent_name, interaction_severity, event_timestamp, trace_id)
TTL event_date + INTERVAL 5 YEAR
SETTINGS index_granularity = 8192;

-- ----------------------------------------------------------------------------
-- 2. Tabela Agregada de FinOps & Governança Diária (Alvo Explícito da MV)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fratuci_audit.finops_daily_spend_rollup
(
    event_date                  Date,
    agent_name                  LowCardinality(String),
    model_version               LowCardinality(String),
    total_requests              SimpleAggregateFunction(sum, UInt64),
    high_severity_alerts        SimpleAggregateFunction(sum, UInt64),
    total_input_tokens          SimpleAggregateFunction(sum, UInt64),
    total_output_tokens         SimpleAggregateFunction(sum, UInt64),
    total_cost_micros_usd       SimpleAggregateFunction(sum, UInt64)
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, agent_name, model_version);

-- Regra Crítica ClickHouse: SEMPRE usar cláusula explícita `TO target_table`
CREATE MATERIALIZED VIEW IF NOT EXISTS fratuci_audit.mv_finops_daily_spend
TO fratuci_audit.finops_daily_spend_rollup
AS
SELECT
    event_date,
    agent_name,
    model_version,
    count() AS total_requests,
    countIf(interaction_severity IN ('ALTA', 'CONTRAINDICADA')) AS high_severity_alerts,
    sum(toUInt64(input_tokens)) AS total_input_tokens,
    sum(toUInt64(output_tokens)) AS total_output_tokens,
    sum(estimated_cost_micros_usd) AS total_cost_micros_usd
FROM fratuci_audit.healthtech_agent_events
GROUP BY
    event_date,
    agent_name,
    model_version;

-- ----------------------------------------------------------------------------
-- 3. Consultas de Auditoria Otimizadas para ClickHouse 26.x (Referência)
-- ----------------------------------------------------------------------------
-- Exemplo A: Busca determinística via Direct Read no índice invertido `array`
-- SET query_plan_direct_read_from_text_index = 1;
-- SELECT event_timestamp, trace_id, interaction_severity, prompt_sha256
-- FROM fratuci_audit.healthtech_agent_events
-- WHERE event_date >= today() - 30
--   AND has(queried_dcb_substances, 'varfarina sódica')
--   AND requires_pharmacist_signoff = 1
-- ORDER BY event_timestamp DESC
-- LIMIT 50;
