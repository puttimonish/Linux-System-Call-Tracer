#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="../Linux-System-Call-Tracer-backup-${STAMP}.tar.gz"

echo "=== 1. Backing up existing project ==="
tar --exclude='./.git' -czf "$BACKUP" .
echo "Backup saved: $BACKUP"

mkdir -p src include tests docs reports logs results

echo "=== 2. Creating syscall-name module ==="
cat > include/syscall_names.h <<'EOF'
#ifndef SYSCALL_NAMES_H
#define SYSCALL_NAMES_H
const char *syscall_name(long number);
#endif
EOF

cat > src/syscall_names.c <<'EOF'
#include "syscall_names.h"

const char *syscall_name(long n)
{
    switch (n) {
        case 0: return "read";
        case 1: return "write";
        case 2: return "open";
        case 3: return "close";
        case 4: return "stat";
        case 5: return "fstat";
        case 6: return "lstat";
        case 7: return "poll";
        case 8: return "lseek";
        case 9: return "mmap";
        case 10: return "mprotect";
        case 11: return "munmap";
        case 12: return "brk";
        case 13: return "rt_sigaction";
        case 14: return "rt_sigprocmask";
        case 16: return "ioctl";
        case 17: return "pread64";
        case 18: return "pwrite64";
        case 19: return "readv";
        case 20: return "writev";
        case 21: return "access";
        case 22: return "pipe";
        case 24: return "sched_yield";
        case 32: return "dup";
        case 33: return "dup2";
        case 35: return "nanosleep";
        case 39: return "getpid";
        case 41: return "socket";
        case 42: return "connect";
        case 43: return "accept";
        case 56: return "clone";
        case 57: return "fork";
        case 58: return "vfork";
        case 59: return "execve";
        case 60: return "exit";
        case 61: return "wait4";
        case 62: return "kill";
        case 72: return "fcntl";
        case 79: return "getcwd";
        case 80: return "chdir";
        case 87: return "unlink";
        case 89: return "readlink";
        case 96: return "gettimeofday";
        case 102: return "getuid";
        case 104: return "getgid";
        case 107: return "geteuid";
        case 108: return "getegid";
        case 131: return "sigaltstack";
        case 137: return "statfs";
        case 157: return "prctl";
        case 158: return "arch_prctl";
        case 186: return "gettid";
        case 202: return "futex";
        case 204: return "sched_getaffinity";
        case 217: return "getdents64";
        case 218: return "set_tid_address";
        case 228: return "clock_gettime";
        case 231: return "exit_group";
        case 257: return "openat";
        case 262: return "newfstatat";
        case 267: return "readlinkat";
        case 273: return "set_robust_list";
        case 302: return "prlimit64";
        case 318: return "getrandom";
        case 322: return "execveat";
        case 332: return "statx";
        case 334: return "rseq";
        case 436: return "close_range";
        case 437: return "openat2";
        default: return "unknown";
    }
}
EOF

echo "=== 3. Creating filter module ==="
cat > include/filter.h <<'EOF'
#ifndef FILTER_H
#define FILTER_H
int filter_set(const char *names);
int filter_allows(long number);
#endif
EOF

cat > src/filter.c <<'EOF'
#include <ctype.h>
#include <stdio.h>
#include <string.h>
#include "filter.h"
#include "syscall_names.h"

#define FILTER_SIZE 2048
static char selected[FILTER_SIZE];
static int enabled = 0;

static void trim(char *s)
{
    char *p = s;
    while (isspace((unsigned char)*p)) p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
    size_t n = strlen(s);
    while (n && isspace((unsigned char)s[n - 1])) s[--n] = '\0';
}

