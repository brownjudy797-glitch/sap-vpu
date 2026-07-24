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
VIVADO ?= vivado
XVLOG ?= xvlog
XELAB ?= xelab
XSIM ?= xsim
POWERSHELL ?= powershell.exe
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
TILED_GEMM_SOC_BUILD_DIR ?= $(ROOT_DIR)/work/tiled_gemm_soc
TILED_GEMM_SOC_ELF := $(TILED_GEMM_SOC_BUILD_DIR)/sap_vpu_tiled_gemm_soc.elf
TILED_GEMM_SOC_BIN := $(TILED_GEMM_SOC_BUILD_DIR)/sap_vpu_tiled_gemm_soc.bin
TILED_GEMM_SOC_HEX := $(TILED_GEMM_SOC_BUILD_DIR)/sap_vpu_tiled_gemm_soc.hex
TILED_GEMM_DMA_SOC_BUILD_DIR ?= $(ROOT_DIR)/work/tiled_gemm_dma_soc
TILED_GEMM_DMA_SOC_ELF := $(TILED_GEMM_DMA_SOC_BUILD_DIR)/sap_vpu_tiled_gemm_dma_soc.elf
TILED_GEMM_DMA_SOC_BIN := $(TILED_GEMM_DMA_SOC_BUILD_DIR)/sap_vpu_tiled_gemm_dma_soc.bin
TILED_GEMM_DMA_SOC_HEX := $(TILED_GEMM_DMA_SOC_BUILD_DIR)/sap_vpu_tiled_gemm_dma_soc.hex
SAP_VPU_SOC_RTL := rtl/sap_vpu_pkg.sv rtl/sap_vpu_core.sv rtl/sap_vpu_tiled_gemm.sv rtl/sap_vpu_subsystem.sv
TINYVIT_BUILD_DIR ?= $(ROOT_DIR)/work/tinyvit
TINYVIT_ELF := $(TINYVIT_BUILD_DIR)/sap_vpu_tinyvit.elf
TINYVIT_BIN := $(TINYVIT_BUILD_DIR)/sap_vpu_tinyvit.bin
TINYVIT_HEX := $(TINYVIT_BUILD_DIR)/sap_vpu_tinyvit.hex
TINYVIT_COUNTER_CSV ?= $(TINYVIT_BUILD_DIR)/tinyvit_smoke_counters.csv
TINYVIT_PAPER_TABLE ?= $(TINYVIT_BUILD_DIR)/tinyvit_paper_table.md
TINYVIT_FIXTURE_JSON ?= $(ROOT_DIR)/sw/baremetal/fixtures/tinyvit_mlp2_activation.json
TINYVIT_CHECKPOINT ?= $(ROOT_DIR)/work/models/tiny_vit_5m_224.dist_in22k_ft_in1k/model.safetensors
TINYVIT_CHECKPOINT_FIXTURE ?= $(ROOT_DIR)/sw/baremetal/fixtures/tinyvit_mlp2_checkpoint.json
TINYVIT_IMAGE ?= $(ROOT_DIR)/work/models/tiny_vit_5m_224.dist_in22k_ft_in1k/input.png
TINYVIT_ACTIVATION_FIXTURE ?= $(ROOT_DIR)/sw/baremetal/fixtures/tinyvit_mlp2_activation.json
TINYVIT_MODEL_PYTHON ?= $(PYTHON)
TINYVIT_EVAL_IMAGE_DIR ?= $(ROOT_DIR)/work/tinyvit_eval_images
TINYVIT_SPARSITY_STUDY ?= $(TINYVIT_BUILD_DIR)/tinyvit_fc2_sparsity_study.json
TINYVIT_FIXTURE_DIR ?= $(TINYVIT_BUILD_DIR)/fixture
TINYVIT_FIXTURE_ASM := $(TINYVIT_FIXTURE_DIR)/tinyvit_mlp2_fixture.inc
TINYVIT_FIXTURE_SVH := $(TINYVIT_FIXTURE_DIR)/tinyvit_mlp2_fixture_tb.svh
TINYVIT_FIXTURE_METADATA := $(TINYVIT_FIXTURE_DIR)/tinyvit_mlp2_fixture_metadata.json
TINYVIT_FIXTURE_MAPPING := $(TINYVIT_FIXTURE_DIR)/tinyvit_mlp2_vdot_mapping.json
TINYVIT_FC1_K128_BUILD_DIR ?= $(ROOT_DIR)/work/tinyvit_fc1_k128
TINYVIT_FC1_K128_ELF := $(TINYVIT_FC1_K128_BUILD_DIR)/sap_vpu_tinyvit_fc1_k128.elf
TINYVIT_FC1_K128_BIN := $(TINYVIT_FC1_K128_BUILD_DIR)/sap_vpu_tinyvit_fc1_k128.bin
TINYVIT_FC1_K128_HEX := $(TINYVIT_FC1_K128_BUILD_DIR)/sap_vpu_tinyvit_fc1_k128.hex
TINYVIT_FC1_K128_ASM := $(TINYVIT_FC1_K128_BUILD_DIR)/tinyvit_fc1_k128_fixture.inc
TINYVIT_FC1_K128_SVH := $(TINYVIT_FC1_K128_BUILD_DIR)/tinyvit_fc2_k128_policy_tb.svh
TINYVIT_FC1_K128_WINDOWS := 0 1 2 3 4 5 6 7
TINYVIT_FC2_K512_BUILD_DIR ?= $(ROOT_DIR)/work/tinyvit_fc2_k512
TINYVIT_FC2_K512_SVH := $(TINYVIT_FC2_K512_BUILD_DIR)/tinyvit_fc2_k512_policy_tb.svh
VPU_CORE_ACTIVITY_DIR ?= $(ROOT_DIR)/work/activity/vpu_core
VPU_CORE_VCD ?= $(VPU_CORE_ACTIVITY_DIR)/sap_vpu_core_tb.vcd
VPU_CORE_SAIF ?= $(VPU_CORE_ACTIVITY_DIR)/sap_vpu_core.saif
TINYVIT_ACTIVITY_DIR ?= $(ROOT_DIR)/work/activity/tinyvit
TINYVIT_VCD ?= $(TINYVIT_ACTIVITY_DIR)/corev_min_soc_tinyvit_tb.vcd
TINYVIT_SAIF ?= $(TINYVIT_ACTIVITY_DIR)/sap_vpu_tinyvit.saif
VCD2SAIF ?= /opt/synopsys/syn/L-2016.03-SP1/linux64/syn/bin/vcd2saif
SAIF_INSTANCE ?= sap_vpu_core_tb/dut
TINYVIT_SAIF_INSTANCE ?= corev_min_soc_tinyvit_tb/dut/vpu_i/core_i
FPGA_PART ?= xc7a35tcsg324-1
FPGA_CLOCK_MHZ ?= 100
FPGA_TOP ?= sap_vpu_core
FPGA_OUT_OF_CONTEXT ?= 0
FPGA_BUILD_DIR ?= $(ROOT_DIR)/work/fpga/vpu_core
FPGA_SAIF_POWER_DIR ?= $(ROOT_DIR)/work/fpga/vpu_core_sliced_140_saif_power
FPGA_SAIF_DCP ?= $(ROOT_DIR)/work/fpga/vpu_core_sliced_140/checkpoints/post_route.dcp
FPGA_SAIF_STRIP_PATH ?=
FPGA_FUNCSIM_DIR ?= $(ROOT_DIR)/work/fpga/vpu_core_sliced_140_funcsim
FPGA_FUNCSIM_DCP ?= $(ROOT_DIR)/work/fpga/vpu_core_sliced_140/checkpoints/post_synth.dcp
FPGA_FUNCSIM_XSIM_DIR ?= $(FPGA_FUNCSIM_DIR)/xsim_gate
FPGA_FUNCSIM_VCD ?= $(FPGA_FUNCSIM_XSIM_DIR)/sap_vpu_core_gate_tb.vcd
FPGA_FUNCSIM_SAIF ?= $(FPGA_FUNCSIM_DIR)/sap_vpu_core_gate.saif
FPGA_FUNCSIM_SAIF_POWER_DIR ?= $(ROOT_DIR)/work/fpga/vpu_core_sliced_140_funcsim_saif_power
VIVADO_ROOT_WINDOWS ?= D:\Xilinx_2023_02\Vivado\2023.2
FPGA_POLICY_POWER_DIR ?= work\fpga\vpu_core_policy_power_matrix
FPGA_POLICY_DCP ?= work\fpga\vpu_core_sliced_140\checkpoints\post_route.dcp
FPGA_POLICY_NETLIST ?= work\fpga\vpu_core_sliced_140_funcsim\sap_vpu_core_funcsim.v
FPGA_POLICY_CLOCK_MHZ ?= 140
FPGA_SUBSYSTEM_POWER_DIR ?= work\fpga\vpu_subsystem_140_saif_power
FPGA_SUBSYSTEM_POST_SYNTH_DCP ?= work\fpga\vpu_subsystem_140\checkpoints\post_synth.dcp
FPGA_SUBSYSTEM_POST_ROUTE_DCP ?= work\fpga\vpu_subsystem_140\checkpoints\post_route.dcp
FPGA_SUBSYSTEM_CLOCK_MHZ ?= 140
FPGA_SUBSYSTEM_ITERATIONS ?= 128
FPGA_SUBSYSTEM_POLICY_POWER_DIR ?= work\fpga\vpu_subsystem_140_policy_power
FPGA_SUBSYSTEM_POLICY_ITERATIONS ?= 32
FPGA_SUBSYSTEM_K512_POLICY_POWER_DIR ?= work\fpga\vpu_subsystem_140_k512_policy_power
FPGA_SUBSYSTEM_K512_POLICY_ITERATIONS ?= 8
FPGA_SUBSYSTEM_K512_PAIR_POLICY_POWER_DIR ?= work\fpga\vpu_subsystem_140_k512_pair_policy_power
FPGA_SUBSYSTEM_K512_PAIR_POLICY_ITERATIONS ?= 2
FPGA_SUBSYSTEM_K512_STREAM_POLICY_POWER_DIR ?= work\fpga\vpu_subsystem_140_k512_stream_policy_power
FPGA_SUBSYSTEM_K512_STREAM_POLICY_ITERATIONS ?= 2
DC_CLOCK_PERIOD ?= 10.0
DC_DESIGN_NAME ?= sap_vpu_core
DC_WORK_DIR ?= $(ROOT_DIR)/work/dc/tsmc28/vpu_core
DC_REPORT_DIR ?= $(ROOT_DIR)/reports/dc/tsmc28/vpu_core
DC_NETLIST_DIR ?= $(ROOT_DIR)/netlist/dc/tsmc28/vpu_core
DC_POLICY_MATRIX_WORK_DIR ?= $(ROOT_DIR)/work/dc/tsmc28/vpu_policy_matrix
DC_POLICY_MATRIX_REPORT_DIR ?= $(ROOT_DIR)/reports/dc/tsmc28/vpu_policy_matrix
DC_POLICY_NETLIST_DIR ?= $(ROOT_DIR)/netlist/dc/tsmc28/vpu_core_gate
SYNOPSYS_ENV_FILE ?= $(HOME)/synopsys_env.sh
VCS_MX_HOME ?= /opt/synopsys/vcs-mx/O-2018.09-SP2
VCS_MX ?= $(VCS_MX_HOME)/bin/vcs
TSMC28_VERILOG ?= /opt/pdk/tsmc28hpcplus/tcbn28hpcplusbwp7t40p140_180b/Front_End/verilog/tcbn28hpcplusbwp7t40p140_110a/tcbn28hpcplusbwp7t40p140.v
DC_GATE_WORK_DIR ?= $(ROOT_DIR)/work/dc/tsmc28/vpu_core_gate
DC_GATE_REPORT_DIR ?= $(ROOT_DIR)/reports/dc/tsmc28/vpu_core_gate
DC_GATE_NETLIST_DIR ?= $(ROOT_DIR)/netlist/dc/tsmc28/vpu_core_gate
DC_GATE_SIM_DIR ?= $(ROOT_DIR)/work/dc/tsmc28/vpu_core_gate_sim
DC_GATE_VCD ?= $(DC_GATE_SIM_DIR)/sap_vpu_core_gate_tb.vcd
DC_GATE_SAIF ?= $(DC_GATE_SIM_DIR)/sap_vpu_core_gate_tb.saif
DC_GATE_POWER_WORK_DIR ?= $(DC_GATE_SIM_DIR)/dc_power
DC_GATE_POWER_REPORT_DIR ?= $(DC_GATE_SIM_DIR)/reports_power

