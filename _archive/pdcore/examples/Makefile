# PicoDrive Debugger Core - Examples Build System
#
# Builds example programs demonstrating pdcore usage

.PHONY: all clean

CC = gcc
CFLAGS = -Wall -Wextra -O2 -I../include
LDFLAGS = -L../build -lpdcore

# Example binaries
EXAMPLES = simple_debugger

all: $(EXAMPLES)

simple_debugger: simple_debugger.c ../build/libpdcore.so
	@echo "==> Building simple_debugger example"
	$(CC) $(CFLAGS) simple_debugger.c -o simple_debugger $(LDFLAGS)
	@echo "✓ Built: simple_debugger"

clean:
	@echo "==> Cleaning examples"
	rm -f $(EXAMPLES)
	@echo "✓ Clean complete"

# Ensure pdcore library is built
../build/libpdcore.so:
	@echo "==> Building pdcore library first"
	$(MAKE) -C ..

# Usage help
help:
	@echo "Examples:"
	@echo "  make              - Build all examples"
	@echo "  make clean        - Remove built examples"
	@echo ""
	@echo "To run examples:"
	@echo "  LD_LIBRARY_PATH=../build:$$LD_LIBRARY_PATH ./simple_debugger [rom.32x]"
