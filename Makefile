SHELL := /bin/bash

ROOT_DIR := $(abspath .)
COREV_DIR ?= $(ROOT_DIR)/third_party/cv32e40x
COREV_REF ?= master
VERILATOR ?= verilator
# ponytail: Ubuntu 20.04's default g++-9 lacks <coroutine>; clang avoids GCC ICEs here.
VERILATOR_CXX ?= clang++-12
VERILATOR_TIMING_CFLAGS ?= -std=c++20 -O0 -Wno-unknown-warning-option
VERILATOR_TIMING_LDFLAGS ?= -no-pie
# ponytail: smaller generated C++ chunks avoid WSL/compiler stalls; raise if build time dominates.
VERILATOR_OUTPUT_SPLIT ?= 1000
VERILATOR_OUTPUT_SPLIT_CFUNCS ?= 1000
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
VPU_BUILD_DIR ?= $(ROOT_DIR)/work/vpu_smoke
VPU_ELF := $(VPU_BUILD_DIR)/sap_vpu_vpu.elf
VPU_BIN := $(VPU_BUILD_DIR)/sap_vpu_vpu.bin
VPU_HEX := $(VPU_BUILD_DIR)/sap_vpu_vpu.hex
TINYVIT_BUILD_DIR ?= $(ROOT_DIR)/work/tinyvit
TINYVIT_ELF := $(TINYVIT_BUILD_DIR)/sap_vpu_tinyvit.elf
TINYVIT_BIN := $(TINYVIT_BUILD_DIR)/sap_vpu_tinyvit.bin
TINYVIT_HEX := $(TINYVIT_BUILD_DIR)/sap_vpu_tinyvit.hex
TINYVIT_COUNTER_CSV ?= $(TINYVIT_BUILD_DIR)/tinyvit_smoke_counters.csv
TINYVIT_PAPER_TABLE ?= $(TINYVIT_BUILD_DIR)/tinyvit_paper_table.md
FPGA_PART ?= xc7a35tcsg324-1
FPGA_CLOCK_MHZ ?= 100
FPGA_BUILD_DIR ?= $(ROOT_DIR)/work/fpga/vpu_core
DC_CLOCK_PERIOD ?= 10.0
DC_WORK_DIR ?= $(ROOT_DIR)/work/dc/tsmc28/vpu_core
DC_REPORT_DIR ?= $(ROOT_DIR)/reports/dc/tsmc28/vpu_core

.DEFAULT_GOAL := help

.PHONY: help plan-check corev-fetch corev-rtl-flist lint-adapter lint-core lint lint-corev-soc sim-adapter sim-core sim-hello sim-vpu sim-tinyvit sim encoding-check legacy-summary hello-build hello-smoke vpu-build vpu-smoke tinyvit-build tinyvit-smoke tinyvit-summary tinyvit-paper-table fpga-vpu-synth fpga-vpu-summary dc-vpu-precheck dc-vpu-synth dc-vpu-summary

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
	  'make hello-smoke' \
	  'make vpu-smoke' \
	  'make tinyvit-smoke' \
	  'make tinyvit-summary' \
	  'make tinyvit-paper-table' \
	  'make fpga-vpu-synth [FPGA_PART=xc7a35tcsg324-1] [FPGA_CLOCK_MHZ=100]' \
	  'make fpga-vpu-summary' \
	  'make dc-vpu-precheck [DC_CLOCK_PERIOD=10.0]' \
	  'make dc-vpu-synth [DC_CLOCK_PERIOD=10.0]' \
	  'make dc-vpu-summary'