.DEFAULT_GOAL := help

.PHONY: help plan-check corev-fetch corev-rtl-flist lint-adapter lint-core lint-tiled-gemm lint-subsystem lint lint-corev-soc sim-adapter sim-core sim-tiled-gemm sim-core-vcd sim-hello sim-vpu sim-tiled-gemm-soc sim-tiled-gemm-dma-soc sim-tinyvit-fc1-k128 sim-tinyvit sim-tinyvit-vcd sim-subsystem-mlp2 sim-subsystem-sparse-policies sim-subsystem-k512-policies sim-subsystem-k512-pair-policies sim-subsystem-k512-stream sim encoding-check legacy-summary hello-build hello-smoke vpu-build vpu-smoke tiled-gemm-soc-build tiled-gemm-soc-smoke tiled-gemm-dma-soc-build tiled-gemm-dma-soc-smoke tinyvit-fc1-k128-fixture tinyvit-fc2-k512-fixture tinyvit-fc1-k128-build tinyvit-fc1-k128-smoke tinyvit-checkpoint-fixture tinyvit-activation-fixture tinyvit-sparsity-study tinyvit-fixture tinyvit-fixture-check tiled-gemm-check tiled-gemm-rtl-check tinyvit-build tinyvit-smoke tinyvit-summary tinyvit-paper-table fpga-vpu-synth fpga-vpu-funcsim-netlist fpga-vpu-funcsim-vcd fpga-vpu-funcsim-saif fpga-vpu-funcsim-saif-power fpga-vpu-policy-power-matrix fpga-vpu-subsystem-saif-power fpga-vpu-subsystem-policy-power-matrix fpga-vpu-subsystem-k512-policy-power-matrix fpga-vpu-subsystem-k512-pair-policy-power-matrix fpga-vpu-subsystem-k512-stream-policy-power-matrix fpga-vpu-saif-power fpga-vpu-summary dc-vpu-gate-netlist-check dc-vpu-gate-synth dc-vpu-gate-sim dc-vpu-gate-saif-power dc-vpu-precheck dc-vpu-synth dc-vpu-power dc-vpu-saif-power dc-vpu-tinyvit-saif-power dc-vpu-policy-power-matrix dc-vpu-summary

