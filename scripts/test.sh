#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift run pets --self-test

python3 -m json.tool hooks/hooks-snippet.json >/dev/null
python3 -m json.tool claude-plugin/ai-companion/.claude-plugin/plugin.json >/dev/null
python3 -m json.tool claude-plugin/ai-companion/hooks/hooks.json >/dev/null
scripts/validate-pet.sh Sources/Pets/Resources/wapuu >/dev/null

python3 - <<'PY'
import json

with open("hooks/hooks-snippet.json") as f:
    snippet = json.load(f)["hooks"]
with open("claude-plugin/ai-companion/hooks/hooks.json") as f:
    plugin = json.load(f)["hooks"]

assert snippet.keys() == plugin.keys(), "hook event sets differ"
for event in snippet:
    assert snippet[event] == plugin[event], f"hook config differs for {event}"
PY

TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

SETTINGS="$TMP/settings.json"
cat >"$SETTINGS" <<'JSON'
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "echo keep" }
        ]
      }
    ]
  }
}
JSON

CLAUDE_SETTINGS="$SETTINGS" PETS_PORT=7399 scripts/install-hooks.sh >/dev/null

python3 - "$SETTINGS" <<'PY'
import json, sys

path = sys.argv[1]
url = "http://127.0.0.1:7399/event"
required = [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
    "PostToolUseFailure", "PermissionRequest", "PermissionDenied",
    "PostToolBatch", "Notification", "SubagentStart", "SubagentStop",
    "TaskCreated", "TaskCompleted", "Stop", "StopFailure",
    "PreCompact", "PostCompact", "Elicitation", "ElicitationResult",
    "SessionEnd",
]
matcher_required = {
    "PreToolUse", "PostToolUse", "PostToolUseFailure",
    "PermissionRequest", "PermissionDenied",
}

with open(path) as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})
for event in required:
    groups = hooks.get(event)
    assert groups, f"missing {event}"
    if event in matcher_required:
        assert any(group.get("matcher") == "*" for group in groups), f"missing matcher for {event}"
    assert any(hook.get("url") == url for group in groups for hook in group.get("hooks", [])), event

assert any(
    hook.get("command") == "echo keep"
    for group in hooks["Stop"]
    for hook in group.get("hooks", [])
), "existing hook was not preserved"
PY

BEFORE="$TMP/before.json"
cp "$SETTINGS" "$BEFORE"
CLAUDE_SETTINGS="$SETTINGS" PETS_PORT=7399 scripts/install-hooks.sh >/dev/null
cmp "$BEFORE" "$SETTINGS" >/dev/null

CLAUDE_SETTINGS="$SETTINGS" PETS_PORT=7399 scripts/install-hooks.sh --remove >/dev/null
python3 - "$SETTINGS" <<'PY'
import json, sys

with open(sys.argv[1]) as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})
assert "Stop" in hooks, "existing Stop group should remain"
assert any(
    hook.get("command") == "echo keep"
    for group in hooks["Stop"]
    for hook in group.get("hooks", [])
), "existing hook was removed"
assert not any(
    hook.get("url") == "http://127.0.0.1:7399/event"
    for groups in hooks.values()
    for group in groups
    for hook in group.get("hooks", [])
), "pet hook URL was not removed"
PY

echo "Tests OK"
