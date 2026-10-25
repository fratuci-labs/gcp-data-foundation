# 💰 Política Corporativa de FinOps — Gestão Inteligente da Cota de US$ 100/mês

**Documento:** `FINOPS-POL-001`  
**Responsável Técnico:** 👤 **Anderson (`@fratuci`) — Arquiteto de Dados & Cloud**  
**Aprovação Societária:** Anderson, Antônio, André e Adriana  
**Orçamento Teto Mensal:** **US$ 100,00 (Cem Dólares Americanos)**

---

## 1. Filosofia FinOps da Fratuci Labs

Na **Fratuci Labs**, a restrição orçamentária de **US$ 100/mês** não é uma limitação, mas uma **vantagem competitiva de engenharia**. Projetos nascidos enxutos têm margem bruta superior a 85% quando escalam para clientes B2B.

> [!IMPORTANT]
> **Regra de Ouro:** Nenhum serviço na nuvem pode ter custo fixo contínuo (*always-on*) sem justificativa aprovada em ADR e sem automação de hibernação fora do horário comercial.

---

## 2. Alocação Mensal do Orçamento por Pilar

| Centro de Custo / Diretoria | Líder | Teto Mensal (USD) | % da Cota | Serviços Contemplados |
| :--- | :--- | :---: | :---: | :--- |
| **Motor Analítico & Storage** | Anderson | **US$ 45,00** | 45% | VM Spot/Agendada ClickHouse ARM (`t2a-standard-2`), discos equilibrados e snapshots no Cloud Storage. |
| **Inferência de IA & Agentes** | Antônio | **US$ 35,00** | 35% | Chamadas de API Vertex AI (`Gemini 2.5 Flash` como padrão; `Gemini 2.5 Pro` restrito a raciocínio complexo). |
| **Automação Gemini-to-GitHub & CI/CD** | Antônio / Adriana / André | **US$ 10,00** | 10% | Cloud Run (`min_instances = 0`), Secret Manager e Artifact Registry. |
| **Reserva Técnica & BigQuery Audit** | Anderson / André | **US$ 10,00** | 10% | BigQuery Billing Export, logs de auditoria jurídica/sanitária e margem de segurança cambial. |
| **TOTAL CORPORATIVO** | **Diretoria** | **US$ 100,00** | **100%** | Monitorado via `google_billing_budget.monthly_100_usd_cap`. |

---

## 3. Régua de Alertas e Ações Automáticas de Contenção

O módulo Terraform em [`infra/main.tf`](../infra/main.tf) configura quatro gatilhos no Cloud Billing:

1. **🟢 50% (US$ 50,00) — Alerta Informativo:**
   - Notificação automática no painel da família com o ranking de consumo por agente (`fratuci_audit.finops_daily_spend_rollup`).
2. **🟡 80% (US$ 80,00) — Modo de Economia Ativa:**
   - Redução automática da janela ligada da instância de homologação do ClickHouse.
   - Bloqueio temporário de modelos pesados (`Pro`), mantendo 100% da operação em `Gemini Flash`.
3. **🟠 95% (US$ 95,00) — Congelamento de Cargas Não-Críticas:**
   - Jobs de backfill em lote e testes de estresse são suspensos até a virada do ciclo mensal.
4. **🔴 100% (US$ 100,00 Previsto ou Realizado) — Hard Stop de Homologação:**
   - Desligamento imediato de VMs de desenvolvimento; apenas o webhook `Scale-to-Zero` e os repositórios GitHub seguem operando a custo zero.

---

## 4. Diretrizes Práticas para os 4 Sócios

- **Para Adriana (Estratégia & Farmácia) e André (Jurídico):**
  - Todo o trabalho exploratório e redação inicial ocorre no **Gemini App / Spark**, que não consome tokens da cota de API do projeto GCP. Apenas a consolidação final enviada via webhook para o GitHub aciona o Cloud Run (custo próximo de zero).
- **Para Antônio (Engenharia de IA):**
  - Uso obrigatório de **Context Caching** para os System Prompts e para a tabela `interacoes-medicamentosas-criticas.json`.
  - Registro obrigatório de `estimated_cost_micros_usd` em cada evento gravado no ClickHouse.
- **Para Anderson (Dados & Cloud):**
  - Proibição de `SELECT *` sem filtro de partição (`event_date`) no BigQuery e no ClickHouse.
  - Uso de índices invertidos nativos `TYPE text` no ClickHouse 26.x para ativar *Direct Read* e reduzir leituras de disco em mais de 90%.