int filter_set(const char *names)
{
    if (!names || !*names || strlen(names) >= sizeof(selected)) {
        fprintf(stderr, "Filter list is empty or too long.\n");
        return -1;
    }

    snprintf(selected, sizeof(selected), "%s", names);

    char copy[FILTER_SIZE];
    snprintf(copy, sizeof(copy), "%s", selected);
    char *save = NULL;
    char *token = strtok_r(copy, ",", &save);

    if (!token) return -1;

    while (token) {
        trim(token);
        int found = 0;

        if (!*token || strcmp(token, "unknown") == 0) {
            fprintf(stderr, "Invalid syscall filter name.\n");
            return -1;
        }

        for (long i = 0; i < 1024; i++) {
            if (strcmp(syscall_name(i), token) == 0) {
                found = 1;
                break;
            }
        }

        if (!found) {
            fprintf(stderr, "Unknown syscall name: %s\n", token);
            return -1;
        }

        token = strtok_r(NULL, ",", &save);
    }

    enabled = 1;
    return 0;
}

int filter_allows(long number)
{
    if (!enabled) return 1;

    char copy[FILTER_SIZE];
    snprintf(copy, sizeof(copy), "%s", selected);
    char *save = NULL;
    char *token = strtok_r(copy, ",", &save);

    while (token) {
        trim(token);
        if (strcmp(token, syscall_name(number)) == 0) return 1;
        token = strtok_r(NULL, ",", &save);
    }

    return 0;
}
EOF

echo "=== 4. Creating statistics module ==="
cat > include/statistics.h <<'EOF'
#ifndef STATISTICS_H
#define STATISTICS_H
#define MAX_SYSCALLS 1024

void statistics_record(long number, long long result, int is_error);
unsigned long long statistics_get_count(long number);
unsigned long long statistics_get_errors(long number);
unsigned long long statistics_total(void);
unsigned long long statistics_error_total(void);
void statistics_print(void);
#endif
EOF

cat > src/statistics.c <<'EOF'
#include <stdio.h>
#include "statistics.h"
#include "syscall_names.h"

static unsigned long long counts[MAX_SYSCALLS];
static unsigned long long errors[MAX_SYSCALLS];
static unsigned long long total;
static unsigned long long failed;

void statistics_record(long number, long long result, int is_error)
{
    (void)result;
    if (number < 0 || number >= MAX_SYSCALLS) return;

    counts[number]++;
    total++;

    if (is_error) {
        errors[number]++;
        failed++;
    }
}

unsigned long long statistics_get_count(long n)
{
    return n >= 0 && n < MAX_SYSCALLS ? counts[n] : 0;
}

unsigned long long statistics_get_errors(long n)
{
    return n >= 0 && n < MAX_SYSCALLS ? errors[n] : 0;
}

unsigned long long statistics_total(void) { return total; }
unsigned long long statistics_error_total(void) { return failed; }

void statistics_print(void)
{
    printf("\n========== SYSCALL ANALYSIS ==========\n");
    printf("%-8s %-22s %10s %10s %9s\n",
           "NUMBER", "NAME", "COUNT", "ERRORS", "PERCENT");

    for (long i = 0; i < MAX_SYSCALLS; i++) {
        if (!counts[i]) continue;

        double pct = total
            ? 100.0 * (double)counts[i] / (double)total : 0.0;

        printf("%-8ld %-22s %10llu %10llu %8.2f%%\n",
               i, syscall_name(i), counts[i], errors[i], pct);
    }

    printf("--------------------------------------\n");
    printf("Total syscall entries: %llu\n", total);
    printf("Failed syscall returns: %llu\n", failed);
    printf("======================================\n");
}
EOF

echo "=== 5. Creating trace logger ==="
cat > include/logger.h <<'EOF'
#ifndef LOGGER_H
#define LOGGER_H
void logger_event(const char *event, long number,
                  const char *name, long long result);
#endif
EOF

cat > src/logger.c <<'EOF'
#include <stdio.h>
#include "logger.h"

void logger_event(const char *event, long number,
                  const char *name, long long result)
{
    FILE *f = fopen("logs/syscall_trace.log", "a");
    if (!f) return;

    fprintf(f, "%-6s syscall=%ld name=%s result=%lld\n",
            event, number, name, result);
    fclose(f);
}
EOF

echo "=== 6. Creating text and CSV reporting ==="
cat > include/report.h <<'EOF'
#ifndef REPORT_H
#define REPORT_H
int report_save(const char *text_path, const char *csv_path);
#endif
EOF

cat > src/report.c <<'EOF'
#include <stdio.h>
#include "report.h"
#include "statistics.h"
#include "syscall_names.h"

