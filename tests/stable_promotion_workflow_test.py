import importlib.util
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "stable_promotion_gate", ROOT / "tools" / "stable_promotion_gate.py"
)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class StablePromotionGateTests(unittest.TestCase):
    def valid_pr(self):
        return {
            "state": "OPEN",
            "isDraft": False,
            "baseRefName": "main",
            "headRefName": "automation/engine-feature-status-merged-v0.1.80-merged-v0.1.82",
            "headRepository": {"name": "gen1recomp-savestates"},
            "headRepositoryOwner": {"login": "MaxTomahawk"},
            "files": [
                {"path": "README.md"},
                {"path": "manifest.json"},
                {"path": "mod.card"},
                {"path": "index/MaxTomahawk@savestates/meta.json"},
                {"path": "index/MaxTomahawk@savestates/description.md"},
            ],
            "statusCheckRollup": [
                {"name": "stable-rom-free", "status": "COMPLETED", "conclusion": "SUCCESS"}
            ],
        }

    def test_accepts_only_same_repository_green_allowlisted_promotion(self):
        gate.validate_pr(self.valid_pr())

    def test_rejects_unexpected_file_or_repository(self):
        pr = self.valid_pr()
        pr["files"].append({"path": "main.lua"})
        with self.assertRaisesRegex(ValueError, "unexpected promotion file"):
            gate.validate_pr(pr)

        pr = self.valid_pr()
        pr["headRepositoryOwner"]["login"] = "attacker"
        with self.assertRaisesRegex(ValueError, "same repository"):
            gate.validate_pr(pr)

    def test_rejects_pending_or_failed_named_check(self):
        for status, conclusion in (("IN_PROGRESS", ""), ("COMPLETED", "FAILURE")):
            with self.subTest(status=status, conclusion=conclusion):
                pr = self.valid_pr()
                pr["statusCheckRollup"][0].update(
                    status=status, conclusion=conclusion
                )
                with self.assertRaisesRegex(ValueError, "stable-rom-free check"):
                    gate.validate_pr(pr)

    def test_tag_decision_is_idempotent_but_refuses_collision(self):
        self.assertEqual(gate.tag_decision(None, "abc123"), "create")
        self.assertEqual(gate.tag_decision("abc123", "abc123"), "current")
        with self.assertRaisesRegex(ValueError, "different commit"):
            gate.tag_decision("deadbeef", "abc123")

    def test_workflows_auto_merge_tag_and_explicitly_dispatch_release(self):
        watcher = (ROOT / ".github/workflows/engine-feature-status.yml").read_text()
        release = (ROOT / ".github/workflows/release.yml").read_text()
        orchestrator = (ROOT / "tools/auto_promote_stable.sh").read_text()
        self.assertIn("python3 tools/stable_promotion_gate.py", orchestrator)
        self.assertIn("gh pr merge", orchestrator)
        self.assertIn("git/refs", orchestrator)
        self.assertIn("gh workflow run release.yml", orchestrator)
        self.assertIn("actions: write", watcher)
        self.assertIn("steps.update.outputs.changed == 'true'", watcher)
        self.assertIn("workflow_dispatch:", release)


if __name__ == "__main__":
    unittest.main()
