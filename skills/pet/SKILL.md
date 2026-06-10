---
name: pet
description: Start, stop, restart, or check the status of the Claude Pets desktop pet app. Use when the user asks to start/stop/restart the pet, check if the pet is running, see what the pet is doing, or mentions the desktop pet not working.
---

# Claude Pets control

The desktop pet app (floating companion that mirrors Claude Code activity) lives at `~/Code/pets`. Control it with:

```sh
~/Code/pets/scripts/petctl.sh start|stop|restart|status
```

- `start` — builds if needed, launches detached (survives the Claude session ending). No-op if already running.
- `stop` — kills the app.
- `restart` — use after code changes in ~/Code/pets.
- `status` — prints pid plus live state JSON from `http://localhost:7387/state`: the pet's display state (asleep/idle/working/waiting/celebrating) and which Claude sessions it is tracking with their per-session state and idle seconds.

Report results conversationally (e.g. "pet is running, currently working, tracking 2 sessions"). Quiet sessions decay automatically: `working` → `idle` after 3 min, `idle` evicts after 10 min (pet sleeps), `waiting` after 30 min.

Logs: `/tmp/pets.log`. Hook config: managed by `~/Code/pets/scripts/install-hooks.sh` (idempotent, `--remove` to uninstall).
