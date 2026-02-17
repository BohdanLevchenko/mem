SHELL := /bin/zsh

SWIFT ?= swift
BUILD_FLAGS ?= --disable-sandbox

CACHE_HOME := .build/cache/user-home
CLANG_CACHE := .build/cache/clang
SWIFT_ENV := HOME=$(CURDIR)/$(CACHE_HOME) CLANG_MODULE_CACHE_PATH=$(CURDIR)/$(CLANG_CACHE)

TOP ?= 20
ARGS ?=

.PHONY: help dirs build release test run run-json clean

help:
	@echo "Targets:"
	@echo "  make build       Build debug binary"
	@echo "  make release     Build release binary"
	@echo "  make test        Run unit tests"
	@echo "  make run         Run release binary (TOP=$(TOP), ARGS='$(ARGS)')"
	@echo "  make run-json    Run release binary with JSON output"
	@echo "  make clean       Remove build artifacts"

dirs:
	@mkdir -p $(CACHE_HOME) $(CLANG_CACHE)

build: dirs
	$(SWIFT_ENV) $(SWIFT) build $(BUILD_FLAGS)

release: dirs
	$(SWIFT_ENV) $(SWIFT) build -c release $(BUILD_FLAGS)

test: dirs
	$(SWIFT_ENV) $(SWIFT) test $(BUILD_FLAGS)

run: release
	./.build/release/memapps --top $(TOP) $(ARGS)

run-json: release
	./.build/release/memapps --top $(TOP) --json $(ARGS)

clean:
	rm -rf .build
