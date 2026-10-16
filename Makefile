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
