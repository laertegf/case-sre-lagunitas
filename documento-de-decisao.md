# Case Técnico SRE DevOps — Lagunitas / HEINEKEN

**Autor:** Laerte Gomes Filho  
**Data:** 02/04/2026  

---

## 1. Diagnóstico — O que falhou e por quê

### 1.1 Causas raiz do incidente

**Causas técnicas:**

1. **Variável `DATABRICKS_HOST` apontando para workspace errado (DEV em vez de PRD).** O token/service connection tinha permissão em ambos os ambientes, e não havia validação pós-deploy do destino. O comando `databricks workspace import_dir` aceita qualquer host válido — ele não valida se o destino é coerente com o ambiente esperado.

2. **Deploy ADF via ARM Template em modo Incremental sem validação de estado pós-deploy.** O ARM deployment completou com sucesso (recurso criado/atualizado), mas os pipelines dependentes ficaram inativos e as triggers não foram reativadas. O Azure DevOps reportou sucesso porque o ARM deployment em si não falhou — mas "deploy sem erro" não significa "deploy funcional".

3. **Ausência de smoke tests pós-deploy.** Nenhum step verificava se os notebooks estavam no path correto do workspace PRD, se os jobs Databricks estavam ativos, se os pipelines ADF estavam Enabled ou se as triggers estavam Running.

4. **Token/Service Principal com escopo excessivo.** Um único token com acesso a DEV e PRD é uma violação do princípio de least privilege. A separação deveria ser por Variable Group vinculado a Key Vault, com secrets distintos por ambiente.

**Causas de processo:**

1. **Ausência de gate de aprovação antes de PRD.** Qualquer merge na main dispara deploy direto em produção sem revisão humana. Em uma plataforma de dados crítica (vendas, supply chain, liderança), isso é inaceitável.

2. **ACC não utilizado como gate formal.** O ambiente de aceitação existe mas não é parte da esteira. Deploy deveria passar por DEV → ACC (com validação) → PRD (com aprovação).

3. **Sem runbook de rollback.** Quando o incidente foi detectado, a remediação foi totalmente manual (42 minutos). Não havia procedimento documentado nem automação de rollback.

4. **Descoberta reativa via stakeholder.** Quem detectou o problema foi o analista de negócios 4h depois — não o pipeline, não o monitoramento, não o time de dados. Isso indica ausência de observabilidade proativa.

### 1.2 Por que o pipeline reportou sucesso?

O pipeline verificava apenas duas coisas:

1. **Build Stage:** `py_compile` nos notebooks — verifica sintaxe Python, nada mais.
2. **Deploy Stage:** Saída dos comandos `databricks workspace import_dir` e `AzureResourceManagerTemplateDeployment@3` — ambos retornam exit code 0 se a operação técnica completou, independente de o destino estar correto ou o resultado ser funcional.

O que o pipeline **deveria** ter verificado:

- O workspace de destino do Databricks corresponde ao ambiente PRD (comparar `DATABRICKS_HOST` com valor esperado hard-coded ou derivado do environment).
- Os notebooks existem no path `/Shared/lagunitas` do workspace PRD após o import.
- Os jobs Databricks associados estão em estado ativo e apontando para os notebooks corretos.
- Os pipelines ADF no factory de PRD estão com status `Enabled`.
- As triggers ADF dependentes estão com status `Started` (Running).

### 1.3 O lint (py_compile) é suficiente?

**O que `py_compile` pega:** erros de sintaxe Python — parênteses não fechados, indentação incorreta, keywords inválidas.

**O que `py_compile` NÃO pega:**

- Erros de lógica (joins errados, filtros invertidos, colunas trocadas)
- Imports que não existem no cluster Databricks (bibliotecas não instaladas)
- Referências a tabelas/schemas/catalogs que não existem no ambiente de destino
- Erros de runtime do PySpark (schema mismatch, null handling, type casting)
- Problemas de performance (full scans, cross joins acidentais)
- Variáveis de ambiente ausentes ou incorretas

Para uma validação adequada, além do `py_compile`, seria necessário: linting com `ruff` ou `flake8`, type checking com `mypy`, e idealmente testes unitários com `pytest` + `chispa` (framework de teste para PySpark DataFrames) executados contra dados mock.

### 1.4 Se pudesse implementar apenas uma melhoria agora

**Gate de aprovação manual antes de PRD com environment protegido.**

Justificativa: das quatro falhas (sem gate, sem smoke test, sem observabilidade, sem rollback), o gate de aprovação é a única que impede o incidente de acontecer em primeiro lugar. As demais melhoram a detecção e a recuperação, mas o gate previne. Se um aprovador tivesse revisado o deploy antes de PRD, teria percebido (ou pelo menos teria a oportunidade de perceber) que a variável de host estava apontando para DEV.

Além disso, é a melhoria com menor esforço de implementação e maior impacto: basta criar um Environment `lagunitas-prd` no Azure DevOps com `required approvers` e referenciar no stage de deploy PRD. Zero código, impacto imediato.

---

## 2. Proposta de Observabilidade do Deploy

