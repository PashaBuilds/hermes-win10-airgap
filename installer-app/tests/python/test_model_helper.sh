#!/usr/bin/env bash
# Runs hermes_model_setup.py against a real Hermes source tree + a fake /v1/models server.
#   HERMES_SRC=<hermes-agent checkout or payload\hermes-agent>  PY=<python with Hermes deps>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HELPER="$HERE/../../src/Resources/hermes_model_setup.py"
: "${HERMES_SRC:?set HERMES_SRC}"; : "${PY:=python3}"
PORT=$((20000 + RANDOM % 20000))
"$PY" "$HERE/fake_openai_server.py" "$PORT" "model-a,model-b" & SRV=$!
PORT2=$((PORT + 1))
"$PY" "$HERE/fake_openai_server.py" "$PORT2" "only-model" & SRV2=$!
trap 'kill $SRV $SRV2 2>/dev/null || true; rm -rf "$TMPH"' EXIT
TMPH="$(mktemp -d)"; export HERMES_HOME="$TMPH/home"; mkdir -p "$HERMES_HOME"
sleep 1
KEY=test-key-123456
run() { "$PY" -X utf8 "$HELPER" "$1" --repo "$HERMES_SRC" ; }
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }

out=$(printf '{"base_url":"http://127.0.0.1:%s/v1","api_key":"%s"}' "$PORT" "$KEY" | run probe || true)
echo "$out" | tail -1
check "probe lists 2 models" '[[ "$out" == *"\"models\": [\"model-a\", \"model-b\"]"* ]]'
check "probe never echoes key" '[[ "$out" != *"$KEY"* && "$out" != *"${KEY:0:8}"* ]]'

out=$(printf '{"base_url":"http://127.0.0.1:%s/v1","api_key":"wrong-key-999999"}' "$PORT" | run probe || true)
echo "$out" | tail -1
check "probe wrong key -> unauthorized diagnosis" '[[ "$out" == *"unauthorized"* ]]'

out=$(printf '{"base_url":"http://127.0.0.1:%s/v1","api_key":"%s","model":"model-b","display_name":"Sirket LLM"}' "$PORT" "$KEY" | run apply || true)
echo "$out" | tail -1
check "apply ok" '[[ "$out" == *"\"ok\": true"* ]]'
check "apply never echoes key" '[[ "$out" != *"$KEY"* && "$out" != *"${KEY:0:8}"* ]]'
check "config.yaml has model-b + custom" 'grep -q "default: model-b" "$HERMES_HOME/config.yaml" && grep -q "provider: custom" "$HERMES_HOME/config.yaml"'
check "config.yaml has no literal key" '! grep -q "$KEY" "$HERMES_HOME/config.yaml"'
check "key stored in .env" 'grep -q "$KEY" "$HERMES_HOME/.env"'
check "display name saved" 'grep -q "Sirket LLM" "$HERMES_HOME/config.yaml"'

# Second run (re-runnable): switch model on same endpoint, single-model endpoint flow.
out=$(printf '{"base_url":"http://127.0.0.1:%s/v1","api_key":"%s","model":"model-a","display_name":"Sirket LLM"}' "$PORT" "$KEY" | run apply || true)
check "re-apply switches model" 'grep -q "default: model-a" "$HERMES_HOME/config.yaml"'
out=$(printf '{"base_url":"http://127.0.0.1:%s/v1","api_key":"%s","model":"only-model"}' "$PORT2" "$KEY" | run apply || true)
echo "$out" | tail -1
check "single-detected-model path" '[[ "$out" == *"\"ok\": true"* ]] && grep -q "default: only-model" "$HERMES_HOME/config.yaml"'
out=$(echo '{}' | run show)
echo "$out" | tail -1
check "show reports model" '[[ "$out" == *"only-model"* ]]'
echo "---- config.yaml (model + custom_providers) ----"; sed -n '/^model:/,/^[a-z_]*:$/p' "$HERMES_HOME/config.yaml" | head -20; grep -A12 '^custom_providers' "$HERMES_HOME/config.yaml" | head -20
echo "---- .env (keys masked) ----"; sed -E 's/=.*/=****/' "$HERMES_HOME/.env"
exit $fail
