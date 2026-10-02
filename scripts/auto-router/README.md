# auto-router

Runs a coding task on the cheapest model/effort that passes your checks, and escalates
one rung at a time only when it has to.

```
auto-route --check "npm test" "fix the failing date parser test"
auto-route --engine codex --check "cargo test -p mycrate" "add retry to the client"
auto-route --stats
```

## How it decides to escalate

The router moves up one rung on the ladder when one of these happens:

1. The agent run errors.
2. The agent prints `ROUTER_ESCALATE: <reason>`. Every prompt tells it to do this
   instead of guessing.
3. `--check` exits non-zero.

When it moves up, the next rung keeps the previous edits in the working tree and also
gets the last 60 lines of the check output. It picks up from there instead of
starting over.

Quality comes from `--check`. A rung only counts as a pass if your tests, linter, or
build pass, so a cheaper model's output is never accepted unverified. Without
`--check`, the only signal is the agent's self-report.

## Ladders

`ladder.claude` and `ladder.codex` list one `model effort` per line, cheapest first.
`-` means the CLI default. Edit them, or pass `--ladder FILE`.

## Controlling spend

- `--max-rung N`: hard cap. For example, never reach the top model on routine work.
- `--budget-usd N` (claude): stops once cumulative spend reaches N. Each attempt is
  also capped with `--max-budget-usd` at the remaining budget.
- `--start N`: skip rungs you know a task type always fails. `--stats` reads the
  attempt log (`~/.auto-router/log.jsonl`) and shows which rung tasks actually
  needed. Use it to tune `--start` instead of guessing.

Escalation has a cost: a task that ends on rung 3 also paid for rungs 1 and 2. This is
cheaper overall only if most tasks pass low on the ladder. Check `--stats`, and raise
`--start` for task types that keep climbing.

## In-session routing (subagents)

The script routes whole tasks. For subagents dispatched inside an interactive
session, add this to `CLAUDE.md` (Claude Code) or `AGENTS.md` (Codex):

```markdown
## Model routing
- Do small or context-heavy work directly. Dispatch a subagent only for broad
  searches, independent parallel work, or long tasks that would bloat context.
- Pick the subagent model by difficulty, starting at the lowest tier that fits:
  haiku/low for lookups and mechanical edits; sonnet/medium for standard
  implementation and tests; opus/high for multi-file or subtle changes; the top
  model only for architecture, security, or after a lower tier failed.
- Escalate one tier only on evidence: failing tests or checks, or a result that
  doesn't hold up on review. Never accept a subagent result unverified.
```

## Tests

`./test.sh` exercises the ladder walk, self-escalation, budget stop, rung cap, the
codex engine, and stats against stub CLIs. It spends no credits.
