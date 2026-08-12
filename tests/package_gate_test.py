import importlib.util
import json
import pathlib
import tempfile
import unittest
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "package_gate", ROOT / "tools" / "package_gate.py"
)
package_gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package_gate)


class PackageGateTest(unittest.TestCase):
    def package(self, directory, packed_at):
        path = pathlib.Path(directory) / "mod.zip"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("manifest.json", "{}")
            archive.writestr(
                ".modkit/pack.json", json.dumps({"packed_at": packed_at})
            )
        return path

    def test_accepts_expected_source_epoch(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.package(directory, "2009-02-13T23:31:30Z")
            self.assertEqual(package_gate.validate(path, 1234567890), True)

    def test_rejects_wall_clock_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.package(directory, "2026-08-07T15:00:00Z")
            with self.assertRaisesRegex(package_gate.GateError, "packed_at"):
                package_gate.validate(path, 1234567890)

    def test_rejects_missing_or_invalid_pack_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "mod.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("manifest.json", "{}")
            with self.assertRaisesRegex(package_gate.GateError, "pack.json"):
                package_gate.validate(path, 1234567890)


if __name__ == "__main__":
    unittest.main()
