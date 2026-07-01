SHELL := /bin/bash

ROOT_DIR := $(abspath .)
COREV_DIR ?= $(ROOT_DIR)/third_party/cv32e40x
COREV_REF ?= master
VERILATOR ?= verilator
PYTHON ?= python3
SIM_DIR ?= $(ROOT_DIR)/work/sim
COREV_RTL_FLIST := $(ROOT_DIR)/work/corev_rtl.f
RISCV_AS ?= riscv64-linux-gnu-as
RISCV_LD ?= riscv64-linux-gnu-ld
RISCV_OBJCOPY ?= riscv64-linux-gnu-objcopy
HELLO_BUILD_DIR ?= $(ROOT_DIR)/work/hello
HELLO_ELF := $(HELLO_BUILD_DIR)/sap_vpu_hello.elf
HELLO_BIN := $(HELLO_BUILD_DIR)/sap_vpu_hello.bin
HELLO_HEX := $(HELLO_BUILD_DIR)/sap_vpu_hello.hex

.DEFAULT_GOAL := help

.PHONY: help plan-check corev-fetch corev-rtl-flist lint-adapter lint-core lint lint-corev-soc sim-adapter sim-core sim-hello sim encoding-check legacy-summary hello-build hello-smoke

help:
	@printf '%s\n' \
	  'make plan-check' \
	  'make corev-fetch [COREV_DIR=third_party/cv32e40x] [COREV_REF=master]' \
	  'make lint-adapter' \
	  'make lint-core' \
	  'make lint-corev-soc' \
	  'make sim-adapter' \
	  'make sim-core' \
	  'make sim-hello' \
	  'make encoding-check' \
	  'make legacy-summary [LEGACY_RESULTS_DIR=../nutvpu/results]' \
	  'make hello-build' \
	  'make hello-smoke'

plan-check:
	test -x scripts/fetch_corev_cv32e40x.sh
	test -f rtl/sap_vpu_pkg.sv
	test -f rtl/sap_vpu_core.sv
	test -f platforms/corev/rtl/cvxif_sap_vpu_adapter.sv
	test -f platforms/corev/rtl/corev_min_soc.sv
	test -f tb/corev_min_soc_hello_tb.sv
	test -f tb/corev_min_soc_hello_tb.cpp
	test -f sw/baremetal/sap_vpu_custom.h
	test -f sw/baremetal/hello.S
	test -f sw/baremetal/link.ld
	test -x scripts/bin_to_verilog_hex.py
	test -f docs/SAP_VPU_RESEARCH_PLAN.md
	test -f docs/SAP_VPU_LITERATURE_MATRIX.md

corev-fetch:
	scripts/fetch_corev_cv32e40x.sh "$(COREV_DIR)" "$(COREV_REF)"

corev-rtl-flist:
	test -d "$(COREV_DIR)/rtl"
	mkdir -p "$(dir $(COREV_RTL_FLIST))"
	grep -E '^(\+incdir|\$$\{DESIGN_RTL_DIR\}/)' "$(COREV_DIR)/cv32e40x_manifest.flist" | \
	  grep -v '\.\./bhv' | grep -v '\.\./sva' > "$(COREV_RTL_FLIST)"
	printf '%s\n' "$(COREV_DIR)/bhv/cv32e40x_sim_clock_gate.sv" >> "$(COREV_RTL_FLIST)"

lint-adapter:
	$(VERILATOR) --lint-only -sv rtl/sap_vpu_pkg.sv platforms/corev/rtl/cvxif_sap_vpu_adapter.sv

lint-core:
	$(VERILATOR) --lint-only -sv rtl/sap_vpu_pkg.sv rtl/sap_vpu_core.sv

lint: lint-adapter lint-core

lint-corev-soc: corev-rtl-flist
	DESIGN_RTL_DIR="$(COREV_DIR)/rtl" $(VERILATOR) --lint-only -sv \
	  -DCOREV_ASSERT_OFF --top-module corev_min_soc -Wno-fatal \
	  -Wno-BLKANDNBLK -Wno-TIMESCALEMOD -Wno-UNOPTFLAT \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT \
	  -Wno-ASCRANGE -Wno-IMPLICIT -Wno-UNSIGNED -Wno-COMBDLY \
	  -f "$(COREV_RTL_FLIST)" \
	  platforms/corev/rtl/corev_min_soc.sv

sim-adapter:
	mkdir -p "$(SIM_DIR)"
	$(VERILATOR) --binary -sv \
	  rtl/sap_vpu_pkg.sv \
	  platforms/corev/rtl/cvxif_sap_vpu_adapter.sv \
	  tb/cvxif_sap_vpu_adapter_tb.sv \
	  --Mdir "$(SIM_DIR)/adapter_obj" \
	  -o cvxif_sap_vpu_adapter_tb
	"$(SIM_DIR)/adapter_obj/cvxif_sap_vpu_adapter_tb"

sim-core:
	mkdir -p "$(SIM_DIR)"
	$(VERILATOR) --binary -sv \
	  rtl/sap_vpu_pkg.sv \
	  rtl/sap_vpu_core.sv \
	  tb/sap_vpu_core_tb.sv \
	  --Mdir "$(SIM_DIR)/core_obj" \
	  -o sap_vpu_core_tb
	"$(SIM_DIR)/core_obj/sap_vpu_core_tb"

sim-hello: hello-build corev-rtl-flist
	mkdir -p "$(SIM_DIR)"
	DESIGN_RTL_DIR="$(COREV_DIR)/rtl" $(VERILATOR) --cc --exe --build -sv \
	  -DCOREV_ASSERT_OFF --top-module corev_min_soc_hello_tb -Wno-fatal \
	  -Wno-BLKANDNBLK -Wno-TIMESCALEMOD -Wno-UNOPTFLAT \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT \
	  -Wno-ASCRANGE -Wno-IMPLICIT -Wno-UNSIGNED -Wno-COMBDLY \
	  -f "$(COREV_RTL_FLIST)" \
	  platforms/corev/rtl/corev_min_soc.sv \
	  tb/corev_min_soc_hello_tb.sv \
	  tb/corev_min_soc_hello_tb.cpp \
	  --Mdir "$(SIM_DIR)/hello_obj" \
	  -CFLAGS "-O0" \
	  -o corev_min_soc_hello_tb
	"$(SIM_DIR)/hello_obj/corev_min_soc_hello_tb"

sim: sim-adapter sim-core

encoding-check:
	$(PYTHON) scripts/check_sap_vpu_encoding.py

legacy-summary:
	$(PYTHON) scripts/summarize_legacy_results.py "$(or $(LEGACY_RESULTS_DIR),../nutvpu/results)"

hello-build:
	mkdir -p "$(HELLO_BUILD_DIR)"
	$(RISCV_AS) -march=rv32imc -mabi=ilp32 \
	  -o "$(HELLO_BUILD_DIR)/hello.o" sw/baremetal/hello.S
	$(RISCV_LD) -m elf32lriscv -T sw/baremetal/link.ld \
	  -o "$(HELLO_ELF)" "$(HELLO_BUILD_DIR)/hello.o"
	$(RISCV_OBJCOPY) -O binary "$(HELLO_ELF)" "$(HELLO_BIN)"
	$(PYTHON) scripts/bin_to_verilog_hex.py "$(HELLO_BIN)" "$(HELLO_HEX)"

hello-smoke: sim-hello lint-corev-soc
	test -s "$(HELLO_HEX)"
