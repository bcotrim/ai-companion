# ai-companion — agent notes

Native macOS desktop pet that mirrors Claude Code activity. Swift + AppKit, zero dependencies, no Electron — keep it that way. Full docs and the spritesheet row table live in [README.md](README.md); keep it in sync when behavior changes.

## Architecture in 30 seconds

Claude Code hooks (`"type": "command"`) silently pipe lifecycle events through `curl` to a loopback-only listener on `127.0.0.1:7387` (override with `PETS_PORT`):

- `Sources/Pets/HttpServer.swift` — hand-rolled HTTP; always replies 200 instantly, never makes Claude Code wait
- `Sources/Pets/PetState.swift` — rolls all concurrent sessions into one `DisplayState`, with decay (working→idle 3 min, idle evicts 10 min, waiting 30 min)
- `Sources/Pets/PetWindow.swift` — floating always-on-top panel: drag, hover, right-click menu
- `Sources/Pets/CodexPets.swift` — reads Codex-format pets from the app's resource bundle (Wapuu, the default) plus `~/.codex/pets/` and `~/.claude/pets/` in place, read-only

Everything is main-thread-only by construction (HTTP callbacks and timers land on the main run loop) — no locks; don't introduce background queues.

## Build, run, iterate

```sh
make build      # swift build -c release
make restart    # relaunch detached; logs → /tmp/pets.log
make status     # pid + live state JSON
make app        # .app bundle → dist/AICompanion.zip
```

Gotcha: `make start`/`restart` only builds when the binary is *missing*, not stale — after code changes run `make build && make restart`.

## Verifying changes

No test suite — drive the state machine with synthetic events and watch the pet:

```sh
curl localhost:7387/state                                                                  # display + tracked sessions
curl -XPOST localhost:7387/event -d '{"hook_event_name":"PreToolUse","session_id":"s1"}'   # → working
curl -XPOST localhost:7387/event -d '{"hook_event_name":"Stop","session_id":"s1"}'         # → done! → idle
curl -XPOST localhost:7387/event -d '{"hook_event_name":"SessionEnd","session_id":"s1"}'   # → asleep
tail -f /tmp/pets.log                                                                      # every event as it arrives
```

## Gotchas (learned the hard way)

- `PreToolUse`/`PostToolUse`-family hook groups **must** have a `"matcher"` (e.g. `"*"`) or they silently never fire; non-tool events fire without one.
- Hooks aren't snapshotted at session start — running sessions pick up newly installed hooks on their next turn.
- Direct `"type": "http"` hooks report connection failures when the app is down; keep the installer on the silent command wrapper.
- `CGImage.cropping(to:)` shares the decoded spritesheet's backing store — copy frames into standalone bitmaps (see `sprite()` in CodexPets.swift) or every pet keeps ~12 MB resident.
- `scripts/install-hooks.sh` must stay additive and idempotent: back up first, never replace existing settings.json entries.

## Constraints

- Spritesheet format is Codex CLI's (8×9 grid of 192×208 cells, row meanings in README) — compatibility with Codex pets is a feature, don't fork the format.
- HTTP listener stays loopback-only and always-200; hooks use async `timeout: 1` command wrappers so a dead app costs Claude Code nothing and stays quiet.
