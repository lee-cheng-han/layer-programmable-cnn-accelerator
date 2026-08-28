import dataclasses
import json
from pathlib import Path
import re
import struct
import unittest

from models.cnn_abi import (
    ABI_VERSION,
    CAPABILITY_RECORD_SIZE,
    ERROR_RECORD_SIZE,
    LAYER_DESCRIPTOR_SIZE,
    MODEL_HEADER_SIZE,
    QUANT_DESCRIPTOR_SIZE,
    REGISTER_MAP_VERSION,
    TENSOR_DESCRIPTOR_SIZE,
    AbiError,
    Activation,
    CapabilityError,
    CapabilityFeature,
    CapabilityRecord,
    ErrorCode,
    ErrorField,
    ErrorRecord,
    ErrorRecordKind,
    ErrorStage,
    LayerDescriptor,
    LayerFlags,
    ModelHeader,
    QuantizationDescriptor,
    RoundingMode,
    ResidualMode,
    TensorDescriptor,
    TensorFlags,
    compute_package_crc32,
    compute_package_sha256,
    fixed_hardware_capabilities,
    parse_model_package,
    parameter_crc32,
    target_v1_capabilities,
    validate_package_capabilities,
    validate_model,
)


def valid_model():
    tensors = [
        TensorDescriptor(0, 0, 48, 4, 4, 3, 0, 0, 1, 12, 3,
                         flags=TensorFlags.MODEL_INPUT),
        TensorDescriptor(1, 64, 48, 4, 4, 3, 0, 1, 1, 12, 3,
                         flags=TensorFlags.MODEL_OUTPUT),
    ]
    quant = [QuantizationDescriptor(
        0,
        channel_count=3,
        quant_multipliers=(1, 3, 5),
        quant_shifts=(4, 5, 6),
    )]
    layers = [
        LayerDescriptor(
            layer_id=0, input_tensor_id=0, output_tensor_id=1,
            quantization_id=0, weight_offset=640, weight_size=81,
            bias_offset=724, bias_size=12, parameter_crc32=0x12345678,
            kernel_height=3, kernel_width=3, stride_y=1, stride_x=1,
            padding_top=1, padding_bottom=1, padding_left=1, padding_right=1,
            activation=Activation.RELU, flags=LayerFlags.BIAS_ENABLE | LayerFlags.LAST_LAYER,
        )
    ]
    header = ModelHeader(
        package_size=768, model_id=7, model_generation_id=9,
        layer_count=1, tensor_count=2, quantization_count=1,
        layer_table_offset=128, tensor_table_offset=256,
        quantization_table_offset=384, parameter_data_offset=640,
        parameter_data_size=128, input_tensor_id=0, output_tensor_id=1,
        workspace_size=128,
    )
    return header, layers, tensors, quant


def encoded_valid_package():
    header, layers, tensors, quant = valid_model()
    weight_bytes = bytes(range(81))
    bias_bytes = bytes(range(12))
    layers[0] = dataclasses.replace(
        layers[0], parameter_crc32=parameter_crc32(weight_bytes, bias_bytes)
    )
    package = bytearray(header.package_size)
    package[:MODEL_HEADER_SIZE] = header.pack()
    package[header.layer_table_offset:header.layer_table_offset + LAYER_DESCRIPTOR_SIZE] = layers[0].pack()
    for index, tensor in enumerate(tensors):
        start = header.tensor_table_offset + index * TENSOR_DESCRIPTOR_SIZE
        package[start:start + TENSOR_DESCRIPTOR_SIZE] = tensor.pack()
    package[header.quantization_table_offset:header.quantization_table_offset
            + QUANT_DESCRIPTOR_SIZE] = quant[0].pack()
    package[640:721] = weight_bytes
    package[724:736] = bias_bytes
    header = dataclasses.replace(header, package_sha256=compute_package_sha256(package))
    package[:MODEL_HEADER_SIZE] = header.pack()
    header = dataclasses.replace(header, package_crc32=compute_package_crc32(package))
    package[:MODEL_HEADER_SIZE] = header.pack()
    return bytes(package)


