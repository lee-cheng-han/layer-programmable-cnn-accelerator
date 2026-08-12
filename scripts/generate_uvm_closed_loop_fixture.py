#!/usr/bin/env python3
"""Generate a compiler/Python-reference fixture for closed-loop UVM testing."""

from __future__ import annotations

import argparse
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from models.cnn_abi import parse_model_package
from models.model_compiler import compile_model
from models.package_executor import execute_model_package


JOB_ID = 0x5556_4D32


def _flatten_region(tensor, x: int, y: int, width: int, height: int) -> bytes:
    values = []
    for row in tensor[y:y + height]:
        for pixel in row[x:x + width]:
            values.extend(value & 0xFF for value in pixel)
    return bytes(values)


def _tile_geometry(layer, input_desc, output_desc):
    tile_height = layer.tile_height_hint or output_desc.height
    tile_width = layer.tile_width_hint or output_desc.width
    for tile_y in range(0, output_desc.height, tile_height):
        height = min(tile_height, output_desc.height - tile_y)
        for tile_x in range(0, output_desc.width, tile_width):
            width = min(tile_width, output_desc.width - tile_x)
            origin_x = tile_x * layer.stride_x - layer.padding_left
            origin_y = tile_y * layer.stride_y - layer.padding_top
            local_width = (width - 1) * layer.stride_x + layer.kernel_width
            local_height = (height - 1) * layer.stride_y + layer.kernel_height
            source_x = max(0, origin_x)
            source_y = max(0, origin_y)
            source_end_x = min(input_desc.width, origin_x + local_width)
            source_end_y = min(input_desc.height, origin_y + local_height)
            yield {
                "tile_x": tile_x,
                "tile_y": tile_y,
                "tile_width": width,
                "tile_height": height,
                "source_x": source_x,
                "source_y": source_y,
                "source_width": max(0, source_end_x - source_x),
                "source_height": max(0, source_end_y - source_y),
            }


def _write_mem(path: Path, values, width: int) -> None:
    digits = (width + 3) // 4
    mask = (1 << width) - 1
    path.write_text(
        "".join(f"{int(value) & mask:0{digits}x}\n" for value in values),
        encoding="ascii",
    )


def _write_packet_table(output: Path, prefix: str, packets) -> None:
    payload = bytearray()
    starts = []
    lengths = []
    for packet in packets:
        starts.append(len(payload))
        payload.extend(packet["payload"])
        lengths.append(len(packet["payload"]))
    fields = {
        "type": (8, (packet["type"] for packet in packets)),
        "tensor": (16, (packet["tensor_id"] for packet in packets)),
        "layer": (16, (packet["layer_id"] for packet in packets)),
        "tile_x": (16, (packet["tile_x"] for packet in packets)),
        "tile_y": (16, (packet["tile_y"] for packet in packets)),
        "tile_width": (16, (packet["tile_width"] for packet in packets)),
        "tile_height": (16, (packet["tile_height"] for packet in packets)),
        "channels": (16, (packet["channels"] for packet in packets)),
        "payload_start": (16, starts),
        "payload_length": (16, lengths),
    }
    for field, (width, values) in fields.items():
        _write_mem(output / f"{prefix}_{field}.mem", values, width)
    _write_mem(output / f"{prefix}_payload.mem", payload, 8)


