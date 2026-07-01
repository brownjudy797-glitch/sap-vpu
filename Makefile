SHELL := /bin/bash

ROOT_DIR := $(abspath .)
COREV_DIR ?= $(ROOT_DIR)/third_party/cv32e40x
COREV_REF ?= master
VERILATOR ?= verilator

.DEFAULT_GOAL := help

.PHONY: help plan-check corev-fetch lint-adapter

help:
	@printf '%s\n' \
	  'make plan-check' \
	  'make corev-fetch [COREV_DIR=third_party/cv32e40x] [COREV_REF=master]' \
	  'make lint-adapter'

plan-check:
	test -x scripts/fetch_corev_cv32e40x.sh
	test -f platforms/corev/rtl/cvxif_sap_vpu_adapter.sv
	test -f docs/SAP_VPU_RESEARCH_PLAN.md
	test -f docs/SAP_VPU_LITERATURE_MATRIX.md

corev-fetch:
	scripts/fetch_corev_cv32e40x.sh "$(COREV_DIR)" "$(COREV_REF)"

lint-adapter:
	$(VERILATOR) --lint-only -sv platforms/corev/rtl/cvxif_sap_vpu_adapter.sv