class TestCnnAbi(unittest.TestCase):
    def test_record_sizes_and_round_trips(self):
        header, layers, tensors, quant = valid_model()
        records = (
            (header, ModelHeader, MODEL_HEADER_SIZE),
            (layers[0], LayerDescriptor, LAYER_DESCRIPTOR_SIZE),
            (tensors[0], TensorDescriptor, TENSOR_DESCRIPTOR_SIZE),
            (quant[0], QuantizationDescriptor, QUANT_DESCRIPTOR_SIZE),
        )
        for record, record_type, expected_size in records:
            encoded = record.pack()
            self.assertEqual(len(encoded), expected_size)
            self.assertEqual(record_type.unpack(encoded), record)

    def test_capability_and_error_record_round_trips(self):
        capabilities = target_v1_capabilities()
        encoded_capabilities = capabilities.pack()
        self.assertEqual(len(encoded_capabilities), CAPABILITY_RECORD_SIZE)
        self.assertEqual(CapabilityRecord.unpack(encoded_capabilities), capabilities)

        error = ErrorRecord(
            error_code=ErrorCode.CAPABILITY_LIMIT_EXCEEDED,
            stage=ErrorStage.PACKAGE_VALIDATE,
            record_kind=ErrorRecordKind.LAYER,
            record_index=5,
            field_id=ErrorField.OUTPUT_CHANNELS,
            observed_value=32,
            expected_min=1,
            expected_max=16,
            model_id=7,
            model_generation_id=9,
            detail=0xA5,
        )
        encoded_error = error.pack()
        self.assertEqual(len(encoded_error), ERROR_RECORD_SIZE)
        self.assertEqual(ErrorRecord.unpack(encoded_error), error)

    def test_fixed_capability_words_match_axi_lite_contract(self):
        words = struct.unpack("<32I", fixed_hardware_capabilities().pack())
        self.assertEqual(words[0], 0x00800001)
        self.assertEqual(words[1], REGISTER_MAP_VERSION)
        self.assertEqual(words[2], 0x00040001)
        self.assertEqual(words[3], 0x8000008B)
        self.assertEqual(words[11], 0x00040003)
        self.assertEqual(words[13], 0x00100010)
        self.assertEqual(words[16], 16)
        self.assertEqual(words[22], 0x00040002)
        self.assertEqual(words[23], 125_000_000)

    def test_binary_is_little_endian_and_versioned(self):
        header, layers, _, _ = valid_model()
        encoded = header.pack()
        self.assertEqual(encoded[:4], b"CNN1")
        self.assertEqual(struct.unpack_from("<H", encoded, 4)[0], ABI_VERSION)
        self.assertEqual(struct.unpack_from("<I", layers[0].pack(), 20)[0], 640)

    def test_reserved_bytes_are_rejected(self):
        _, layers, _, _ = valid_model()
        encoded = bytearray(layers[0].pack())
        encoded[127] = 1
        with self.assertRaisesRegex(AbiError, "reserved bytes"):
            LayerDescriptor.unpack(bytes(encoded))

    def test_unknown_flags_are_rejected(self):
        _, layers, _, _ = valid_model()
        encoded = bytearray(layers[0].pack())
        struct.pack_into("<I", encoded, 8, 0x80000000)
        with self.assertRaisesRegex(AbiError, "unknown layer flags"):
            LayerDescriptor.unpack(bytes(encoded))

    def test_parameter_crc_covers_weights_then_biases(self):
        self.assertEqual(parameter_crc32(b"weights", b"bias"), 0x54E5C5F8)
        self.assertNotEqual(parameter_crc32(b"bias", b"weights"), 0x54E5C5F8)

    def test_c_and_systemverilog_constants_match_python(self):
        root = Path(__file__).resolve().parents[1]
        c_header = (root / "software/zynq_baremetal/cnn_accel_abi_constants.h").read_text()
        sv_package = (root / "rtl/include/cnn_accel_abi_constants.svh").read_text()
        expected = {
            "ABI_VERSION": ABI_VERSION,
            "MODEL_HEADER_SIZE": MODEL_HEADER_SIZE,
            "LAYER_DESCRIPTOR_SIZE": LAYER_DESCRIPTOR_SIZE,
            "TENSOR_DESCRIPTOR_SIZE": TENSOR_DESCRIPTOR_SIZE,
            "QUANT_DESCRIPTOR_SIZE": QUANT_DESCRIPTOR_SIZE,
            "CAPABILITY_RECORD_SIZE": CAPABILITY_RECORD_SIZE,
            "ERROR_RECORD_SIZE": ERROR_RECORD_SIZE,
        }
        c_names = {
            "ABI_VERSION": "CNN_ABI_VERSION",
            "MODEL_HEADER_SIZE": "CNN_MODEL_HEADER_SIZE",
            "LAYER_DESCRIPTOR_SIZE": "CNN_LAYER_DESCRIPTOR_SIZE",
            "TENSOR_DESCRIPTOR_SIZE": "CNN_TENSOR_DESCRIPTOR_SIZE",
            "QUANT_DESCRIPTOR_SIZE": "CNN_QUANT_DESCRIPTOR_SIZE",
            "CAPABILITY_RECORD_SIZE": "CNN_CAPABILITY_RECORD_SIZE",
            "ERROR_RECORD_SIZE": "CNN_ERROR_RECORD_SIZE",
        }
        sv_names = {
            "ABI_VERSION": "ABI_VERSION",
            "MODEL_HEADER_SIZE": "MODEL_HEADER_BYTES",
            "LAYER_DESCRIPTOR_SIZE": "LAYER_DESCRIPTOR_BYTES",
            "TENSOR_DESCRIPTOR_SIZE": "TENSOR_DESCRIPTOR_BYTES",
            "QUANT_DESCRIPTOR_SIZE": "QUANT_DESCRIPTOR_BYTES",
            "CAPABILITY_RECORD_SIZE": "CAPABILITY_RECORD_BYTES",
            "ERROR_RECORD_SIZE": "ERROR_RECORD_BYTES",
        }
        for key, value in expected.items():
            self.assertRegex(
                c_header,
                rf"#define\s+{c_names[key]}\s+0x{value:08X}u",
            )
            self.assertRegex(sv_package, rf"{sv_names[key]}\s*=\s*{value};")

    def test_generated_register_map_version_is_consistent(self):
        root = Path(__file__).resolve().parents[1]
        c_header = (root / "software/zynq_baremetal/cnn_accel_abi_constants.h").read_text()
        sv_package = (root / "rtl/include/cnn_accel_abi_constants.svh").read_text()
        self.assertIn(f"0x{REGISTER_MAP_VERSION:08X}u", c_header)
        self.assertIn(f"32'h{REGISTER_MAP_VERSION:08X}", sv_package)

    def test_generated_record_layouts_match_schema_in_every_language(self):
        root = Path(__file__).resolve().parents[1]
        schema = json.loads((root / "abi/cnn_accel_v1.json").read_text())
        python_constants = (
            root / "models/cnn_abi_constants.py"
        ).read_text()
        c_header = (
            root / "software/zynq_baremetal/cnn_accel_abi_constants.h"
        ).read_text()
        sv_constants = (
            root / "rtl/include/cnn_accel_abi_constants.svh"
        ).read_text()
        for record, fields in schema["record_fields"].items():
            for field, (offset, size) in fields.items():
                stem = f"{record}_{field}"
                self.assertRegex(python_constants, rf"(?m)^{stem}_OFS = {offset}$")
                self.assertRegex(python_constants, rf"(?m)^{stem}_SIZE = {size}$")
                self.assertIn(
                    f"#define CNN_{stem}_OFS 0x{offset:03X}u", c_header
                )
                self.assertIn(
                    f"#define CNN_{stem}_SIZE 0x{size:03X}u", c_header
                )
                self.assertIn(
                    f"localparam int unsigned {stem}_OFS = {offset};",
                    sv_constants,
                )
                self.assertIn(
                    f"localparam int unsigned {stem}_SIZE = {size};",
                    sv_constants,
                )

    def test_complete_valid_model(self):
        validate_model(*valid_model())

    def test_complete_package_integrity_and_parse(self):
        package = encoded_valid_package()
        header, layers, tensors, quant = parse_model_package(package)
        self.assertEqual(header.model_id, 7)
        self.assertEqual([layer.layer_id for layer in layers], [0])
        self.assertEqual([tensor.tensor_id for tensor in tensors], [0, 1])
        self.assertEqual([item.quantization_id for item in quant], [0])

        corrupted = bytearray(package)
        corrupted[-1] ^= 1
        with self.assertRaisesRegex(AbiError, "SHA-256 mismatch"):
            parse_model_package(bytes(corrupted))

    def test_package_matches_final_v1_capabilities(self):
        validate_package_capabilities(
            encoded_valid_package(), target_v1_capabilities()
        )

    def test_fixed_hardware_honestly_rejects_model_packages(self):
        capabilities = fixed_hardware_capabilities()
        self.assertTrue(capabilities.feature_flags & CapabilityFeature.FIXED_NETWORK)
        self.assertFalse(capabilities.feature_flags & CapabilityFeature.MODEL_PACKAGES)
        with self.assertRaises(CapabilityError) as caught:
            validate_package_capabilities(encoded_valid_package(), capabilities)
        error = caught.exception.record
        self.assertEqual(error.error_code, ErrorCode.CAPABILITY_FEATURE_MISSING)
        self.assertEqual(error.field_id, ErrorField.FEATURE_FLAGS)
        self.assertEqual(error.model_id, 7)

    def test_structured_limit_error_identifies_tensor_and_field(self):
        capabilities = dataclasses.replace(
            target_v1_capabilities(), max_tensor_width=3
        )
        with self.assertRaises(CapabilityError) as caught:
            validate_package_capabilities(encoded_valid_package(), capabilities)
        error = caught.exception.record
        self.assertEqual(error.record_kind, ErrorRecordKind.TENSOR)
        self.assertEqual(error.record_index, 0)
        self.assertEqual(error.field_id, ErrorField.WIDTH)
        self.assertEqual(error.observed_value, 4)
        self.assertEqual(error.expected_max, 3)

    def test_structured_error_rejects_unsupported_rounding_mode(self):
        capabilities = dataclasses.replace(
            target_v1_capabilities(),
            rounding_mode_mask=1 << int(RoundingMode.ARITHMETIC_SHIFT),
        )
        with self.assertRaises(CapabilityError) as caught:
            validate_package_capabilities(encoded_valid_package(), capabilities)
        error = caught.exception.record
        self.assertEqual(error.error_code, ErrorCode.UNSUPPORTED_OPERATION)
        self.assertEqual(error.record_kind, ErrorRecordKind.QUANTIZATION)
        self.assertEqual(error.record_index, 0)
        self.assertEqual(error.field_id, ErrorField.ROUNDING_MODE)
        self.assertEqual(error.observed_value, RoundingMode.ROUND_HALF_TO_EVEN)

    def test_rejects_parameter_corruption_even_with_rebuilt_package_checksums(self):
        package = bytearray(encoded_valid_package())
        package[640] ^= 1
        header = ModelHeader.unpack(package[:MODEL_HEADER_SIZE])
        header = dataclasses.replace(
            header, package_crc32=0, package_sha256=bytes(32)
        )
        package[:MODEL_HEADER_SIZE] = header.pack()
        header = dataclasses.replace(header, package_sha256=compute_package_sha256(package))
        package[:MODEL_HEADER_SIZE] = header.pack()
        header = dataclasses.replace(header, package_crc32=compute_package_crc32(package))
        package[:MODEL_HEADER_SIZE] = header.pack()
        with self.assertRaisesRegex(AbiError, "parameter CRC32 mismatch"):
            parse_model_package(bytes(package))

    def test_rejects_live_tensor_allocation_overlap(self):
        header, layers, tensors, quant = valid_model()
        tensors[1] = dataclasses.replace(tensors[1], ddr_offset=32)
        with self.assertRaisesRegex(AbiError, "overlap in DDR"):
            validate_model(header, layers, tensors, quant)

    def test_rejects_unsupported_quantization(self):
        header, layers, tensors, quant = valid_model()
        quant[0] = dataclasses.replace(quant[0], quant_multipliers=(1, 0, 5))
        with self.assertRaisesRegex(AbiError, "multipliers must be positive"):
            validate_model(header, layers, tensors, quant)

        quant[0] = dataclasses.replace(
            valid_model()[3][0], rounding_mode=RoundingMode.ARITHMETIC_SHIFT
        )
        with self.assertRaisesRegex(AbiError, "round-half-to-even"):
            validate_model(header, layers, tensors, quant)

    def test_rejects_tensor_beyond_functional_maximum(self):
        header, layers, tensors, quant = valid_model()
        tensors[0] = dataclasses.replace(tensors[0], width=1025, row_stride=3075,
                                         allocation_size=12300)
        with self.assertRaisesRegex(AbiError, "width is outside"):
            validate_model(header, layers, tensors, quant)

    def test_rejects_wrong_parameter_length(self):
        header, layers, tensors, quant = valid_model()
        layers[0] = dataclasses.replace(layers[0], weight_size=80)
        with self.assertRaisesRegex(AbiError, "weight payload size"):
            validate_model(header, layers, tensors, quant)

    def test_rejects_residual_quantization_mismatch(self):
        header, layers, tensors, quant = valid_model()
        quant.append(QuantizationDescriptor(
            1, channel_count=3, quant_multipliers=(1, 1, 1), quant_shifts=(0, 0, 0)
        ))
        header = dataclasses.replace(
            header, package_size=896, quantization_count=2,
            parameter_data_offset=768,
        )
        layers[0] = dataclasses.replace(
            layers[0], weight_offset=768, bias_offset=852
        )
        tensors[0] = dataclasses.replace(tensors[0], quantization_id=1)
        layers[0] = dataclasses.replace(
            layers[0], residual_mode=ResidualMode.POST_QUANT_SUBTRACT,
            residual_tensor_id=0,
        )
        with self.assertRaisesRegex(AbiError, "quantization IDs must match"):
            validate_model(header, layers, tensors, quant)


if __name__ == "__main__":
    unittest.main()
