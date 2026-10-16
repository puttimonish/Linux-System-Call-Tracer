# Linux System Call Tracer

A command-line system-call tracing prototype written in C for Linux.
It launches a target command, observes syscall entry/exit events with
`ptrace`, displays selected calls, calculates counts and percentages,
and writes text, CSV, and trace-log files.

## Requirements
- Linux x86-64 environment
- GCC
- GNU Make

## Build
```bash
make clean
make
```

## Demo commands
```bash
./syscall_tracer /bin/echo "Hello tracer"
./syscall_tracer --filter openat,read,write /bin/ls
./syscall_tracer --help
```

## Output files
- `reports/syscall_report.txt`
- `reports/syscall_report.csv`
- `logs/syscall_trace.log`

## Tests
```bash
make test
```

## Modules
1. Tracing engine: process launch and ptrace event loop
2. Syscall decoder: selected syscall-number mappings
3. Filter: syscall-name filtering
4. Statistics: call counts, error counts, percentages
5. Reporting: text and CSV exports
6. Event logger: entry/exit trace log

## Limitations
- This version traces the initial target process, not all descendants.
- Syscall names are mapped for a selection of x86-64 Linux syscall numbers.
- Error counts use the kernel's syscall-exit error flag.
- The ptrace syscall-info ABI is Linux-specific and should be validated on
  other architectures before use.
- Tracing may be restricted by system security settings.
