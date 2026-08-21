"""Canonical V1 model-package ABI for the programmable CNN accelerator.

The wire format is little-endian and uses fixed-size, explicitly versioned
records.  This module intentionally has no third-party dependencies so the
model compiler, CI, and bare-metal tooling can share one bit-exact contract.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum, IntFlag
import hashlib
import struct
import zlib
from typing import Mapping, Sequence

from models.cnn_abi_constants import (
    ABI_VERSION,
    BIAS_BANK_CAPACITY_BYTES,
    CAPABILITY_RECORD_SIZE,
    ERROR_RECORD_SIZE,
    LAYER_DESCRIPTOR_SIZE,
    MAX_CHANNELS,
    MAX_LAYER_BIAS_BYTES,
    MAX_LAYER_WEIGHT_BYTES,
    MAX_LAYERS,
    MAX_QUANTIZATIONS,
    MAX_TENSORS,
    MAX_TENSOR_HEIGHT,
    MAX_TENSOR_WIDTH,
    MODEL_HEADER_SIZE,
    MODEL_MAGIC,
    NO_TENSOR_ID,
    POSTPROCESS_BANK_CAPACITY_BYTES,
    POSTPROCESS_ENTRY_SIZE,
    QUANT_DESCRIPTOR_SIZE,
    RECORD_ALIGNMENT,
    REGISTER_MAP_VERSION,
    TENSOR_DESCRIPTOR_SIZE,
    WEIGHT_BANK_CAPACITY_BYTES,
)


class AbiError(ValueError):
    """Raised when a binary record or model violates the V1 ABI."""


class Opcode(IntEnum):
    CONV2D = 1


class LayerFlags(IntFlag):
    BIAS_ENABLE = 1 << 0
    LAST_LAYER = 1 << 1


KNOWN_LAYER_FLAGS = int(LayerFlags.BIAS_ENABLE | LayerFlags.LAST_LAYER)


class TensorFlags(IntFlag):
    MODEL_INPUT = 1 << 0
    MODEL_OUTPUT = 1 << 1
    CONSTANT = 1 << 2


KNOWN_TENSOR_FLAGS = int(
    TensorFlags.MODEL_INPUT | TensorFlags.MODEL_OUTPUT | TensorFlags.CONSTANT
)


class ElementType(IntEnum):
    INT8 = 1


class TensorLayout(IntEnum):
    NHWC = 1


class Activation(IntEnum):
    NONE = 0
    RELU = 1


class ResidualMode(IntEnum):
    NONE = 0
    POST_QUANT_ADD = 1
    POST_QUANT_SUBTRACT = 2


class RoundingMode(IntEnum):
    ARITHMETIC_SHIFT = 0
    ROUND_HALF_TO_EVEN = 1


class ModelStagingState(IntEnum):
    UNLOADED = 0
    LOADING = 1
    LOADED_UNVALIDATED = 2
    VALIDATED = 3


class ModelLifecycleError(IntEnum):
    NONE = 0
    BAD_STATE = 1
    BUSY = 2
    BAD_ADDRESS = 3
    INCOMPLETE = 4
    BAD_HEADER = 5
    LIMIT = 6
    BAD_DESCRIPTOR = 7


class CapabilityFeature(IntFlag):
    CAPABILITY_QUERY = 1 << 0
    STRUCTURED_ERRORS = 1 << 1
    MODEL_PACKAGES = 1 << 2
    RUNTIME_METADATA = 1 << 3
    PACKED_DMA = 1 << 4
    DDR_TILING = 1 << 5
    AUTONOMOUS_FETCH = 1 << 6
    INTERRUPTS = 1 << 7
    FIXED_NETWORK = 1 << 31


class ErrorCode(IntEnum):
    NONE = 0
    PACKAGE_VALIDATION_FAILED = 0x0101
    MODEL_ABI_UNSUPPORTED = 0x0102
    CAPABILITY_FEATURE_MISSING = 0x0201
    CAPABILITY_LIMIT_EXCEEDED = 0x0202
    UNSUPPORTED_OPERATION = 0x0203
    DATA_PLANE_PROTOCOL = 0x0400


class ErrorStage(IntEnum):
    NONE = 0
    PACKAGE_LOAD = 1
    PACKAGE_VALIDATE = 2
    MODEL_ACTIVATE = 3
    EXECUTE = 4
    DATA_PLANE = 5


class ErrorRecordKind(IntEnum):
    NONE = 0
    MODEL = 1
    LAYER = 2
    TENSOR = 3
    QUANTIZATION = 4
    PACKET = 5


class ErrorField(IntEnum):
    NONE = 0
    ABI_VERSION = 1
    FEATURE_FLAGS = 2
    LAYER_COUNT = 3
    TENSOR_COUNT = 4
    QUANTIZATION_COUNT = 5
    WIDTH = 6
    HEIGHT = 7
    INPUT_CHANNELS = 8
    OUTPUT_CHANNELS = 9
    OPCODE = 10
    KERNEL_SIZE = 11
    STRIDE = 12
    PADDING = 13
    WEIGHT_BYTES = 14
    BIAS_BYTES = 15
    ELEMENT_TYPE = 16
    ACTIVATION = 17
    ROUNDING_MODE = 18
    RESIDUAL_MODE = 19
    PACKET_TYPE = 20
    PAYLOAD_LENGTH = 21
    TENSOR_ELEMENTS = 22
    QUANT_MULTIPLIER = 23
    QUANT_SHIFT = 24
    OUTPUT_ZERO_POINT = 25


class CapabilityError(AbiError):
    """Raised with a machine-readable record when hardware cannot run a model."""

    def __init__(self, message: str, record: "ErrorRecord") -> None:
        super().__init__(message)
        self.record = record


def _check_u(name: str, value: int, bits: int) -> None:
    if not 0 <= int(value) < (1 << bits):
        raise AbiError(f"{name}={value} does not fit unsigned {bits} bits")


def _check_i(name: str, value: int, bits: int) -> None:
    low = -(1 << (bits - 1))
    high = (1 << (bits - 1)) - 1
    if not low <= int(value) <= high:
        raise AbiError(f"{name}={value} does not fit signed {bits} bits")


def _require_zero(data: bytes, start: int, end: int, record: str) -> None:
    if any(data[start:end]):
        raise AbiError(f"{record} reserved bytes {start}..{end - 1} must be zero")


def _enum(enum_type: type[IntEnum], value: int, field: str) -> IntEnum:
    try:
        return enum_type(value)
    except ValueError as exc:
        raise AbiError(f"unsupported {field} value {value}") from exc


@dataclass(frozen=True)
class ModelHeader:
    package_size: int
    model_id: int
    model_generation_id: int
    layer_count: int
    tensor_count: int
    quantization_count: int
    layer_table_offset: int
    tensor_table_offset: int
    quantization_table_offset: int
    parameter_data_offset: int
    parameter_data_size: int
    input_tensor_id: int
    output_tensor_id: int
    workspace_size: int
    package_crc32: int = 0
    package_sha256: bytes = bytes(32)
    flags: int = 0

    def pack(self) -> bytes:
        if len(self.package_sha256) != 32:
            raise AbiError("package_sha256 must contain exactly 32 bytes")
        for name, value in (
            ("package_size", self.package_size),
            ("model_id", self.model_id),
            ("model_generation_id", self.model_generation_id),
            ("layer_table_offset", self.layer_table_offset),
            ("tensor_table_offset", self.tensor_table_offset),
            ("quantization_table_offset", self.quantization_table_offset),
            ("parameter_data_offset", self.parameter_data_offset),
            ("parameter_data_size", self.parameter_data_size),
            ("workspace_size", self.workspace_size),
            ("package_crc32", self.package_crc32),
            ("flags", self.flags),
        ):
            _check_u(name, value, 32)
        for name, value in (
            ("layer_count", self.layer_count),
            ("tensor_count", self.tensor_count),
            ("quantization_count", self.quantization_count),
            ("input_tensor_id", self.input_tensor_id),
            ("output_tensor_id", self.output_tensor_id),
        ):
            _check_u(name, value, 16)

        out = bytearray(MODEL_HEADER_SIZE)
        struct.pack_into("<IHH", out, 0, MODEL_MAGIC, ABI_VERSION, MODEL_HEADER_SIZE)
        struct.pack_into("<IIII", out, 8, self.package_size, self.flags, self.model_id,
                         self.model_generation_id)
        struct.pack_into("<HHHH", out, 24, self.layer_count, self.tensor_count,
                         self.quantization_count, 0)
        struct.pack_into("<IIIIIII", out, 32, self.layer_table_offset,
                         self.tensor_table_offset, self.quantization_table_offset,
                         self.parameter_data_offset, self.parameter_data_size,
                         self.workspace_size, self.package_crc32)
        struct.pack_into("<HH", out, 60, self.input_tensor_id, self.output_tensor_id)
        out[64:96] = self.package_sha256
        return bytes(out)

    @classmethod
    def unpack(cls, data: bytes) -> "ModelHeader":
        if len(data) != MODEL_HEADER_SIZE:
            raise AbiError(f"model header must be {MODEL_HEADER_SIZE} bytes")
        magic, version, size = struct.unpack_from("<IHH", data, 0)
        if magic != MODEL_MAGIC:
            raise AbiError(f"bad model magic 0x{magic:08x}")
        if version != ABI_VERSION or size != MODEL_HEADER_SIZE:
            raise AbiError(f"unsupported model header version/size {version}/{size}")
        _require_zero(data, 30, 32, "model header")
        _require_zero(data, 96, 128, "model header")
        package_size, flags, model_id, generation = struct.unpack_from("<IIII", data, 8)
        layer_count, tensor_count, quant_count = struct.unpack_from("<HHH", data, 24)
        values = struct.unpack_from("<IIIIIII", data, 32)
        input_id, output_id = struct.unpack_from("<HH", data, 60)
        return cls(
            package_size=package_size,
            flags=flags,
            model_id=model_id,
            model_generation_id=generation,
            layer_count=layer_count,
            tensor_count=tensor_count,
            quantization_count=quant_count,
            layer_table_offset=values[0],
            tensor_table_offset=values[1],
            quantization_table_offset=values[2],
            parameter_data_offset=values[3],
            parameter_data_size=values[4],
            workspace_size=values[5],
            package_crc32=values[6],
            input_tensor_id=input_id,
            output_tensor_id=output_id,
            package_sha256=bytes(data[64:96]),
        )


@dataclass(frozen=True)
class LayerDescriptor:
    layer_id: int
    input_tensor_id: int
    output_tensor_id: int
    quantization_id: int
    weight_offset: int
    weight_size: int
    bias_offset: int
    bias_size: int
    parameter_crc32: int
    kernel_height: int
    kernel_width: int
    stride_y: int
    stride_x: int
    padding_top: int
    padding_bottom: int
    padding_left: int
    padding_right: int
    activation: Activation = Activation.NONE
    residual_mode: ResidualMode = ResidualMode.NONE
    residual_tensor_id: int = NO_TENSOR_ID
    tile_height_hint: int = 0
    tile_width_hint: int = 0
    opcode: Opcode = Opcode.CONV2D
    flags: LayerFlags = LayerFlags.BIAS_ENABLE
    dilation_y: int = 1
    dilation_x: int = 1

    def pack(self) -> bytes:
        for name, value in (
            ("layer_id", self.layer_id), ("input_tensor_id", self.input_tensor_id),
            ("output_tensor_id", self.output_tensor_id),
            ("residual_tensor_id", self.residual_tensor_id),
            ("quantization_id", self.quantization_id),
            ("tile_height_hint", self.tile_height_hint),
            ("tile_width_hint", self.tile_width_hint),
        ):
            _check_u(name, value, 16)
        for name, value in (
            ("weight_offset", self.weight_offset), ("weight_size", self.weight_size),
            ("bias_offset", self.bias_offset), ("bias_size", self.bias_size),
            ("parameter_crc32", self.parameter_crc32),
        ):
            _check_u(name, value, 32)
        if int(self.flags) & ~KNOWN_LAYER_FLAGS:
            raise AbiError(f"unknown layer flags 0x{int(self.flags):08x}")

        out = bytearray(LAYER_DESCRIPTOR_SIZE)
        struct.pack_into("<HHHHI", out, 0, ABI_VERSION, LAYER_DESCRIPTOR_SIZE,
                         self.layer_id, int(self.opcode), int(self.flags))
        struct.pack_into("<HHHH", out, 12, self.input_tensor_id, self.output_tensor_id,
                         self.residual_tensor_id, self.quantization_id)
        struct.pack_into("<IIIII", out, 20, self.weight_offset, self.weight_size,
                         self.bias_offset, self.bias_size, self.parameter_crc32)
        struct.pack_into("<12B", out, 40, self.kernel_height, self.kernel_width,
                         self.stride_y, self.stride_x, self.padding_top,
                         self.padding_bottom, self.padding_left, self.padding_right,
                         self.dilation_y, self.dilation_x, int(self.activation),
                         int(self.residual_mode))
        struct.pack_into("<HH", out, 52, self.tile_height_hint, self.tile_width_hint)
        return bytes(out)

    @classmethod
    def unpack(cls, data: bytes) -> "LayerDescriptor":
        if len(data) != LAYER_DESCRIPTOR_SIZE:
            raise AbiError(f"layer descriptor must be {LAYER_DESCRIPTOR_SIZE} bytes")
        version, size, layer_id, opcode, flags = struct.unpack_from("<HHHHI", data, 0)
        if version != ABI_VERSION or size != LAYER_DESCRIPTOR_SIZE:
            raise AbiError(f"unsupported layer descriptor version/size {version}/{size}")
        if flags & ~KNOWN_LAYER_FLAGS:
            raise AbiError(f"unknown layer flags 0x{flags:08x}")
        _require_zero(data, 56, 128, "layer descriptor")
        tensor_ids = struct.unpack_from("<HHHH", data, 12)
        params = struct.unpack_from("<IIIII", data, 20)
        geometry = struct.unpack_from("<12B", data, 40)
        tile_h, tile_w = struct.unpack_from("<HH", data, 52)
        return cls(
            layer_id=layer_id,
            opcode=_enum(Opcode, opcode, "opcode"),
            flags=LayerFlags(flags),
            input_tensor_id=tensor_ids[0], output_tensor_id=tensor_ids[1],
            residual_tensor_id=tensor_ids[2], quantization_id=tensor_ids[3],
            weight_offset=params[0], weight_size=params[1], bias_offset=params[2],
            bias_size=params[3], parameter_crc32=params[4],
            kernel_height=geometry[0], kernel_width=geometry[1],
            stride_y=geometry[2], stride_x=geometry[3],
            padding_top=geometry[4], padding_bottom=geometry[5],
            padding_left=geometry[6], padding_right=geometry[7],
            dilation_y=geometry[8], dilation_x=geometry[9],
            activation=_enum(Activation, geometry[10], "activation"),
            residual_mode=_enum(ResidualMode, geometry[11], "residual mode"),
            tile_height_hint=tile_h, tile_width_hint=tile_w,
        )


@dataclass(frozen=True)
class TensorDescriptor:
    tensor_id: int
    ddr_offset: int
    allocation_size: int
    width: int
    height: int
    channels: int
    quantization_id: int
    lifetime_begin: int
    lifetime_end: int
    row_stride: int
    pixel_stride: int
    channel_stride: int = 1
    element_type: ElementType = ElementType.INT8
    layout: TensorLayout = TensorLayout.NHWC
    flags: TensorFlags = TensorFlags(0)

    def pack(self) -> bytes:
        for name, value in (
            ("tensor_id", self.tensor_id), ("flags", int(self.flags)),
            ("width", self.width), ("height", self.height),
            ("channels", self.channels), ("quantization_id", self.quantization_id),
            ("lifetime_begin", self.lifetime_begin), ("lifetime_end", self.lifetime_end),
        ):
            _check_u(name, value, 16)
        _check_u("ddr_offset", self.ddr_offset, 64)
        for name, value in (
            ("allocation_size", self.allocation_size), ("row_stride", self.row_stride),
            ("pixel_stride", self.pixel_stride), ("channel_stride", self.channel_stride),
        ):
            _check_u(name, value, 32)
        if int(self.flags) & ~KNOWN_TENSOR_FLAGS:
            raise AbiError(f"unknown tensor flags 0x{int(self.flags):04x}")

        out = bytearray(TENSOR_DESCRIPTOR_SIZE)
        struct.pack_into("<HHHH", out, 0, ABI_VERSION, TENSOR_DESCRIPTOR_SIZE,
                         self.tensor_id, int(self.flags))
        struct.pack_into("<QI", out, 8, self.ddr_offset, self.allocation_size)
        struct.pack_into("<HHHBBHHH", out, 20, self.width, self.height, self.channels,
                         int(self.element_type), int(self.layout), self.quantization_id,
                         self.lifetime_begin, self.lifetime_end)
        struct.pack_into("<III", out, 36, self.row_stride, self.pixel_stride,
                         self.channel_stride)
        return bytes(out)

    @classmethod
    def unpack(cls, data: bytes) -> "TensorDescriptor":
        if len(data) != TENSOR_DESCRIPTOR_SIZE:
            raise AbiError(f"tensor descriptor must be {TENSOR_DESCRIPTOR_SIZE} bytes")
        version, size, tensor_id, flags = struct.unpack_from("<HHHH", data, 0)
        if version != ABI_VERSION or size != TENSOR_DESCRIPTOR_SIZE:
            raise AbiError(f"unsupported tensor descriptor version/size {version}/{size}")
        if flags & ~KNOWN_TENSOR_FLAGS:
            raise AbiError(f"unknown tensor flags 0x{flags:04x}")
        _require_zero(data, 34, 36, "tensor descriptor")
        _require_zero(data, 48, 64, "tensor descriptor")
        ddr_offset, allocation_size = struct.unpack_from("<QI", data, 8)
        shape = struct.unpack_from("<HHHBBHHH", data, 20)
        row_stride, pixel_stride, channel_stride = struct.unpack_from("<III", data, 36)
        return cls(
            tensor_id=tensor_id, flags=TensorFlags(flags), ddr_offset=ddr_offset,
            allocation_size=allocation_size, width=shape[0], height=shape[1],
            channels=shape[2], element_type=_enum(ElementType, shape[3], "element type"),
            layout=_enum(TensorLayout, shape[4], "tensor layout"),
            quantization_id=shape[5], lifetime_begin=shape[6], lifetime_end=shape[7],
            row_stride=row_stride, pixel_stride=pixel_stride,
            channel_stride=channel_stride,
        )


@dataclass(frozen=True)
class QuantizationDescriptor:
    quantization_id: int
    channel_count: int = 1
    quant_multipliers: tuple[int, ...] = (1,)
    quant_shifts: tuple[int, ...] = (0,)
    output_zero_point: int = 0
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_TO_EVEN
    flags: int = 0

    def pack(self) -> bytes:
        _check_u("quantization_id", self.quantization_id, 16)
        _check_u("flags", self.flags, 16)
        _check_u("channel_count", self.channel_count, 16)
        if not 1 <= self.channel_count <= MAX_CHANNELS:
            raise AbiError(f"channel_count must be in range 1..{MAX_CHANNELS}")
        if len(self.quant_multipliers) != self.channel_count:
            raise AbiError("quant_multipliers length must match channel_count")
        if len(self.quant_shifts) != self.channel_count:
            raise AbiError("quant_shifts length must match channel_count")
        _check_i("output_zero_point", self.output_zero_point, 8)
        out = bytearray(QUANT_DESCRIPTOR_SIZE)
        struct.pack_into("<HHHH", out, 0, ABI_VERSION, QUANT_DESCRIPTOR_SIZE,
                         self.quantization_id, self.flags)
        struct.pack_into("<HBb", out, 8, self.channel_count,
                         int(self.rounding_mode), self.output_zero_point)
        for channel, (multiplier, shift) in enumerate(
            zip(self.quant_multipliers, self.quant_shifts)
        ):
            _check_i(f"quant_multipliers[{channel}]", multiplier, 32)
            _check_u(f"quant_shifts[{channel}]", shift, 8)
            struct.pack_into("<iB", out, 64 + channel * 8, multiplier, shift)
        return bytes(out)

    @classmethod
    def unpack(cls, data: bytes) -> "QuantizationDescriptor":
        if len(data) != QUANT_DESCRIPTOR_SIZE:
            raise AbiError(f"quant descriptor must be {QUANT_DESCRIPTOR_SIZE} bytes")
        version, size, quant_id, flags = struct.unpack_from("<HHHH", data, 0)
        if version != ABI_VERSION or size != QUANT_DESCRIPTOR_SIZE:
            raise AbiError(f"unsupported quant descriptor version/size {version}/{size}")
        channel_count, rounding, zero_point = struct.unpack_from("<HBb", data, 8)
        if not 1 <= channel_count <= MAX_CHANNELS:
            raise AbiError(f"quant channel_count must be in range 1..{MAX_CHANNELS}")
        _require_zero(data, 12, 64, "quant descriptor")
        multipliers = []
        shifts = []
        for channel in range(MAX_CHANNELS):
            offset = 64 + channel * 8
            multiplier, shift = struct.unpack_from("<iB", data, offset)
            _require_zero(data, offset + 5, offset + 8, "quant channel entry")
            if channel < channel_count:
                multipliers.append(multiplier)
                shifts.append(shift)
            elif multiplier != 0 or shift != 0:
                raise AbiError("unused quant channel entries must be zero")
        return cls(
            quantization_id=quant_id, flags=flags, channel_count=channel_count,
            quant_multipliers=tuple(multipliers), quant_shifts=tuple(shifts),
            output_zero_point=zero_point,
            rounding_mode=_enum(RoundingMode, rounding, "rounding mode"),
        )


@dataclass(frozen=True)
class CapabilityRecord:
    hardware_interface_version: int
    model_abi_version: int
    dma_data_width_bytes: int
    feature_flags: CapabilityFeature
    opcode_mask: int
    element_type_mask: int
    activation_mask: int
    rounding_mode_mask: int
    residual_mode_mask: int
    kernel_size_mask: int
    stride_mask: int
    max_layers: int
    max_tensors: int
    max_quantizations: int
    max_input_channels: int
    max_output_channels: int
    max_tensor_width: int
    max_tensor_height: int
    max_padding_per_edge: int
    max_tile_width: int
    max_tile_height: int
    max_tensor_elements: int
    weight_bank_capacity_bytes: int
    bias_bank_capacity_bytes: int
    max_layer_weight_bytes: int
    max_layer_bias_bytes: int
    record_alignment_bytes: int
    parameter_alignment_bytes: int
    parallel_input_channels: int
    parallel_output_channels: int
    clock_hz: int

    def pack(self) -> bytes:
        out = bytearray(CAPABILITY_RECORD_SIZE)
        struct.pack_into("<HHIHH", out, 0, ABI_VERSION, CAPABILITY_RECORD_SIZE,
                         self.hardware_interface_version, self.model_abi_version,
                         self.dma_data_width_bytes)
        struct.pack_into("<8I", out, 12, int(self.feature_flags), self.opcode_mask,
                         self.element_type_mask, self.activation_mask,
                         self.rounding_mode_mask, self.residual_mode_mask,
                         self.kernel_size_mask, self.stride_mask)
        struct.pack_into(
            "<10H", out, 44, self.max_layers, self.max_tensors,
            self.max_quantizations, self.max_input_channels,
            self.max_output_channels, self.max_tensor_width,
            self.max_tensor_height, self.max_padding_per_edge,
            self.max_tile_width, self.max_tile_height,
        )
        struct.pack_into(
            "<5I", out, 64, self.max_tensor_elements,
            self.weight_bank_capacity_bytes, self.bias_bank_capacity_bytes,
            self.max_layer_weight_bytes, self.max_layer_bias_bytes,
        )
        struct.pack_into(
            "<4HI", out, 84, self.record_alignment_bytes,
            self.parameter_alignment_bytes, self.parallel_input_channels,
            self.parallel_output_channels, self.clock_hz,
        )
        return bytes(out)

    @classmethod
    def unpack(cls, data: bytes) -> "CapabilityRecord":
        if len(data) != CAPABILITY_RECORD_SIZE:
            raise AbiError(f"capability record must be {CAPABILITY_RECORD_SIZE} bytes")
        version, size, hardware_version, model_abi, dma_bytes = struct.unpack_from(
            "<HHIHH", data, 0
        )
        if version != ABI_VERSION or size != CAPABILITY_RECORD_SIZE:
            raise AbiError(f"unsupported capability record version/size {version}/{size}")
        masks = struct.unpack_from("<8I", data, 12)
        limits = struct.unpack_from("<10H", data, 44)
        capacities = struct.unpack_from("<5I", data, 64)
        alignment = struct.unpack_from("<4HI", data, 84)
        _require_zero(data, 96, 128, "capability record")
        return cls(
            hardware_interface_version=hardware_version,
            model_abi_version=model_abi,
            dma_data_width_bytes=dma_bytes,
            feature_flags=CapabilityFeature(masks[0]), opcode_mask=masks[1],
            element_type_mask=masks[2], activation_mask=masks[3],
            rounding_mode_mask=masks[4], residual_mode_mask=masks[5],
            kernel_size_mask=masks[6], stride_mask=masks[7],
            max_layers=limits[0], max_tensors=limits[1],
            max_quantizations=limits[2], max_input_channels=limits[3],
            max_output_channels=limits[4], max_tensor_width=limits[5],
            max_tensor_height=limits[6], max_padding_per_edge=limits[7],
            max_tile_width=limits[8], max_tile_height=limits[9],
            max_tensor_elements=capacities[0],
            weight_bank_capacity_bytes=capacities[1],
            bias_bank_capacity_bytes=capacities[2],
            max_layer_weight_bytes=capacities[3],
            max_layer_bias_bytes=capacities[4],
            record_alignment_bytes=alignment[0],
            parameter_alignment_bytes=alignment[1],
            parallel_input_channels=alignment[2],
            parallel_output_channels=alignment[3], clock_hz=alignment[4],
        )


@dataclass(frozen=True)
class ErrorRecord:
    error_code: ErrorCode
    stage: ErrorStage
    record_kind: ErrorRecordKind = ErrorRecordKind.NONE
    record_index: int = 0
    field_id: ErrorField = ErrorField.NONE
    observed_value: int = 0
    expected_min: int = 0
    expected_max: int = 0
    model_id: int = 0
    model_generation_id: int = 0
    detail: int = 0
    flags: int = 0

    def pack(self) -> bytes:
        out = bytearray(ERROR_RECORD_SIZE)
        struct.pack_into("<HHI", out, 0, ABI_VERSION, ERROR_RECORD_SIZE,
                         int(self.error_code))
        struct.pack_into("<BBH", out, 8, int(self.stage), int(self.record_kind), self.flags)
        struct.pack_into("<HH", out, 12, self.record_index, int(self.field_id))
        struct.pack_into("<QQQ", out, 16, self.observed_value,
                         self.expected_min, self.expected_max)
        struct.pack_into("<III", out, 40, self.model_id,
                         self.model_generation_id, self.detail)
        return bytes(out)

    @classmethod
    def unpack(cls, data: bytes) -> "ErrorRecord":
        if len(data) != ERROR_RECORD_SIZE:
            raise AbiError(f"error record must be {ERROR_RECORD_SIZE} bytes")
        version, size, code = struct.unpack_from("<HHI", data, 0)
        if version != ABI_VERSION or size != ERROR_RECORD_SIZE:
            raise AbiError(f"unsupported error record version/size {version}/{size}")
        stage, kind, flags = struct.unpack_from("<BBH", data, 8)
        record_index, field = struct.unpack_from("<HH", data, 12)
        observed, expected_min, expected_max = struct.unpack_from("<QQQ", data, 16)
        model_id, generation, detail = struct.unpack_from("<III", data, 40)
        _require_zero(data, 52, 64, "error record")
        return cls(
            error_code=_enum(ErrorCode, code, "error code"),
            stage=_enum(ErrorStage, stage, "error stage"),
            record_kind=_enum(ErrorRecordKind, kind, "error record kind"),
            record_index=record_index,
            field_id=_enum(ErrorField, field, "error field"),
            flags=flags, observed_value=observed,
            expected_min=expected_min, expected_max=expected_max,
            model_id=model_id, model_generation_id=generation, detail=detail,
        )


def target_v1_capabilities(
    *,
    parallel_input_channels: int = 2,
    parallel_output_channels: int = 4,
    clock_hz: int = 125_000_000,
) -> CapabilityRecord:
    """Return the final V1 architectural capability envelope."""
    return CapabilityRecord(
        hardware_interface_version=REGISTER_MAP_VERSION,
        model_abi_version=ABI_VERSION,
        dma_data_width_bytes=4,
        feature_flags=(
            CapabilityFeature.CAPABILITY_QUERY
            | CapabilityFeature.STRUCTURED_ERRORS
            | CapabilityFeature.MODEL_PACKAGES
            | CapabilityFeature.RUNTIME_METADATA
            | CapabilityFeature.PACKED_DMA
            | CapabilityFeature.DDR_TILING
            | CapabilityFeature.AUTONOMOUS_FETCH
            | CapabilityFeature.INTERRUPTS
        ),
        opcode_mask=1 << int(Opcode.CONV2D),
        element_type_mask=1 << int(ElementType.INT8),
        activation_mask=(1 << int(Activation.NONE)) | (1 << int(Activation.RELU)),
        rounding_mode_mask=1 << int(RoundingMode.ROUND_HALF_TO_EVEN),
        residual_mode_mask=(
            (1 << int(ResidualMode.NONE))
            | (1 << int(ResidualMode.POST_QUANT_ADD))
            | (1 << int(ResidualMode.POST_QUANT_SUBTRACT))
        ),
        kernel_size_mask=(1 << 1) | (1 << 3),
        stride_mask=(1 << 1) | (1 << 2),
        max_layers=MAX_LAYERS, max_tensors=MAX_TENSORS,
        max_quantizations=MAX_QUANTIZATIONS,
        max_input_channels=MAX_CHANNELS, max_output_channels=MAX_CHANNELS,
        max_tensor_width=MAX_TENSOR_WIDTH, max_tensor_height=MAX_TENSOR_HEIGHT,
        max_padding_per_edge=1, max_tile_width=16, max_tile_height=16,
        max_tensor_elements=MAX_TENSOR_WIDTH * MAX_TENSOR_HEIGHT,
        weight_bank_capacity_bytes=WEIGHT_BANK_CAPACITY_BYTES,
        bias_bank_capacity_bytes=POSTPROCESS_BANK_CAPACITY_BYTES,
        max_layer_weight_bytes=MAX_LAYER_WEIGHT_BYTES,
        max_layer_bias_bytes=MAX_LAYER_BIAS_BYTES,
        record_alignment_bytes=RECORD_ALIGNMENT,
        parameter_alignment_bytes=64,
        parallel_input_channels=parallel_input_channels,
        parallel_output_channels=parallel_output_channels,
        clock_hz=clock_hz,
    )


def fixed_hardware_capabilities(
    *,
    max_input_channels: int = 16,
    max_output_channels: int = 16,
    max_pixels: int = 16,
    parallel_input_channels: int = 2,
    parallel_output_channels: int = 4,
    clock_hz: int = 125_000_000,
) -> CapabilityRecord:
    """Describe the current fixed three-layer board implementation honestly."""
    return CapabilityRecord(
        hardware_interface_version=REGISTER_MAP_VERSION,
        model_abi_version=ABI_VERSION,
        dma_data_width_bytes=4,
        feature_flags=(
            CapabilityFeature.CAPABILITY_QUERY
            | CapabilityFeature.STRUCTURED_ERRORS
            | CapabilityFeature.RUNTIME_METADATA
            | CapabilityFeature.INTERRUPTS
            | CapabilityFeature.FIXED_NETWORK
        ),
        opcode_mask=1 << int(Opcode.CONV2D),
        element_type_mask=1 << int(ElementType.INT8),
        activation_mask=(1 << int(Activation.NONE)) | (1 << int(Activation.RELU)),
        rounding_mode_mask=1 << int(RoundingMode.ARITHMETIC_SHIFT),
        residual_mode_mask=(
            (1 << int(ResidualMode.NONE))
            | (1 << int(ResidualMode.POST_QUANT_SUBTRACT))
        ),
        kernel_size_mask=1 << 3,
        stride_mask=1 << 1,
        max_layers=3, max_tensors=4, max_quantizations=3,
        max_input_channels=max_input_channels,
        max_output_channels=max_output_channels,
        max_tensor_width=max_pixels, max_tensor_height=max_pixels,
        max_padding_per_edge=1, max_tile_width=1, max_tile_height=1,
        max_tensor_elements=max_pixels,
        weight_bank_capacity_bytes=MAX_LAYER_WEIGHT_BYTES,
        bias_bank_capacity_bytes=MAX_LAYER_BIAS_BYTES,
        max_layer_weight_bytes=MAX_LAYER_WEIGHT_BYTES,
        max_layer_bias_bytes=MAX_LAYER_BIAS_BYTES,
        record_alignment_bytes=1, parameter_alignment_bytes=1,
        parallel_input_channels=parallel_input_channels,
        parallel_output_channels=parallel_output_channels,
        clock_hz=clock_hz,
    )


def validate_package_capabilities(package: bytes, capabilities: CapabilityRecord) -> None:
    """Raise ``CapabilityError`` with structured context if a package cannot run."""
    header, layers, tensors, quantizations = parse_model_package(package)

    def reject(message, code, kind, index, field, observed, expected_min, expected_max):
        raise CapabilityError(
            message,
            ErrorRecord(
                error_code=code, stage=ErrorStage.PACKAGE_VALIDATE,
                record_kind=kind, record_index=index, field_id=field,
                observed_value=observed, expected_min=expected_min,
                expected_max=expected_max, model_id=header.model_id,
                model_generation_id=header.model_generation_id,
            ),
        )

    if capabilities.model_abi_version != ABI_VERSION:
        reject(
            "hardware does not support the package ABI version",
            ErrorCode.MODEL_ABI_UNSUPPORTED, ErrorRecordKind.MODEL, 0,
            ErrorField.ABI_VERSION, ABI_VERSION,
            capabilities.model_abi_version, capabilities.model_abi_version,
        )
    if not capabilities.feature_flags & CapabilityFeature.MODEL_PACKAGES:
        reject(
            "hardware does not implement runtime model packages",
            ErrorCode.CAPABILITY_FEATURE_MISSING, ErrorRecordKind.MODEL, 0,
            ErrorField.FEATURE_FLAGS, int(CapabilityFeature.MODEL_PACKAGES),
            int(CapabilityFeature.MODEL_PACKAGES),
            int(CapabilityFeature.MODEL_PACKAGES),
        )

    for count, maximum, field in (
        (len(layers), capabilities.max_layers, ErrorField.LAYER_COUNT),
        (len(tensors), capabilities.max_tensors, ErrorField.TENSOR_COUNT),
        (len(quantizations), capabilities.max_quantizations,
         ErrorField.QUANTIZATION_COUNT),
    ):
        if count > maximum:
            reject(
                f"package {field.name.lower()} exceeds hardware capability",
                ErrorCode.CAPABILITY_LIMIT_EXCEEDED, ErrorRecordKind.MODEL, 0,
                field, count, 0, maximum,
            )

    tensor_by_id = {tensor.tensor_id: tensor for tensor in tensors}
    for quantization in quantizations:
        if not capabilities.rounding_mode_mask & (
            1 << int(quantization.rounding_mode)
        ):
            reject(
                f"quantization {quantization.quantization_id} uses unsupported "
                "rounding mode",
                ErrorCode.UNSUPPORTED_OPERATION,
                ErrorRecordKind.QUANTIZATION,
                quantization.quantization_id,
                ErrorField.ROUNDING_MODE,
                int(quantization.rounding_mode),
                0,
                capabilities.rounding_mode_mask,
            )

    for tensor in tensors:
        for observed, maximum, field in (
            (tensor.width, capabilities.max_tensor_width, ErrorField.WIDTH),
            (tensor.height, capabilities.max_tensor_height, ErrorField.HEIGHT),
            (tensor.width * tensor.height, capabilities.max_tensor_elements,
             ErrorField.TENSOR_ELEMENTS),
        ):
            if observed > maximum:
                reject(
                    f"tensor {tensor.tensor_id} exceeds {field.name.lower()} capability",
                    ErrorCode.CAPABILITY_LIMIT_EXCEEDED,
                    ErrorRecordKind.TENSOR, tensor.tensor_id, field,
                    observed, 1, maximum,
                )
        if not capabilities.element_type_mask & (1 << int(tensor.element_type)):
            reject(
                f"tensor {tensor.tensor_id} element type is unsupported",
                ErrorCode.UNSUPPORTED_OPERATION, ErrorRecordKind.TENSOR,
                tensor.tensor_id, ErrorField.ELEMENT_TYPE,
                int(tensor.element_type), 0, capabilities.element_type_mask,
            )

    for layer in layers:
        input_tensor = tensor_by_id[layer.input_tensor_id]
        output_tensor = tensor_by_id[layer.output_tensor_id]
        checks = (
            (input_tensor.channels, capabilities.max_input_channels,
             ErrorField.INPUT_CHANNELS),
            (output_tensor.channels, capabilities.max_output_channels,
             ErrorField.OUTPUT_CHANNELS),
            (layer.weight_size, capabilities.max_layer_weight_bytes,
             ErrorField.WEIGHT_BYTES),
            (layer.bias_size, capabilities.max_layer_bias_bytes,
             ErrorField.BIAS_BYTES),
        )
        for observed, maximum, field in checks:
            if observed > maximum:
                reject(
                    f"layer {layer.layer_id} exceeds {field.name.lower()} capability",
                    ErrorCode.CAPABILITY_LIMIT_EXCEEDED, ErrorRecordKind.LAYER,
                    layer.layer_id, field, observed, 0, maximum,
                )
        bit_checks = (
            (int(layer.opcode), capabilities.opcode_mask, ErrorField.OPCODE),
            (layer.kernel_width, capabilities.kernel_size_mask,
             ErrorField.KERNEL_SIZE),
            (layer.stride_x, capabilities.stride_mask, ErrorField.STRIDE),
            (layer.stride_y, capabilities.stride_mask, ErrorField.STRIDE),
            (int(layer.activation), capabilities.activation_mask,
             ErrorField.ACTIVATION),
            (int(layer.residual_mode), capabilities.residual_mode_mask,
             ErrorField.RESIDUAL_MODE),
        )
        for observed, mask, field in bit_checks:
            if not mask & (1 << observed):
                reject(
                    f"layer {layer.layer_id} uses unsupported {field.name.lower()}",
                    ErrorCode.UNSUPPORTED_OPERATION, ErrorRecordKind.LAYER,
                    layer.layer_id, field, observed, 0, mask,
                )
        maximum_padding = max(
            layer.padding_top, layer.padding_bottom,
            layer.padding_left, layer.padding_right,
        )
        if maximum_padding > capabilities.max_padding_per_edge:
            reject(
                f"layer {layer.layer_id} padding exceeds hardware capability",
                ErrorCode.CAPABILITY_LIMIT_EXCEEDED, ErrorRecordKind.LAYER,
                layer.layer_id, ErrorField.PADDING, maximum_padding,
                0, capabilities.max_padding_per_edge,
            )


def parameter_crc32(weight_bytes: bytes, bias_bytes: bytes) -> int:
    """Return the V1 layer CRC over exact weight bytes followed by bias bytes."""
    return zlib.crc32(bias_bytes, zlib.crc32(weight_bytes)) & 0xFFFFFFFF


def compute_package_sha256(package: bytes) -> bytes:
    """Compute the V1 package digest with checksum fields canonicalized."""
    if len(package) < MODEL_HEADER_SIZE:
        raise AbiError("package is smaller than the model header")
    canonical = bytearray(package)
    canonical[56:60] = bytes(4)
    canonical[64:96] = bytes(32)
    return hashlib.sha256(canonical).digest()


def compute_package_crc32(package: bytes) -> int:
    """Compute the V1 package CRC with only its CRC field set to zero."""
    if len(package) < MODEL_HEADER_SIZE:
        raise AbiError("package is smaller than the model header")
    canonical = bytearray(package)
    canonical[56:60] = bytes(4)
    return zlib.crc32(canonical) & 0xFFFFFFFF


def parse_model_package(package: bytes, *, verify_integrity: bool = True):
    """Parse, integrity-check, and semantically validate a complete package."""
    if len(package) < MODEL_HEADER_SIZE:
        raise AbiError("package is smaller than the model header")
    header = ModelHeader.unpack(package[:MODEL_HEADER_SIZE])
    if len(package) != header.package_size:
        raise AbiError(
            f"package buffer has {len(package)} bytes, header declares {header.package_size}"
        )
    if verify_integrity:
        if compute_package_sha256(package) != header.package_sha256:
            raise AbiError("package SHA-256 mismatch")
        if compute_package_crc32(package) != header.package_crc32:
            raise AbiError("package CRC32 mismatch")

    layers = _unpack_table(
        package, header.layer_table_offset, header.layer_count,
        LAYER_DESCRIPTOR_SIZE, LayerDescriptor,
    )
    tensors = _unpack_table(
        package, header.tensor_table_offset, header.tensor_count,
        TENSOR_DESCRIPTOR_SIZE, TensorDescriptor,
    )
    quantizations = _unpack_table(
        package, header.quantization_table_offset, header.quantization_count,
        QUANT_DESCRIPTOR_SIZE, QuantizationDescriptor,
    )
    validate_model(header, layers, tensors, quantizations)
    for layer in layers:
        weights = package[layer.weight_offset:layer.weight_offset + layer.weight_size]
        biases = package[layer.bias_offset:layer.bias_offset + layer.bias_size]
        if parameter_crc32(weights, biases) != layer.parameter_crc32:
            raise AbiError(f"layer {layer.layer_id} parameter CRC32 mismatch")
    return header, layers, tensors, quantizations


def validate_model(
    header: ModelHeader,
    layers: Sequence[LayerDescriptor],
    tensors: Sequence[TensorDescriptor],
    quantizations: Sequence[QuantizationDescriptor],
) -> None:
    """Validate all cross-record invariants required by the V1 accelerator."""
    if header.flags != 0:
        raise AbiError(f"unknown model flags 0x{header.flags:08x}")
    if not 1 <= len(layers) <= MAX_LAYERS:
        raise AbiError(f"layer count must be in range 1..{MAX_LAYERS}")
    if not 2 <= len(tensors) <= MAX_TENSORS:
        raise AbiError(f"tensor count must be in range 2..{MAX_TENSORS}")
    if not 1 <= len(quantizations) <= MAX_QUANTIZATIONS:
        raise AbiError(f"quantization count must be in range 1..{MAX_QUANTIZATIONS}")
    if (header.layer_count, header.tensor_count, header.quantization_count) != (
        len(layers), len(tensors), len(quantizations)
    ):
        raise AbiError("header table counts do not match supplied records")

    table_regions = (
        ("layer table", header.layer_table_offset, len(layers) * LAYER_DESCRIPTOR_SIZE),
        ("tensor table", header.tensor_table_offset, len(tensors) * TENSOR_DESCRIPTOR_SIZE),
        ("quant table", header.quantization_table_offset,
         len(quantizations) * QUANT_DESCRIPTOR_SIZE),
        ("parameter data", header.parameter_data_offset, header.parameter_data_size),
    )
    for name, offset, size in table_regions:
        if offset % RECORD_ALIGNMENT:
            raise AbiError(f"{name} offset {offset} is not {RECORD_ALIGNMENT}-byte aligned")
        if offset < MODEL_HEADER_SIZE or offset + size > header.package_size:
            raise AbiError(f"{name} lies outside package_size={header.package_size}")
    for index, (name_a, start_a, size_a) in enumerate(table_regions):
        for name_b, start_b, size_b in table_regions[index + 1:]:
            if size_a and size_b and start_a < start_b + size_b and start_b < start_a + size_a:
                raise AbiError(f"{name_a} overlaps {name_b}")

    tensor_by_id: Mapping[int, TensorDescriptor] = _unique_by_id(
        tensors, "tensor", lambda item: item.tensor_id
    )
    quant_by_id: Mapping[int, QuantizationDescriptor] = _unique_by_id(
        quantizations, "quantization", lambda item: item.quantization_id
    )
    layer_by_id = _unique_by_id(layers, "layer", lambda item: item.layer_id)
    if set(layer_by_id) != set(range(len(layers))):
        raise AbiError("layer IDs must be contiguous in execution order starting at zero")
    if header.input_tensor_id not in tensor_by_id or header.output_tensor_id not in tensor_by_id:
        raise AbiError("model input/output tensor ID is missing from tensor table")
    if not tensor_by_id[header.input_tensor_id].flags & TensorFlags.MODEL_INPUT:
        raise AbiError("entry input tensor is missing MODEL_INPUT flag")
    if not tensor_by_id[header.output_tensor_id].flags & TensorFlags.MODEL_OUTPUT:
        raise AbiError("entry output tensor is missing MODEL_OUTPUT flag")

    for quant in quantizations:
        if quant.flags != 0:
            raise AbiError(f"quantization {quant.quantization_id} has unknown flags")
        if not 1 <= quant.channel_count <= MAX_CHANNELS:
            raise AbiError("V1 quantization channel_count is outside capability")
        if len(quant.quant_multipliers) != quant.channel_count:
            raise AbiError("V1 quantization multiplier count does not match channels")
        if len(quant.quant_shifts) != quant.channel_count:
            raise AbiError("V1 quantization shift count does not match channels")
        if any(multiplier <= 0 for multiplier in quant.quant_multipliers):
            raise AbiError("V1 quantization multipliers must be positive INT32 values")
        if any(not 0 <= shift <= 62 for shift in quant.quant_shifts):
            raise AbiError("V1 quantization shifts must be in range 0..62")
        if quant.output_zero_point != 0:
            raise AbiError("V1 supports symmetric output_zero_point=0 only")
        if quant.rounding_mode != RoundingMode.ROUND_HALF_TO_EVEN:
            raise AbiError("V1 requires round-half-to-even requantization")

    for tensor in tensors:
        if not 1 <= tensor.width <= MAX_TENSOR_WIDTH:
            raise AbiError(f"tensor {tensor.tensor_id} width is outside V1 capability")
        if not 1 <= tensor.height <= MAX_TENSOR_HEIGHT:
            raise AbiError(f"tensor {tensor.tensor_id} height is outside V1 capability")
        if not 1 <= tensor.channels <= MAX_CHANNELS:
            raise AbiError(f"tensor {tensor.tensor_id} channels are outside V1 capability")
        if tensor.quantization_id not in quant_by_id:
            raise AbiError(f"tensor {tensor.tensor_id} references missing quantization")
        if quant_by_id[tensor.quantization_id].channel_count != tensor.channels:
            raise AbiError(
                f"tensor {tensor.tensor_id} channel count does not match quantization"
            )
        if tensor.element_type != ElementType.INT8 or tensor.layout != TensorLayout.NHWC:
            raise AbiError(f"tensor {tensor.tensor_id} must be signed INT8 NHWC in V1")
        if tensor.channel_stride != 1 or tensor.pixel_stride < tensor.channels:
            raise AbiError(f"tensor {tensor.tensor_id} has invalid NHWC channel/pixel stride")
        if tensor.row_stride < tensor.width * tensor.pixel_stride:
            raise AbiError(f"tensor {tensor.tensor_id} row stride is too small")
        required = ((tensor.height - 1) * tensor.row_stride
                    + (tensor.width - 1) * tensor.pixel_stride
                    + tensor.channels)
        if tensor.allocation_size < required:
            raise AbiError(f"tensor {tensor.tensor_id} allocation is smaller than its strides require")
        if tensor.lifetime_begin > tensor.lifetime_end or tensor.lifetime_end > len(layers):
            raise AbiError(f"tensor {tensor.tensor_id} has invalid lifetime")
        if tensor.ddr_offset + tensor.allocation_size > header.workspace_size:
            raise AbiError(f"tensor {tensor.tensor_id} lies outside model workspace")
    for index, tensor_a in enumerate(tensors):
        for tensor_b in tensors[index + 1:]:
            address_overlap = (
                tensor_a.ddr_offset < tensor_b.ddr_offset + tensor_b.allocation_size
                and tensor_b.ddr_offset < tensor_a.ddr_offset + tensor_a.allocation_size
            )
            lifetime_overlap = (
                tensor_a.lifetime_begin <= tensor_b.lifetime_end
                and tensor_b.lifetime_begin <= tensor_a.lifetime_end
            )
            if address_overlap and lifetime_overlap:
                raise AbiError(
                    f"tensor {tensor_a.tensor_id} and tensor {tensor_b.tensor_id} "
                    "overlap in DDR while both are live"
                )

    for index, layer in enumerate(layers):
        if layer.layer_id != index:
            raise AbiError("layer table order must match contiguous layer IDs")
        if layer.opcode != Opcode.CONV2D:
            raise AbiError(f"layer {index} uses unsupported opcode")
        if layer.kernel_height != layer.kernel_width or layer.kernel_width not in (1, 3):
            raise AbiError(f"layer {index} kernel must be square 1x1 or 3x3")
        if layer.stride_x not in (1, 2) or layer.stride_y not in (1, 2):
            raise AbiError(f"layer {index} stride must be 1 or 2")
        if any(pad not in (0, 1) for pad in (
            layer.padding_top, layer.padding_bottom, layer.padding_left, layer.padding_right
        )):
            raise AbiError(f"layer {index} padding must be 0 or 1 per edge")
        if layer.dilation_x != 1 or layer.dilation_y != 1:
            raise AbiError(f"layer {index} dilation must be one in V1")
        if layer.input_tensor_id not in tensor_by_id or layer.output_tensor_id not in tensor_by_id:
            raise AbiError(f"layer {index} references a missing input/output tensor")
        if layer.quantization_id not in quant_by_id:
            raise AbiError(f"layer {index} references a missing quantization")

        input_tensor = tensor_by_id[layer.input_tensor_id]
        output_tensor = tensor_by_id[layer.output_tensor_id]
        if layer.quantization_id != output_tensor.quantization_id:
            raise AbiError(f"layer {index} quantization must match its output tensor")
        expected_w = ((input_tensor.width + layer.padding_left + layer.padding_right
                       - layer.kernel_width) // layer.stride_x) + 1
        expected_h = ((input_tensor.height + layer.padding_top + layer.padding_bottom
                       - layer.kernel_height) // layer.stride_y) + 1
        if (output_tensor.width, output_tensor.height) != (expected_w, expected_h):
            raise AbiError(f"layer {index} output tensor shape does not match convolution geometry")

        expected_weights = (layer.kernel_width * layer.kernel_height
                            * input_tensor.channels * output_tensor.channels)
        expected_bias = output_tensor.channels * 4 if layer.flags & LayerFlags.BIAS_ENABLE else 0
        if layer.weight_size != expected_weights or layer.weight_size > MAX_LAYER_WEIGHT_BYTES:
            raise AbiError(f"layer {index} weight payload size is invalid")
        if layer.bias_size != expected_bias or layer.bias_size > MAX_LAYER_BIAS_BYTES:
            raise AbiError(f"layer {index} bias payload size is invalid")
        if layer.weight_size > WEIGHT_BANK_CAPACITY_BYTES or layer.bias_size > BIAS_BANK_CAPACITY_BYTES:
            raise AbiError(f"layer {index} exceeds physical parameter bank capacity")
        for name, offset, size, alignment in (
            ("weight", layer.weight_offset, layer.weight_size, 64),
            ("bias", layer.bias_offset, layer.bias_size, 4),
        ):
            if size and offset % alignment:
                raise AbiError(f"layer {index} {name} offset is not {alignment}-byte aligned")
            if size and not (header.parameter_data_offset <= offset
                             and offset + size <= header.parameter_data_offset
                             + header.parameter_data_size):
                raise AbiError(f"layer {index} {name} payload lies outside parameter data")

        if layer.residual_mode == ResidualMode.NONE:
            if layer.residual_tensor_id != NO_TENSOR_ID:
                raise AbiError(f"layer {index} has residual tensor with residual mode NONE")
        else:
            residual = tensor_by_id.get(layer.residual_tensor_id)
            if residual is None:
                raise AbiError(f"layer {index} references a missing residual tensor")
            if (residual.width, residual.height, residual.channels) != (
                output_tensor.width, output_tensor.height, output_tensor.channels
            ):
                raise AbiError(f"layer {index} residual tensor shape does not match output")
            if residual.quantization_id != output_tensor.quantization_id:
                raise AbiError(f"layer {index} residual and output quantization IDs must match")

        should_be_last = index == len(layers) - 1
        if bool(layer.flags & LayerFlags.LAST_LAYER) != should_be_last:
            raise AbiError("LAST_LAYER must be set on exactly the final descriptor")


def _unique_by_id(items, kind: str, get_id):
    result = {}
    for item in items:
        item_id = get_id(item)
        if item_id in result:
            raise AbiError(f"duplicate {kind} ID {item_id}")
        result[item_id] = item
    return result


def _unpack_table(package, offset, count, record_size, record_type):
    records = []
    for index in range(count):
        start = offset + index * record_size
        end = start + record_size
        if end > len(package):
            raise AbiError(f"{record_type.__name__} table exceeds package bounds")
        records.append(record_type.unpack(package[start:end]))
    return records