def _model_spec():
    identity = [0, 0, 0, 0, 1, 0, 0, 0, 0]
    horizontal_edge = [0, 0, 0, -1, 0, 1, 0, 0, 0]
    return {
        "format": "cnn-accelerator-model-v1",
        "model_id": 0x5556_4D02,
        "model_generation_id": 20260811,
        "input": {"name": "input", "width": 4, "height": 4, "channels": 1},
        "layers": [
            {
                "name": "spatial_features",
                "output": "features",
                "output_channels": 2,
                "kernel_size": 3,
                "stride": 1,
                "padding": 1,
                "activation": "none",
                "bias_enable": True,
                "bias": [1, -1],
                "quant_multipliers": [1, 1],
                "quant_shifts": [0, 0],
                "tile_width_hint": 2,
                "tile_height_hint": 2,
                "weights": identity + horizontal_edge,
            },
            {
                "name": "channel_projection",
                "output": "output",
                "output_channels": 1,
                "kernel_size": 1,
                "stride": 1,
                "padding": 0,
                "activation": "relu",
                "bias_enable": True,
                "bias": [3],
                "quant_multiplier": 1,
                "quant_shift": 1,
                "tile_width_hint": 2,
                "tile_height_hint": 2,
                "weights": [2, -1],
            },
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    input_tensor = [
        [[-6], [-2], [3], [7]],
        [[-4], [0], [5], [9]],
        [[-8], [1], [4], [6]],
        [[-3], [2], [8], [10]],
    ]
    package = compile_model(_model_spec())
    final_tensor, tensor_values = execute_model_package(
        package, input_tensor, return_tensors=True
    )
    header, layers, tensors, quantizations = parse_model_package(package)
    tensor_by_id = {tensor.tensor_id: tensor for tensor in tensors}

    metadata = []
    records = [(0, 0, header.pack())]
    records += [(1, index, record.pack()) for index, record in enumerate(layers)]
    records += [(2, index, record.pack()) for index, record in enumerate(tensors)]
    records += [(3, index, record.pack()) for index, record in enumerate(quantizations)]
    for kind, record_index, data in records:
        for word_index, (word,) in enumerate(struct.iter_unpack("<I", data)):
            metadata.append((0, kind, record_index, word_index, word))
        metadata.append((1, kind, record_index, 0, 0))

    _write_mem(args.output / "metadata_action.mem", (op[0] for op in metadata), 1)
    _write_mem(args.output / "metadata_kind.mem", (op[1] for op in metadata), 2)
    _write_mem(args.output / "metadata_record.mem", (op[2] for op in metadata), 6)
    _write_mem(args.output / "metadata_word.mem", (op[3] for op in metadata), 6)
    _write_mem(args.output / "metadata_data.mem", (op[4] for op in metadata), 32)

    parameter_packets = []
    input_packets = []
    expected_packets = []
    for layer in layers:
        input_desc = tensor_by_id[layer.input_tensor_id]
        output_desc = tensor_by_id[layer.output_tensor_id]
        parameter_packets.append({
            "type": 2,
            "tensor_id": layer.input_tensor_id,
            "layer_id": layer.layer_id,
            "tile_x": 0,
            "tile_y": 0,
            "tile_width": 0,
            "tile_height": 0,
            "channels": 0,
            "payload": package[layer.weight_offset:layer.weight_offset + layer.weight_size],
        })
        if layer.bias_size:
            parameter_packets.append({
                "type": 3,
                "tensor_id": layer.output_tensor_id,
                "layer_id": layer.layer_id,
                "tile_x": 0,
                "tile_y": 0,
                "tile_width": 0,
                "tile_height": 0,
                "channels": 0,
                "payload": package[layer.bias_offset:layer.bias_offset + layer.bias_size],
            })
        for tile in _tile_geometry(layer, input_desc, output_desc):
            if layer.layer_id == 0:
                input_packets.append({
                    "type": 1,
                    "tensor_id": layer.input_tensor_id,
                    "layer_id": layer.layer_id,
                    "tile_x": tile["tile_x"],
                    "tile_y": tile["tile_y"],
                    "tile_width": tile["tile_width"],
                    "tile_height": tile["tile_height"],
                    "channels": input_desc.channels,
                    "payload": _flatten_region(
                        tensor_values[layer.input_tensor_id],
                        tile["source_x"], tile["source_y"],
                        tile["source_width"], tile["source_height"],
                    ),
                })
            expected_packets.append({
                "type": 4,
                "tensor_id": layer.output_tensor_id,
                "layer_id": layer.layer_id,
                "tile_x": tile["tile_x"],
                "tile_y": tile["tile_y"],
                "tile_width": tile["tile_width"],
                "tile_height": tile["tile_height"],
                "channels": output_desc.channels,
                "payload": _flatten_region(
                    tensor_values[layer.output_tensor_id],
                    tile["tile_x"], tile["tile_y"],
                    tile["tile_width"], tile["tile_height"],
                ),
            })

    _write_packet_table(args.output, "parameter", parameter_packets)
    _write_packet_table(args.output, "input", input_packets)
    _write_packet_table(args.output, "expected", expected_packets)
    _write_mem(
        args.output / "final_tensor.mem",
        _flatten_region(final_tensor, 0, 0, len(final_tensor[0]), len(final_tensor)),
        8,
    )

    intermediate = tensor_by_id[layers[0].output_tensor_id]
    final = tensor_by_id[header.output_tensor_id]
    layer_zero_outputs = sum(
        packet["layer_id"] == 0 for packet in expected_packets
    )
    constants = {
        "UVM_FIXTURE_METADATA_OPS": len(metadata),
        "UVM_FIXTURE_PARAMETER_PACKETS": len(parameter_packets),
        "UVM_FIXTURE_PARAMETER_BYTES": sum(len(p["payload"]) for p in parameter_packets),
        "UVM_FIXTURE_INPUT_PACKETS": len(input_packets),
        "UVM_FIXTURE_INPUT_BYTES": sum(len(p["payload"]) for p in input_packets),
        "UVM_FIXTURE_EXPECTED_PACKETS": len(expected_packets),
        "UVM_FIXTURE_EXPECTED_BYTES": sum(len(p["payload"]) for p in expected_packets),
        "UVM_FIXTURE_LAYER_ZERO_OUTPUTS": layer_zero_outputs,
        "UVM_FIXTURE_FINAL_ELEMENTS": final.width * final.height * final.channels,
        "UVM_FIXTURE_JOB_ID": JOB_ID,
        "UVM_FIXTURE_MODEL_ID": header.model_id,
        "UVM_FIXTURE_INTERMEDIATE_ID": intermediate.tensor_id,
        "UVM_FIXTURE_INTERMEDIATE_BASE": intermediate.ddr_offset,
        "UVM_FIXTURE_INTERMEDIATE_WIDTH": intermediate.width,
        "UVM_FIXTURE_INTERMEDIATE_HEIGHT": intermediate.height,
        "UVM_FIXTURE_INTERMEDIATE_CHANNELS": intermediate.channels,
        "UVM_FIXTURE_INTERMEDIATE_ROW_STRIDE": intermediate.row_stride,
        "UVM_FIXTURE_INTERMEDIATE_PIXEL_STRIDE": intermediate.pixel_stride,
        "UVM_FIXTURE_FINAL_ID": final.tensor_id,
        "UVM_FIXTURE_FINAL_BASE": final.ddr_offset,
        "UVM_FIXTURE_FINAL_WIDTH": final.width,
        "UVM_FIXTURE_FINAL_HEIGHT": final.height,
        "UVM_FIXTURE_FINAL_CHANNELS": final.channels,
        "UVM_FIXTURE_FINAL_ROW_STRIDE": final.row_stride,
        "UVM_FIXTURE_FINAL_PIXEL_STRIDE": final.pixel_stride,
    }
    (args.output / "uvm_closed_loop_fixture.svh").write_text(
        "".join(
            f"localparam int unsigned {name} = {value};\n"
            for name, value in constants.items()
        ),
        encoding="ascii",
    )
    (args.output / "model.cnn").write_bytes(package)
    print(
        "Wrote compiler-driven UVM fixture: "
        f"layers={len(layers)} input_packets={len(input_packets)} "
        f"output_packets={len(expected_packets)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
