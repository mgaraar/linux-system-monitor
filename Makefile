SHELL := /bin/bash

MONITOR := monitor.sh
CONFIG := config.example.sh
HELPER := tests/helpers/common.bash
SOURCES := $(MONITOR) $(CONFIG) $(HELPER)

BATS ?= bats
SHFMT ?= shfmt

.PHONY: test lint fmt fmt-check check

# Jalankan seluruh test bats.
test:
	$(BATS) -r tests

# Periksa script dengan shellcheck.
lint:
	shellcheck -s bash $(SOURCES)

# Rapikan format dengan shfmt.
fmt:
	$(SHFMT) -i 0 -w $(SOURCES)

# Pastikan format sudah sesuai tanpa mengubah file.
fmt-check:
	$(SHFMT) -i 0 -d $(SOURCES)

# Semua pemeriksaan yang dijalankan CI.
check: lint fmt-check test