help:
	@printf '%s\n' \
	  'make plan-check' \
	  'make corev-fetch [COREV_DIR=third_party/cv32e40x] [COREV_REF=master]' \
	  'make lint-adapter' \
	  'make lint-core' \
	  'make tiled-gemm-rtl-check' \
	  'make lint-corev-soc' \
	  'make sim-adapter' \
	  'make sim-core' \
	  'make sim-core-vcd' \
	  'make sim-hello' \
	  'make sim-tinyvit-vcd' \
	  'make sim-subsystem-mlp2' \
	  'make sim-subsystem-sparse-policies' \
	  'make sim-subsystem-k512-policies' \
	  'make sim-subsystem-k512-pair-policies' \
	  'make sim-subsystem-k512-stream' \
	  'make encoding-check' \
	  'make legacy-summary [LEGACY_RESULTS_DIR=../nutvpu/results]' \
	  'make hello-build' \
	  'make hello-smoke' \
	  'make vpu-smoke' \
	  'make tiled-gemm-soc-smoke' \
	  'make tiled-gemm-dma-soc-smoke' \
	  'make tinyvit-fc1-k128-smoke' \
	  'make tinyvit-smoke' \
	  'make tinyvit-checkpoint-fixture [TINYVIT_CHECKPOINT=/path/to/model.safetensors]' \
	  'make tinyvit-activation-fixture [TINYVIT_MODEL_PYTHON=/path/to/python]' \
	  'make tinyvit-sparsity-study TINYVIT_MODEL_PYTHON=/path/to/python' \
	  'make tinyvit-fixture [TINYVIT_FIXTURE_JSON=/path/to/fixture.json]' \
	  'make tinyvit-fixture-check' \
	  'make tiled-gemm-check' \
	  'make tinyvit-summary' \
	  'make tinyvit-paper-table' \
	  'make fpga-vpu-synth [FPGA_PART=xc7a35tcsg324-1] [FPGA_CLOCK_MHZ=100]' \
	  'make fpga-vpu-funcsim-netlist [FPGA_FUNCSIM_DCP=work/fpga/vpu_core_sliced_140/checkpoints/post_synth.dcp]' \
	  'make fpga-vpu-funcsim-vcd' \
	  'make fpga-vpu-funcsim-saif-power [FPGA_SAIF_DCP=work/fpga/vpu_core_sliced_140/checkpoints/post_route.dcp]' \
	  'make fpga-vpu-policy-power-matrix' \
	  'make fpga-vpu-subsystem-saif-power' \
	  'make fpga-vpu-subsystem-policy-power-matrix' \
	  'make fpga-vpu-subsystem-k512-policy-power-matrix' \
	  'make fpga-vpu-subsystem-k512-pair-policy-power-matrix' \
	  'make fpga-vpu-subsystem-k512-stream-policy-power-matrix' \
	  'make fpga-vpu-saif-power [FPGA_SAIF_DCP=work/fpga/vpu_core_sliced_140/checkpoints/post_route.dcp]' \
	  'make fpga-vpu-summary' \
	  'make dc-vpu-gate-netlist-check [DC_NETLIST_DIR=netlist/dc/tsmc28/vpu_core]' \
	  'make dc-vpu-gate-synth' \
	  'make dc-vpu-gate-sim' \
	  'make dc-vpu-gate-saif-power' \
	  'make dc-vpu-precheck [DC_CLOCK_PERIOD=10.0]' \
	  'make dc-vpu-synth [DC_CLOCK_PERIOD=10.0]' \
	  'make dc-vpu-power [DC_NETLIST_DIR=netlist/dc/tsmc28/vpu_core]' \
	  'make dc-vpu-saif-power [DC_NETLIST_DIR=netlist/dc/tsmc28/vpu_core]' \
	  'make dc-vpu-tinyvit-saif-power [DC_NETLIST_DIR=netlist/dc/tsmc28/vpu_core]' \
	  'make dc-vpu-policy-power-matrix' \
	  'make dc-vpu-summary'

plan-check:
	test -x scripts/fetch_corev_cv32e40x.sh
	test -f rtl/sap_vpu_pkg.sv
	test -f rtl/sap_vpu_core.sv
	test -f rtl/sap_vpu_tiled_gemm.sv
	test -f rtl/sap_vpu_subsystem.sv
	test -f platforms/corev/rtl/cvxif_sap_vpu_adapter.sv
	test -f platforms/corev/rtl/corev_min_soc.sv
	test -f tb/corev_min_soc_hello_tb.sv
	test -f tb/corev_min_soc_vpu_tb.sv
	test -f tb/corev_min_soc_tinyvit_tb.sv
	test -f tb/sap_vpu_core_gate_tb.sv
	test -f tb/sap_vpu_tiled_gemm_tb.sv
	test -f tb/corev_min_soc_tiled_gemm_tb.sv
	test -f tb/corev_min_soc_tiled_gemm_dma_tb.sv
	test -f tb/sap_vpu_subsystem_gate_tb.sv
	test -f scripts/run_fpga_vpu_policy_matrix.ps1
	test -f scripts/run_fpga_vpu_subsystem_power.ps1
	test -f sw/baremetal/sap_vpu_custom.h
	test -f sw/baremetal/hello.S
	test -f sw/baremetal/vpu_smoke.S
	test -f sw/baremetal/tiled_gemm_soc_smoke.S
	test -f sw/baremetal/tiled_gemm_dma_soc_smoke.S
	test -f sw/baremetal/tinyvit_fc1_k128_smoke.S
	test -f sw/baremetal/tinyvit_mlp_smoke.S
	test -f sw/baremetal/fixtures/tinyvit_mlp2_smoke.json
	test -f sw/baremetal/fixtures/tinyvit_mlp2_checkpoint.json
	test -f sw/baremetal/fixtures/tinyvit_mlp2_activation.json
	test -f sw/baremetal/link.ld
	test -x scripts/bin_to_verilog_hex.py
	test -x scripts/summarize_tinyvit_counters.py
	test -x scripts/prepare_tinyvit_mlp2_fixture.py
	test -x scripts/export_tinyvit_checkpoint_fixture.py
	test -x scripts/export_tinyvit_activation_fixture.py
	test -x scripts/evaluate_tinyvit_fc2_sparsity.py
	test -x scripts/prepare_tinyvit_fc1_k128.py
	test -x scripts/prepare_tinyvit_fc2_k512.py
	test -x scripts/check_tinyvit_fc2_window_aggregate.py
	test -x scripts/check_tiled_gemm_reference.py
	test -f docs/SAP_VPU_MODEL_MAPPING_CONTRACT.md
	test -f scripts/vivado_vpu_synth.tcl
	test -f scripts/vivado_vpu_write_funcsim.tcl
	test -f scripts/vivado_vpu_saif_power.tcl
	test -x scripts/summarize_vivado_reports.py
	test -f scripts/dc_vpu_synth.tcl
	test -x scripts/run_dc_vpu_synth.sh
	test -x scripts/run_dc_vpu_policy_matrix.sh
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

lint-tiled-gemm:
	$(VERILATOR) --lint-only -sv --top-module sap_vpu_tiled_gemm -Wno-fatal \
	  rtl/sap_vpu_pkg.sv rtl/sap_vpu_tiled_gemm.sv

lint-subsystem:
	$(VERILATOR) --lint-only -sv --top-module sap_vpu_subsystem -Wno-fatal $(SAP_VPU_SOC_RTL)

lint: lint-adapter lint-core lint-tiled-gemm lint-subsystem

lint-corev-soc: corev-rtl-flist
	DESIGN_RTL_DIR="$(COREV_DIR)/rtl" $(VERILATOR) --lint-only -sv \
	  -DCOREV_ASSERT_OFF --top-module corev_min_soc -Wno-fatal \
	  -Wno-BLKANDNBLK -Wno-TIMESCALEMOD -Wno-UNOPTFLAT \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT \
	  -Wno-ASCRANGE -Wno-IMPLICIT -Wno-UNSIGNED -Wno-COMBDLY \
	  -f "$(COREV_RTL_FLIST)" \
	  $(SAP_VPU_SOC_RTL) \
	  platforms/corev/rtl/cvxif_sap_vpu_adapter.sv \
	  platforms/corev/rtl/corev_min_soc.sv

sim-adapter:
	mkdir -p "$(SIM_DIR)"
	$(VERILATOR) --binary -sv \
	  rtl/sap_vpu_pkg.sv \
	  platforms/corev/rtl/cvxif_sap_vpu_adapter.sv \
	  tb/cvxif_sap_vpu_adapter_tb.sv \
	  --Mdir "$(SIM_DIR)/adapter_obj" \
	  -MAKEFLAGS "CXX=$(VERILATOR_CXX)" \
	  -CFLAGS "$(VERILATOR_TIMING_CFLAGS)" \
	  -LDFLAGS "$(VERILATOR_TIMING_LDFLAGS)" \
	  -o cvxif_sap_vpu_adapter_tb
	"$(SIM_DIR)/adapter_obj/cvxif_sap_vpu_adapter_tb"

sim-core:
	mkdir -p "$(SIM_DIR)"
	$(VERILATOR) --binary --timing --assert -sv -DSAP_VPU_TRACE_TIMING \
	  rtl/sap_vpu_pkg.sv \
	  rtl/sap_vpu_core.sv \
	  tb/sap_vpu_core_tb.sv \
	  --Mdir "$(SIM_DIR)/core_obj" \
	  -MAKEFLAGS "CXX=$(VERILATOR_CXX)" \
	  -CFLAGS "$(VERILATOR_TIMING_CFLAGS)" \
	  -LDFLAGS "$(VERILATOR_TIMING_LDFLAGS)" \
	  -o sap_vpu_core_tb
	"$(SIM_DIR)/core_obj/sap_vpu_core_tb"

