SHELL := /bin/bash

TB ?= tb_axi_stream_full_network_golden_flow
VITIS_DATA_DIR ?= $(CURDIR)/build/vitis_data

.PHONY: xsim regression xsim-regression lint clean flow-report report-flow check-warnings docs-check preboard-proof
.PHONY: unit descriptor-test parameter-bank-test programmable-engine-test packed-dma-test packed-dma-runtime-test packed-dma-writer-test model-test model-package-example golden-test synth-sweep synth-report
.PHONY: top-impl top-report baremetal-headers vitis-app
.PHONY: zybo-z7-project zybo-z7-bitstream zybo-z7-xsa full-zybo-z7-flow
.PHONY: boot-image full-preboard-proof program-zybo-z7

xsim:
	bash scripts/run_unit_tb.sh $(TB)

xsim-regression: regression

unit:
	bash scripts/run_unit.sh

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

model-test:
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

vitis-app: baremetal-headers
	mkdir -p $(VITIS_DATA_DIR)
	XILINX_VITIS_DATA_DIR=$(VITIS_DATA_DIR) $(HOME)/Xilinx/2025.2/Vitis/bin/vitis -s scripts/vitis/create_zynq_baremetal_app.py

regression: model-test golden-test unit

synth-sweep:
	bash scripts/run_synth_sweep.sh

synth-report:
	python3 scripts/report_synth_sweep.py --sweep-root build/synth_sweep --markdown docs/synthesis_experiments.md

top-impl:
	$(HOME)/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/impl_top_ooc.tcl
	python3 scripts/report_top_impl.py --build-dir build/top_impl --markdown docs/top_implementation.md

top-report:
	python3 scripts/report_top_impl.py --build-dir build/top_impl --markdown docs/top_implementation.md

zybo-z7-project:
	$(HOME)/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/create_zybo_z7_20_project.tcl

zybo-z7-bitstream:
	$(HOME)/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/build_zybo_z7_20_bitstream.tcl

zybo-z7-xsa:
	$(HOME)/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/export_zybo_z7_20_xsa.tcl

full-zybo-z7-flow:
	$(MAKE) zybo-z7-project
	$(MAKE) zybo-z7-bitstream
	$(MAKE) zybo-z7-xsa
	$(MAKE) vitis-app

boot-image:
	bash scripts/zynq/create_boot_image.sh

full-preboard-proof:
	$(MAKE) regression
	$(MAKE) full-zybo-z7-flow
	$(MAKE) check-warnings
	$(MAKE) boot-image
	$(MAKE) flow-report

preboard-proof: full-preboard-proof

program-zybo-z7:
	$(HOME)/Xilinx/2025.2/Vitis/bin/xsct scripts/zynq/program_and_run_dma.tcl

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
