# Privacy

AI Companion is local-first:

- The listener binds to `127.0.0.1` only.
- The app does not collect telemetry.
- The app does not upload hook payloads, transcripts, pet files, diagnostics, or settings.
- Diagnostics are generated locally and copied only when you choose **Copy Diagnostics**.
- Update checks call GitHub's releases API only when you choose **Check for Updates...**.

Claude Code sends hook payloads to the local listener. Those payloads can include session IDs, tool names, working directories, prompt text for `UserPromptSubmit`, notification messages, and transcript paths. AI Companion keeps only in-memory session state plus a short in-memory recent-event list for the dashboard and `/state` endpoint.

Pet imports are copied to `~/.claude/pets/`. Pets discovered in `~/.codex/pets/` are read in place and not modified.
