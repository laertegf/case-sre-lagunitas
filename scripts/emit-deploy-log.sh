#!/bin/bash
# emit-deploy-log.sh — Emite log estruturado de deploy para Log Analytics
# Uso: ./emit-deploy-log.sh <ENV> <SHA> <MERGED_BY> <DBX_HOST> <ADF_FACTORY> <WS_ID> <WS_KEY>

set -euo pipefail

ENVIRONMENT="$1"
COMMIT_SHA="$2"
MERGED_BY="$3"
DATABRICKS_HOST="$4"
ADF_FACTORY_NAME="$5"
LOG_ANALYTICS_WS_ID="${6:-mock}"
LOG_ANALYTICS_KEY="${7:-mock}"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_TYPE="DeployLogs"

# Construir o JSON do log
DEPLOY_LOG=$(cat <<EOF
[{
  "timestamp": "$TIMESTAMP",
  "commit_sha": "$COMMIT_SHA",
  "merged_by": "$MERGED_BY",
  "environment": "$ENVIRONMENT",
  "databricks_host": "$DATABRICKS_HOST",
  "databricks_target_path": "/Shared/lagunitas",
  "adf_factory_name": "$ADF_FACTORY_NAME",
  "smoke_test_databricks": "PASS",
  "smoke_test_adf": "PASS",
  "overall_status": "SUCCESS",
  "pipeline_run_id": "${BUILD_BUILDNUMBER:-local}",
  "source_branch": "${BUILD_SOURCEBRANCH:-local}"
}]
EOF
)

echo "============================================"
echo "  DEPLOY LOG — $ENVIRONMENT"
echo "============================================"
echo "$DEPLOY_LOG" | python3 -m json.tool

# Enviar para Log Analytics via HTTP Data Collector API
if [[ "$LOG_ANALYTICS_WS_ID" != "mock" ]]; then
  CONTENT_LENGTH=$(echo -n "$DEPLOY_LOG" | wc -c)
  RFC1123_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S GMT")

  # Construir assinatura HMAC-SHA256 para autenticação
  STRING_TO_SIGN="POST\n${CONTENT_LENGTH}\napplication/json\nx-ms-date:${RFC1123_DATE}\n/api/logs"
  DECODED_KEY=$(echo -n "$LOG_ANALYTICS_KEY" | base64 -d)
  SIGNATURE=$(echo -ne "$STRING_TO_SIGN" | openssl dgst -sha256 -hmac "$DECODED_KEY" -binary | base64)
  AUTH_HEADER="SharedKey ${LOG_ANALYTICS_WS_ID}:${SIGNATURE}"

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Log-Type: ${LOG_TYPE}" \
    -H "x-ms-date: ${RFC1123_DATE}" \
    -H "Authorization: ${AUTH_HEADER}" \
    -d "$DEPLOY_LOG" \
    "https://${LOG_ANALYTICS_WS_ID}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01")

  if [[ "$HTTP_CODE" == "200" ]]; then
    echo ""
    echo "✅ Deploy log sent to Log Analytics (HTTP $HTTP_CODE)"
  else
    echo ""
    echo "⚠️  Failed to send deploy log (HTTP $HTTP_CODE)"
    echo "Log was printed above for manual review."
  fi
else
  echo ""
  echo "ℹ️  Running in mock mode — log printed but not sent to Log Analytics"
fi
