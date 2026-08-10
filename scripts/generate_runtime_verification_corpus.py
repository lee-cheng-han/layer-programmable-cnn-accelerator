#!/usr/bin/env python3
"""Generate deterministic mixed-network packages for runtime verification."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import random
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from models.cnn_abi import parse_model_package
from models.model_compiler import compile_model, package_summary
from models.package_executor import execute_model_package


def tensor(height: int, width: int, channels: int, rng: random.Random):
    return [
        [[rng.randint(-16, 16) for _ in range(channels)] for _ in range(width)]
        for _ in range(height)
    ]


def make_case(case_index: int, seed: int):
    rng = random.Random(seed + case_index * 7919)
    layer_count = (case_index % 8) + 1
    width = rng.randint(7, 15)
    height = rng.randint(7, 15)
    input_channels = rng.randint(1, 8)
    current_channels = input_channels
    layers = []

    for layer_index in range(layer_count):
        kernel = 1 if (case_index + layer_index) % 2 == 0 else 3
        stride = 2 if layer_index == 0 and case_index % 3 == 0 else 1
        padding = 1 if kernel == 3 else 0
        output_channels = rng.randint(1, 8)
        weight_count = kernel * kernel * current_channels * output_channels
        bias_enable = (case_index + layer_index) % 4 != 0
        layer = {
            "name": f"case_{case_index}_layer_{layer_index}",
            "output": f"tensor_{layer_index + 1}",
            "output_channels": output_channels,
            "kernel_size": kernel,
            "stride": stride,
            "padding": padding,
            "activation": "relu" if rng.randrange(2) else "none",
            "bias_enable": bias_enable,
            "quant_multipliers": [rng.randint(1, 3) for _ in range(output_channels)],
            "quant_shifts": [rng.randint(0, 4) for _ in range(output_channels)],
            "tile_width_hint": rng.randint(1, 4),
            "tile_height_hint": rng.randint(1, 4),
            "weights": [rng.randint(-3, 3) for _ in range(weight_count)],
        }
        if bias_enable:
            layer["bias"] = [rng.randint(-32, 32) for _ in range(output_channels)]
        layers.append(layer)
        current_channels = output_channels

    spec = {
        "format": "cnn-accelerator-model-v1",
        "model_id": 1000 + case_index,
        "model_generation_id": seed,
        "input": {
            "name": "input",
            "width": width,
            "height": height,
            "channels": input_channels,
        },
        "layers": layers,
    }
    input_tensor = tensor(height, width, input_channels, rng)
    return spec, input_tensor


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cases", type=int, default=24)
    parser.add_argument("--seed", type=int, default=20260809)
    args = parser.parse_args()
    if args.cases < 8:
        parser.error("--cases must be at least 8 to cover every layer count")

    args.output.mkdir(parents=True, exist_ok=True)
    manifest = {"seed": args.seed, "cases": []}
    for case_index in range(args.cases):
        spec, input_tensor = make_case(case_index, args.seed)
        package = compile_model(spec)
        output_tensor = execute_model_package(package, input_tensor)
        header, layers, tensors, _ = parse_model_package(package)
        package_name = f"case_{case_index:02d}.cnn"
        (args.output / package_name).write_bytes(package)
        manifest["cases"].append({
            "case": case_index,
            "package": package_name,
            "model": package_summary(package),
            "input_sha256": hashlib.sha256(
                json.dumps(input_tensor, separators=(",", ":")).encode()
            ).hexdigest(),
            "output_sha256": hashlib.sha256(
                json.dumps(output_tensor, separators=(",", ":")).encode()
            ).hexdigest(),
            "max_tensor_bytes": max(tensor.allocation_size for tensor in tensors),
            "layer_ids": [layer.layer_id for layer in layers],
        })
    (args.output / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"Wrote {args.cases} deterministic runtime packages to {args.output} "
        f"(seed={args.seed})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
