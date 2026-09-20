ZIG ?= zig

.PHONY: build test lint fmt
build:
	$(ZIG) build -Doptimize=ReleaseSafe

test:
	$(ZIG) build test

lint:
	$(ZIG) build test

fmt:
	$(ZIG) fmt build.zig build.zig.zon build src
