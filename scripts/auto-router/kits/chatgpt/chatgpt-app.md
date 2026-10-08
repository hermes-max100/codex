# ChatGPT app (chatgpt.com, desktop, mobile)

The chat app has no API for routing, so routing there is the picker plus instructions.

## Picker
- Leave **Instant** selected with automatic switching on (model picker -> Configure). It
  moves to Thinking by itself on harder prompts, and those automatic switches do not
  count toward manual Thinking limits.
- Pick **Thinking** yourself only for work you already know is hard. Set its effort as
  low as the task allows.
- Use **Pro** last (Pro, Business, Enterprise, and Edu plans only).

## Custom instructions (Settings -> Personalization -> Custom instructions)
Paste:

> Answer at the lowest depth that fully solves the request. If a request needs deeper
> reasoning, longer research, or code execution than this reply can do reliably, say so
> in one line at the top and recommend switching to Thinking (or Pro) instead of guessing.
> Separate verified facts from inferences. Do not pad answers.

Codex usage (CLI, IDE, cloud) draws from a shared allowance with ChatGPT Work. Regular
chat has its own limits. Check `/status` in the Codex CLI before long runs.
