# Agent Event API

AI Companion accepts Claude Code hook-shaped JSON over local HTTP:

```sh
curl -XPOST http://127.0.0.1:7387/event \
  -d '{"hook_event_name":"PreToolUse","session_id":"demo","tool_name":"Bash"}'
```

The server always replies `200 OK` quickly. Invalid JSON is ignored so hooks never block Claude Code.

Minimum useful payload:

```json
{
  "hook_event_name": "UserPromptSubmit",
  "session_id": "demo"
}
```

Useful optional fields:

- `tool_name`
- `message`
- `notification_type`
- `permission_mode`
- `prompt`
- `title`, `session_title`, `conversation_title`, `thread_title`
- `cwd`
- `transcript_path`
- `subagent_type`, `agent_name`
- `task_description`, `task_title`

Current display mapping:

| Event | Display |
| --- | --- |
| `SessionStart` | idle |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolBatch` | working |
| `PermissionRequest`, blocked `Notification`, `Elicitation` | needs you |
| `PermissionDenied` | working with note |
| `PostToolUseFailure`, `StopFailure` | oops |
| `SubagentStart` | subagent |
| `TaskCreated`, `TaskCompleted` | task |
| `PreCompact` | compacting |
| `Stop` | done / idle |
| `SessionEnd` | removes session |

Debug current state:

```sh
curl http://127.0.0.1:7387/state
```
