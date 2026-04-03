# Case Técnico SRE DevOps — Lagunitas / HEINEKEN

**Candidato:** Laerte Gomes Filho  
**Prazo:** 02/04/2026 a 07/04/2026

---

## Repositório GitHub

**Link:** `https://github.com/laertegomes/case-sre-lagunitas`

> O pipeline GitHub Actions roda automaticamente a cada push na `main` ou via `workflow_dispatch` (execução manual).

---

## Estrutura do repositório

```
case-sre-laerte-gomes/
├── azure-pipelines.yml              # YAML refatorado para Azure DevOps (obrigatório)
├── documento-de-decisao.md          # Diagnóstico, observabilidade e rollback
├── notebooks/
│   ├── silver_vendas.py             # Notebook de transformação Silver (vendas)
│   └── silver_distribuicao.py       # Notebook de transformação Silver (distribuição)
├── adf/
│   ├── ARMTemplateForFactory.json           # ARM Template mock do ADF
│   └── ARMTemplateParametersForFactory.json # Parâmetros do ARM Template
├── scripts/
│   ├── smoke-test-databricks.sh     # Smoke tests para Databricks
│   ├── smoke-test-adf.sh           # Smoke tests para ADF
│   └── emit-deploy-log.sh          # Emissão de log estruturado
├── .github/
│   └── workflows/
│       └── lagunitas-ci.yml        # GitHub Actions equivalente com mocks
└── README.md                        # Este arquivo
```

---

## O que cada entregável contém

| # | Entregável | Arquivo |
|---|-----------|---------|
| 1 | Diagnóstico: causas raiz, análise do YAML original, priorização | `documento-de-decisao.md` §1 |
| 2 | YAML refatorado com gate, smoke tests, multi-ambiente | `azure-pipelines.yml` |
| 3 | Proposta de observabilidade (Log Analytics + KQL) | `documento-de-decisao.md` §2 |
| 4 | Estratégia de rollback (Databricks + ADF) com RTO | `documento-de-decisao.md` §3 |
| 5 | GitHub Actions com mocks rodando | `.github/workflows/lagunitas-ci.yml` |

---

## Como rodar o pipeline

### Execução automática
Qualquer push na branch `main` dispara o workflow automaticamente.

### Execução manual
1. Ir em **Actions** → **Lagunitas CI/CD Pipeline**
2. Clicar em **Run workflow** → **Run workflow**

### Configurar aprovação para PRD (opcional)
1. **Settings** → **Environments** → **New environment**: `prd`
2. Marcar **Required reviewers** → adicionar seu usuário
3. O job `deploy-prd` vai pausar e aguardar aprovação

---

## Fluxo do pipeline

```
Build & Validate
    ↓
Deploy DEV (automático)
    ↓
Deploy ACC (automático + smoke tests)
    ↓
Deploy PRD (requer aprovação) ← gate manual
    ↓
Smoke Tests PRD + Deploy Log
```

### O que cada stage faz

- **Build**: lint Python (`py_compile` + `ruff`), validação de ARM templates JSON
- **Deploy DEV**: import notebooks + deploy ARM template no ambiente DEV
- **Deploy ACC**: mesmo fluxo de DEV + smoke tests de validação
- **Deploy PRD**: snapshot pré-deploy → validação de host → deploy → reativação de triggers
- **Smoke Tests PRD**: valida workspace, notebooks, pipelines, triggers + emite log estruturado

---

## Decisões técnicas (resumo)

O documento completo está em `documento-de-decisao.md`. Destaques:

1. **Gate de aprovação** é a melhoria #1 — previne o incidente ao invés de apenas detectar
2. **Variable Groups por ambiente** vinculados a Key Vault separados eliminam risco de cross-env deploy
3. **Smoke tests não executam dados** — validam estado (workspace correto, notebooks existem, triggers ativas)
4. **Log estruturado em JSON** para Log Analytics permite RCA em minutos via KQL ao invés de 40 min
5. **Rollback via Git SHA** para notebooks (RTO: 3 min) e **snapshot ARM** para ADF (RTO: 5 min)
6. **RTO total proposto: 15 minutos** (vs 42 min do incidente)