int report_save(const char *text_path, const char *csv_path)
{
    FILE *f = fopen(text_path, "w");
    if (!f) {
        perror(text_path);
        return -1;
    }

    fprintf(f, "LINUX SYSTEM CALL TRACER REPORT\n");
    fprintf(f, "================================\n");
    fprintf(f, "Total syscall entries: %llu\n",
            statistics_total());
    fprintf(f, "Failed syscall returns: %llu\n\n",
            statistics_error_total());
    fprintf(f, "%-8s %-22s %10s %10s %9s\n",
            "NUMBER", "NAME", "COUNT", "ERRORS", "PERCENT");

    for (long i = 0; i < MAX_SYSCALLS; i++) {
        unsigned long long count = statistics_get_count(i);
        if (!count) continue;

        double pct = statistics_total()
            ? 100.0 * (double)count / (double)statistics_total() : 0.0;

        fprintf(f, "%-8ld %-22s %10llu %10llu %8.2f%%\n",
                i, syscall_name(i), count,
                statistics_get_errors(i), pct);
    }

    fprintf(f, "\nEnd of report\n");
    if (fclose(f) != 0) {
        perror("closing text report");
        return -1;
    }

    f = fopen(csv_path, "w");
    if (!f) {
        perror(csv_path);
        return -1;
    }

    fprintf(f, "number,name,count,errors,percentage\n");

    for (long i = 0; i < MAX_SYSCALLS; i++) {
        unsigned long long count = statistics_get_count(i);
        if (!count) continue;

        double pct = statistics_total()
            ? 100.0 * (double)count / (double)statistics_total() : 0.0;

        fprintf(f, "%ld,%s,%llu,%llu,%.2f\n",
                i, syscall_name(i), count,
                statistics_get_errors(i), pct);
    }

    if (fclose(f) != 0) {
        perror("closing CSV report");
        return -1;
    }

    printf("Text report: %s\n", text_path);
    printf("CSV report:  %s\n", csv_path);
    return 0;
}
EOF

echo "=== 7. Creating tracing engine ==="
cat > src/syscall_tracer.c <<'EOF'
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "syscall_names.h"
#include "statistics.h"
#include "report.h"
#include "filter.h"
#include "logger.h"

#ifndef PTRACE_GET_SYSCALL_INFO
#define PTRACE_GET_SYSCALL_INFO 0x420e
#endif

#define INFO_ENTRY 1
#define INFO_EXIT 2
#define INFO_SECCOMP 3

struct syscall_info_local {
    uint8_t op;
    uint8_t pad[3];
    uint32_t arch;
    uint64_t instruction_pointer;
    uint64_t stack_pointer;
    union {
        struct { uint64_t nr; uint64_t args[6]; } entry;
        struct { int64_t rval; uint8_t is_error; } exit;
        struct {
            uint64_t nr;
            uint64_t args[6];
            uint32_t ret_data;
        } seccomp;
    } data;
};

static void usage(const char *p)
{
    fprintf(stderr,
        "Usage: %s [--filter name1,name2,...] <command> [arguments...]\n"
        "Example: %s --filter read,write /bin/echo Hello\n", p, p);
}

