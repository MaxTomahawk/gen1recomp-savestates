SHELL := /bin/bash

GEN1RECOMP ?= ../gen1recomp
MODKIT ?= $(GEN1RECOMP)/tools/modkit.py
LUAJIT ?= luajit
PYTHON ?= python3
VERSION := $(shell $(PYTHON) -c 'import json; print(json.load(open("manifest.json"))["version"])')
PACKAGE := .artifacts/savestates-$(VERSION).zip
PACKAGE_SOURCES := manifest.json mod.card main.lua README.md CHANGELOG.md LICENSE \
	src .modkitignore docs/architecture.md docs/battle-state-map.md \
	docs/compatibility.md docs/cross-mod-compatibility.md docs/state-format.md
PACK_EPOCH ?= $(shell git -c safe.directory="$(CURDIR)" log -1 --format=%ct \
	-- $(PACKAGE_SOURCES) 2>/dev/null || printf '0')
TEST_FILES := $(sort $(wildcard tests/*_test.lua))

.PHONY: test validate lint pack package-check clean-install-check check clean

test:
	@if [ -z "$(TEST_FILES)" ]; then \
		echo "No Lua behavior tests have landed yet."; \
	else \
		for file in $(TEST_FILES); do $(LUAJIT) "$$file"; done; \
	fi
	$(PYTHON) -m unittest discover -s tests -p '*_test.py'

validate:
	$(PYTHON) $(MODKIT) validate --repo $(GEN1RECOMP) --base fixture .

lint:
	$(PYTHON) $(MODKIT) lint --repo $(GEN1RECOMP) .

pack:
	mkdir -p .artifacts
	SOURCE_DATE_EPOCH=$(PACK_EPOCH) $(PYTHON) $(MODKIT) pack \
		--repo $(GEN1RECOMP) --base fixture \
		-o $(PACKAGE) .

package-check: pack
	$(PYTHON) tools/package_gate.py $(PACKAGE) $(PACK_EPOCH)
	@second="$$(mktemp)"; \
	trap 'rm -f "$$second"' EXIT; \
	SOURCE_DATE_EPOCH=$(PACK_EPOCH) $(PYTHON) $(MODKIT) pack \
		--repo $(GEN1RECOMP) --base fixture --quiet -o "$$second" .; \
	cmp -s $(PACKAGE) "$$second"; \
	echo "Verified reproducible archive bytes: $(PACKAGE)"
	@test "$$(unzip -Z1 $(PACKAGE) | grep -c '^manifest.json$$')" -eq 1
	@test "$$(unzip -Z1 $(PACKAGE) | grep -c '/manifest.json$$')" -eq 0
	@test "$$(unzip -Z1 $(PACKAGE) | grep -c '^tests/')" -eq 0
	@test "$$(unzip -Z1 $(PACKAGE) | grep -c '^docs/cross-mod-compatibility.md$$')" -eq 1
	@test "$$(unzip -Z1 $(PACKAGE) | grep -Ec '^(AGENTS.md|Makefile|docs/project-plan.md)$$')" -eq 0
	@echo "Verified installable archive root: $(PACKAGE)"

clean-install-check: package-check
	@install_dir="$$(mktemp -d)"; \
	trap 'rm -rf "$$install_dir"' EXIT; \
	unzip -q $(PACKAGE) -d "$$install_dir"; \
	$(PYTHON) $(MODKIT) validate \
		--repo $(GEN1RECOMP) --base fixture "$$install_dir"; \
	$(PYTHON) $(MODKIT) lint \
		--repo $(GEN1RECOMP) "$$install_dir"; \
	test -f "$$install_dir/.modkit/pack.json"; \
	echo "Verified clean extracted install: $(PACKAGE)"

check: test validate lint clean-install-check

clean:
	rm -f $(PACKAGE)