### 2.1 Destino dos logs: Azure Monitor / Log Analytics

**Escolha:** Log Analytics Workspace via Azure Monitor.

**Justificativa:**

- É o destino nativo para logs estruturados no ecossistema Azure que a Lagunitas já utiliza.
- Permite queries via KQL para troubleshooting rápido — o RCA que levou 40 min levaria 5 min com uma query tipo `DeployLogs_CL | where TimeGenerated > ago(6h) | where Environment_s == "PRD"`.
- Integra com Azure Monitor Alerts para criar regras proativas (ex: "deploy aconteceu mas pipelines ADF não executaram em 2h").
- Workbooks permitem dashboards de deploy history para o time e para a liderança.
- O custo é proporcional ao volume ingerido (pay-per-GB), que para logs de deploy é negligível.

### 2.2 Estrutura do log estruturado

Ao final de cada deploy, o pipeline emite um JSON para Log Analytics:

```json
{
  "timestamp": "2026-04-02T14:42:00Z",
  "pipeline_run_id": "20260402.7",
  "commit_sha": "a1b2c3d",
  "commit_message": "fix: silver notebooks join logic",
  "branch": "main",
  "merged_by": "joao.silva@lagunitas.com",
  "approved_by": "maria.santos@lagunitas.com",
  "environment": "PRD",
  "deploy_components": {
    "databricks_notebooks": {
      "workspace_host": "https://adb-prd.azuredatabricks.net",
      "target_path": "/Shared/lagunitas",
      "notebooks_deployed": ["silver_vendas.py", "silver_distribuicao.py"],
      "status": "success"
    },
    "adf_pipelines": {
      "factory_name": "adf-lagunitas-prd",
      "pipelines_deployed": ["pl_silver_vendas", "pl_silver_distribuicao"],
      "status": "success"
    }
  },
  "smoke_tests": {
    "databricks_workspace_validation": "PASS",
    "databricks_notebooks_exist": "PASS",
    "databricks_jobs_active": "PASS",
    "adf_pipelines_enabled": "PASS",
    "adf_triggers_active": "PASS"
  },
  "overall_status": "SUCCESS",
  "duration_seconds": 187
}
```

### 2.3 Respondendo à pergunta-chave

> "O deploy das 14h42 de terça deployou o quê, onde, e tudo estava ok depois?"

Com os logs estruturados, a resposta vem de uma query KQL:

```kql
DeployLogs_CL
| where TimeGenerated between (datetime(2026-04-01 14:00) .. datetime(2026-04-01 15:00))
| project TimeGenerated, commit_sha_s, environment_s, merged_by_s, 
          smoke_tests_overall_s, deploy_components_s
```

Resposta esperada: "Deploy do commit `a1b2c3d` por `joao.silva`, aprovado por `maria.santos`, no ambiente PRD, notebooks `silver_vendas.py` e `silver_distribuicao.py` publicados em `/Shared/lagunitas` no workspace `adb-prd`, pipelines ADF `pl_silver_vendas` e `pl_silver_distribuicao` no factory `adf-lagunitas-prd`. Todos os smoke tests passaram."

---

## 3. Estratégia de Rollback

### 3.1 Databricks Notebooks

**O que é possível automatizar:**

- Re-deploy da versão anterior via git SHA. O repositório Git é a fonte de verdade. Para rollback, basta executar `databricks workspace import_dir` apontando para o commit anterior: `git checkout <previous-sha> -- ./notebooks && databricks workspace import_dir ./notebooks /Shared/lagunitas`.
- O pipeline de rollback recebe o SHA como parâmetro e executa o mesmo fluxo de deploy + smoke tests.

**Limitações sem Asset Bundles:**

- `import_dir` sobrescreve tudo — não há versionamento no workspace. Não existe "voltar para versão anterior" nativamente; é sempre "importar de novo a partir do Git".
- Não há deployment history no Databricks sem DABs. O histórico fica no Git e nos logs de deploy (Log Analytics).
- Jobs Databricks que referenciam notebooks por path não são atualizados automaticamente — se o rollback muda o nome de um notebook, o job quebra.

### 3.2 ADF ARM Templates

**O que o Azure guarda por padrão:**

- O Azure Resource Manager mantém histórico de deployments no resource group (últimas 800 entradas). É possível consultar via `az deployment group list` e ver os templates aplicados.
- Porém, o modo `Incremental` não remove recursos — se o deploy adicionou um pipeline, o rollback via template anterior não o remove.

**O que precisamos armazenar explicitamente:**

- Cada deploy deve salvar o ARM Template atual (pré-deploy) como artefato no pipeline — um snapshot do estado antes da mudança.
- Implementação: antes do deploy ADF, executar `az datafactory show` + export do ARM Template e armazenar como artifact no Azure DevOps ou no storage account de artefatos.

**Procedimento de rollback ADF:**

1. Identificar o deployment anterior no histórico do resource group
2. Re-aplicar o ARM Template da versão anterior (armazenado como artefato)
3. Usar modo `Complete` (não Incremental) se necessário remover recursos adicionados
4. Reativar triggers manualmente ou via script (`az datafactory trigger start`)

