#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
coverage_root="${UVM_COVERAGE_ROOT:-$repo_root/build/uvm_coverage}"
database_dir="$coverage_root/databases"
run_dir="$coverage_root/runs"
report_dir="$coverage_root/report"
merge_dir="$coverage_root/merged"
base_seed="${UVM_COVERAGE_SEED:-20260813}"

if [[ -n "${XILINX_VIVADO:-}" ]]; then
  xcrg_bin="${XCRG:-$XILINX_VIVADO/bin/xcrg}"
elif command -v xcrg >/dev/null 2>&1; then
  xcrg_bin="$(command -v xcrg)"
else
  xcrg_bin="${XCRG:-$HOME/Xilinx/2026.1/Vivado/bin/xcrg}"
fi
if [[ ! -x "$xcrg_bin" ]]; then
  echo "ERROR: xcrg not found: $xcrg_bin" >&2
  exit 1
fi

if [[ "${UVM_COVERAGE_RESUME:-0}" != "1" ]]; then
  rm -rf "$coverage_root"
fi
mkdir -p "$database_dir" "$run_dir" "$report_dir" "$merge_dir"

run_case() {
  local name="$1"
  local test_name="$2"
  local profile="${3:-directed}"
  local layers="${4:-2}"
  local seed="${5:-$base_seed}"
  local log_file="$run_dir/$name/${test_name}.log"
  if [[ "${UVM_COVERAGE_RESUME:-0}" == "1" ]] &&
     [[ -f "$log_file" ]] &&
     grep -Eq 'UVM_ERROR *: *0' "$log_file" &&
     grep -Eq 'UVM_FATAL *: *0' "$log_file"; then
    echo "[UVM coverage] skip completed case=$name"
    return
  fi
  echo "[UVM coverage] case=$name test=$test_name profile=$profile layers=$layers seed=$seed"
  UVM_COVERAGE=1 \
    UVM_COVERAGE_DIR="$database_dir" \
    UVM_COVERAGE_NAME="$name" \
    UVM_BUILD_DIR="$run_dir/$name" \
    UVM_TESTNAME="$test_name" \
    UVM_FIXTURE_PROFILE="$profile" \
    UVM_FIXTURE_LAYERS="$layers" \
    UVM_FIXTURE_SEED="$seed" \
    bash "$repo_root/scripts/run_uvm_xsim.sh"
}

run_case register_access cnn_uvm_register_access_test
run_case protocol_ral cnn_uvm_protocol_ral_test
run_case protocol_recovery cnn_uvm_protocol_recovery_test
run_case parameter_crc cnn_uvm_parameter_crc_recovery_test
run_case reset_recovery cnn_uvm_reset_recovery_test
run_case starvation_abort cnn_uvm_starvation_abort_test
run_case ordering_recovery cnn_uvm_ordering_recovery_test
run_case model_replacement cnn_uvm_model_replacement_test
run_case interrupt cnn_uvm_interrupt_test
run_case smoke cnn_uvm_smoke_test
run_case closed_loop cnn_uvm_closed_loop_ddr_test
run_case directed cnn_uvm_compiler_reference_test directed
run_case residual_add cnn_uvm_compiler_reference_test residual-add
run_case residual_subtract cnn_uvm_compiler_reference_test residual-subtract
run_case saturation cnn_uvm_compiler_reference_test saturation

for layers in {1..8}; do
  run_case "random_${layers}layer" cnn_uvm_compiler_reference_test randomized \
    "$layers" "$((base_seed + layers))"
done

xcrg_prefix=()
if command -v systemd-run >/dev/null 2>&1 &&
   systemctl --user is-system-running >/dev/null 2>&1; then
  xcrg_prefix=(
    systemd-run --user --scope --quiet
    --property="MemoryMax=${UVM_XCRG_MEMORY_MAX:-12G}"
    --property="MemorySwapMax=${UVM_XCRG_SWAP_MAX:-4G}"
    --
  )
fi

functional_list="$coverage_root/functional_databases.txt"
code_list="$coverage_root/code_databases.txt"
find "$database_dir/xsim.covdb" -mindepth 1 -maxdepth 1 -type d | \
  sort > "$functional_list"
find "$database_dir/xsim.codeCov" -mindepth 1 -maxdepth 1 -type d | \
  sort > "$code_list"

run_xcrg() {
  local kind="$1"
  local database_list="$2"
  local output_dir="$3"
  local merged_name="$4"
  local expected_report="$5"
  local log_file="$coverage_root/xcrg-${kind}.log"
  local status

  if [[ "${UVM_COVERAGE_RESUME:-0}" == "1" ]] && [[ -s "$expected_report" ]]; then
    echo "[UVM coverage] reuse $kind report=$expected_report"
    return
  fi

  set +e
  "${xcrg_prefix[@]}" "$xcrg_bin" -file "$database_list" \
    -merge_dir "$merge_dir/$kind" -merge_db_name "$merged_name" \
    -report_dir "$output_dir" -report_format all -log "$log_file"
  status=$?
  set -e
  if [[ ! -s "$expected_report" ]]; then
    if [[ "$kind" == "code" ]] &&
       [[ -s "$merge_dir/$kind/xsim.codeCov/$merged_name/xsim.CCInfo" ]]; then
      echo "WARNING: xcrg code merge completed but report generation failed " \
           "with exit status $status" >&2
      return
    fi
    echo "ERROR: xcrg $kind report missing after exit status $status" >&2
    return 1
  fi
  if [[ $status -ne 0 ]]; then
    echo "WARNING: xcrg $kind exited $status after producing a valid report" >&2
  fi
}

code_report="$report_dir/code/codeCoverageReport/dashboard.html"
if [[ "${UVM_COVERAGE_RESUME:-0}" == "1" ]] &&
   [[ -s "$report_dir/codeCoverageReport/dashboard.html" ]]; then
  code_report="$report_dir/codeCoverageReport/dashboard.html"
fi
functional_report="$report_dir/functional/functionalCoverageReport/xcrg_func_cov_report.txt"
if [[ "${UVM_COVERAGE_RESUME:-0}" == "1" ]] &&
   [[ -s "$coverage_root/report-functional/functionalCoverageReport/xcrg_func_cov_report.txt" ]]; then
  functional_report="$coverage_root/report-functional/functionalCoverageReport/xcrg_func_cov_report.txt"
fi

run_xcrg code "$code_list" "$report_dir/code" uvm_u5_code \
  "$code_report"
run_xcrg functional "$functional_list" "$report_dir/functional" \
  uvm_u5_functional \
  "$functional_report"

if ! find "$report_dir" -type f -print -quit | grep -q .; then
  echo "ERROR: xcrg produced no coverage report" >&2
  exit 1
fi

cp "$repo_root/verification/uvm_signoff.json" "$coverage_root/uvm_signoff.json"
python3 "$repo_root/scripts/report_uvm_coverage.py" \
  --coverage-root "$coverage_root" \
  --manifest "$repo_root/verification/uvm_signoff.json"
echo "[PASS] U5 coverage campaign and merge: $report_dir"