int main(int argc, char **argv)
{
    int command_index = 1;

    if (argc < 2) {
        usage(argv[0]);
        return EXIT_FAILURE;
    }

    if (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h")) {
        usage(argv[0]);
        return EXIT_SUCCESS;
    }

    if (!strcmp(argv[1], "--filter")) {
        if (argc < 4 || filter_set(argv[2]) != 0) {
            usage(argv[0]);
            return EXIT_FAILURE;
        }
        command_index = 3;
    }

    char **target = &argv[command_index];
    pid_t child = fork();

    if (child == -1) {
        perror("fork");
        return EXIT_FAILURE;
    }

    if (child == 0) {
        if (ptrace(PTRACE_TRACEME, 0, NULL, NULL) == -1) {
            perror("PTRACE_TRACEME");
            _exit(127);
        }

        execvp(target[0], target);
        perror("execvp");
        _exit(127);
    }

    int status;
    if (waitpid(child, &status, 0) == -1) {
        perror("waitpid");
        kill(child, SIGKILL);
        (void)waitpid(child, NULL, 0);
        return EXIT_FAILURE;
    }

    if (!WIFSTOPPED(status)) {
        fprintf(stderr, "Target did not stop for tracing.\n");
        return EXIT_FAILURE;
    }

    if (ptrace(PTRACE_SETOPTIONS, child, 0,
               (void *)(long)PTRACE_O_TRACESYSGOOD) == -1) {
        perror("PTRACE_SETOPTIONS");
        kill(child, SIGKILL);
        (void)waitpid(child, NULL, 0);
        return EXIT_FAILURE;
    }

    FILE *log = fopen("logs/syscall_trace.log", "w");
    if (log) {
        fprintf(log, "LINUX SYSTEM CALL TRACE\nTarget PID: %ld\n", (long)child);
        fclose(log);
    }

    printf("====================================================\n");
    printf("          LINUX SYSTEM CALL TRACER\n");
    printf("====================================================\n");
    printf("Target PID: %ld\nCommand   :", (long)child);
    for (int i = command_index; i < argc; i++) printf(" %s", argv[i]);
    printf("\n----------------------------------------------------\n");
    printf("%-8s %-22s %-12s\n", "EVENT", "SYSTEM_CALL", "RESULT");
    printf("----------------------------------------------------\n");
    fflush(stdout);

    long active_number = -1;
    unsigned long long entries = 0;
    int deliver_signal = 0;
    int failed = 0;

    for (;;) {
        if (ptrace(PTRACE_SYSCALL, child, 0,
                   (void *)(long)deliver_signal) == -1) {
            if (errno == ESRCH) break;
            perror("PTRACE_SYSCALL");
            failed = 1;
            break;
        }

        deliver_signal = 0;

        if (waitpid(child, &status, 0) == -1) {
            if (errno == EINTR) continue;
            perror("waitpid");
            failed = 1;
            break;
        }

        if (WIFEXITED(status)) {
            printf("\nChild exited with status %d\n", WEXITSTATUS(status));
            break;
        }

        if (WIFSIGNALED(status)) {
            printf("\nChild terminated by signal %d\n", WTERMSIG(status));
            break;
        }

        if (!WIFSTOPPED(status)) continue;

        int sig = WSTOPSIG(status);

        if (sig == (SIGTRAP | 0x80)) {
            struct syscall_info_local info;
            memset(&info, 0, sizeof(info));

            long bytes = ptrace(PTRACE_GET_SYSCALL_INFO, child,
                                sizeof(info), &info);
            if (bytes == -1) {
                perror("PTRACE_GET_SYSCALL_INFO");
                failed = 1;
                break;
            }

            if (info.op == INFO_ENTRY) {
                active_number = (long)info.data.entry.nr;
                entries++;

                if (filter_allows(active_number)) {
                    printf("%-8s %-22s %-12s\n",
                           "ENTRY", syscall_name(active_number), "-");
                    fflush(stdout);
                }

                logger_event("ENTRY", active_number,
                             syscall_name(active_number), 0);
            } else if (info.op == INFO_EXIT) {
                long long result = (long long)info.data.exit.rval;
                int is_error = info.data.exit.is_error != 0;

                statistics_record(active_number, result, is_error);

                if (filter_allows(active_number)) {
                    printf("%-8s %-22s %-12lld\n",
                           "EXIT", syscall_name(active_number), result);
                    fflush(stdout);
                }

                logger_event("EXIT", active_number,
                             syscall_name(active_number), result);
            } else if (info.op == INFO_SECCOMP) {
                fprintf(stderr, "Notice: seccomp syscall event.\n");
            }
        } else if (sig != SIGTRAP) {
            deliver_signal = sig;
        }
    }

    if (failed) {
        kill(child, SIGKILL);
        while (waitpid(child, &status, 0) == -1 && errno == EINTR) {}
    }

    printf("----------------------------------------------------\n");
    printf("Observed syscall entries: %llu\n", entries);
    statistics_print();

    if (report_save("reports/syscall_report.txt",
                    "reports/syscall_report.csv") != 0) {
        failed = 1;
    }

    printf("Trace log: logs/syscall_trace.log\n");
    printf("====================================================\n");
    return failed ? EXIT_FAILURE : EXIT_SUCCESS;
}
EOF