sim-tiled-gemm:
	mkdir -p "$(SIM_DIR)"
	$(VERILATOR) --binary --timing -sv --top-module sap_vpu_tiled_gemm_tb -Wno-fatal \
	  rtl/sap_vpu_pkg.sv \
	  rtl/sap_vpu_core.sv \
	  rtl/sap_vpu_tiled_gemm.sv \
	  tb/sap_vpu_tiled_gemm_tb.sv \
	  --Mdir "$(SIM_DIR)/tiled_gemm_obj" \
	  -MAKEFLAGS "CXX=$(VERILATOR_CXX)" \
	  -CFLAGS "$(VERILATOR_TIMING_CFLAGS)" \
	  -LDFLAGS "$(VERILATOR_TIMING_LDFLAGS)" \
	  -o sap_vpu_tiled_gemm_tb
	"$(SIM_DIR)/tiled_gemm_obj/sap_vpu_tiled_gemm_tb"

tiled-gemm-rtl-check: lint-tiled-gemm sim-tiled-gemm

sim-core-vcd:
	mkdir -p "$(SIM_DIR)" "$(VPU_CORE_ACTIVITY_DIR)"
	$(VERILATOR) --binary --timing --trace -sv -DSAP_VPU_TRACE_TIMING \
	  rtl/sap_vpu_pkg.sv \
	  rtl/sap_vpu_core.sv \
	  tb/sap_vpu_core_tb.sv \
	  --Mdir "$(SIM_DIR)/core_vcd_obj" \
	  -MAKEFLAGS "CXX=$(VERILATOR_CXX)" \
	  -CFLAGS "$(VERILATOR_TIMING_CFLAGS)" \
	  -LDFLAGS "$(VERILATOR_TIMING_LDFLAGS)" \
	  -o sap_vpu_core_tb
	"$(SIM_DIR)/core_vcd_obj/sap_vpu_core_tb" +vcd="$(VPU_CORE_VCD)"
	test -s "$(VPU_CORE_VCD)"

sim-hello: hello-build corev-rtl-flist
	mkdir -p "$(SIM_DIR)"
	DESIGN_RTL_DIR="$(COREV_DIR)/rtl" $(VERILATOR) --binary --timing -sv \
	  -DCOREV_ASSERT_OFF --top-module corev_min_soc_hello_tb -Wno-fatal \
	  -Wno-BLKANDNBLK -Wno-TIMESCALEMOD -Wno-UNOPTFLAT \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT \
	  -Wno-ASCRANGE -Wno-IMPLICIT -Wno-UNSIGNED -Wno-COMBDLY \
	  --output-split $(VERILATOR_OUTPUT_SPLIT) --output-split-cfuncs $(VERILATOR_OUTPUT_SPLIT_CFUNCS) \
	  -f "$(COREV_RTL_FLIST)" \
	  $(SAP_VPU_SOC_RTL) \
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
	  $(SAP_VPU_SOC_RTL) \
	  platforms/corev/rtl/cvxif_sap_vpu_adapter.sv \
	  platforms/corev/rtl/corev_min_soc.sv \
	  tb/corev_min_soc_vpu_tb.sv \
	  --Mdir "$(SIM_DIR)/vpu_obj" \
	  -MAKEFLAGS "CXX=$(VERILATOR_CXX)" \
	  -CFLAGS "$(VERILATOR_TIMING_CFLAGS)" \
	  -LDFLAGS "$(VERILATOR_TIMING_LDFLAGS)" \
	  -o corev_min_soc_vpu_tb
	"$(SIM_DIR)/vpu_obj/corev_min_soc_vpu_tb"

sim-tiled-gemm-soc: tiled-gemm-soc-build corev-rtl-flist
	mkdir -p "$(SIM_DIR)"
	DESIGN_RTL_DIR="$(COREV_DIR)/rtl" $(VERILATOR) --binary --timing -sv \
	  -DCOREV_ASSERT_OFF --top-module corev_min_soc_tiled_gemm_tb -Wno-fatal \
	  -Wno-BLKANDNBLK -Wno-TIMESCALEMOD -Wno-UNOPTFLAT \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT \
	  -Wno-ASCRANGE -Wno-IMPLICIT -Wno-UNSIGNED -Wno-COMBDLY \
	  --output-split $(VERILATOR_OUTPUT_SPLIT) --output-split-cfuncs $(VERILATOR_OUTPUT_SPLIT_CFUNCS) \
	  -f "$(COREV_RTL_FLIST)" \
	  $(SAP_VPU_SOC_RTL) \
	  platforms/corev/rtl/cvxif_sap_vpu_adapter.sv \
	  platforms/corev/rtl/corev_min_soc.sv \
	  tb/corev_min_soc_tiled_gemm_tb.sv \
	  --Mdir "$(SIM_DIR)/tiled_gemm_soc_obj" \
	  -MAKEFLAGS "CXX=$(VERILATOR_CXX)" \
	  -CFLAGS "$(VERILATOR_TIMING_CFLAGS)" \
	  -LDFLAGS "$(VERILATOR_TIMING_LDFLAGS)" \
	  -o corev_min_soc_tiled_gemm_tb
	"$(SIM_DIR)/tiled_gemm_soc_obj/corev_min_soc_tiled_gemm_tb"

sim-tiled-gemm-dma-soc: tiled-gemm-dma-soc-build corev-rtl-flist
	mkdir -p "$(SIM_DIR)"
	DESIGN_RTL_DIR="$(COREV_DIR)/rtl" $(VERILATOR) --binary --timing -sv \
	  -DCOREV_ASSERT_OFF --top-module corev_min_soc_tiled_gemm_dma_tb -Wno-fatal \
	  -Wno-BLKANDNBLK -Wno-TIMESCALEMOD -Wno-UNOPTFLAT \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT \
	  -Wno-ASCRANGE -Wno-IMPLICIT -Wno-UNSIGNED -Wno-COMBDLY \
	  --output-split $(VERILATOR_OUTPUT_SPLIT) --output-split-cfuncs $(VERILATOR_OUTPUT_SPLIT_CFUNCS) \
	  -f "$(COREV_RTL_FLIST)" \
	  $(SAP_VPU_SOC_RTL) \
	  platforms/corev/rtl/cvxif_sap_vpu_adapter.sv \
	  platforms/corev/rtl/corev_min_soc.sv \
	  tb/corev_min_soc_tiled_gemm_dma_tb.sv \
	  --Mdir "$(SIM_DIR)/tiled_gemm_dma_soc_obj" \
	  -MAKEFLAGS "CXX=$(VERILATOR_CXX)" \
	  -CFLAGS "$(VERILATOR_TIMING_CFLAGS)" \
	  -LDFLAGS "$(VERILATOR_TIMING_LDFLAGS)" \
	  -o corev_min_soc_tiled_gemm_dma_tb
	"$(SIM_DIR)/tiled_gemm_dma_soc_obj/corev_min_soc_tiled_gemm_dma_tb"

