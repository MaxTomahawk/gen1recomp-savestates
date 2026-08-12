import json
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "release_gate.py"


class ReleaseGateTests(unittest.TestCase):
    def run_gate(self, manifest, tag):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "manifest.json"
            path.write_text(json.dumps(manifest), encoding="utf-8")
            return subprocess.run(
                ["python3", str(SCRIPT), str(path), tag],
                text=True,
                capture_output=True,
                check=False,
            )

    def release_manifest(self, **overrides):
        manifest = {
            "version": "1.0.0",
            "experimental": False,
            "game_version": ">=0.1.79 <1.0.0",
        }
        manifest.update(overrides)
        return manifest

    def test_emits_exact_minimum_engine_release_ref(self):
        result = self.run_gate(self.release_manifest(), "v1.0.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "engine_ref=v0.1.79\n")

    def test_rejects_tag_that_does_not_match_manifest(self):
        result = self.run_gate(self.release_manifest(), "v1.0.1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match", result.stderr)

    def test_rejects_experimental_release(self):
        result = self.run_gate(
            self.release_manifest(experimental=True), "v1.0.0"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("experimental", result.stderr)

    def test_rejects_dev_or_ambiguous_minimum(self):
        for game_range in (">=0.0.0-dev <1.0.0", ">0.1.75 <1.0.0"):
            with self.subTest(game_range=game_range):
                result = self.run_gate(
                    self.release_manifest(game_version=game_range), "v1.0.0"
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("released minimum", result.stderr)


if __name__ == "__main__":
    unittest.main()
