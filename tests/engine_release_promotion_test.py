import importlib.util
import json
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "engine_release_promotion", ROOT / "tools" / "promote_engine_features.py"
)
promotion = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(promotion)


class EngineReleasePromotionTests(unittest.TestCase):
    def test_later_feature_release_becomes_the_minimum(self):
        self.assertEqual(
            promotion.minimum_release("v0.1.80", "v0.1.82"), "v0.1.82"
        )
        self.assertEqual(
            promotion.minimum_release("v0.2.0", "v0.1.99"), "v0.2.0"
        )

    def test_both_released_update_mod_and_index_contracts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            index = root / "index" / "MaxTomahawk@savestates"
            index.mkdir(parents=True)
            (root / "README.md").write_text(
                """# Save States
<!-- engine-feature-status:start -->old<!-- engine-feature-status:end -->
<!-- battle-feature-note:start -->pending battle<!-- battle-feature-note:end -->
<!-- icon-feature-note:start -->pending icons<!-- icon-feature-note:end -->
""",
                encoding="utf-8",
            )
            (root / "manifest.json").write_text(
                json.dumps({
                    "game_version": ">=0.1.79 <1.0.0",
                    "experimental": True,
                }), encoding="utf-8",
            )
            (root / "mod.card").write_text(
                'return { known = {\n'
                '  "battle START-menu access awaits upstream PR #1077",\n'
                '  "Party icons await upstream PR #1079",\n'
                '}, compat = { engine = ">=0.1.79 <1.0.0", modApi = 2 } }\n',
                encoding="utf-8",
            )
            (index / "meta.json").write_text(
                json.dumps({
                    "game_version": ">=0.1.79 <1.0.0",
                    "experimental": True,
                }), encoding="utf-8",
            )
            (index / "description.md").write_text(
                """# Save States
<!-- battle-feature-note:start -->pending battle<!-- battle-feature-note:end -->
<!-- icon-feature-note:start -->pending icons<!-- icon-feature-note:end -->
""",
                encoding="utf-8",
            )

            changed = promotion.promote(
                root, battle_release="v0.1.80", icon_release="v0.1.82"
            )

            self.assertEqual(changed, True)
            manifest = json.loads((root / "manifest.json").read_text())
            index_meta = json.loads((index / "meta.json").read_text())
            self.assertEqual(manifest["game_version"], ">=0.1.82 <1.0.0")
            self.assertEqual(index_meta["game_version"], ">=0.1.82 <1.0.0")
            self.assertEqual(manifest["experimental"], True)
            self.assertEqual(index_meta["experimental"], True)
            card = (root / "mod.card").read_text()
            self.assertIn(">=0.1.82 <1.0.0", card)
            self.assertNotIn("#1077", card)
            self.assertNotIn("#1079", card)
            readme = (root / "README.md").read_text()
            description = (index / "description.md").read_text()
            self.assertIn("requires **Gen1Recomp v0.1.82 or newer**", readme)
            self.assertIn("Battle START menu:** available in **v0.1.80", readme)
            self.assertIn("Party icons in state details:** available in **v0.1.82", readme)
            self.assertIn("included in Gen1Recomp **v0.1.80", readme)
            self.assertIn("included in Gen1Recomp **v0.1.82", description)
            self.assertNotIn("pending battle", description)

    def test_partial_release_keeps_the_installable_core_minimum(self):
        self.assertIsNone(promotion.minimum_release("v0.1.80", None))

    def test_refuses_to_promote_non_release_values(self):
        for value in ("dev", "0.1.80", "v0.1.80-rc.1", ""):
            with self.subTest(value=value):
                with self.assertRaisesRegex(ValueError, "official release tag"):
                    promotion.minimum_release(value, "v0.1.82")


if __name__ == "__main__":
    unittest.main()