sim-tinyvit-fc1-k128: tinyvit-fc1-k128-build corev-rtl-flist
	mkdir -p "$(SIM_DIR)"
	DESIGN_RTL_DIR="$(COREV_DIR)/rtl" $(VERILATOR) --binary --timing -sv \
	  -DCOREV_ASSERT_OFF --top-module corev_min_soc_tiled_gemm_dma_tb -Wno-fatal \
	  -GROM_INIT_FILE=\"$(TINYVIT_FC1_K128_HEX)\" \
	  -Wno-BLKANDNBLK -Wno-TIMESCALEMOD -Wno-UNOPTFLAT \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT \
	  -Wno-ASCRANGE -Wno-IMPLICIT -Wno-UNSIGNED -Wno-COMBDLY \
	  --output-split $(VERILATOR_OUTPUT_SPLIT) --output-split-cfuncs $(VERILATOR_OUTPUT_SPLIT_CFUNCS) \
	  -f "$(COREV_RTL_FLIST)" \
	  $(SAP_VPU_SOC_RTL) \
	  platforms/corev/rtl/cvxif_sap_vpu_adapter.sv \
	  platforms/corev/rtl/corev_min_soc.sv \
	  tb/corev_min_soc_tiled_gemm_dma_tb.sv \
	  --Mdir "$(SIM_DIR)/tinyvit_fc1_k128_obj" \
	  -MAKEFLAGS "CXX=$(VERILATOR_CXX)" \
	  -CFLAGS "$(VERILATOR_TIMING_CFLAGS)" \
	  -LDFLAGS "$(VERILATOR_TIMING_LDFLAGS)" \
	  -o corev_min_soc_tinyvit_fc1_k128_tb
	set -e; for window in $(TINYVIT_FC1_K128_WINDOWS); do \
	  log="$(TINYVIT_FC1_K128_BUILD_DIR)/tinyvit_fc1_k128_window$${window}.log"; \
	  "$(SIM_DIR)/tinyvit_fc1_k128_obj/corev_min_soc_tinyvit_fc1_k128_tb" \
	    +ram_init="$(TINYVIT_FC1_K128_BUILD_DIR)/tinyvit_fc1_k128_ram_window$${window}.hex" > "$${log}"; \
	  cat "$${log}"; \
	done
	$(PYTHON) scripts/check_tinyvit_fc2_window_aggregate.py \
	  "$(TINYVIT_FIXTURE_JSON)" \
	  $(foreach window,$(TINYVIT_FC1_K128_WINDOWS),"$(TINYVIT_FC1_K128_BUILD_DIR)/tinyvit_fc1_k128_window$(window).log")

sim-tinyvit: tinyvit-build corev-rtl-flist
	mkdir -p "$(SIM_DIR)" "$(dir $(TINYVIT_COUNTER_CSV))"
	DESIGN_RTL_DIR="$(COREV_DIR)/rtl" $(VERILATOR) --binary --timing -sv \
	  -DCOREV_ASSERT_OFF --top-module corev_min_soc_tinyvit_tb -Wno-fatal \
	  -GROM_INIT_FILE=\"$(TINYVIT_HEX)\" \
	  -I"$(TINYVIT_FIXTURE_DIR)" \
	  -Wno-BLKANDNBLK -Wno-TIMESCALEMOD -Wno-UNOPTFLAT \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT \
	  -Wno-ASCRANGE -Wno-IMPLICIT -Wno-UNSIGNED -Wno-COMBDLY \
	  --output-split $(VERILATOR_OUTPUT_SPLIT) --output-split-cfuncs $(VERILATOR_OUTPUT_SPLIT_CFUNCS) \
	  -f "$(COREV_RTL_FLIST)" \
	  $(SAP_VPU_SOC_RTL) \
	  platforms/corev/rtl/cvxif_sap_vpu_adapter.sv \
	  platforms/corev/rtl/corev_min_soc.sv \
	  tb/corev_min_soc_tinyvit_tb.sv \
	  --Mdir "$(SIM_DIR)/tinyvit_obj" \
	  -MAKEFLAGS "CXX=$(VERILATOR_CXX)" \
	  -CFLAGS "$(VERILATOR_TIMING_CFLAGS)" \
	  -LDFLAGS "$(VERILATOR_TIMING_LDFLAGS)" \
	  -o corev_min_soc_tinyvit_tb
	"$(SIM_DIR)/tinyvit_obj/corev_min_soc_tinyvit_tb" +counter_csv="$(TINYVIT_COUNTER_CSV)"

sim-tinyvit-vcd: tinyvit-build corev-rtl-flist
	mkdir -p "$(SIM_DIR)" "$(TINYVIT_ACTIVITY_DIR)" "$(dir $(TINYVIT_COUNTER_CSV))"
	DESIGN_RTL_DIR="$(COREV_DIR)/rtl" $(VERILATOR) --binary --timing --trace -sv \
	  -DCOREV_ASSERT_OFF --top-module corev_min_soc_tinyvit_tb -Wno-fatal \
	  -GROM_INIT_FILE=\"$(TINYVIT_HEX)\" \
	  -I"$(TINYVIT_FIXTURE_DIR)" \
	  -Wno-BLKANDNBLK -Wno-TIMESCALEMOD -Wno-UNOPTFLAT \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT \
	  -Wno-ASCRANGE -Wno-IMPLICIT -Wno-UNSIGNED -Wno-COMBDLY \
	  --output-split $(VERILATOR_OUTPUT_SPLIT) --output-split-cfuncs $(VERILATOR_OUTPUT_SPLIT_CFUNCS) \
	  -f "$(COREV_RTL_FLIST)" \
	  $(SAP_VPU_SOC_RTL) \
	  platforms/corev/rtl/cvxif_sap_vpu_adapter.sv \
	  platforms/corev/rtl/corev_min_soc.sv \
	  tb/corev_min_soc_tinyvit_tb.sv \
	  --Mdir "$(SIM_DIR)/tinyvit_vcd_obj" \
	  -MAKEFLAGS "CXX=$(VERILATOR_CXX)" \
	  -CFLAGS "$(VERILATOR_TIMING_CFLAGS)" \
	  -LDFLAGS "$(VERILATOR_TIMING_LDFLAGS)" \
	  -o corev_min_soc_tinyvit_tb
	"$(SIM_DIR)/tinyvit_vcd_obj/corev_min_soc_tinyvit_tb" \
	  +counter_csv="$(TINYVIT_COUNTER_CSV)" +vcd="$(TINYVIT_VCD)"
	test -s "$(TINYVIT_VCD)"

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

tiled-gemm-soc-build:
	mkdir -p "$(TILED_GEMM_SOC_BUILD_DIR)"
	$(RISCV_AS) -march=rv32imc -mabi=ilp32 \
	  -o "$(TILED_GEMM_SOC_BUILD_DIR)/tiled_gemm_soc_smoke.o" sw/baremetal/tiled_gemm_soc_smoke.S
	$(RISCV_LD) -m elf32lriscv -T sw/baremetal/link.ld \
	  -o "$(TILED_GEMM_SOC_ELF)" "$(TILED_GEMM_SOC_BUILD_DIR)/tiled_gemm_soc_smoke.o"
	$(RISCV_OBJCOPY) -O binary "$(TILED_GEMM_SOC_ELF)" "$(TILED_GEMM_SOC_BIN)"
	$(PYTHON) scripts/bin_to_verilog_hex.py "$(TILED_GEMM_SOC_BIN)" "$(TILED_GEMM_SOC_HEX)"

tiled-gemm-soc-smoke: sim-tiled-gemm-soc lint-corev-soc
	test -s "$(TILED_GEMM_SOC_HEX)"

tiled-gemm-dma-soc-build:
	mkdir -p "$(TILED_GEMM_DMA_SOC_BUILD_DIR)"
	$(RISCV_AS) -march=rv32imc -mabi=ilp32 \
	  -o "$(TILED_GEMM_DMA_SOC_BUILD_DIR)/tiled_gemm_dma_soc_smoke.o" sw/baremetal/tiled_gemm_dma_soc_smoke.S
	$(RISCV_LD) -m elf32lriscv -T sw/baremetal/link.ld \
	  -o "$(TILED_GEMM_DMA_SOC_ELF)" "$(TILED_GEMM_DMA_SOC_BUILD_DIR)/tiled_gemm_dma_soc_smoke.o"
	$(RISCV_OBJCOPY) -O binary "$(TILED_GEMM_DMA_SOC_ELF)" "$(TILED_GEMM_DMA_SOC_BIN)"
	$(PYTHON) scripts/bin_to_verilog_hex.py "$(TILED_GEMM_DMA_SOC_BIN)" "$(TILED_GEMM_DMA_SOC_HEX)"

tiled-gemm-dma-soc-smoke: sim-tiled-gemm-dma-soc lint-corev-soc
	test -s "$(TILED_GEMM_DMA_SOC_HEX)"

