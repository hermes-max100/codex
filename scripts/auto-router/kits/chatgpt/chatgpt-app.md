# ChatGPT app (chatgpt.com, desktop, mobile)

The chat app has no routing API. Here, routing means where you set the Thinking slider,
plus instructions that tell you when to move it.

## Thinking slider
Levels run Instant -> Medium -> High -> Extra High -> Pro. On paid plans, Instant and
the thinking levels use GPT-5.6 Sol.

- **Plus and Pro:** Instant does not switch to a higher thinking level by itself
  (except for safety), and asking it to "think harder" does not change the level.
  Start on Instant and move the slider up yourself only when an answer falls short.
- **Business:** Settings -> General -> Higher intelligence controls whether Instant
  adds thinking automatically. Turn it on for hands-off routing. Enterprise and Edu
  depend on workspace settings.
- Use **Pro** last. It has its own daily and weekly allowances.

## Custom instructions (Settings -> Personalization -> Custom instructions)
Paste:

> Answer at the lowest depth that fully solves the request. If a request needs deeper
> reasoning, longer research, or code execution than this reply can do reliably, say so
> in one line at the top and name the Thinking level to switch to (Medium, High, or Extra
> High) instead of guessing. Separate verified facts from inferences. Do not pad answers.

This makes the model tell you when to move the slider, since it cannot move it itself
on Plus or Pro.

Codex usage (CLI, IDE, cloud) draws from a shared allowance with ChatGPT Work. Regular
chat has its own limits. Check `/status` in the Codex CLI before long runs.