echo "=== 8. Creating automated tests ==="
cat > tests/test_tracer.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

echo "[1/5] Normal trace"
./syscall_tracer /bin/echo "Tracer test" >"$tmp/normal" 2>&1 ||
    fail "normal trace failed"
grep -q "Tracer test" "$tmp/normal" || fail "target output missing"
grep -q "Observed syscall entries:" "$tmp/normal" || fail "summary missing"
pass "normal tracing"

echo "[2/5] Filtered trace"
./syscall_tracer --filter write /bin/echo "Filter test" >"$tmp/filter" 2>&1 ||
    fail "filtered trace failed"
grep -Eq '^ENTRY[[:space:]]+write([[:space:]]|$)' "$tmp/filter" ||
    fail "write entry not shown"
if grep -Eq '^ENTRY[[:space:]]+mmap([[:space:]]|$)' "$tmp/filter"; then
    fail "mmap entry appeared in write-only filtered trace"
fi
pass "filtering"

echo "[3/5] Invalid filter"
if ./syscall_tracer --filter not_a_syscall /bin/echo test >"$tmp/invalid" 2>&1; then
    fail "invalid filter accepted"
fi
grep -q "Unknown syscall name" "$tmp/invalid" || fail "error message missing"
pass "invalid filter rejected"

echo "[4/5] Help"
./syscall_tracer --help >"$tmp/help" 2>&1 || fail "help failed"
grep -q "Usage:" "$tmp/help" || fail "help text missing"
pass "help"

echo "[5/5] Reports and log"
test -s reports/syscall_report.txt || fail "text report missing"
test -s reports/syscall_report.csv || fail "CSV report missing"
test -s logs/syscall_trace.log || fail "trace log missing"
grep -q "LINUX SYSTEM CALL TRACER REPORT" reports/syscall_report.txt ||
    fail "report header missing"
grep -q '^number,name,count,errors,percentage$' reports/syscall_report.csv ||
    fail "CSV header missing"
pass "text report, CSV report, and trace log"

echo "All automated tests passed."
EOF

echo "=== 9. Correcting Makefile ==="
cat > Makefile <<'EOF'
CC = gcc
CFLAGS = -Wall -Wextra -Wpedantic -std=c11 -g -Iinclude
TARGET = syscall_tracer
SOURCES = src/syscall_tracer.c src/syscall_names.c src/statistics.c src/report.c src/filter.c src/logger.c
OBJECTS = $(SOURCES:.c=.o)

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) $(CFLAGS) $(OBJECTS) -o $(TARGET)

src/%.o: src/%.c
	$(CC) $(CFLAGS) -c $< -o $@

test: $(TARGET)
	bash tests/test_tracer.sh

clean:
	rm -f $(OBJECTS) $(TARGET)
EOF

echo "=== 10. Creating documentation ==="
cat > README.md <<'EOF'
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
EOF

cat > docs/ARCHITECTURE.md <<'EOF'
# Architecture

The tracing engine forks a child, requests tracing with PTRACE_TRACEME,
executes the requested program, and observes syscall stops using
PTRACE_SYSCALL and PTRACE_GET_SYSCALL_INFO.

The syscall decoder converts known syscall numbers to names. The filter
controls which events are displayed. Statistics record completed syscall
entries, failure flags, and percentages. The logger writes trace events to
logs/syscall_trace.log. The report module exports text and CSV summaries.

This version traces the initial process only; descendant-process tracing
is a future extension and is not claimed as implemented.
EOF

echo "=== 11. Creating guided live-demo menu ==="
cat > demo.sh <<'EOF'
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
EOF

chmod +x demo.sh tests/test_tracer.sh

echo "=== 12. Compiling project ==="
make clean
make

echo "=== 13. Running automated tests ==="
make test

echo
echo "UPGRADE FINISHED"
echo "Backup: $BACKUP"
echo "Start guided demo with: bash demo.sh"