plan-check:
	test -x scripts/fetch_corev_cv32e40x.sh
	test -f rtl/sap_vpu_pkg.sv
	test -f rtl/sap_vpu_core.sv
	test -f platforms/corev/rtl/cvxif_sap_vpu_adapter.sv
	test -f platforms/corev/rtl/corev_min_soc.sv
	test -f tb/corev_min_soc_hello_tb.sv
	test -f tb/corev_min_soc_vpu_tb.sv
	test -f tb/corev_min_soc_tinyvit_tb.sv
	test -f sw/baremetal/sap_vpu_custom.h
	test -f sw/baremetal/hello.S
	test -f sw/baremetal/vpu_smoke.S
	test -f sw/baremetal/tinyvit_mlp_smoke.S
	test -f sw/baremetal/link.ld
	test -x scripts/bin_to_verilog_hex.py
	test -x scripts/summarize_tinyvit_counters.py
	test -f scripts/vivado_vpu_synth.tcl
	test -x scripts/summarize_vivado_reports.py
	test -f scripts/dc_vpu_synth.tcl
	test -x scripts/run_dc_vpu_synth.sh
	test -x scripts/summarize_dc_reports.py
	test -f docs/SAP_VPU_RESEARCH_PLAN.md
	test -f docs/SAP_VPU_LITERATURE_MATRIX.md
	test -f docs/SAP_VPU_TINYVIT_SMOKE_RECORD.md
	test -f docs/SAP_VPU_FPGA_FLOW.md
	test -f docs/SAP_VPU_ASIC_FLOW.md

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
	  rtl/sap_vpu_pkg.sv \
	  rtl/sap_vpu_core.sv \
	  platforms/corev/rtl/cvxif_sap_vpu_adapter.sv \
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
	DESIGN_RTL_DIR="$(COREV_DIR)/rtl" $(VERILATOR) --binary --timing -sv \
	  -DCOREV_ASSERT_OFF --top-module corev_min_soc_hello_tb -Wno-fatal \
	  -Wno-BLKANDNBLK -Wno-TIMESCALEMOD -Wno-UNOPTFLAT \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT \
	  -Wno-ASCRANGE -Wno-IMPLICIT -Wno-UNSIGNED -Wno-COMBDLY \
	  --output-split $(VERILATOR_OUTPUT_SPLIT) --output-split-cfuncs $(VERILATOR_OUTPUT_SPLIT_CFUNCS) \
	  -f "$(COREV_RTL_FLIST)" \
	  rtl/sap_vpu_pkg.sv \
	  rtl/sap_vpu_core.sv \
	  platforms/corev/rtl/cvxif_sap_vpu_adapter.sv \
	  platforms/corev/rtl/corev_min_soc.sv \
	  tb/corev_min_soc_hello_tb.sv \
	  --Mdir "$(SIM_DIR)/hello_obj" \
	  -MAKEFLAGS "CXX=$(VERILATOR_CXX)" \
	  -CFLAGS "$(VERILATOR_TIMING_CFLAGS)" \
	  -LDFLAGS "$(VERILATOR_TIMING_LDFLAGS)" \
	  -o corev_min_soc_hello_tb
	"$(SIM_DIR)/hello_obj/corev_min_soc_hello_tb"

sim-vpu: vpu-build corev-rtl-flist
	mkdir -p "$(SIM_DIR)"
	DESIGN_RTL_DIR="$(COREV_DIR)/rtl" $(VERILATOR) --binary --timing -sv \
	  -DCOREV_ASSERT_OFF --top-module corev_min_soc_vpu_tb -Wno-fatal \
	  -Wno-BLKANDNBLK -Wno-TIMESCALEMOD -Wno-UNOPTFLAT \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT \
	  -Wno-ASCRANGE -Wno-IMPLICIT -Wno-UNSIGNED -Wno-COMBDLY \
	  --output-split $(VERILATOR_OUTPUT_SPLIT) --output-split-cfuncs $(VERILATOR_OUTPUT_SPLIT_CFUNCS) \
	  -f "$(COREV_RTL_FLIST)" \
	  rtl/sap_vpu_pkg.sv \
	  rtl/sap_vpu_core.sv \
	  platforms/corev/rtl/cvxif_sap_vpu_adapter.sv \
	  platforms/corev/rtl/corev_min_soc.sv \
	  tb/corev_min_soc_vpu_tb.sv \
	  --Mdir "$(SIM_DIR)/vpu_obj" \
	  -MAKEFLAGS "CXX=$(VERILATOR_CXX)" \
	  -CFLAGS "$(VERILATOR_TIMING_CFLAGS)" \
	  -LDFLAGS "$(VERILATOR_TIMING_LDFLAGS)" \
	  -o corev_min_soc_vpu_tb
	"$(SIM_DIR)/vpu_obj/corev_min_soc_vpu_tb"