tinyvit-fc1-k128-fixture:
	mkdir -p "$(TINYVIT_FC1_K128_BUILD_DIR)"
	set -e; for window in $(TINYVIT_FC1_K128_WINDOWS); do \
	  $(PYTHON) scripts/prepare_tinyvit_fc1_k128.py "$(TINYVIT_FIXTURE_JSON)" \
	    --asm "$(TINYVIT_FC1_K128_ASM)" \
	    --svh "$(TINYVIT_FC1_K128_SVH)" \
	    --ram-hex "$(TINYVIT_FC1_K128_BUILD_DIR)/tinyvit_fc1_k128_ram_window$${window}.hex" \
	    --window "$${window}"; \
	done

tinyvit-fc2-k512-fixture:
	mkdir -p "$(TINYVIT_FC2_K512_BUILD_DIR)"
	$(PYTHON) scripts/prepare_tinyvit_fc2_k512.py "$(TINYVIT_FIXTURE_JSON)" \
	  --svh "$(TINYVIT_FC2_K512_SVH)"

tinyvit-fc1-k128-build: tinyvit-fc1-k128-fixture
	$(RISCV_AS) -I "$(TINYVIT_FC1_K128_BUILD_DIR)" -march=rv32imc -mabi=ilp32 \
	  -o "$(TINYVIT_FC1_K128_BUILD_DIR)/tinyvit_fc1_k128_smoke.o" sw/baremetal/tinyvit_fc1_k128_smoke.S
	$(RISCV_LD) -m elf32lriscv -T sw/baremetal/link.ld \
	  -o "$(TINYVIT_FC1_K128_ELF)" "$(TINYVIT_FC1_K128_BUILD_DIR)/tinyvit_fc1_k128_smoke.o"
	$(RISCV_OBJCOPY) -O binary "$(TINYVIT_FC1_K128_ELF)" "$(TINYVIT_FC1_K128_BIN)"
	$(PYTHON) scripts/bin_to_verilog_hex.py "$(TINYVIT_FC1_K128_BIN)" "$(TINYVIT_FC1_K128_HEX)"

tinyvit-fc1-k128-smoke: sim-tinyvit-fc1-k128 lint-corev-soc
	test -s "$(TINYVIT_FC1_K128_HEX)"
	set -e; for window in $(TINYVIT_FC1_K128_WINDOWS); do \
	  test -s "$(TINYVIT_FC1_K128_BUILD_DIR)/tinyvit_fc1_k128_ram_window$${window}.hex"; \
	  test -s "$(TINYVIT_FC1_K128_BUILD_DIR)/tinyvit_fc1_k128_window$${window}.log"; \
	done

tinyvit-checkpoint-fixture:
	$(PYTHON) scripts/export_tinyvit_checkpoint_fixture.py \
	  "$(TINYVIT_CHECKPOINT)" "$(TINYVIT_CHECKPOINT_FIXTURE)"

tinyvit-activation-fixture:
	$(TINYVIT_MODEL_PYTHON) scripts/export_tinyvit_activation_fixture.py \
	  "$(TINYVIT_CHECKPOINT)" "$(TINYVIT_IMAGE)" "$(TINYVIT_ACTIVATION_FIXTURE)"

tinyvit-sparsity-study:
	$(TINYVIT_MODEL_PYTHON) scripts/evaluate_tinyvit_fc2_sparsity.py --self-test
	$(TINYVIT_MODEL_PYTHON) scripts/evaluate_tinyvit_fc2_sparsity.py \
	  "$(TINYVIT_CHECKPOINT)" "$(TINYVIT_EVAL_IMAGE_DIR)" "$(TINYVIT_SPARSITY_STUDY)"
	test -s "$(TINYVIT_SPARSITY_STUDY)"

tinyvit-fixture:
	mkdir -p "$(TINYVIT_FIXTURE_DIR)"
	$(PYTHON) scripts/prepare_tinyvit_mlp2_fixture.py "$(TINYVIT_FIXTURE_JSON)" \
	  --asm "$(TINYVIT_FIXTURE_ASM)" \
	  --svh "$(TINYVIT_FIXTURE_SVH)" \
	  --metadata "$(TINYVIT_FIXTURE_METADATA)" \
	  --mapping "$(TINYVIT_FIXTURE_MAPPING)"

tinyvit-fixture-check:
	$(PYTHON) scripts/prepare_tinyvit_mlp2_fixture.py --self-test
	$(PYTHON) scripts/prepare_tinyvit_fc1_k128.py --self-test
	$(PYTHON) scripts/prepare_tinyvit_fc2_k512.py --self-test
	$(PYTHON) scripts/export_tinyvit_checkpoint_fixture.py --self-test

sim-subsystem-mlp2: tinyvit-fixture tinyvit-fc1-k128-fixture tinyvit-fc2-k512-fixture
	mkdir -p "$(SIM_DIR)/subsystem_mlp2_obj"
	$(VERILATOR) --binary --timing -sv --top-module sap_vpu_subsystem_gate_tb -Wno-fatal \
	  -I"$(TINYVIT_FIXTURE_DIR)" -I"$(TINYVIT_FC1_K128_BUILD_DIR)" -I"$(TINYVIT_FC2_K512_BUILD_DIR)" \
	  $(SAP_VPU_SOC_RTL) tb/sap_vpu_subsystem_gate_tb.sv \
	  --Mdir "$(SIM_DIR)/subsystem_mlp2_obj" \
	  -MAKEFLAGS "CXX=clang++-12" \
	  -CFLAGS "-std=c++20 -O0 -Wno-unknown-warning-option" \
	  -LDFLAGS "-no-pie" \
	  -o sap_vpu_subsystem_mlp2_tb
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1

sim-subsystem-sparse-policies: sim-subsystem-mlp2
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_dense
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_global_l1_6p25
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_l1_budget_2pct

sim-subsystem-k512-policies: sim-subsystem-mlp2
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_k512_dense
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_k512_global_l1_6p25
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_k512_l1_budget_2pct

sim-subsystem-k512-pair-policies: sim-subsystem-mlp2
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_k512_pairs_dense
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_k512_pairs_global_l1_6p25
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_k512_pairs_l1_budget_1pct

sim-subsystem-k512-stream: sim-subsystem-mlp2
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_k512_stream_dense
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_k512_stream_global_l1_6p25
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_k512_stream_l1_budget_2pct
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_k512_stream_pairs_dense
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_k512_stream_pairs_global_l1_12p5
	"$(SIM_DIR)/subsystem_mlp2_obj/sap_vpu_subsystem_mlp2_tb" +iterations=1 +policy=fc2_k512_stream_pairs_l1_budget_5pct

tiled-gemm-check:
	$(PYTHON) scripts/check_tiled_gemm_reference.py

tinyvit-build: tinyvit-fixture
	mkdir -p "$(TINYVIT_BUILD_DIR)"
	$(RISCV_AS) -I "$(TINYVIT_FIXTURE_DIR)" -march=rv32imc -mabi=ilp32 \
	  -o "$(TINYVIT_BUILD_DIR)/tinyvit_mlp_smoke.o" sw/baremetal/tinyvit_mlp_smoke.S
	$(RISCV_LD) -m elf32lriscv --defsym=__rom_length=8192 -T sw/baremetal/link.ld \
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
	cd "$(FPGA_BUILD_DIR)" && $(VIVADO) -mode batch -source "$(ROOT_DIR)/scripts/vivado_vpu_synth.tcl" \
	  -tclargs "$(FPGA_PART)" "$(FPGA_CLOCK_MHZ)" "$(FPGA_BUILD_DIR)" "$(FPGA_TOP)" "$(FPGA_OUT_OF_CONTEXT)"

fpga-vpu-funcsim-netlist:
	test -s "$(FPGA_FUNCSIM_DCP)"
	mkdir -p "$(FPGA_FUNCSIM_DIR)"
	cd "$(FPGA_FUNCSIM_DIR)" && $(VIVADO) -mode batch -source "$(ROOT_DIR)/scripts/vivado_vpu_write_funcsim.tcl" \
	  -tclargs "$(FPGA_FUNCSIM_DCP)" "$(FPGA_FUNCSIM_DIR)"

