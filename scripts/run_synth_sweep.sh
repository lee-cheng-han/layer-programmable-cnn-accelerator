#!/usr/bin/env bash
set -euo pipefail

VIVADO_BIN="${VIVADO_BIN:-$(command -v vivado 2>/dev/null || printf '%s' "${HOME}/Xilinx/2026.1/Vivado/bin/vivado")}"
SWEEP_ROOT="${SWEEP_ROOT:-build/synth_sweep}"

if [[ ! -x "$VIVADO_BIN" ]]; then
 echo "ERROR: Vivado executable not found: $VIVADO_BIN"
 exit 1
fi

configs=(
 "2 8"
 "4 4"
 "4 8"
)

mkdir -p "$SWEEP_ROOT"

for config in "${configs[@]}"; do
 read -r pc pk <<< "$config"
 out_dir="${SWEEP_ROOT}/pc${pc}_pk${pk}"
 mkdir -p "$out_dir"

 echo "============================================================"
 echo "[ SYNTH] PC=${pc} PK=${pk}"
 echo "============================================================"

 PC="$pc" PK="$pk" OUT_DIR="$out_dir" \
 "$VIVADO_BIN" \
 -mode batch \
 -source scripts/synth_pc_pk_config.tcl \
 -log "${out_dir}/vivado.log" \
 -journal "${out_dir}/vivado.jou"
done

python3 scripts/report_synth_sweep.py \
 --sweep-root "$SWEEP_ROOT" \
 --markdown docs/synthesis_experiments.md
