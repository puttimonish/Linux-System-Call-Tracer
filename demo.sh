#!/usr/bin/env bash
set -u
cd "$(dirname "$0")" || exit 1

pause() { echo; read -r -p "Press Enter to return to menu..." _; }

while true; do
    clear
    echo "=============================================="
    echo "      LINUX SYSTEM CALL TRACER - DEMO"
    echo "=============================================="
    echo "1. Build project"
    echo "2. Basic tracing with echo"
    echo "3. Filter system calls"
    echo "4. Analyze a failed file operation"
    echo "5. View text and CSV reports"
    echo "6. View trace log"
    echo "7. Run automated tests"
    echo "8. Show source modules"
    echo "0. Exit"
    echo "----------------------------------------------"
    read -r -p "Choose a stage: " choice

    case "$choice" in
        1)
            make clean && make
            pause
            ;;
        2)
            ./syscall_tracer /bin/echo "Hello from our tracer"
            pause
            ;;
        3)
            ./syscall_tracer --filter openat,read,write /bin/ls
            pause
            ;;
        4)
            ./syscall_tracer /bin/cat /tmp/tracer_file_that_does_not_exist
            pause
            ;;
        5)
            echo "--- Text report ---"
            cat reports/syscall_report.txt 2>/dev/null || echo "Run a trace first."
            echo
            echo "--- CSV preview ---"
            head -n 12 reports/syscall_report.csv 2>/dev/null || true
            pause
            ;;
        6)
            less logs/syscall_trace.log 2>/dev/null || cat logs/syscall_trace.log 2>/dev/null || true
            pause
            ;;
        7)
            make test
            pause
            ;;
        8)
            find src include tests docs -maxdepth 2 -type f -print
            pause
            ;;
        0) exit 0 ;;
        *) echo "Invalid choice."; sleep 1 ;;
    esac
done
