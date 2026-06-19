# AI Companion Claude Code Plugin

This package installs the default AI Companion HTTP hooks for Claude Code.

It expects the desktop app to listen on `127.0.0.1:7387`. If you change the app port, use the in-app hook installer or `scripts/install-hooks.sh` instead, because this plugin intentionally stays static and self-contained.

The hooks are local-only and use `timeout: 1`, so a stopped app does not slow Claude Code down.
