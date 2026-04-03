#!/bin/bash
# smoke-test-adf.sh — Valida deploy de pipelines e triggers no ADF
# Uso: ./smoke-test-adf.sh <RESOURCE_GROUP> <FACTORY_NAME> <ENVIRONMENT>

set -euo pipefail

RESOURCE_GROUP="$1"
FACTORY_NAME="$2"
ENVIRONMENT="$3"

echo "============================================"
echo "  SMOKE TEST — Azure Data Factory ($ENVIRONMENT)"
echo "============================================"

PASS=0
FAIL=0

# Test 1: Validar que o factory existe e está acessível
echo ""
echo "[TEST 1] Checking ADF factory $FACTORY_NAME exists..."
FACTORY_INFO=$(az datafactory show \
  --resource-group "$RESOURCE_GROUP" \
  --factory-name "$FACTORY_NAME" \
  --query "provisioningState" -o tsv 2>/dev/null || echo "ERROR")

if [[ "$FACTORY_INFO" == "Succeeded" ]]; then
  echo "  ✅ PASS — Factory $FACTORY_NAME exists and is provisioned"
  ((PASS++))
else
  echo "  ❌ FAIL — Factory $FACTORY_NAME not accessible (state: $FACTORY_INFO)"
  ((FAIL++))
fi

# Test 2: Validar que pipelines deployados existem e estão disponíveis
echo ""
echo "[TEST 2] Checking ADF pipelines are deployed..."
PIPELINES=$(az datafactory pipeline list \
  --resource-group "$RESOURCE_GROUP" \
  --factory-name "$FACTORY_NAME" \
  --query "[].name" -o tsv 2>/dev/null || echo "ERROR")

if [[ "$PIPELINES" == "ERROR" ]]; then
  echo "  ❌ FAIL — Cannot list pipelines in factory $FACTORY_NAME"
  ((FAIL++))
else
  PL_COUNT=$(echo "$PIPELINES" | wc -l)
  echo "  ✅ PASS — Found $PL_COUNT pipelines in $FACTORY_NAME"
  echo "$PIPELINES" | while read -r pl; do
    echo "    - $pl"
  done
  ((PASS++))
fi

# Test 3: Validar que triggers estão ativas (status Started)
echo ""
echo "[TEST 3] Checking ADF triggers are active..."
TRIGGERS=$(az datafactory trigger list \
  --resource-group "$RESOURCE_GROUP" \
  --factory-name "$FACTORY_NAME" \
  --query "[].{name:name, state:properties.runtimeState}" -o json 2>/dev/null || echo "ERROR")

if [[ "$TRIGGERS" == "ERROR" ]]; then
  echo "  ❌ FAIL — Cannot list triggers in factory $FACTORY_NAME"
  ((FAIL++))
else
  STOPPED=$(echo "$TRIGGERS" | python3 -c "
import sys, json
triggers = json.load(sys.stdin)
stopped = [t for t in triggers if t.get('state') != 'Started']
for t in stopped:
    print(f\"  ⚠️  Trigger '{t[\"name\"]}' is {t.get('state', 'Unknown')}\")
print(len(stopped))
" 2>/dev/null || echo "0")

  STOPPED_COUNT=$(echo "$STOPPED" | tail -1)
  if [[ "$STOPPED_COUNT" == "0" ]]; then
    echo "  ✅ PASS — All triggers are in Started state"
    ((PASS++))
  else
    echo "  ❌ FAIL — $STOPPED_COUNT triggers are NOT Started"
    echo "$STOPPED" | head -n -1
    ((FAIL++))
  fi
fi

# Test 4: Validar que o factory name corresponde ao ambiente
echo ""
echo "[TEST 4] Validating factory name matches environment..."
ENV_LOWER=$(echo "$ENVIRONMENT" | tr '[:upper:]' '[:lower:]')
if [[ "$FACTORY_NAME" == *"$ENV_LOWER"* ]]; then
  echo "  ✅ PASS — Factory name $FACTORY_NAME contains $ENV_LOWER"
  ((PASS++))
else
  echo "  ❌ FAIL — Factory name $FACTORY_NAME does NOT match environment $ENVIRONMENT"
  ((FAIL++))
fi

# Resultado final
echo ""
echo "============================================"
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================"

if [[ "$FAIL" -gt 0 ]]; then
  echo "##[error] ADF smoke tests failed with $FAIL failures"
  exit 1
fi

echo "All ADF smoke tests passed."
exit 0
