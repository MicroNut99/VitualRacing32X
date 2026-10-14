# PicoDrive Debugger Core - Test Suite Build System
#
# Builds integration test that validates all MVP-1 phases

.PHONY: all clean run

CC = gcc
CFLAGS = -Wall -Wextra -O2 -I../include
LDFLAGS = -L../build -lpdcore

# Test executable
TEST_BIN = integration_test

all: $(TEST_BIN)

$(TEST_BIN): integration_test.c picodrive_stubs.c ../build/libpdcore.so
	@echo "==> Building integration test (with PicoDrive stubs)"
	$(CC) $(CFLAGS) integration_test.c picodrive_stubs.c -o $(TEST_BIN) $(LDFLAGS)
	@echo "✓ Built: $(TEST_BIN)"

run: $(TEST_BIN)
	@echo "==> Running integration test"
	@LD_LIBRARY_PATH=../build:$$LD_LIBRARY_PATH ./$(TEST_BIN)

clean:
	@echo "==> Cleaning test artifacts"
	rm -f $(TEST_BIN)
	@echo "✓ Clean complete"

# Ensure pdcore library is built
../build/libpdcore.so:
	@echo "==> Building pdcore library first"
	$(MAKE) -C ..
