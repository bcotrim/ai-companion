#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=.build/release/pets
PORT="${PETS_PORT:-7387}"

case "${1:-status}" in
  start)
    if pgrep -qx pets; then
      echo "pets already running (pid $(pgrep -x pets | head -1))"
      exit 0
    fi
    [ -x "$BIN" ] || swift build -c release
    nohup "$BIN" >/tmp/pets.log 2>&1 &
    disown
    sleep 0.5
    if pgrep -qx pets; then
      echo "pets started (pid $(pgrep -x pets | head -1)) — log: /tmp/pets.log"
    else
      echo "pets failed to start — check /tmp/pets.log" >&2
      exit 1
    fi
    ;;
  stop)
    if pkill -x pets; then echo "pets stopped"; else echo "pets not running"; fi
    ;;
  restart)
    "$0" stop >/dev/null || true
    sleep 0.5
    "$0" start
    ;;
  status)
    if pgrep -qx pets; then
      echo "pets running (pid $(pgrep -x pets | head -1))"
      curl -s --max-time 2 "localhost:$PORT/state" || echo "(state endpoint not responding)"
    else
      echo "pets not running"
    fi
    ;;
  *)
    echo "usage: petctl.sh start|stop|restart|status" >&2
    exit 1
    ;;
esac
