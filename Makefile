SHELL := /bin/bash

TB ?= tb_axi_stream_full_network_golden_flow
VITIS_DATA_DIR ?= $(CURDIR)/build/vitis_data
UVM_COVERAGE_ROOT ?= $(CURDIR)/build/uvm_coverage
VIVADO ?= $(shell command -v vivado 2>/dev/null || printf '%s' '$(HOME)/Xilinx/2026.1/Vivado/bin/vivado')
VITIS ?= $(shell command -v vitis 2>/dev/null || printf '%s' '$(HOME)/Xilinx/2026.1/Vitis/bin/vitis')
XSCT ?= $(shell command -v xsct 2>/dev/null || printf '%s' '$(HOME)/Xilinx/2026.1/Vitis/bin/xsct')
BOOTGEN ?= $(shell command -v bootgen 2>/dev/null || printf '%s' '$(HOME)/Xilinx/2026.1/Vitis/bin/bootgen')

.PHONY: xsim regression xsim-regression lint clean flow-report report-flow check-warnings docs-check preboard-proof abi-generate abi-check
.PHONY: unit tile-test programmable-runtime-test programmable-system-test randomized-package-rtl-test uvm-compile uvm-smoke uvm-closed-loop uvm-compiler-reference uvm-randomized uvm-faults uvm-u4 uvm-signoff uvm-coverage uvm-u5 uvm-protocol-ral uvm-regression numeric-runtime-test descriptor-test parameter-bank-test programmable-engine-test packed-dma-test packed-dma-runtime-test packed-dma-writer-test model-test model-package-example golden-test synth-sweep synth-report
.PHONY: top-impl top-report programmable-top-synth programmable-top-impl programmable-top-report baremetal-headers baremetal-runtime-test runtime-corpus-test vitis-app
.PHONY: zybo-z7-project zybo-z7-bitstream zybo-z7-xsa full-zybo-z7-flow
.PHONY: boot-image full-preboard-proof program-zybo-z7

xsim:
	bash scripts/run_unit_tb.sh $(TB)

xsim-regression: regression

unit:
	bash scripts/run_unit.sh

tile-test:
	bash scripts/run_unit_tb.sh tb_spatial_tile_planner
	bash scripts/run_unit_tb.sh tb_halo_tile_load_controller
	bash scripts/run_unit_tb.sh tb_tiled_layer_runtime
	bash scripts/run_unit_tb.sh tb_tiled_layer_runtime_3x3_stride2
	bash scripts/run_unit_tb.sh tb_tiled_multi_layer_controller

programmable-runtime-test:
	bash scripts/run_requantizer_tb.sh
	bash scripts/run_numeric_runtime_tb.sh
	bash scripts/run_programmable_runtime_tb.sh

numeric-runtime-test:
	bash scripts/run_requantizer_tb.sh
	bash scripts/run_numeric_runtime_tb.sh

programmable-system-test:
	bash scripts/run_programmable_system_tb.sh

randomized-package-rtl-test:
	bash scripts/run_randomized_programmable_package_tb.sh

uvm-compile:
	UVM_COMPILE_ONLY=1 bash scripts/run_uvm_xsim.sh

uvm-smoke:
	UVM_TESTNAME=cnn_uvm_smoke_test bash scripts/run_uvm_xsim.sh

uvm-closed-loop:
	UVM_TESTNAME=cnn_uvm_closed_loop_ddr_test bash scripts/run_uvm_xsim.sh

uvm-compiler-reference:
	UVM_TESTNAME=cnn_uvm_compiler_reference_test bash scripts/run_uvm_xsim.sh

uvm-randomized:
	bash scripts/run_uvm_randomized_campaign.sh

uvm-faults:
	bash scripts/run_uvm_fault_campaign.sh

uvm-u4: uvm-randomized uvm-faults

uvm-signoff:
	python3 scripts/check_uvm_signoff.py

uvm-coverage: uvm-signoff
	bash scripts/run_uvm_coverage_campaign.sh

