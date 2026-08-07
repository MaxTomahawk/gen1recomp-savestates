SHELL := /bin/bash

GEN1RECOMP ?= ../gen1recomp
LUAJIT ?= luajit
PYTHON ?= python3
VERSION := $(shell $(PYTHON) -c 'import json; print(json.load(open("manifest.json"))["version"])')
PACKAGE := .artifacts/savestates-$(VERSION).zip
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
	$(PYTHON) $(GEN1RECOMP)/tools/modkit.py validate --repo $(GEN1RECOMP) --base fixture .

lint:
	$(PYTHON) $(GEN1RECOMP)/tools/modkit.py lint --repo $(GEN1RECOMP) .

pack:
	mkdir -p .artifacts
	$(PYTHON) $(GEN1RECOMP)/tools/modkit.py pack --repo $(GEN1RECOMP) --base fixture \
		-o $(PACKAGE) .

package-check: pack
	@test "$$(unzip -Z1 $(PACKAGE) | grep -c '^manifest.json$$')" -eq 1
	@test "$$(unzip -Z1 $(PACKAGE) | grep -c '/manifest.json$$')" -eq 0
	@test "$$(unzip -Z1 $(PACKAGE) | grep -c '^tests/')" -eq 0
	@test "$$(unzip -Z1 $(PACKAGE) | grep -Ec '^(AGENTS.md|Makefile|docs/project-plan.md)$$')" -eq 0
	@echo "Verified installable archive root: $(PACKAGE)"

clean-install-check: package-check
	@install_dir="$$(mktemp -d)"; \
	trap 'rm -rf "$$install_dir"' EXIT; \
	unzip -q $(PACKAGE) -d "$$install_dir"; \
	$(PYTHON) $(GEN1RECOMP)/tools/modkit.py validate \
		--repo $(GEN1RECOMP) --base fixture "$$install_dir"; \
	$(PYTHON) $(GEN1RECOMP)/tools/modkit.py lint \
		--repo $(GEN1RECOMP) "$$install_dir"; \
	test -f "$$install_dir/.modkit/pack.json"; \
	echo "Verified clean extracted install: $(PACKAGE)"

check: test validate lint clean-install-check

clean:
	rm -f $(PACKAGE)