### 3.3 RTO (Recovery Time Objective)

**RTO proposto: 15 minutos.**

- Rollback Databricks (re-import via SHA): ~3 minutos (checkout + import + smoke tests)
- Rollback ADF (re-apply ARM template anterior): ~5 minutos (download artefato + deploy + reativar triggers)
- Validação pós-rollback (smoke tests): ~3 minutos
- Margem de comunicação e decisão: ~4 minutos

**A estratégia proposta atinge o RTO?** Sim. O rollback de Databricks é simples (Git é fonte de verdade). O rollback de ADF depende de ter o artefato salvo — por isso o pipeline refatorado salva o snapshot pré-deploy. O total estimado é 11 minutos de execução técnica + 4 de decisão = 15 min, muito melhor que os 42 min do incidente.

---

## 4. Questões de Aprofundamento

### 4.1 Databricks Asset Bundles (DABs) vs CLI import_dir

**Diferenças principais:**

| Aspecto | CLI (import_dir) | DABs |
|---------|-----------------|------|
| Versionamento | Nenhum no workspace | Managed deployments com histórico |
| Rollback | Manual (re-import de SHA) | `databricks bundle destroy` + re-deploy |
| Rastreabilidade | Nenhuma nativa | Deployment metadata (quem, quando, o quê) |
| Configuração por ambiente | Variáveis externas | `databricks.yml` com targets (dev/staging/prod) |
| Jobs/Clusters | Gerenciados separadamente | Declarados no bundle, deployados junto |
| Validação | Nenhuma | `databricks bundle validate` pré-deploy |

DABs melhoram rastreabilidade porque cada deployment é registrado com metadata no workspace. O rollback é mais confiável porque o bundle gerencia o estado completo (notebooks + jobs + clusters config), não apenas os arquivos.

### 4.2 Variable Groups + Key Vault para isolamento de ambiente

Estrutura proposta:

- **Key Vault `kv-lagunitas-dev`**: contém `DATABRICKS-TOKEN-DEV` e `DATABRICKS-HOST-DEV`
- **Key Vault `kv-lagunitas-acc`**: contém `DATABRICKS-TOKEN-ACC` e `DATABRICKS-HOST-ACC`  
- **Key Vault `kv-lagunitas-prd`**: contém `DATABRICKS-TOKEN-PRD` e `DATABRICKS-HOST-PRD`

Cada Variable Group no Azure DevOps (`lagunitas-dev-vars`, `lagunitas-acc-vars`, `lagunitas-prd-vars`) é vinculado ao Key Vault do respectivo ambiente. O pipeline referencia o Variable Group correto em cada stage:

```yaml
- stage: DeployDEV
  variables:
    - group: lagunitas-dev-vars   # tokens de DEV, impossível acessar PRD

- stage: DeployPRD
  variables:
    - group: lagunitas-prd-vars   # tokens de PRD, impossível acessar DEV
```

Isso elimina o risco de cross-environment deploy por configuração errada: mesmo que alguém troque uma variável, o token simplesmente não tem permissão no ambiente errado. O isolamento é por credencial, não por configuração.

### 4.3 Alerta proativo: deploy sem execução ADF em 2h

Estrutura no Azure Monitor:

1. **Log de deploy** emitido pelo pipeline (seção 2.2) é ingerido no Log Analytics.
2. **Scheduled Query Rule** no Azure Monitor executa KQL a cada 30 minutos:

```kql
let deploys = DeployLogs_CL 
    | where TimeGenerated > ago(3h) 
    | where environment_s == "PRD" 
    | where overall_status_s == "SUCCESS"
    | project deploy_time = TimeGenerated, pipelines_deployed = deploy_components_adf_pipelines_s;
let executions = ADFPipelineRun 
    | where TimeGenerated > ago(3h) 
    | where Status == "Succeeded"
    | project exec_time = TimeGenerated, PipelineName;
deploys
| mv-expand pipeline = parse_json(pipelines_deployed)
| extend pipeline_name = tostring(pipeline)
| join kind=leftanti (executions | project PipelineName) on $left.pipeline_name == $right.PipelineName
| where datetime_diff('hour', now(), deploy_time) >= 2
```

3. Se a query retorna resultados (deploy aconteceu há 2+ horas mas pipeline ADF não executou), dispara **Action Group** com notificação via email para o time de dados e canal Teams/Slack.

---

## 5. Estrutura do Repositório

```
case-sre-laerte-gomes/
├── azure-pipelines.yml          # YAML refatorado para Azure DevOps
├── documento-de-decisao.md      # Este documento
├── scripts/
│   ├── smoke-test-databricks.sh # Smoke tests Databricks
│   ├── smoke-test-adf.sh        # Smoke tests ADF
│   └── emit-deploy-log.sh       # Emissão de log estruturado
├── .github/
│   └── workflows/
│       └── lagunitas-ci.yml     # GitHub Actions equivalente com mocks
└── README.md                    # Instruções + link do repo
```
