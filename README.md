# ai-companion 🐾

A tiny native macOS desktop pet for [Claude Code](https://claude.com/claude-code) — a floating, always-on-top companion that mirrors what your agent is doing in real time. Compatible with [OpenAI Codex pets](https://github.com/openai/codex): pets you hatched in Codex work here as-is.

- **asleep** 💤 — no active sessions
- **idle** — sessions open, Claude waiting for your next prompt
- **working…** — Claude is running tools
- **needs you!** — Claude is waiting for input or a permission approval
- **done!** 🎉 — brief celebration when Claude finishes responding

Zero dependencies, ~600 lines of Swift, no Electron. ~0% CPU and ~35 MB when idle: the animation timer stops entirely while asleep, spritesheets decode lazily, and the HTTP listener is just an idle socket.

## How it works

Claude Code [hooks](https://code.claude.com/docs/en/hooks) support `"type": "http"`, which POSTs each lifecycle event (SessionStart, PreToolUse, Notification, Stop, …) to a URL. The app runs a minimal hand-rolled HTTP listener on `127.0.0.1:7387`, replies 200 instantly, and rolls all concurrent Claude sessions up into one pet state. Hooks use `timeout: 1`, and when the app isn't running, loopback connection-refused fails in microseconds — Claude Code is never slowed down.

## Setup

```sh
make start          # build (release) and launch detached
make install-hooks  # safely merge hooks into ~/.claude/settings.json
```

The hook installer backs up your settings, appends (never replaces) entries, and is idempotent; `make uninstall-hooks` reverts. Prefer manual setup? Merge `hooks/hooks-snippet.json` yourself. Running Claude Code sessions pick the hooks up on their next turn.

## Usage

- **Drag** the pet anywhere — it plays the run-left/run-right animation while carried; position is remembered.
- **Hover** for a happy bounce.
- **Left-click** opens Claude Desktop.
- **Right-click** for the gallery: pick a pet, toggle the text label, quit.
- Everything persists across launches.

## Codex pets

Pets hatched in OpenAI Codex (`/hatch`) work without copying or converting: the app reads `~/.codex/pets/<id>/` **in place** (read-only — they keep working in Codex) and also scans `~/.claude/pets/` for pets in the same format. Use **Pet → Reload Pets** after hatching a new one.

The format (from open-source `codex-rs/tui/src/pets/`): a folder with `pet.json` + `spritesheet.webp`, an 8×9 grid of 192×208 px cells (1536×1872 total), row-major:

| Row | Animation | Used for |
|-----|-----------|----------|
| 0 | idle | idle / asleep (static first frame) |
| 1 | running-right | dragging right |
| 2 | running-left | dragging left |
| 3 | waving | done! |
| 4 | jumping | hover |
| 6 | waiting | needs you! |
| 7 | running | working… |

Custom `frame` / `animations` overrides in `pet.json` are honored. Frames are copied into small downscaled bitmaps at load so the full decoded sheets are released immediately.

## Controlling from Claude

`scripts/petctl.sh start|stop|restart|status` manages the app detached from any session (also `make start|stop|restart|status`). `status` includes live state JSON from `http://localhost:7387/state` — which sessions are tracked and what the pet is showing.

`skills/pet/SKILL.md` is a Claude Code skill that wraps petctl — copy it to `~/.claude/skills/pet/` and you can just ask Claude "start the pet" or "what's the pet doing?".

## Debugging

```sh
curl localhost:7387/state   # display state + tracked sessions
tail -f /tmp/pets.log       # every hook event as it arrives
```

Synthetic events work too:

```sh
curl -XPOST localhost:7387/event -d '{"hook_event_name":"PreToolUse","session_id":"s1"}'   # working
curl -XPOST localhost:7387/event -d '{"hook_event_name":"Stop","session_id":"s1"}'         # done! → idle
curl -XPOST localhost:7387/event -d '{"hook_event_name":"SessionEnd","session_id":"s1"}'   # asleep
```

Sessions that die without a `SessionEnd` are evicted after 30 minutes of silence.

## Gotchas learned the hard way

- `PreToolUse`/`PostToolUse` hook groups **must** have a `"matcher"` (e.g. `"*"`) or they silently never fire; non-tool events fire without one.
- Hooks are not snapshotted at session start: running sessions pick up newly installed hooks on their next turn.
- When slicing the spritesheet, `CGImage.cropping(to:)` shares the full decoded sheet's backing store — copy frames into standalone bitmaps or every pet keeps ~12 MB resident.
