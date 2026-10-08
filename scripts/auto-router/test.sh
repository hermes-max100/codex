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
cat > "$STUB_WORK/stdin_seen"
[ -n "${STUB_BAD_JSON:-}" ] && { echo '{"truncated'; exit 1; }
case " ${STUB_ESCALATE_MODELS:-} " in
  *" $model "*) result="ROUTER_ESCALATE: too hard for $model" ;;
  *) result="done by $model" ;;
esac
[ -n "${STUB_PAD:-}" ] && result="$result
$(head -c 100000 /dev/zero | tr '\0' x)"
jq -nc --arg r "$result" '{type: "result", is_error: false, result: $r,
  total_cost_usd: 0.1, usage: {input_tokens: 100, output_tokens: 10}}'
EOF

# Stub codex: records "model effort provider" and emits one completed turn.
cat > "$tmp/bin/codex" <<'EOF'
#!/usr/bin/env bash
last="" model=default effort=default provider=default
while [ $# -gt 1 ]; do
  case "$1" in
    -o) last=$2; shift 2 ;;
    -m) model=$2; shift 2 ;;
    -c)
      case "$2" in
        model_reasoning_effort=*) effort=${2#*=}; effort=${effort//\"/} ;;
        model_provider=*) provider=${2#*=}; provider=${provider//\"/} ;;
      esac
      shift 2 ;;
    *) shift ;;
  esac
done
echo "$model $effort $provider" > "$STUB_WORK/last_model"
echo "done at $model $effort" > "$last"
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

# 6. ChatGPT engine (codex alias) climbs Luna -> Terra on the default ladder and logs tokens.
log="$tmp/log6.jsonl"
out=$("$router" --engine codex --log "$log" --check "grep -q '^gpt-5.6-terra high' $tmp/last_model" "task" 2>/dev/null)
[ "$out" = "done at gpt-5.6-terra high" ] || fail "chatgpt result: $out"
got=$(jq -sc 'map([.engine, .model, .effort, .tokens])' "$log")
[ "$got" = '[["chatgpt","gpt-5.6-luna","low",55],["chatgpt","gpt-5.6-luna","medium",55],["chatgpt","gpt-5.6-terra","medium",55],["chatgpt","gpt-5.6-terra","high",55]]' ] \
  || fail "chatgpt walk: $got"

# 6b. Muse engine requires MODEL_API_KEY and routes through the meta provider.
set +e
env -u MODEL_API_KEY "$router" --engine muse --log "$tmp/log6b.jsonl" "t" >/dev/null 2>&1
code=$?
set -e
[ "$code" = 2 ] || fail "muse without key should exit 2, got $code"
out=$(MODEL_API_KEY=k "$router" --engine muse --log "$tmp/log6b.jsonl" --check "grep -qx 'muse-spark-1.3 medium meta' $tmp/last_model" "t" 2>/dev/null)
[ "$out" = "done at muse-spark-1.3 medium" ] || fail "muse result: $out"

# 7. Stats summarize which rung runs needed.
"$router" --stats --log "$tmp/log1.jsonl" | grep -q "rung 3: 1 runs" || fail "stats"

# 8. Usage errors exit 2: missing option value, non-numeric limits.
for bad in "--check" "--max-rung abc task" "--start x task" "--budget-usd 1e9x task"; do
  set +e
  # shellcheck disable=SC2086
  "$router" --log "$tmp/log8.jsonl" $bad >/dev/null 2>&1
  code=$?
  set -e
  [ "$code" = 2 ] || fail "'$bad' should exit 2, got $code"
done

# 9. A ladder file without a trailing newline keeps its last rung.
printf 'haiku -\nopus high' > "$tmp/ladder"
log="$tmp/log9.jsonl"
"$router" --ladder "$tmp/ladder" --log "$log" --check "grep -qx opus $tmp/last_model" "t" >/dev/null 2>&1 \
  || fail "unterminated ladder row dropped"

# 10. Unknown cost under a budget stops after that rung.
log="$tmp/log10.jsonl"
set +e
STUB_BAD_JSON=1 "$router" --log "$log" --budget-usd 5 "t" >/dev/null 2>&1
code=$?
set -e
[ "$code" = 3 ] || fail "unknown cost should exit 3, got $code"
[ "$(jq -s length "$log")" = 1 ] || fail "unknown cost should stop after 1 rung"

# 11. ROUTER_ESCALATE is detected even when followed by large output.
log="$tmp/log11.jsonl"
out=$(STUB_PAD=1 STUB_ESCALATE_MODELS="haiku" "$router" --log "$log" "t" 2>/dev/null)
[ "${out%%$'\n'*}" = "done by sonnet" ] || fail "large-output escalation: $out"

# 12. The agent does not consume the router's stdin.
echo "next task" | "$router" --log "$tmp/log12.jsonl" --check true "t" >/dev/null 2>&1
[ ! -s "$tmp/stdin_seen" ] || fail "agent consumed router stdin"

# 13. Stats separate engines.
cat "$tmp/log1.jsonl" "$tmp/log6.jsonl" > "$tmp/mixed.jsonl"
[ "$("$router" --stats --log "$tmp/mixed.jsonl" | grep -c '^\[')" = 2 ] || fail "stats per engine"

# 14. A second positional task and a Codex working-directory change are usage errors.
for bad in "one two" "--engine chatgpt t -- -C /tmp" "--engine chatgpt t -- --cd=/tmp"; do
  set +e
  # shellcheck disable=SC2086
  "$router" --log "$tmp/log14.jsonl" $bad >/dev/null 2>&1
  code=$?
  set -e
  [ "$code" = 2 ] || fail "'$bad' should exit 2, got $code"
done

# 15. CRLF ladder rows work; blank CRLF lines are not rungs.
printf 'haiku -\r\n\r\nopus high\r\n' > "$tmp/crlf"
log="$tmp/log15.jsonl"
"$router" --ladder "$tmp/crlf" --log "$log" --check "grep -qx opus $tmp/last_model" "t" >/dev/null 2>&1 \
  || fail "CRLF ladder"
[ "$(jq -sc 'map([.model, .effort])' "$log")" = '[["haiku","-"],["opus","high"]]' ] || fail "CRLF rungs"

# 16. Failed Codex turns log unknown usage, and the log is owner-only.
cat > "$tmp/bin/codex" <<'EOF'
#!/usr/bin/env bash
echo '{"type":"turn.failed","error":{"message":"boom"}}'
EOF
log="$tmp/private/log16.jsonl"
"$router" --engine chatgpt --max-rung 1 --log "$log" "t" >/dev/null 2>&1 || true
[ "$(jq -s '.[0].tokens' "$log")" = null ] || fail "failed codex turn should log null tokens"
[ "$(stat -c %a "$log" 2>/dev/null || stat -f %Lp "$log")" = 600 ] || fail "log should be mode 600"

echo "all auto-route tests passed"
