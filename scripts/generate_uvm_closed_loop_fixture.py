#!/usr/bin/env python3
"""Generate a compiler/Python-reference fixture for closed-loop UVM testing."""

from __future__ import annotations

import argparse
from pathlib import Path
import random
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from models.cnn_abi import NO_TENSOR_ID, parse_model_package
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
        "source_x": (
            16, (packet.get("source_x", packet["tile_x"]) for packet in packets)
        ),
        "source_y": (
            16, (packet.get("source_y", packet["tile_y"]) for packet in packets)
        ),
        "source_width": (
            16,
            (packet.get("source_width", packet["tile_width"]) for packet in packets),
        ),
        "source_height": (
            16,
            (packet.get("source_height", packet["tile_height"]) for packet in packets),
        ),
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


def _random_model_spec(layer_count: int, seed: int):
    rng = random.Random(seed)
    input_channels = rng.randint(1, 2)
    current_channels = input_channels
    current_width = 4
    current_height = 4
    layers = []
    for layer_index in range(layer_count):
        kernel = 3 if (layer_index + seed) % 2 == 0 else 1
        stride = 2 if layer_index == 0 and seed % 3 == 0 else 1
        output_channels = rng.randint(1, 2)
        quant_shift = rng.randint(0, 2)
        weight_count = kernel * kernel * current_channels * output_channels
        padding = 0
        if kernel == 3:
            padding_mask = (seed + 7 * layer_index) & 0xF
            padding = {
                "top": padding_mask & 1,
                "bottom": (padding_mask >> 1) & 1,
                "left": (padding_mask >> 2) & 1,
                "right": (padding_mask >> 3) & 1,
            }
            output_width = (
                current_width + padding["left"] + padding["right"] - kernel
            ) // stride + 1
            output_height = (
                current_height + padding["top"] + padding["bottom"] - kernel
            ) // stride + 1
            if output_width < 1 or output_height < 1:
                padding = {"top": 1, "bottom": 1, "left": 1, "right": 1}
        padding_top = padding["top"] if isinstance(padding, dict) else padding
        padding_bottom = padding["bottom"] if isinstance(padding, dict) else padding
        padding_left = padding["left"] if isinstance(padding, dict) else padding
        padding_right = padding["right"] if isinstance(padding, dict) else padding
        current_width = (
            current_width + padding_left + padding_right - kernel
        ) // stride + 1
        current_height = (
            current_height + padding_top + padding_bottom - kernel
        ) // stride + 1
        layers.append({
            "name": f"random_layer_{layer_index}",
            "output": f"tensor_{layer_index + 1}",
            "output_channels": output_channels,
            "kernel_size": kernel,
            "stride": stride,
            "padding": padding,
            "activation": "relu" if rng.randrange(2) else "none",
            "bias_enable": True,
            "bias": [rng.randint(-4, 4) for _ in range(output_channels)],
            "quant_multipliers": [1] * output_channels,
            "quant_shifts": [quant_shift] * output_channels,
            "tile_width_hint": 2,
            "tile_height_hint": 2,
            "weights": [rng.randint(-2, 2) for _ in range(weight_count)],
        })
        current_channels = output_channels
    return {
        "format": "cnn-accelerator-model-v1",
        "model_id": 0x5556_0000 | (seed & 0xFFFF),
        "model_generation_id": seed,
        "input": {
            "name": "input", "width": 4, "height": 4,
            "channels": input_channels,
        },
        "layers": layers,
    }


def _residual_model_spec(mode: str):
    return {
        "format": "cnn-accelerator-model-v1",
        "model_id": 0x5556_5200 | (1 if mode == "add" else 2),
        "model_generation_id": 20260812,
        "input": {"name": "input", "width": 4, "height": 4, "channels": 1},
        "layers": [{
            "name": f"residual_{mode}",
            "output": "output",
            "output_channels": 1,
            "kernel_size": 1,
            "stride": 1,
            "padding": 0,
            "activation": "none",
            "bias_enable": False,
            "quantization_profile": "input",
            "quant_multiplier": 1,
            "quant_shift": 0,
            "tile_width_hint": 2,
            "tile_height_hint": 2,
            "weights": [1],
            "residual": "input",
            "residual_mode": mode,
        }],
    }


def _saturation_model_spec():
    return {
        "format": "cnn-accelerator-model-v1",
        "model_id": 0x5556_5A70,
        "model_generation_id": 20260812,
        "input": {"name": "input", "width": 4, "height": 4, "channels": 1},
        "layers": [{
            "name": "forced_saturation",
            "output": "output",
            "output_channels": 1,
            "kernel_size": 1,
            "stride": 1,
            "padding": 0,
            "activation": "none",
            "bias_enable": False,
            "quant_multiplier": 1,
            "quant_shift": 0,
            "tile_width_hint": 2,
            "tile_height_hint": 2,
            "weights": [127],
        }],
    }


