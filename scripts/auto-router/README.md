# auto-router

Runs a coding task on the cheapest model/effort that passes your checks, and escalates
one rung at a time only when it has to.

```
auto-route --check "npm test" "fix the failing date parser test"
auto-route --engine chatgpt --check "cargo test -p mycrate" "add retry to the client"
MODEL_API_KEY=... auto-route --engine muse --check "pytest" "handle empty input"
auto-route --stats
```

| Engine | Drives | Default ladder (cheapest first) |
| --- | --- | --- |
| `claude` | Claude Code CLI | haiku -> sonnet/medium -> opus/high -> fable/high -> fable/max |
| `chatgpt` (alias `codex`) | Codex CLI on a ChatGPT plan | gpt-5.6-luna low/medium -> terra medium/high -> sol high/xhigh |
| `muse` | Codex CLI pointed at Meta Model API | muse-spark-1.3 low -> medium -> high |

The `muse` engine uses the Codex CLI because Meta Model API accepts the OpenAI Responses
API. The router passes the provider settings with `-c` and reads the key from
`MODEL_API_KEY`.

Runs are headless, so the router gives the agent permission to edit files and nothing
more: `--permission-mode acceptEdits` for Claude, `-s workspace-write` for Codex. The
router runs `--check` itself. To allow more, pass your own mode after `--`, for example
`-- --permission-mode auto`. Your setting replaces the default.

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

`ladder.claude`, `ladder.chatgpt`, and `ladder.muse` list one `model effort` per line,
cheapest first.
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

## In-session kits

The script routes whole tasks run from the shell. The kits route the work inside
interactive sessions, where subagents get dispatched:

- `kits/claude/`: put `CLAUDE.md.snippet` in `CLAUDE.md`, and copy `agents/*.md` to
  `.claude/agents/`. You get `scout` (haiku, read-only), `builder` (sonnet), and
  `architect` (opus). The main session decides which one gets each job.
- `kits/chatgpt/`: put `AGENTS.md.snippet` in `AGENTS.md` and `config.toml.snippet` in
  `~/.codex/config.toml`. Subagents default to Luna at low effort. Copy
  `deep.config.toml` to `~/.codex/` and use `codex --profile deep` for hard sessions.
  `chatgpt-app.md` covers the chat app: picker settings and custom instructions.
- `kits/muse/`: copy `muse.config.toml` to `~/.codex/` and run `codex --profile muse`.
  Put `MUSE.md.snippet` in your Muse instructions or `AGENTS.md`.

## Tests

`./test.sh` runs against stub CLIs and spends no credits. It covers the ladder walk,
self-escalation, budget stops, rung caps, all three engines, input validation, and stats.
