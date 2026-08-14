import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts" / "generate_uvm_closed_loop_fixture.py"


class UvmFixtureGeneratorTests(unittest.TestCase):
    def generate(self, layers: int, seed: int) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        output = Path(temporary.name)
        subprocess.run(
            [
                sys.executable,
                str(GENERATOR),
                "--output", str(output),
                "--randomized",
                "--layers", str(layers),
                "--seed", str(seed),
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        return output

    def test_layer_count_boundaries_emit_complete_contract(self):
        for layers in (1, 8):
            with self.subTest(layers=layers):
                output = self.generate(layers, 20260812 + layers)
                constants = (output / "uvm_closed_loop_fixture.svh").read_text(
                    encoding="ascii"
                )
                self.assertIn(f"UVM_FIXTURE_LAYERS = {layers};", constants)
                self.assertEqual(
                    len((output / "tensor_id.mem").read_text().splitlines()),
                    layers,
                )
                self.assertEqual(
                    len((output / "layer_output_count.mem").read_text().splitlines()),
                    layers,
                )
                self.assertTrue((output / "model.cnn").stat().st_size > 0)
                self.assertTrue((output / "activation_source_width.mem").is_file())
                self.assertTrue((output / "final_tensor.mem").stat().st_size > 0)

    def test_seed_is_reproducible(self):
        first = self.generate(4, 12345)
        second = self.generate(4, 12345)
        for filename in ("model.cnn", "activation_payload.mem", "final_tensor.mem"):
            self.assertEqual(
                (first / filename).read_bytes(),
                (second / filename).read_bytes(),
            )

    def test_numeric_fault_profiles_emit_expected_packets(self):
        for profile, residual_packets, saturation in (
            ("residual-add", 4, 0),
            ("residual-subtract", 4, 0),
            ("saturation", 0, 1),
        ):
            with self.subTest(profile=profile):
                temporary = tempfile.TemporaryDirectory()
                self.addCleanup(temporary.cleanup)
                output = Path(temporary.name)
                subprocess.run(
                    [sys.executable, str(GENERATOR), "--output", str(output),
                     "--profile", profile],
                    cwd=ROOT,
                    check=True,
                    capture_output=True,
                    text=True,
                )
                constants = (output / "uvm_closed_loop_fixture.svh").read_text(
                    encoding="ascii"
                )
                self.assertIn(
                    f"UVM_FIXTURE_RESIDUAL_PACKETS = {residual_packets};",
                    constants,
                )
                self.assertIn(
                    f"UVM_FIXTURE_EXPECT_SATURATION = {saturation};",
                    constants,
                )


if __name__ == "__main__":
    unittest.main()