fpga-vpu-funcsim-vcd: fpga-vpu-funcsim-netlist
	mkdir -p "$(FPGA_FUNCSIM_XSIM_DIR)"
	cd "$(FPGA_FUNCSIM_XSIM_DIR)" && \
	  $(XVLOG) -sv "$(ROOT_DIR)/rtl/sap_vpu_pkg.sv" "$(ROOT_DIR)/tb/sap_vpu_core_gate_tb.sv" "$(FPGA_FUNCSIM_DIR)/sap_vpu_core_funcsim.v" && \
	  $(XELAB) -debug typical -L unisims_ver sap_vpu_core_gate_tb glbl -s sap_vpu_core_gate_tb_snapshot && \
	  $(XSIM) --nolog -R sap_vpu_core_gate_tb_snapshot | tee xsim.log
	grep -q "GATE_SMOKE_PASS" "$(FPGA_FUNCSIM_XSIM_DIR)/xsim.log"
	! grep -q "GATE_SMOKE_FAIL" "$(FPGA_FUNCSIM_XSIM_DIR)/xsim.log"
	test -s "$(FPGA_FUNCSIM_VCD)"

fpga-vpu-funcsim-saif: fpga-vpu-funcsim-vcd
	$(VCD2SAIF) -input "$(FPGA_FUNCSIM_VCD)" -output "$(FPGA_FUNCSIM_SAIF)"
	test -s "$(FPGA_FUNCSIM_SAIF)"

fpga-vpu-funcsim-saif-power: fpga-vpu-funcsim-saif
	test -s "$(FPGA_SAIF_DCP)"
	mkdir -p "$(FPGA_FUNCSIM_SAIF_POWER_DIR)"
	cd "$(FPGA_FUNCSIM_SAIF_POWER_DIR)" && $(VIVADO) -mode batch -source "$(ROOT_DIR)/scripts/vivado_vpu_saif_power.tcl" \
	  -tclargs "$(FPGA_SAIF_DCP)" "$(FPGA_FUNCSIM_SAIF)" "$(FPGA_FUNCSIM_SAIF_POWER_DIR)" "$(FPGA_SAIF_STRIP_PATH)"

fpga-vpu-policy-power-matrix:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass \
	  -File scripts/run_fpga_vpu_policy_matrix.ps1 \
	  -VivadoRoot '$(VIVADO_ROOT_WINDOWS)' \
	  -OutDir '$(FPGA_POLICY_POWER_DIR)' \
	  -Dcp '$(FPGA_POLICY_DCP)' \
	  -Netlist '$(FPGA_POLICY_NETLIST)' \
	  -ClockMhz '$(FPGA_POLICY_CLOCK_MHZ)'

fpga-vpu-subsystem-saif-power: tinyvit-fixture tinyvit-fc1-k128-fixture tinyvit-fc2-k512-fixture
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass \
	  -File scripts/run_fpga_vpu_subsystem_power.ps1 \
	  -VivadoRoot '$(VIVADO_ROOT_WINDOWS)' \
	  -OutDir '$(FPGA_SUBSYSTEM_POWER_DIR)' \
	  -PostSynthDcp '$(FPGA_SUBSYSTEM_POST_SYNTH_DCP)' \
	  -PostRouteDcp '$(FPGA_SUBSYSTEM_POST_ROUTE_DCP)' \
	  -ClockMhz '$(FPGA_SUBSYSTEM_CLOCK_MHZ)' \
	  -Iterations '$(FPGA_SUBSYSTEM_ITERATIONS)'

fpga-vpu-subsystem-policy-power-matrix: tinyvit-fixture tinyvit-fc1-k128-fixture tinyvit-fc2-k512-fixture
	set -e; for policy in fc2_dense fc2_global_l1_6p25 fc2_l1_budget_2pct; do \
	  $(POWERSHELL) -NoProfile -ExecutionPolicy Bypass \
	    -File scripts/run_fpga_vpu_subsystem_power.ps1 \
	    -VivadoRoot '$(VIVADO_ROOT_WINDOWS)' \
	    -OutDir '$(FPGA_SUBSYSTEM_POLICY_POWER_DIR)'/$$policy \
	    -PostSynthDcp '$(FPGA_SUBSYSTEM_POST_SYNTH_DCP)' \
	    -PostRouteDcp '$(FPGA_SUBSYSTEM_POST_ROUTE_DCP)' \
	    -ClockMhz '$(FPGA_SUBSYSTEM_CLOCK_MHZ)' \
	    -Iterations '$(FPGA_SUBSYSTEM_POLICY_ITERATIONS)' \
	    -Policy $$policy; \
	done

fpga-vpu-subsystem-k512-policy-power-matrix: tinyvit-fixture tinyvit-fc1-k128-fixture tinyvit-fc2-k512-fixture
	set -e; for policy in fc2_k512_dense fc2_k512_global_l1_6p25 fc2_k512_l1_budget_2pct; do \
	  $(POWERSHELL) -NoProfile -ExecutionPolicy Bypass \
	    -File scripts/run_fpga_vpu_subsystem_power.ps1 \
	    -VivadoRoot '$(VIVADO_ROOT_WINDOWS)' \
	    -OutDir '$(FPGA_SUBSYSTEM_K512_POLICY_POWER_DIR)'/$$policy \
	    -PostSynthDcp '$(FPGA_SUBSYSTEM_POST_SYNTH_DCP)' \
	    -PostRouteDcp '$(FPGA_SUBSYSTEM_POST_ROUTE_DCP)' \
	    -ClockMhz '$(FPGA_SUBSYSTEM_CLOCK_MHZ)' \
	    -Iterations '$(FPGA_SUBSYSTEM_K512_POLICY_ITERATIONS)' \
	    -Policy $$policy; \
	done

fpga-vpu-subsystem-k512-pair-policy-power-matrix: tinyvit-fixture tinyvit-fc1-k128-fixture tinyvit-fc2-k512-fixture
	set -e; for policy in fc2_k512_pairs_dense fc2_k512_pairs_global_l1_6p25 fc2_k512_pairs_l1_budget_1pct; do \
	  $(POWERSHELL) -NoProfile -ExecutionPolicy Bypass \
	    -File scripts/run_fpga_vpu_subsystem_power.ps1 \
	    -VivadoRoot '$(VIVADO_ROOT_WINDOWS)' \
	    -OutDir '$(FPGA_SUBSYSTEM_K512_PAIR_POLICY_POWER_DIR)'/$$policy \
	    -PostSynthDcp '$(FPGA_SUBSYSTEM_POST_SYNTH_DCP)' \
	    -PostRouteDcp '$(FPGA_SUBSYSTEM_POST_ROUTE_DCP)' \
	    -ClockMhz '$(FPGA_SUBSYSTEM_CLOCK_MHZ)' \
	    -Iterations '$(FPGA_SUBSYSTEM_K512_PAIR_POLICY_ITERATIONS)' \
	    -Policy $$policy; \
	done

fpga-vpu-subsystem-k512-stream-policy-power-matrix: tinyvit-fixture tinyvit-fc1-k128-fixture tinyvit-fc2-k512-fixture
	set -e; for policy in fc2_k512_stream_pairs_dense fc2_k512_stream_pairs_global_l1_12p5 fc2_k512_stream_pairs_l1_budget_5pct; do \
	  $(POWERSHELL) -NoProfile -ExecutionPolicy Bypass \
	    -File scripts/run_fpga_vpu_subsystem_power.ps1 \
	    -VivadoRoot '$(VIVADO_ROOT_WINDOWS)' \
	    -OutDir '$(FPGA_SUBSYSTEM_K512_STREAM_POLICY_POWER_DIR)'/$$policy \
	    -PostSynthDcp '$(FPGA_SUBSYSTEM_POST_SYNTH_DCP)' \
	    -PostRouteDcp '$(FPGA_SUBSYSTEM_POST_ROUTE_DCP)' \
	    -ClockMhz '$(FPGA_SUBSYSTEM_CLOCK_MHZ)' \
	    -Iterations '$(FPGA_SUBSYSTEM_K512_STREAM_POLICY_ITERATIONS)' \
	    -Policy $$policy; \
	done

