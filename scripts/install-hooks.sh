#!/bin/bash
# Safely merge (or remove, with --remove) pets HTTP hooks into ~/.claude/settings.json.
# Idempotent: re-running makes no changes. Backs up the original before writing.
set -euo pipefail

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
PORT="${PETS_PORT:-7387}"
URL="http://127.0.0.1:${PORT}/event"
MODE="${1:-install}"

python3 - "$SETTINGS" "$URL" "$MODE" <<'EOF'
import json, os, sys, time

path, url, mode = sys.argv[1], sys.argv[2], sys.argv[3]
events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
          "PostToolUseFailure", "PermissionRequest", "PermissionDenied",
          "PostToolBatch", "Notification", "SubagentStart", "SubagentStop",
          "TaskCreated", "TaskCompleted", "Stop", "StopFailure",
          "PreCompact", "PostCompact", "Elicitation", "ElicitationResult",
          "SessionEnd"]

settings = {}
if os.path.exists(path):
    with open(path) as f:
        settings = json.load(f)

hooks = settings.setdefault("hooks", {})
changed = []

if mode == "--remove":
    for ev in list(hooks):
        before = len(hooks[ev])
        hooks[ev] = [g for g in hooks[ev]
                     if not any(h.get("url") == url for h in g.get("hooks", []))]
        if len(hooks[ev]) != before:
            changed.append(ev)
        if not hooks[ev]:
            del hooks[ev]
    if not hooks:
        settings.pop("hooks", None)
else:
    for ev in events:
        groups = hooks.setdefault(ev, [])
        if any(h.get("url") == url for g in groups for h in g.get("hooks", [])):
            continue
        group = {"hooks": [{"type": "http", "url": url, "timeout": 1}]}
        if ev in ("PreToolUse", "PostToolUse", "PostToolUseFailure",
                  "PermissionRequest", "PermissionDenied"):
            group["matcher"] = "*"
        groups.append(group)
        changed.append(ev)

if not changed:
    state = "absent" if mode == "--remove" else "installed"
    print(f"no changes needed (pets hooks already {state})")
    sys.exit(0)

if os.path.exists(path):
    backup = f"{path}.bak.{int(time.time())}"
    os.rename(path, backup)
    print(f"backed up original to {backup}")

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

verb = "removed from" if mode == "--remove" else "added to"
print(f"pets hooks {verb} {path}: {', '.join(changed)}")
print("note: running sessions pick hooks up on their next turn; restart them if not")
EOF