uvm-u5: uvm-coverage
	python3 scripts/report_uvm_coverage.py \
		--coverage-root "$(UVM_COVERAGE_ROOT)" --require-targets

uvm-protocol-ral:
	UVM_TESTNAME=cnn_uvm_protocol_ral_test bash scripts/run_uvm_xsim.sh

uvm-regression:
	UVM_TESTNAME=cnn_uvm_register_access_test bash scripts/run_uvm_xsim.sh
	UVM_TESTNAME=cnn_uvm_protocol_ral_test bash scripts/run_uvm_xsim.sh
	UVM_TESTNAME=cnn_uvm_protocol_recovery_test bash scripts/run_uvm_xsim.sh
	UVM_TESTNAME=cnn_uvm_parameter_crc_recovery_test bash scripts/run_uvm_xsim.sh
	UVM_TESTNAME=cnn_uvm_reset_recovery_test bash scripts/run_uvm_xsim.sh
	UVM_TESTNAME=cnn_uvm_starvation_abort_test bash scripts/run_uvm_xsim.sh
	UVM_TESTNAME=cnn_uvm_ordering_recovery_test bash scripts/run_uvm_xsim.sh
	UVM_TESTNAME=cnn_uvm_model_replacement_test bash scripts/run_uvm_xsim.sh
	UVM_TESTNAME=cnn_uvm_interrupt_test bash scripts/run_uvm_xsim.sh
	UVM_TESTNAME=cnn_uvm_smoke_test bash scripts/run_uvm_xsim.sh
	UVM_TESTNAME=cnn_uvm_closed_loop_ddr_test bash scripts/run_uvm_xsim.sh
	UVM_TESTNAME=cnn_uvm_compiler_reference_test bash scripts/run_uvm_xsim.sh

descriptor-test:
	bash scripts/run_descriptor_controller_tb.sh

parameter-bank-test:
	bash scripts/run_parameter_banks_tb.sh

programmable-engine-test:
	bash scripts/run_programmable_engine_tb.sh

packed-dma-test:
	bash scripts/run_packed_dma_tb.sh

packed-dma-runtime-test:
	bash scripts/run_packed_dma_runtime_tb.sh

packed-dma-writer-test:
	bash scripts/run_packed_dma_writer_tb.sh

abi-generate:
	python3 scripts/generate_abi_constants.py

abi-check:
	python3 scripts/generate_abi_constants.py --check

model-test: abi-check
	python3 -m unittest discover -s tests -p 'test_*.py'

model-package-example:
	python3 models/model_compiler.py examples/models/rgb_identity.json \
		-o build/models/rgb_identity.cnn \
		--summary build/models/rgb_identity.summary.json
	python3 models/package_executor.py build/models/rgb_identity.cnn \
		examples/tensors/rgb_4x4.json \
		-o build/models/rgb_identity.output.json

golden-test:
	python3 models/generate_golden_tensors.py
	bash scripts/run_unit_tb.sh tb_golden_tensor_flow
	bash scripts/run_unit_tb.sh tb_full_network_golden_flow
	bash scripts/run_unit_tb.sh tb_stream_loaded_full_network_golden_flow
	bash scripts/run_unit_tb.sh tb_axi_stream_full_network_golden_flow

baremetal-headers:
	python3 models/generate_golden_tensors.py
	python3 scripts/generate_baremetal_golden_headers.py
	python3 scripts/generate_programmable_baremetal_demo.py

baremetal-runtime-test: model-package-example
	mkdir -p build/host_tests
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -Werror \
		-Isoftware/zynq_baremetal \
		software/zynq_baremetal/cnn_programmable_runtime.c \
		tests/c/test_programmable_runtime.c \
		-o build/host_tests/test_programmable_runtime
	build/host_tests/test_programmable_runtime build/models/rgb_identity.cnn
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-main \
		-Itests/c/xilinx_stubs -Isoftware/zynq_baremetal \
		-c software/zynq_baremetal/main.c \
		-o build/host_tests/programmable_main.o

