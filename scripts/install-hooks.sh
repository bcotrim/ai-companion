#!/bin/bash
# Safely merge (or remove, with --remove) pets hooks into ~/.claude/settings.json.
# Idempotent: re-running makes no changes. Backs up the original before writing.
set -euo pipefail

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
PORT="${PETS_PORT:-7387}"
URL="http://127.0.0.1:${PORT}/event"
MODE="${1:-install}"

python3 - "$SETTINGS" "$URL" "$MODE" <<'EOF'
import json, os, sys, time

path, url, mode = sys.argv[1], sys.argv[2], sys.argv[3]
command = ("/usr/bin/curl --silent --max-time 0.5 --connect-timeout 0.2 "
           "--header 'Content-Type: application/json' --data-binary @- "
           f"'{url}' >/dev/null 2>&1 || true")
default_events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                  "PostToolBatch",
                  "PostToolUseFailure", "PermissionRequest", "PermissionDenied",
                  "Notification", "Stop", "SessionEnd"]

settings = {}
if os.path.exists(path):
    with open(path) as f:
        settings = json.load(f)

hooks = settings.setdefault("hooks", {})
changed = []

def is_current_pets_hook(hook):
    value = hook.get("command")
    return hook.get("type") == "command" and isinstance(value, str) and value == command

def is_legacy_pets_hook(hook):
    if hook.get("url") == url:
        return True
    value = hook.get("command")
    return hook.get("type") == "command" and isinstance(value, str) and value != command and url in value

def is_pets_hook(hook):
    return is_current_pets_hook(hook) or is_legacy_pets_hook(hook)

def strip_pets_hooks(group, predicate):
    items = group.get("hooks")
    if not isinstance(items, list):
        return group, False
    kept = [hook for hook in items if not predicate(hook)]
    if len(kept) == len(items):
        return group, False
    if not kept:
        return None, True
    updated = dict(group)
    updated["hooks"] = kept
    return updated, True

def prune_event(event, predicate):
    groups = hooks.get(event)
    if not isinstance(groups, list):
        return False
    next_groups = []
    removed = False
    for group in groups:
        if not isinstance(group, dict):
            next_groups.append(group)
            continue
        updated, did_remove = strip_pets_hooks(group, predicate)
        removed = removed or did_remove
        if updated is not None:
            next_groups.append(updated)
    if next_groups:
        hooks[event] = next_groups
    else:
        hooks.pop(event, None)
    return removed

if mode == "--remove":
    for ev in list(hooks):
        if prune_event(ev, is_pets_hook):
            changed.append(ev)
    if not hooks:
        settings.pop("hooks", None)
else:
    events = list(default_events)
    migrated = []
    for ev in list(hooks):
        if prune_event(ev, is_legacy_pets_hook):
            migrated.append(ev)
            if ev not in events:
                events.append(ev)

    for ev in events:
        groups = hooks.setdefault(ev, [])
        if any(any(is_current_pets_hook(h) for h in g.get("hooks", []))
               for g in groups if isinstance(g, dict)):
            if ev in migrated:
                changed.append(ev)
            continue
        group = {"hooks": [{"type": "command", "command": command, "timeout": 1, "async": True}]}
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
    base = f"{path}.bak.{int(time.time())}"
    backup = base
    counter = 1
    while os.path.exists(backup):
        backup = f"{base}.{counter}"
        counter += 1
    os.rename(path, backup)
    print(f"backed up original to {backup}")

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

verb = "removed from" if mode == "--remove" else "added to"
print(f"pets hooks {verb} {path}: {', '.join(changed)}")
print("note: running sessions pick hooks up on their next turn; restart them if not")
EOF
