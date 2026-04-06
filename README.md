# Case Técnico SRE DevOps — Lagunitas / HEINEKEN

**Candidato:** Laerte Gomes Filho  
**Prazo:** 02/04/2026 a 07/04/2026

---

## Repositório GitHub

**Link:** `https://github.com/laertegf/case-sre-lagunitas`

> O pipeline GitHub Actions roda automaticamente a cada push na `main` ou via `workflow_dispatch` (execução manual).

---

## Estrutura do repositório

```
case-sre-laerte-gomes/
├── azure-pipelines.yml              # YAML refatorado para Azure DevOps 
├── documento-de-decisao.pdf          # Diagnóstico, observabilidade e rollback
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
| 1 | Diagnóstico: causas raiz, análise do YAML original, priorização | `documento-de-decisao.pdf` §1 |
| 2 | YAML refatorado com gate, smoke tests, multi-ambiente | `azure-pipelines.yml` |
| 3 | Proposta de observabilidade (Log Analytics + KQL) | `documento-de-decisao.pdf` §2 |
| 4 | Estratégia de rollback (Databricks + ADF) com RTO | `documento-de-decisao.pdf` §3 |
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


## Evidências de execução do pipeline

O pipeline foi executado com sucesso no GitHub Actions utilizando mocks dos recursos Azure. Abaixo estão as evidências de cada etapa do fluxo.

### Pipeline completo — 5 jobs com sucesso
Build & Validate → Deploy DEV → Deploy ACC → Deploy PRD (com aprovação) → Smoke Tests & Deploy Log. Tempo total: 40 segundos.

<img width="2173" height="351" alt="image" src="https://github.com/user-attachments/assets/9681483a-578d-4327-961d-96a5824b410e" />

### Gate de aprovação — Deploy PRD aguardando review
O Environment "prd" foi configurado com Required Reviewers. O pipeline pausou automaticamente antes do deploy em produção, aguardando aprovação.

<img width="2169" height="671" alt="image" src="https://github.com/user-attachments/assets/65215899-e8a5-43eb-95cd-913d28b931d8" />

### Confirmação de deploy
Tela de aprovação exigindo confirmação explícita antes de prosseguir com o deploy em PRD.

<img width="2179" height="671" alt="image" src="https://github.com/user-attachments/assets/4356847c-fb17-4758-a323-41afcb0a80cf" />
<img width="2195" height="686" alt="image" src="https://github.com/user-attachments/assets/7b421b28-89dd-4ac4-b05f-9d9a6c295ec4" />

### Smoke Test — Databricks (PRD)
3 validações executadas: workspace host correto, notebooks no path esperado, jobs ativos. Resultado: 3 passed, 0 failed.

<img width="637" height="740" alt="image" src="https://github.com/user-attachments/assets/15e4f56e-e749-4d27-b1ad-a888ac54df84" />

### Smoke Test — ADF (PRD)
4 validações executadas: factory acessível, pipelines Enabled, triggers Started, factory name corresponde a PRD. Resultado: 4 passed, 0 failed.

<img width="623" height="923" alt="image" src="https://github.com/user-attachments/assets/91adccda-eee7-45fd-9b9a-5bd81f0c1316" />

### Log estruturado de deploy
JSON emitido ao final do pipeline com timestamp, commit SHA, ambiente, resultado de cada smoke test e status geral. Em produção, seria enviado ao Azure Log Analytics via HTTP Data Collector API.

<img width="574" height="879" alt="image" src="https://github.com/user-attachments/assets/f61b3b6c-b43b-4184-afb7-78bc76a4135a" />


---

## Decisões técnicas (resumo)

O documento completo está em `documento-de-decisao.pdf`. Destaques:

1. **Gate de aprovação** é a melhoria #1 — previne o incidente ao invés de apenas detectar
2. **Variable Groups por ambiente** vinculados a Key Vault separados eliminam risco de cross-env deploy
3. **Smoke tests não executam dados** — validam estado (workspace correto, notebooks existem, triggers ativas)
4. **Log estruturado em JSON** para Log Analytics permite RCA em minutos via KQL ao invés de 40 min
5. **Rollback via Git SHA** para notebooks (RTO: 3 min) e **snapshot ARM** para ADF (RTO: 5 min)
6. **RTO total proposto: 15 minutos** (vs 42 min do incidente)
