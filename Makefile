SHELL := /bin/bash

ROOT_DIR := $(abspath .)
COREV_DIR ?= $(ROOT_DIR)/third_party/cv32e40x
COREV_REF ?= master
VERILATOR ?= verilator
PYTHON ?= python3
SIM_DIR ?= $(ROOT_DIR)/work/sim

.DEFAULT_GOAL := help

.PHONY: help plan-check corev-fetch lint-adapter lint-core lint sim-adapter sim-core sim encoding-check legacy-summary

help:
	@printf '%s\n' \
	  'make plan-check' \
	  'make corev-fetch [COREV_DIR=third_party/cv32e40x] [COREV_REF=master]' \
	  'make lint-adapter' \
	  'make lint-core' \
	  'make sim-adapter' \
	  'make sim-core' \
	  'make encoding-check' \
	  'make legacy-summary [LEGACY_RESULTS_DIR=../nutvpu/results]'

plan-check:
	test -x scripts/fetch_corev_cv32e40x.sh
	test -f rtl/sap_vpu_pkg.sv
	test -f rtl/sap_vpu_core.sv
	test -f platforms/corev/rtl/cvxif_sap_vpu_adapter.sv
	test -f sw/baremetal/sap_vpu_custom.h
	test -f docs/SAP_VPU_RESEARCH_PLAN.md
	test -f docs/SAP_VPU_LITERATURE_MATRIX.md

corev-fetch:
	scripts/fetch_corev_cv32e40x.sh "$(COREV_DIR)" "$(COREV_REF)"

lint-adapter:
	$(VERILATOR) --lint-only -sv rtl/sap_vpu_pkg.sv platforms/corev/rtl/cvxif_sap_vpu_adapter.sv

lint-core:
	$(VERILATOR) --lint-only -sv rtl/sap_vpu_pkg.sv rtl/sap_vpu_core.sv

lint: lint-adapter lint-core

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

sim: sim-adapter sim-core

encoding-check:
	$(PYTHON) scripts/check_sap_vpu_encoding.py

legacy-summary:
	$(PYTHON) scripts/summarize_legacy_results.py "$(or $(LEGACY_RESULTS_DIR),../nutvpu/results)"