def _input_tensor(width: int, height: int, channels: int, seed: int):
    rng = random.Random(seed ^ 0xC001_C0DE)
    return [
        [[rng.randint(-12, 12) for _ in range(channels)] for _ in range(width)]
        for _ in range(height)
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--layers", type=int, default=2)
    parser.add_argument("--seed", type=int, default=20260811)
    parser.add_argument("--randomized", action="store_true")
    parser.add_argument(
        "--profile",
        choices=("directed", "randomized", "residual-add", "residual-subtract",
                 "saturation"),
    )
    args = parser.parse_args()
    if not 1 <= args.layers <= 8:
        parser.error("--layers must be in the range 1..8")
    args.output.mkdir(parents=True, exist_ok=True)

    profile = args.profile or ("randomized" if args.randomized else "directed")
    if profile == "randomized":
        spec = _random_model_spec(args.layers, args.seed)
    elif profile == "residual-add":
        spec = _residual_model_spec("add")
    elif profile == "residual-subtract":
        spec = _residual_model_spec("subtract")
    elif profile == "saturation":
        spec = _saturation_model_spec()
    else:
        spec = _model_spec()
    input_desc = spec["input"]
    input_tensor = _input_tensor(
        input_desc["width"], input_desc["height"], input_desc["channels"], args.seed
    ) if profile == "randomized" else [
        [[-6], [-2], [3], [7]],
        [[-4], [0], [5], [9]],
        [[-8], [1], [4], [6]],
        [[-3], [2], [8], [10]],
    ]
    if profile == "saturation":
        input_tensor = [[[127] for _ in range(4)] for _ in range(4)]
    package = compile_model(spec)
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
    activation_packets = []
    residual_packets = []
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
            "channels": input_desc.channels,
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
                "channels": output_desc.channels,
                "payload": package[layer.bias_offset:layer.bias_offset + layer.bias_size],
            })
        for tile in _tile_geometry(layer, input_desc, output_desc):
            activation_packets.append({
                "type": 1,
                "tensor_id": layer.input_tensor_id,
                "layer_id": layer.layer_id,
                "tile_x": tile["tile_x"],
                "tile_y": tile["tile_y"],
                "tile_width": tile["tile_width"],
                "tile_height": tile["tile_height"],
                "source_x": tile["source_x"],
                "source_y": tile["source_y"],
                "source_width": tile["source_width"],
                "source_height": tile["source_height"],
                "channels": input_desc.channels,
                "payload": (
                    _flatten_region(
                        tensor_values[layer.input_tensor_id],
                        tile["source_x"], tile["source_y"],
                        tile["source_width"], tile["source_height"],
                    ) if layer.layer_id == 0 else b""
                ),
            })
            if layer.residual_tensor_id != NO_TENSOR_ID:
                residual_desc = tensor_by_id[layer.residual_tensor_id]
                residual_packets.append({
                    "type": 1,
                    "tensor_id": layer.residual_tensor_id,
                    "layer_id": layer.layer_id,
                    "tile_x": tile["tile_x"],
                    "tile_y": tile["tile_y"],
                    "tile_width": tile["tile_width"],
                    "tile_height": tile["tile_height"],
                    "source_x": tile["tile_x"],
                    "source_y": tile["tile_y"],
                    "source_width": tile["tile_width"],
                    "source_height": tile["tile_height"],
                    "channels": residual_desc.channels,
                    "payload": (
                        _flatten_region(
                            tensor_values[layer.residual_tensor_id],
                            tile["tile_x"], tile["tile_y"],
                            tile["tile_width"], tile["tile_height"],
                        ) if layer.residual_tensor_id == header.input_tensor_id else b""
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
    _write_packet_table(args.output, "activation", activation_packets)
    residual_storage_packets = residual_packets or [{
        "type": 1, "tensor_id": 0, "layer_id": 0,
        "tile_x": 0, "tile_y": 0, "tile_width": 1, "tile_height": 1,
        "channels": 1, "payload": b"\0",
    }]
    _write_packet_table(args.output, "residual", residual_storage_packets)
    _write_packet_table(args.output, "expected", expected_packets)
    _write_mem(
        args.output / "final_tensor.mem",
        _flatten_region(final_tensor, 0, 0, len(final_tensor[0]), len(final_tensor)),
        8,
    )

    final = tensor_by_id[header.output_tensor_id]
    output_tensors = [tensor_by_id[layer.output_tensor_id] for layer in layers]
    _write_mem(args.output / "tensor_id.mem", (t.tensor_id for t in output_tensors), 16)
    _write_mem(args.output / "tensor_base.mem", (t.ddr_offset for t in output_tensors), 64)
    _write_mem(args.output / "tensor_width.mem", (t.width for t in output_tensors), 16)
    _write_mem(args.output / "tensor_height.mem", (t.height for t in output_tensors), 16)
    _write_mem(args.output / "tensor_channels.mem", (t.channels for t in output_tensors), 16)
    _write_mem(
        args.output / "tensor_row_stride.mem",
        (t.row_stride for t in output_tensors), 32,
    )
    _write_mem(
        args.output / "tensor_pixel_stride.mem",
        (t.pixel_stride for t in output_tensors), 32,
    )
    layer_output_counts = [
        sum(packet["layer_id"] == layer for packet in expected_packets)
        for layer in range(len(layers))
    ]
    _write_mem(args.output / "layer_output_count.mem", layer_output_counts, 16)
    _write_mem(args.output / "layer_kernel.mem", (layer.kernel_width for layer in layers), 8)
    _write_mem(args.output / "layer_stride.mem", (layer.stride_x for layer in layers), 8)
    _write_mem(
        args.output / "layer_input_channels.mem",
        (tensor_by_id[layer.input_tensor_id].channels for layer in layers), 16,
    )
    _write_mem(
        args.output / "layer_output_channels.mem",
        (tensor_by_id[layer.output_tensor_id].channels for layer in layers), 16,
    )
    _write_mem(args.output / "layer_activation.mem", (int(layer.activation) for layer in layers), 8)
    _write_mem(args.output / "layer_residual.mem", (int(layer.residual_mode) for layer in layers), 8)
    _write_mem(
        args.output / "layer_padding.mem",
        (
            layer.padding_top
            | (layer.padding_bottom << 1)
            | (layer.padding_left << 2)
            | (layer.padding_right << 3)
            for layer in layers
        ), 8,
    )
    constants = {
        "UVM_FIXTURE_METADATA_OPS": len(metadata),
        "UVM_FIXTURE_PARAMETER_PACKETS": len(parameter_packets),
        "UVM_FIXTURE_PARAMETER_BYTES": sum(len(p["payload"]) for p in parameter_packets),
        "UVM_FIXTURE_LAYERS": len(layers),
        "UVM_FIXTURE_TENSORS": len(output_tensors),
        "UVM_FIXTURE_ACTIVATION_PACKETS": len(activation_packets),
        "UVM_FIXTURE_ACTIVATION_BYTES": sum(len(p["payload"]) for p in activation_packets),
        "UVM_FIXTURE_RESIDUAL_PACKETS": len(residual_packets),
        "UVM_FIXTURE_RESIDUAL_PACKET_STORAGE": len(residual_storage_packets),
        "UVM_FIXTURE_RESIDUAL_BYTES": sum(
            len(p["payload"]) for p in residual_storage_packets
        ),
        "UVM_FIXTURE_EXPECTED_PACKETS": len(expected_packets),
        "UVM_FIXTURE_EXPECTED_BYTES": sum(len(p["payload"]) for p in expected_packets),
        "UVM_FIXTURE_FINAL_ELEMENTS": final.width * final.height * final.channels,
        "UVM_FIXTURE_JOB_ID": JOB_ID,
        "UVM_FIXTURE_MODEL_ID": header.model_id,
        "UVM_FIXTURE_FINAL_ID": final.tensor_id,
        "UVM_FIXTURE_FINAL_BASE": final.ddr_offset,
        "UVM_FIXTURE_FINAL_WIDTH": final.width,
        "UVM_FIXTURE_FINAL_HEIGHT": final.height,
        "UVM_FIXTURE_FINAL_CHANNELS": final.channels,
        "UVM_FIXTURE_FINAL_ROW_STRIDE": final.row_stride,
        "UVM_FIXTURE_FINAL_PIXEL_STRIDE": final.pixel_stride,
        "UVM_FIXTURE_SEED": args.seed,
        "UVM_FIXTURE_EXPECT_SATURATION": int(profile == "saturation"),
        "UVM_FIXTURE_PROFILE_ID": {
            "directed": 0,
            "randomized": 1,
            "residual-add": 2,
            "residual-subtract": 3,
            "saturation": 4,
        }[profile],
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
        f"profile={profile} layers={len(layers)} "
        f"activation_packets={len(activation_packets)} "
        f"output_packets={len(expected_packets)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
