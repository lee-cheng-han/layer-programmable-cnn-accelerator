#!/usr/bin/env python3
"""Generate a compiler-derived mixed-network fixture for programmable RTL."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import random
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from models.cnn_abi import parse_model_package
from models.model_compiler import compile_model
from models.package_executor import execute_model_package


JOB_ID = 0x524E_4431
PACKET_MAGIC = 0x3150_4E43
PACKET_VERSION = 1
PACKET_HEADER_WORDS = 8
PACKET_INPUT_TILE = 1
PACKET_LAYER_WEIGHTS = 2
PACKET_LAYER_BIASES = 3
PACKET_OUTPUT_TILE = 4


def _tensor(height: int, width: int, channels: int, rng: random.Random):
    return [
        [[rng.randint(-9, 9) for _ in range(channels)] for _ in range(width)]
        for _ in range(height)
    ]


def _flatten_region(tensor, x: int, y: int, width: int, height: int) -> bytes:
    values = []
    for row in tensor[y:y + height]:
        for pixel in row[x:x + width]:
            values.extend(value & 0xFF for value in pixel)
    return bytes(values)


def _packet(
    packet_type: int,
    payload: bytes,
    *,
    tensor_id: int,
    layer_id: int,
    tile_x: int = 0,
    tile_y: int = 0,
    tile_width: int = 0,
    tile_height: int = 0,
    channel_count: int = 0,
):
    words = [
        PACKET_MAGIC,
        PACKET_VERSION | (PACKET_HEADER_WORDS << 8) | (packet_type << 16),
        JOB_ID,
        tensor_id | (layer_id << 16),
        tile_x | (tile_y << 16),
        tile_width | (tile_height << 16),
        channel_count << 16,
        len(payload),
    ]
    beats = [(word, 0xF, 0) for word in words]
    for offset in range(0, len(payload), 4):
        chunk = payload[offset:offset + 4]
        data = int.from_bytes(chunk.ljust(4, b"\0"), "little")
        beats.append((data, (1 << len(chunk)) - 1, int(offset + 4 >= len(payload))))
    return beats


def _write_mem(path: Path, values, width: int) -> None:
    digits = (width + 3) // 4
    mask = (1 << width) - 1
    path.write_text(
        "".join(f"{int(value) & mask:0{digits}x}\n" for value in values),
        encoding="ascii",
    )


def _write_beats(output: Path, prefix: str, beats) -> None:
    _write_mem(output / f"{prefix}_data.mem", (beat[0] for beat in beats), 32)
    _write_mem(output / f"{prefix}_keep.mem", (beat[1] for beat in beats), 4)
    _write_mem(output / f"{prefix}_last.mem", (beat[2] for beat in beats), 1)


def _make_spec(seed: int):
    rng = random.Random(seed)
    shapes = [(3, 4, 1, 1, 0), (4, 3, 3, 1, 1),
              (3, 4, 1, 2, 0), (4, 2, 3, 1, 1)]
    layers = []
    for index, (cin, cout, kernel, stride, padding) in enumerate(shapes):
        assert cin == (3 if index == 0 else shapes[index - 1][1])
        weight_count = cin * cout * kernel * kernel
        bias_enable = index != 2
        layer = {
            "name": f"mixed_layer_{index}",
            "output": f"tensor_{index + 1}",
            "output_channels": cout,
            "kernel_size": kernel,
            "stride": stride,
            "padding": padding,
            "activation": "relu" if index in (1, 3) else "none",
            "bias_enable": bias_enable,
            "quant_multipliers": [rng.randint(1, 3) for _ in range(cout)],
            "quant_shifts": [rng.randint(1, 4) for _ in range(cout)],
            "tile_width_hint": 2,
            "tile_height_hint": 2,
            "weights": [rng.randint(-3, 3) for _ in range(weight_count)],
        }
        if bias_enable:
            layer["bias"] = [rng.randint(-12, 12) for _ in range(cout)]
        layers.append(layer)
    spec = {
        "format": "cnn-accelerator-model-v1",
        "model_id": 0x524E_4401,
        "model_generation_id": seed,
        "input": {"name": "input", "width": 5, "height": 5, "channels": 3},
        "layers": layers,
    }
    return spec, _tensor(5, 5, 3, rng)


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
            yield (
                tile_x, tile_y, width, height, source_x, source_y,
                max(0, source_end_x - source_x), max(0, source_end_y - source_y),
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=20260809)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    spec, input_tensor = _make_spec(args.seed)
    package = compile_model(spec)
    result, tensor_values = execute_model_package(package, input_tensor, return_tensors=True)
    header, layers, tensors, quantizations = parse_model_package(package)
    tensor_by_id = {tensor.tensor_id: tensor for tensor in tensors}

    metadata_action = []
    metadata_kind = []
    metadata_record = []
    metadata_word = []
    metadata_data = []
    records = [(0, 0, header.pack())]
    records += [(1, index, record.pack()) for index, record in enumerate(layers)]
    records += [(2, index, record.pack()) for index, record in enumerate(tensors)]
    records += [(3, index, record.pack()) for index, record in enumerate(quantizations)]
    for kind, record_index, data in records:
        for word_index, (word,) in enumerate(struct.iter_unpack("<I", data)):
            metadata_action.append(0)
            metadata_kind.append(kind)
            metadata_record.append(record_index)
            metadata_word.append(word_index)
            metadata_data.append(word)
        metadata_action.append(1)
        metadata_kind.append(kind)
        metadata_record.append(record_index)
        metadata_word.append(0)
        metadata_data.append(0)

    parameter_beats = []
    parameter_start = []
    parameter_count = []
    activation_beats = []
    activation_start = []
    activation_count = []
    expected_beats = []
    tile_count = 0
    final_layer_tile_count = 0

    for layer in layers:
        input_desc = tensor_by_id[layer.input_tensor_id]
        output_desc = tensor_by_id[layer.output_tensor_id]
        parameter_start.append(len(parameter_beats))
        weight_payload = package[layer.weight_offset:layer.weight_offset + layer.weight_size]
        parameter_beats.extend(_packet(
            PACKET_LAYER_WEIGHTS, weight_payload,
            tensor_id=layer.input_tensor_id, layer_id=layer.layer_id,
        ))
        if layer.bias_size:
            bias_payload = package[layer.bias_offset:layer.bias_offset + layer.bias_size]
            parameter_beats.extend(_packet(
                PACKET_LAYER_BIASES, bias_payload,
                tensor_id=layer.output_tensor_id, layer_id=layer.layer_id,
            ))
        parameter_count.append(len(parameter_beats) - parameter_start[-1])

        activation_start.append(len(activation_beats))
        for tile in _tile_geometry(layer, input_desc, output_desc):
            tile_x, tile_y, width, height, source_x, source_y, source_width, source_height = tile
            input_payload = _flatten_region(
                tensor_values[layer.input_tensor_id], source_x, source_y,
                source_width, source_height,
            )
            activation_beats.extend(_packet(
                PACKET_INPUT_TILE, input_payload,
                tensor_id=layer.input_tensor_id, layer_id=layer.layer_id,
                tile_x=tile_x, tile_y=tile_y, tile_width=width,
                tile_height=height, channel_count=input_desc.channels,
            ))
            output_payload = _flatten_region(
                tensor_values[layer.output_tensor_id], tile_x, tile_y, width, height,
            )
            expected_beats.extend(_packet(
                PACKET_OUTPUT_TILE, output_payload,
                tensor_id=layer.output_tensor_id, layer_id=layer.layer_id,
                tile_x=tile_x, tile_y=tile_y, tile_width=width,
                tile_height=height, channel_count=output_desc.channels,
            ))
            tile_count += 1
            if layer.layer_id == len(layers) - 1:
                final_layer_tile_count += 1
        activation_count.append(len(activation_beats) - activation_start[-1])

    _write_mem(args.output / "metadata_action.mem", metadata_action, 1)
    _write_mem(args.output / "metadata_kind.mem", metadata_kind, 2)
    _write_mem(args.output / "metadata_record.mem", metadata_record, 6)
    _write_mem(args.output / "metadata_word.mem", metadata_word, 6)
    _write_mem(args.output / "metadata_data.mem", metadata_data, 32)
    _write_mem(args.output / "parameter_start.mem", parameter_start, 16)
    _write_mem(args.output / "parameter_count.mem", parameter_count, 16)
    _write_mem(args.output / "activation_start.mem", activation_start, 16)
    _write_mem(args.output / "activation_count.mem", activation_count, 16)
    _write_beats(args.output, "parameter", parameter_beats)
    _write_beats(args.output, "activation", activation_beats)
    _write_beats(args.output, "expected", expected_beats)
    (args.output / "fixture_constants.svh").write_text(
        "\n".join([
            f"localparam int FIXTURE_LAYER_COUNT = {len(layers)};",
            f"localparam int FIXTURE_METADATA_OP_COUNT = {len(metadata_action)};",
            f"localparam int FIXTURE_PARAMETER_BEAT_COUNT = {len(parameter_beats)};",
            f"localparam int FIXTURE_ACTIVATION_BEAT_COUNT = {len(activation_beats)};",
            f"localparam int FIXTURE_EXPECTED_BEAT_COUNT = {len(expected_beats)};",
            f"localparam int FIXTURE_TILE_COUNT = {tile_count};",
            f"localparam int FIXTURE_FINAL_LAYER_TILE_COUNT = {final_layer_tile_count};",
            f"localparam logic [31:0] FIXTURE_JOB_ID = 32'h{JOB_ID:08x};",
            f"localparam logic [31:0] FIXTURE_MODEL_ID = 32'h{header.model_id:08x};",
            "",
        ]), encoding="ascii",
    )
    (args.output / "model.cnn").write_bytes(package)
    (args.output / "fixture.json").write_text(json.dumps({
        "seed": args.seed,
        "input_shape": [5, 5, 3],
        "output_shape": [len(result), len(result[0]), len(result[0][0])],
        "layer_shapes": [
            [tensor_by_id[layer.output_tensor_id].height,
             tensor_by_id[layer.output_tensor_id].width,
             tensor_by_id[layer.output_tensor_id].channels]
            for layer in layers
        ],
        "tiles": tile_count,
        "expected_beats": len(expected_beats),
    }, indent=2) + "\n", encoding="utf-8")
    print(
        f"Wrote randomized RTL fixture: layers={len(layers)} tiles={tile_count} "
        f"expected_beats={len(expected_beats)} seed={args.seed}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