sim-tinyvit: tinyvit-build corev-rtl-flist
	mkdir -p "$(SIM_DIR)"
	DESIGN_RTL_DIR="$(COREV_DIR)/rtl" $(VERILATOR) --binary --timing -sv \
	  -DCOREV_ASSERT_OFF --top-module corev_min_soc_tinyvit_tb -Wno-fatal \
	  -Wno-BLKANDNBLK -Wno-TIMESCALEMOD -Wno-UNOPTFLAT \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT \
	  -Wno-ASCRANGE -Wno-IMPLICIT -Wno-UNSIGNED -Wno-COMBDLY \
	  --output-split $(VERILATOR_OUTPUT_SPLIT) --output-split-cfuncs $(VERILATOR_OUTPUT_SPLIT_CFUNCS) \
	  -f "$(COREV_RTL_FLIST)" \
	  rtl/sap_vpu_pkg.sv \
	  rtl/sap_vpu_core.sv \
	  platforms/corev/rtl/cvxif_sap_vpu_adapter.sv \
	  platforms/corev/rtl/corev_min_soc.sv \
	  tb/corev_min_soc_tinyvit_tb.sv \
	  --Mdir "$(SIM_DIR)/tinyvit_obj" \
	  -MAKEFLAGS "CXX=$(VERILATOR_CXX)" \
	  -CFLAGS "$(VERILATOR_TIMING_CFLAGS)" \
	  -LDFLAGS "$(VERILATOR_TIMING_LDFLAGS)" \
	  -o corev_min_soc_tinyvit_tb
	"$(SIM_DIR)/tinyvit_obj/corev_min_soc_tinyvit_tb"

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

vpu-build:
	mkdir -p "$(VPU_BUILD_DIR)"
	$(RISCV_AS) -march=rv32imc -mabi=ilp32 \
	  -o "$(VPU_BUILD_DIR)/vpu_smoke.o" sw/baremetal/vpu_smoke.S
	$(RISCV_LD) -m elf32lriscv -T sw/baremetal/link.ld \
	  -o "$(VPU_ELF)" "$(VPU_BUILD_DIR)/vpu_smoke.o"
	$(RISCV_OBJCOPY) -O binary "$(VPU_ELF)" "$(VPU_BIN)"
	$(PYTHON) scripts/bin_to_verilog_hex.py "$(VPU_BIN)" "$(VPU_HEX)"

vpu-smoke: sim-vpu lint-corev-soc
	test -s "$(VPU_HEX)"

tinyvit-build:
	mkdir -p "$(TINYVIT_BUILD_DIR)"
	$(RISCV_AS) -march=rv32imc -mabi=ilp32 \
	  -o "$(TINYVIT_BUILD_DIR)/tinyvit_mlp_smoke.o" sw/baremetal/tinyvit_mlp_smoke.S
	$(RISCV_LD) -m elf32lriscv -T sw/baremetal/link.ld \
	  -o "$(TINYVIT_ELF)" "$(TINYVIT_BUILD_DIR)/tinyvit_mlp_smoke.o"
	$(RISCV_OBJCOPY) -O binary "$(TINYVIT_ELF)" "$(TINYVIT_BIN)"
	$(PYTHON) scripts/bin_to_verilog_hex.py "$(TINYVIT_BIN)" "$(TINYVIT_HEX)"

tinyvit-smoke: sim-tinyvit lint-corev-soc
	test -s "$(TINYVIT_HEX)"

tinyvit-summary: tinyvit-smoke
	$(PYTHON) scripts/summarize_tinyvit_counters.py "$(TINYVIT_COUNTER_CSV)"

tinyvit-paper-table: tinyvit-smoke
	$(PYTHON) scripts/summarize_tinyvit_counters.py "$(TINYVIT_COUNTER_CSV)" > "$(TINYVIT_PAPER_TABLE)"
	@printf 'Wrote %s\n' "$(TINYVIT_PAPER_TABLE)"

fpga-vpu-synth:
	mkdir -p "$(FPGA_BUILD_DIR)"
	vivado -mode batch -source scripts/vivado_vpu_synth.tcl \
	  -tclargs "$(FPGA_PART)" "$(FPGA_CLOCK_MHZ)" "$(FPGA_BUILD_DIR)"

fpga-vpu-summary:
	$(PYTHON) scripts/summarize_vivado_reports.py "$(FPGA_BUILD_DIR)"

dc-vpu-precheck:
	PRECHECK_ONLY=1 CLOCK_PERIOD="$(DC_CLOCK_PERIOD)" \
	  WORK_DIR="$(DC_WORK_DIR)" REPORT_DIR="$(DC_REPORT_DIR)" \
	  scripts/run_dc_vpu_synth.sh

dc-vpu-synth:
	CLOCK_PERIOD="$(DC_CLOCK_PERIOD)" \
	  WORK_DIR="$(DC_WORK_DIR)" REPORT_DIR="$(DC_REPORT_DIR)" \
	  scripts/run_dc_vpu_synth.sh

dc-vpu-summary:
	$(PYTHON) scripts/summarize_dc_reports.py "$(DC_WORK_DIR)" "$(DC_REPORT_DIR)"
