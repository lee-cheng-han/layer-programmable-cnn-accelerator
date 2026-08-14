#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_seed="${UVM_CAMPAIGN_SEED:-20260812}"
seed_count="${UVM_CAMPAIGN_SEEDS:-2}"

if (( seed_count < 1 )); then
  echo "ERROR: UVM_CAMPAIGN_SEEDS must be positive" >&2
  exit 1
fi

for ((seed_index = 0; seed_index < seed_count; seed_index++)); do
  for layer_count in {1..8}; do
    seed=$((base_seed + seed_index * 101 + layer_count))
    echo "[UVM] seed=$seed layers=$layer_count"
    UVM_TESTNAME=cnn_uvm_compiler_reference_test \
      UVM_FIXTURE_RANDOMIZED=1 \
      UVM_FIXTURE_LAYERS="$layer_count" \
      UVM_FIXTURE_SEED="$seed" \
      UVM_BUILD_DIR="${TMPDIR:-/tmp}/cnn_uvm_random_${seed}_${layer_count}" \
      bash "$repo_root/scripts/run_uvm_xsim.sh"
  done
done

echo "[PASS] compiler-generated UVM campaign: seeds=$seed_count layer_counts=1..8"
