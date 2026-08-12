import importlib.util
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "engine_feature_status", ROOT / "tools" / "update_engine_feature_status.py"
)
engine_feature_status = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(engine_feature_status)


class EngineFeatureStatusTests(unittest.TestCase):
    def readme(self):
        return """# Save States

<!-- engine-feature-status:start -->
old status
<!-- engine-feature-status:end -->

## Features
Body remains untouched.
"""

    def test_pending_features_name_the_current_release_and_pull_requests(self):
        rendered = engine_feature_status.render(
            self.readme(), minimum="v0.1.79", battle_release=None,
            icon_release=None,
        )
        self.assertIn("requires **Gen1Recomp v0.1.79 or newer**", rendered)
        self.assertIn("[#1077]", rendered)
        self.assertIn("[#1079]", rendered)
        self.assertIn("Text-only party details remain available", rendered)
        self.assertIn("Body remains untouched.", rendered)

    def test_each_feature_records_the_first_release_that_contains_it(self):
        rendered = engine_feature_status.render(
            self.readme(), minimum="v0.1.79", battle_release="v0.1.80",
            icon_release="v0.1.81",
        )
        self.assertIn("Battle START menu:** available in **v0.1.80", rendered)
        self.assertIn("Party icons in state details:** available in **v0.1.81", rendered)
        self.assertNotIn("awaiting merge", rendered)

    def test_merged_but_unreleased_features_report_the_release_gate(self):
        rendered = engine_feature_status.render(
            self.readme(), minimum="v0.1.79", battle_state="merged",
            battle_release=None, icon_state="merged", icon_release=None,
        )
        self.assertIn("Battle START menu:** merged upstream; awaiting", rendered)
        self.assertIn("Party icons in state details:** merged upstream; awaiting", rendered)

    def test_rejects_missing_or_duplicate_markers(self):
        for text in ("# no markers", self.readme() + self.readme()):
            with self.subTest(text=text[:20]):
                with self.assertRaisesRegex(ValueError, "exactly one status block"):
                    engine_feature_status.render(
                        text, minimum="v0.1.79", battle_release=None,
                        icon_release=None,
                    )

    def test_rejects_non_release_version_values(self):
        for value in ("0.1.79", "v0.1.79-dev", "main", ""):
            with self.subTest(value=value):
                with self.assertRaisesRegex(ValueError, "official release tag"):
                    engine_feature_status.render(
                        self.readme(), minimum=value, battle_release=None,
                        icon_release=None,
                    )


if __name__ == "__main__":
    unittest.main()