runtime-corpus-test:
	python3 scripts/generate_runtime_verification_corpus.py \
		--output build/runtime_corpus --cases 24 --seed 20260809
	mkdir -p build/host_tests
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -Werror \
		-Isoftware/zynq_baremetal \
		software/zynq_baremetal/cnn_programmable_runtime.c \
		tests/c/test_programmable_runtime_corpus.c \
		-o build/host_tests/test_programmable_runtime_corpus
	build/host_tests/test_programmable_runtime_corpus \
		build/runtime_corpus/case_*.cnn

vitis-app: baremetal-headers
	mkdir -p $(VITIS_DATA_DIR)
	XILINX_VITIS_DATA_DIR=$(VITIS_DATA_DIR) $(VITIS) -s scripts/vitis/create_zynq_baremetal_app.py

regression: model-test golden-test unit

synth-sweep:
	bash scripts/run_synth_sweep.sh

synth-report:
	python3 scripts/report_synth_sweep.py --sweep-root build/synth_sweep --markdown docs/synthesis_experiments.md

top-impl:
	$(VIVADO) -mode batch -source scripts/impl_top_ooc.tcl
	python3 scripts/report_top_impl.py --build-dir build/top_impl --markdown docs/top_implementation.md

top-report:
	python3 scripts/report_top_impl.py --build-dir build/top_impl --markdown docs/top_implementation.md

programmable-top-impl:
	TOP_NAME=cnn_programmable_system_top OUT_DIR=build/programmable_top_impl \
		$(VIVADO) -mode batch -source scripts/impl_top_ooc.tcl
	python3 scripts/report_top_impl.py --build-dir build/programmable_top_impl \
		--markdown docs/programmable_top_implementation.md

programmable-top-synth:
	TOP_NAME=cnn_programmable_system_top SYNTH_ONLY=1 \
		OUT_DIR=build/programmable_top_synth_candidate \
		$(VIVADO) -mode batch -source scripts/impl_top_ooc.tcl

programmable-top-report:
	python3 scripts/report_top_impl.py --build-dir build/programmable_top_impl \
		--markdown docs/programmable_top_implementation.md

programmable-top-physical-baseline:
	$(VIVADO) -mode batch \
		-source scripts/implement_checkpoint.tcl \
		-tclargs build/programmable_top_impl/top_synth.dcp \
		build/programmable_top_physical_baseline

zybo-z7-project:
	$(VIVADO) -mode batch -source scripts/zynq/create_zybo_z7_20_project.tcl

zybo-z7-bitstream:
	$(VIVADO) -mode batch -source scripts/zynq/build_zybo_z7_20_bitstream.tcl

zybo-z7-xsa:
	$(VIVADO) -mode batch -source scripts/zynq/export_zybo_z7_20_xsa.tcl

full-zybo-z7-flow:
	$(MAKE) zybo-z7-project
	$(MAKE) zybo-z7-bitstream
	$(MAKE) zybo-z7-xsa
	$(MAKE) vitis-app

boot-image:
	BOOTGEN=$(BOOTGEN) bash scripts/zynq/create_boot_image.sh

full-preboard-proof:
	$(MAKE) regression
	$(MAKE) full-zybo-z7-flow
	$(MAKE) check-warnings
	$(MAKE) boot-image
	$(MAKE) flow-report

preboard-proof: full-preboard-proof

program-zybo-z7:
	$(XSCT) scripts/zynq/program_and_run_dma.tcl

lint:
	bash scripts/lint_verilator.sh

flow-report:
	python3 scripts/report_flow.py

report-flow: flow-report

check-warnings:
	python3 scripts/check_vivado_warnings.py

docs-check:
	python3 scripts/check_docs_evidence.py

clean:
	rm -rf sim xsim.dir .Xil
	rm -f *.jou *.log *.pb *.vcd *.wdb *.str *.rpt *.fst
