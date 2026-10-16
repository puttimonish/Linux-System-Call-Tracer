#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
case "${1:-help}" in
  run)
    shift
    exec python3 scripts/history.py run -- "$@"
    ;;
  history|--history)
    shift 2>/dev/null || true
    exec python3 scripts/history.py history "$@"
    ;;
  syscall|--syscall)
    shift
    exec python3 scripts/history.py syscall "$@"
    ;;
  process|--process)
    shift
    exec python3 scripts/history.py process "$@"
    ;;
  session|--session)
    shift
    exec python3 scripts/history.py session "$@"
    ;;
  help|--help|-h)
    cat <<'HELP'
Linux System Call Tracer - History Commands
-------------------------------------------
./history.sh run ./bin/file_demo
./history.sh run /usr/bin/ls -la
./history.sh history
./history.sh history --limit 5
./history.sh syscall openat
./history.sh syscall mmap
./history.sh session SESSION_ID
./history.sh process PID

The history wrapper archives the existing tracer log after each run.
Session history persists under results/history/.
HELP
    ;;
  *)
    echo "Unknown command: $1"
    echo "Run: ./history.sh help"
    exit 2
    ;;
esac