fpga-vpu-saif-power: sim-core-vcd
	$(VCD2SAIF) -input "$(VPU_CORE_VCD)" -output "$(VPU_CORE_SAIF)"
	test -s "$(VPU_CORE_SAIF)"
	test -s "$(FPGA_SAIF_DCP)"
	mkdir -p "$(FPGA_SAIF_POWER_DIR)"
	cd "$(FPGA_SAIF_POWER_DIR)" && $(VIVADO) -mode batch -source "$(ROOT_DIR)/scripts/vivado_vpu_saif_power.tcl" \
	  -tclargs "$(FPGA_SAIF_DCP)" "$(VPU_CORE_SAIF)" "$(FPGA_SAIF_POWER_DIR)" "$(FPGA_SAIF_STRIP_PATH)"

fpga-vpu-summary:
	$(PYTHON) scripts/summarize_vivado_reports.py "$(FPGA_BUILD_DIR)"

dc-vpu-gate-netlist-check:
	test -s "$(DC_NETLIST_DIR)/sap_vpu_core.v"
	@if grep -n "SYNOPSYS_UNCONNECTED" "$(DC_NETLIST_DIR)/sap_vpu_core.v"; then \
	  echo "Gate netlist has unconnected outputs; do not generate gate-level SAIF." >&2; \
	  exit 1; \
	fi

dc-vpu-gate-synth:
	COMPILE_ULTRA=0 CLOCK_PERIOD="$(DC_CLOCK_PERIOD)" \
	  WORK_DIR="$(DC_GATE_WORK_DIR)" REPORT_DIR="$(DC_GATE_REPORT_DIR)" NETLIST_DIR="$(DC_GATE_NETLIST_DIR)" \
	  scripts/run_dc_vpu_synth.sh
	$(MAKE) dc-vpu-gate-netlist-check DC_NETLIST_DIR="$(DC_GATE_NETLIST_DIR)"

dc-vpu-gate-sim:
	test -s "$(abspath $(DC_GATE_NETLIST_DIR))/sap_vpu_core.ddc"
	$(MAKE) dc-vpu-gate-netlist-check DC_NETLIST_DIR="$(abspath $(DC_GATE_NETLIST_DIR))"
	test -f "$(SYNOPSYS_ENV_FILE)"
	test -x "$(VCS_MX)"
	test -s "$(TSMC28_VERILOG)"
	mkdir -p "$(abspath $(DC_GATE_SIM_DIR))"
	source "$(SYNOPSYS_ENV_FILE)"; lmstart || true; \
	cd "$(abspath $(DC_GATE_SIM_DIR))" && \
	  VCS_HOME="$(VCS_MX_HOME)" VCS_ARCH_OVERRIDE=linux "$(VCS_MX)" -full64 -sverilog \
	  -LDFLAGS "-Wl,--no-as-needed" -o simv \
	  "$(ROOT_DIR)/rtl/sap_vpu_pkg.sv" "$(ROOT_DIR)/tb/sap_vpu_core_gate_tb.sv" \
	  "$(TSMC28_VERILOG)" "$(abspath $(DC_GATE_NETLIST_DIR))/sap_vpu_core.v" && \
	  ./simv | tee gate.log
	grep -q "GATE_SMOKE_PASS" "$(abspath $(DC_GATE_SIM_DIR))/gate.log"
	test -s "$(abspath $(DC_GATE_VCD))"

dc-vpu-gate-saif-power: dc-vpu-gate-sim
	"$(VCD2SAIF)" -input "$(abspath $(DC_GATE_VCD))" -output "$(abspath $(DC_GATE_SAIF))" -instance sap_vpu_core_gate_tb/dut
	test -s "$(abspath $(DC_GATE_SAIF))"
	POWER_ONLY=1 CLOCK_PERIOD="$(DC_CLOCK_PERIOD)" \
	  WORK_DIR="$(DC_GATE_POWER_WORK_DIR)" REPORT_DIR="$(DC_GATE_POWER_REPORT_DIR)" NETLIST_DIR="$(DC_GATE_NETLIST_DIR)" \
	  DDC_FILE="$(abspath $(DC_GATE_NETLIST_DIR))/sap_vpu_core.ddc" SAIF_FILE="$(abspath $(DC_GATE_SAIF))" \
	  SAIF_INSTANCE="sap_vpu_core_gate_tb/dut" scripts/run_dc_vpu_synth.sh
	! grep -q "PWR-452" "$(DC_GATE_POWER_WORK_DIR)/dc.log"

dc-vpu-precheck:
	PRECHECK_ONLY=1 DESIGN_NAME="$(DC_DESIGN_NAME)" CLOCK_PERIOD="$(DC_CLOCK_PERIOD)" \
	  WORK_DIR="$(DC_WORK_DIR)" REPORT_DIR="$(DC_REPORT_DIR)" NETLIST_DIR="$(DC_NETLIST_DIR)" \
	  scripts/run_dc_vpu_synth.sh

dc-vpu-synth:
	DESIGN_NAME="$(DC_DESIGN_NAME)" CLOCK_PERIOD="$(DC_CLOCK_PERIOD)" \
	  WORK_DIR="$(DC_WORK_DIR)" REPORT_DIR="$(DC_REPORT_DIR)" NETLIST_DIR="$(DC_NETLIST_DIR)" \
	  scripts/run_dc_vpu_synth.sh

dc-vpu-power:
	POWER_ONLY=1 CLOCK_PERIOD="$(DC_CLOCK_PERIOD)" \
	  WORK_DIR="$(DC_WORK_DIR)" REPORT_DIR="$(DC_REPORT_DIR)" NETLIST_DIR="$(DC_NETLIST_DIR)" \
	  DDC_FILE="$(DC_NETLIST_DIR)/sap_vpu_core.ddc" \
	  scripts/run_dc_vpu_synth.sh

dc-vpu-saif-power: sim-core-vcd
	$(VCD2SAIF) -input "$(VPU_CORE_VCD)" -output "$(VPU_CORE_SAIF)"
	test -s "$(VPU_CORE_SAIF)"
	POWER_ONLY=1 CLOCK_PERIOD="$(DC_CLOCK_PERIOD)" \
	  WORK_DIR="$(DC_WORK_DIR)" REPORT_DIR="$(DC_REPORT_DIR)" NETLIST_DIR="$(DC_NETLIST_DIR)" \
	  DDC_FILE="$(DC_NETLIST_DIR)/sap_vpu_core.ddc" \
	  SAIF_FILE="$(VPU_CORE_SAIF)" SAIF_INSTANCE="$(SAIF_INSTANCE)" \
	  scripts/run_dc_vpu_synth.sh

dc-vpu-tinyvit-saif-power: sim-tinyvit-vcd
	$(VCD2SAIF) -input "$(TINYVIT_VCD)" -output "$(TINYVIT_SAIF)"
	test -s "$(TINYVIT_SAIF)"
	POWER_ONLY=1 CLOCK_PERIOD="$(DC_CLOCK_PERIOD)" \
	  WORK_DIR="$(DC_WORK_DIR)" REPORT_DIR="$(DC_REPORT_DIR)" NETLIST_DIR="$(DC_NETLIST_DIR)" \
	  DDC_FILE="$(DC_NETLIST_DIR)/sap_vpu_core.ddc" \
	  SAIF_FILE="$(TINYVIT_SAIF)" SAIF_INSTANCE="$(TINYVIT_SAIF_INSTANCE)" \
	  scripts/run_dc_vpu_synth.sh

dc-vpu-policy-power-matrix:
	DC_POLICY_MATRIX_WORK_DIR="$(DC_POLICY_MATRIX_WORK_DIR)" \
	  DC_POLICY_MATRIX_REPORT_DIR="$(DC_POLICY_MATRIX_REPORT_DIR)" \
	  DC_NETLIST_DIR="$(DC_POLICY_NETLIST_DIR)" \
	  scripts/run_dc_vpu_policy_matrix.sh

dc-vpu-summary:
	$(PYTHON) scripts/summarize_dc_reports.py "$(DC_WORK_DIR)" "$(DC_REPORT_DIR)"
