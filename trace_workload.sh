#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$0")"

if [[ $# -ne 1 ]]; then
    echo "Usage: bash trace_workload.sh file|memory|error|process"
    exit 1
fi

name="$1"
source_file="workloads/${name}_demo.c"
program="bin/${name}_demo"

case "$name" in
    file|memory|error|process) ;;
    *)
        echo "Unknown workload: $name"
        echo "Choose: file, memory, error, process"
        exit 1
        ;;
esac

if [[ ! -f "$source_file" ]]; then
    echo "Missing source: $source_file"
    exit 1
fi

mkdir -p bin results logs reports

echo "=== Compiling ${name}_demo ==="
gcc -Wall -Wextra -std=c11 -g "$source_file" -o "$program"

echo
echo "=== Running tracer on ${name}_demo ==="
echo "Saving terminal trace to results/${name}_demo.trace.txt"
./syscall_tracer "./$program" 2>&1 |
    tee "results/${name}_demo.trace.txt"

echo
echo "=== Saving this run's log and report ==="
cp logs/syscall_trace.log "results/${name}_demo.syscalls.log"
cp reports/syscall_report.txt "results/${name}_demo.report.txt"

if [[ -f reports/syscall_report.csv ]]; then
    cp reports/syscall_report.csv "results/${name}_demo.report.csv"
fi

echo
echo "=== Saved files ==="
printf '%s\n' \
    "results/${name}_demo.trace.txt" \
    "results/${name}_demo.syscalls.log" \
    "results/${name}_demo.report.txt" \
    "results/${name}_demo.report.csv"
