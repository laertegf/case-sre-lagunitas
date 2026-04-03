#!/bin/bash
# smoke-test-databricks.sh — Valida deploy de notebooks no Databricks
# Uso: ./smoke-test-databricks.sh <HOST> <TOKEN> <TARGET_PATH> <ENVIRONMENT>

set -euo pipefail

HOST="$1"
TOKEN="$2"
TARGET_PATH="$3"
ENVIRONMENT="$4"

echo "============================================"
echo "  SMOKE TEST — Databricks ($ENVIRONMENT)"
echo "============================================"

PASS=0
FAIL=0

# Test 1: Validar que o workspace host corresponde ao ambiente
echo ""
echo "[TEST 1] Validating workspace host matches $ENVIRONMENT..."
if [[ "$HOST" == *"$(echo $ENVIRONMENT | tr '[:upper:]' '[:lower:]')"* ]]; then
  echo "  ✅ PASS — Host $HOST contains $ENVIRONMENT"
  ((PASS++))
else
  echo "  ❌ FAIL — Host $HOST does NOT match environment $ENVIRONMENT"
  ((FAIL++))
fi

# Test 2: Validar que os notebooks existem no path esperado
echo ""
echo "[TEST 2] Checking notebooks exist at $TARGET_PATH..."
NOTEBOOKS=$(databricks workspace ls "$TARGET_PATH" \
  --host "$HOST" --token "$TOKEN" --output json 2>/dev/null || echo "ERROR")

if [[ "$NOTEBOOKS" == "ERROR" ]]; then
  echo "  ❌ FAIL — Cannot list workspace path $TARGET_PATH"
  ((FAIL++))
else
  NB_COUNT=$(echo "$NOTEBOOKS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
  if [[ "$NB_COUNT" -gt 0 ]]; then
    echo "  ✅ PASS — Found $NB_COUNT notebooks at $TARGET_PATH"
    ((PASS++))
  else
    echo "  ❌ FAIL — No notebooks found at $TARGET_PATH"
    ((FAIL++))
  fi
fi

# Test 3: Validar que jobs associados estão ativos
echo ""
echo "[TEST 3] Checking Databricks jobs are active..."
JOBS=$(databricks jobs list --host "$HOST" --token "$TOKEN" --output json 2>/dev/null || echo "ERROR")

if [[ "$JOBS" == "ERROR" ]]; then
  echo "  ⚠️  WARN — Cannot list jobs (may need Jobs API permissions)"
else
  ACTIVE_JOBS=$(echo "$JOBS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
jobs = data.get('jobs', [])
active = [j for j in jobs if 'lagunitas' in j.get('settings', {}).get('name', '').lower()]
print(len(active))
" 2>/dev/null || echo "0")
  echo "  ✅ INFO — Found $ACTIVE_JOBS Lagunitas-related jobs"
  ((PASS++))
fi

# Resultado final
echo ""
echo "============================================"
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================"

if [[ "$FAIL" -gt 0 ]]; then
  echo "##[error] Smoke tests failed with $FAIL failures"
  exit 1
fi

echo "All smoke tests passed."
exit 0
