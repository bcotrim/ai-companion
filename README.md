# ai-companion 🐾

A tiny native macOS desktop pet for [Claude Code](https://claude.com/claude-code) — a floating, always-on-top companion that mirrors what your agent is doing in real time. Compatible with [OpenAI Codex pets](https://github.com/openai/codex): pets you hatched in Codex work here as-is.

- **asleep** 💤 — no active sessions
- **idle** — sessions open, Claude waiting for your next prompt
- **working…** — Claude is running tools
- **subagent…** — Claude delegated work to a subagent
- **task…** — Claude created or completed a task
- **compacting…** — Claude is compacting context
- **needs you!** — Claude is waiting for input or a permission approval
- **done!** 🎉 — brief celebration when Claude finishes responding

Zero dependencies, native Swift/AppKit, no Electron. ~0% CPU and ~35 MB when idle: the animation timer stops entirely while asleep, spritesheets decode lazily, and the HTTP listener is just an idle socket.

## How it works

Claude Code [hooks](https://code.claude.com/docs/en/hooks) support `"type": "http"`, which POSTs each lifecycle event (SessionStart, PreToolUse, Notification, Stop, …) to a URL. The app runs a minimal hand-rolled HTTP listener on `127.0.0.1:7387`, replies 200 instantly, and rolls all concurrent Claude sessions up into one pet state. Hooks use `timeout: 1`, and when the app isn't running, loopback connection-refused fails in microseconds — Claude Code is never slowed down.

## Install

**Download** (Apple Silicon): grab `AICompanion.zip` from the [latest release](https://github.com/bcotrim/ai-companion/releases/latest), verify the published SHA-256 checksum if you want, unzip, move `AICompanion.app` to /Applications and open it. On first launch it offers to install the Claude Code hooks for you.

The downloadable build is open source and ad-hoc signed, not Apple Developer ID notarized. On first launch macOS may require right-click → Open, or:

```sh
xattr -d com.apple.quarantine /Applications/AICompanion.app
```

**From source** (any Mac):

```sh
make start          # build (release) and launch detached
make install-hooks  # safely merge hooks into ~/.claude/settings.json
make app            # or: build the .app bundle yourself (dist/AICompanion.zip)
```

The hook installer backs up your settings, appends (never replaces) entries, and is idempotent; `make uninstall-hooks` reverts. Prefer manual setup? Merge `hooks/hooks-snippet.json` yourself. Running Claude Code sessions pick the hooks up on their next turn.

Prefer Claude Code's plugin flow? The repo also includes `claude-plugin/ai-companion/`, a self-contained plugin package with the default hook set for port `7387`.

## Release signing

`make app` creates an ad-hoc signed zip and `dist/AICompanion.zip.sha256`. That keeps releases free for an open source project, but it means users may see Gatekeeper friction on first launch.

Developer ID signing and notarization are optional. They require the paid Apple Developer Program. If you later want fully trusted downloads:

```sh
security find-identity -v -p codesigning
xcrun notarytool store-credentials ai-companion \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"

make notarized-app SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=ai-companion
```

`make notarized-app` signs with hardened runtime, submits `dist/AICompanion.zip` to Apple, staples the ticket to `AICompanion.app`, validates it, and rebuilds the final zip.

## Usage

- **Drag** the pet anywhere — it plays the run-left/run-right animation while carried; position is remembered.
- **Hover** for a happy bounce.
- **Left-click** runs your configured click action (Claude Desktop by default).
- **Right-click** for the gallery, settings, diagnostics, session state, hook repair, and quit.
- Everything persists across launches.

On first launch, the setup guide can install/repair hooks and copy local diagnostics. Settings include per-display pet size, text label, attention bubbles, attention mode, click action, hook port, hook install, and launch-at-login when running as the `.app` bundle. The pet remembers its position separately for each display.

Attention modes:

- **Quiet** — no attention bubbles or system notifications
- **Normal** — in-window bubbles for blocked, failed, completed, subagent, task, and compaction states
- **Loud** — Normal plus macOS notifications for blocked, failed, and completed turns

Right-click **Agent Dashboard…** for active sessions, hook health, last event, and a short in-memory recent-event timeline. Use **Copy Diagnostics** when reporting issues.

Use **Check for Updates…** to ask GitHub for the latest release. When running from `AICompanion.app`, the app verifies the release checksum, replaces itself, and relaunches. Source/bare-binary runs only offer a verified download.

Privacy: the app listens on loopback only, does not collect telemetry, and does not upload hook payloads. See [docs/privacy.md](docs/privacy.md).

## Codex pets

Pets hatched in OpenAI Codex (`/hatch`) work without copying or converting: the app reads `~/.codex/pets/<id>/` **in place** (read-only — they keep working in Codex) and also scans `~/.claude/pets/` for pets in the same format. Use **Pet → Reload Pets** after hatching a new one.

The default pet, **Wapuu**, ships inside the app in this same format (`Sources/Pets/Resources/wapuu/`); a same-id pet in your user dirs is ignored.

Use **Pet → Install Pet…** to import a Codex-format pet folder or `.zip` into `~/.claude/pets/`. The app validates `pet.json`, spritesheet dimensions, and animation frame references before copying.

The format (from open-source `codex-rs/tui/src/pets/`): a folder with `pet.json` + `spritesheet.webp`, an 8×9 grid of 192×208 px cells (1536×1872 total), row-major:

| Row | Animation | Used for |
|-----|-----------|----------|
| 0 | idle | idle / asleep (static first frame) |
| 1 | running-right | dragging right |
| 2 | running-left | dragging left |
| 3 | waving | done! |
| 4 | jumping | hover / compacting fallback |
| 5 | failed | oops! (a tool call failed) |
| 6 | waiting | needs you! — alternates with a couple of waves |
| 7 | running | working… / subagent fallback |
| 8 | review | planning… (session in plan mode) / task fallback |

Custom `frame` / `animations` overrides in `pet.json` are honored. Frames are copied into small downscaled bitmaps at load so the full decoded sheets are released immediately.

Validate a pet from the command line:

```sh
make validate-pet PET=/path/to/pet-or.zip
```

See [docs/pet-sdk.md](docs/pet-sdk.md) for the compact pet authoring reference.

## Event API

AI Companion accepts Claude Code hook-shaped JSON on `POST /event` and exposes current state on `GET /state`. This makes it possible to build adapters for other local agents without changing the app. See [docs/agent-events.md](docs/agent-events.md).

## Controlling from Claude

`scripts/petctl.sh start|stop|restart|status` manages the app detached from any session (also `make start|stop|restart|status`). `status` includes live state JSON from `http://localhost:7387/state` — which sessions are tracked and what the pet is showing.

`skills/pet/SKILL.md` is a Claude Code skill that wraps petctl — copy it to `~/.claude/skills/pet/` and you can just ask Claude "start the pet" or "what's the pet doing?".

## Debugging

```sh
curl localhost:7387/state   # display state + tracked sessions
tail -f /tmp/pets.log       # every hook event as it arrives
```

The right-click menu also shows whether hooks are installed for the active port, when the last event arrived, and which sessions are currently tracked. Session labels use explicit hook title fields, prompt text, the first real user message in the transcript, or a meaningful working folder name, with internal command wrappers and generated slugs ignored.

## Project health

```sh
make test   # state self-test, hook installer tests, pet validation, JSON validation
make build  # release Swift build
make app    # unsigned/ad-hoc signed app bundle + checksum
```

GitHub Actions runs the same health checks on macOS and builds the app artifact. Release steps live in [docs/release-checklist.md](docs/release-checklist.md).

Synthetic events work too:

```sh
curl -XPOST localhost:7387/event -d '{"hook_event_name":"PreToolUse","session_id":"s1"}'   # working
curl -XPOST localhost:7387/event -d '{"hook_event_name":"Stop","session_id":"s1"}'         # done! → idle
curl -XPOST localhost:7387/event -d '{"hook_event_name":"SessionEnd","session_id":"s1"}'   # asleep
```

States decay Codex-style when a session goes quiet: `working` → `idle` after 3 min (covers missed Stop events), `idle` sessions evict after 10 min (pet falls asleep), `waiting` after 30 min. Notifications only mean "needs you!" when Claude is blocked mid-task (permission prompt, question) — the post-Stop "waiting for your input" notification leaves the pet idle.

## Gotchas learned the hard way

- `PreToolUse`/`PostToolUse` hook groups **must** have a `"matcher"` (e.g. `"*"`) or they silently never fire; non-tool events fire without one.
- Hooks are not snapshotted at session start: running sessions pick up newly installed hooks on their next turn.
- When slicing the spritesheet, `CGImage.cropping(to:)` shares the full decoded sheet's backing store — copy frames into standalone bitmaps or every pet keeps ~12 MB resident.
