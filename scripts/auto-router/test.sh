#!/usr/bin/env bash
# Tests auto-route against stub claude/codex binaries; spends no real credits.
set -euo pipefail

router="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/auto-route"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# Stub claude: records its model, charges $0.10 per call, and says
# ROUTER_ESCALATE when its model is listed in $STUB_ESCALATE_MODELS.
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
model=default
while [ $# -gt 1 ]; do
  case "$1" in --model) model=$2; shift 2 ;; *) shift ;; esac
done
echo "$model" > "$STUB_WORK/last_model"
case " ${STUB_ESCALATE_MODELS:-} " in
  *" $model "*) result="ROUTER_ESCALATE: too hard for $model" ;;
  *) result="done by $model" ;;
esac
jq -nc --arg r "$result" '{type: "result", is_error: false, result: $r,
  total_cost_usd: 0.1, usage: {input_tokens: 100, output_tokens: 10}}'
EOF

# Stub codex: records its reasoning effort and emits one completed turn.
cat > "$tmp/bin/codex" <<'EOF'
#!/usr/bin/env bash
last="" effort=default
while [ $# -gt 1 ]; do
  case "$1" in
    -o) last=$2; shift 2 ;;
    -c) effort=${2#model_reasoning_effort=}; effort=${effort//\"/}; shift 2 ;;
    *) shift ;;
  esac
done
echo "$effort" > "$STUB_WORK/last_model"
echo "done at $effort" > "$last"
echo '{"type":"turn.completed","usage":{"input_tokens":50,"output_tokens":5}}'
EOF
chmod +x "$tmp/bin/claude" "$tmp/bin/codex"
export PATH="$tmp/bin:$PATH" STUB_WORK="$tmp"

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. Escalates only until the check passes (opus), never touches fable.
log="$tmp/log1.jsonl"
out=$("$router" --log "$log" --check "grep -qx opus $tmp/last_model" "fix it" 2>/dev/null)
[ "$out" = "done by opus" ] || fail "expected opus result, got: $out"
got=$(jq -sc 'map([.rung, .model, .passed])' "$log")
[ "$got" = '[[1,"haiku",false],[2,"sonnet",false],[3,"opus",true]]' ] || fail "ladder walk: $got"

# 2. Cheapest rung that passes is used with no escalation.
log="$tmp/log2.jsonl"
"$router" --log "$log" --check true "easy" >/dev/null 2>&1
[ "$(jq -s length "$log")" = 1 ] || fail "easy task should use one rung"

# 3. Self-reported ROUTER_ESCALATE triggers escalation without a check.
log="$tmp/log3.jsonl"
out=$(STUB_ESCALATE_MODELS="haiku" "$router" --log "$log" "task" 2>/dev/null)
[ "$out" = "done by sonnet" ] || fail "self-escalation: $out"

# 4. Budget stops escalation: $0.10/call, $0.15 budget => stops after rung 2.
log="$tmp/log4.jsonl"
set +e
"$router" --log "$log" --budget-usd 0.15 --check false "task" >/dev/null 2>&1
code=$?
set -e
[ "$code" = 3 ] || fail "budget exit code: $code"
[ "$(jq -s length "$log")" = 2 ] || fail "budget should stop after 2 rungs"

# 5. --max-rung caps the ladder; exhausting it exits 1.
log="$tmp/log5.jsonl"
set +e
"$router" --log "$log" --max-rung 2 --check false "task" >/dev/null 2>&1
code=$?
set -e
[ "$code" = 1 ] || fail "max-rung exit code: $code"
[ "$(jq -s 'map(.model)' -c "$log")" = '["haiku","sonnet"]' ] || fail "max-rung models"

# 6. Codex engine escalates reasoning effort and logs tokens.
log="$tmp/log6.jsonl"
out=$("$router" --engine codex --log "$log" --check "grep -qx high $tmp/last_model" "task" 2>/dev/null)
[ "$out" = "done at high" ] || fail "codex result: $out"
got=$(jq -sc 'map([.effort, .tokens])' "$log")
[ "$got" = '[["low",55],["medium",55],["high",55]]' ] || fail "codex walk: $got"

# 7. Stats summarize which rung runs needed.
"$router" --stats --log "$tmp/log1.jsonl" | grep -q "rung 3: 1 runs" || fail "stats"

echo "all auto-route tests passed"
