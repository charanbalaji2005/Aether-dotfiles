# AI assistant

Optional, **off by default**, and **local-only by default**. Open with `SUPER+Y`.

## Setup

**Local (recommended):** install [Ollama](https://ollama.com), pull a model (`ollama pull llama3.2`),
then Settings → AI assistant → enable. Nothing leaves your computer.

**OpenAI-compatible:** llama.cpp `llama-server`, LM Studio, vLLM, LocalAI on this machine work with
local-only on. For a remote service, turn local-only off (https is required), choose the
*OpenAI-compatible* provider, set the endpoint and model, and store the key:

```sh
aether ai set-key --provider openai     # prompts with hidden input; stored in your keyring
aether ai status --probe                # checks the endpoint and lists models
```

## What it can and can't do

It answers questions (with *Share a system summary* on, it also knows your GPU, memory and the
recommended quality tier) and may **propose** actions from a fixed list:

`open-panel`, `open-settings`, `launch-app`, `switch-workspace`, `apply-layout`, `apply-profile`,
`set-quality`, `set-theme-mode`, `set-palette`, `set-volume`, `set-dnd`, `set-dock`,
`set-power-profile`, `lock-screen` (`aether ai actions`).

Each proposal is validated against your system (the app must be installed, the layout must
exist…) and shown as a card; **nothing runs until you click Run**. There is no shell, file or
network action, and nothing destructive. Runs and declines are recorded in the audit log
(`aether logs --audit`).

## Privacy and security

* API keys: desktop keyring (Secret Service) via `secret-tool`, passed on stdin; never in
  config.json, logs, the audit trail or the shell's memory beyond the write. Without a keyring,
  `AETHER_AI_API_KEY` is read from the environment (never stored).
* Local-only refuses non-loopback endpoints; remote endpoints must use https and may not embed
  credentials in the URL.
* History is off by default; when on, it's local, redacted and 0600 (`aether ai history --clear`).
* The conversation is sent to the backend on stdin, never as command-line arguments.
