#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_test() {
  local test_name="$1"
  local profile="${2:-directed}"
  echo "[UVM fault] test=$test_name profile=$profile"
  UVM_TESTNAME="$test_name" \
    UVM_FIXTURE_PROFILE="$profile" \
    UVM_BUILD_DIR="${TMPDIR:-/tmp}/cnn_uvm_fault_${test_name}_${profile}" \
    bash "$repo_root/scripts/run_uvm_xsim.sh"
}

run_test cnn_uvm_protocol_recovery_test
run_test cnn_uvm_parameter_crc_recovery_test
run_test cnn_uvm_reset_recovery_test
run_test cnn_uvm_starvation_abort_test
run_test cnn_uvm_ordering_recovery_test
run_test cnn_uvm_model_replacement_test
run_test cnn_uvm_interrupt_test
run_test cnn_uvm_compiler_reference_test residual-add
run_test cnn_uvm_compiler_reference_test residual-subtract
run_test cnn_uvm_compiler_reference_test saturation

echo "[PASS] UVM reset, recovery, ordering, lifecycle, IRQ, residual, and saturation faults"
