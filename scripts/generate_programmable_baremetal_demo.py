#!/usr/bin/env python3
"""Generate a deterministic package/input/golden header for board bring-up."""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from models.model_compiler import compile_model
from models.package_executor import execute_model_package


OUTPUT = ROOT / "software" / "zynq_baremetal" / "generated" / "programmable_demo.h"


def c_bytes(name: str, values: bytes) -> str:
    rows = []
    for offset in range(0, len(values), 12):
        rows.append("    " + ", ".join(f"0x{value:02x}" for value in values[offset:offset + 12]))
    return f"static const uint8_t {name}[{len(values)}] = {{\n" + ",\n".join(rows) + "\n};\n"


def flatten(tensor):
    return bytes(value & 0xFF for row in tensor for pixel in row for value in pixel)


def main() -> None:
    spec_path = ROOT / "examples" / "models" / "rgb_identity.json"
    input_path = ROOT / "examples" / "tensors" / "rgb_4x4.json"
    spec = json.loads(spec_path.read_text())
    input_tensor = json.loads(input_path.read_text())
    package = compile_model(spec, base_dir=spec_path.parent)
    output_tensor = execute_model_package(package, input_tensor)
    text = """#ifndef CNN_PROGRAMMABLE_DEMO_H
#define CNN_PROGRAMMABLE_DEMO_H

#include <stdint.h>

/* Generated from examples/models/rgb_identity.json. */
"""
    text += c_bytes("cnn_demo_model_package", package)
    text += c_bytes("cnn_demo_input", flatten(input_tensor))
    text += c_bytes("cnn_demo_expected", flatten(output_tensor))
    text += "\n#endif\n"
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(text)
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
