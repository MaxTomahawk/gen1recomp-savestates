#!/usr/bin/env python3
"""Promote released optional engine features and prepare the index handoff."""

import argparse
import json
import pathlib
import re
import sys


TOOLS = pathlib.Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
from update_engine_feature_status import render as render_status  # noqa: E402


TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
RANGE = re.compile(r">=\d+\.\d+\.\d+\s+<1\.0\.0")


def _version(tag):
    match = TAG.fullmatch(tag or "")
    if not match:
        raise ValueError(f"{tag!r} is not an official release tag")
    return tuple(int(part) for part in match.groups())


def minimum_release(battle_release, icon_release):
    if battle_release is not None:
        battle = _version(battle_release)
    else:
        battle = None
    if icon_release is not None:
        icon = _version(icon_release)
    else:
        icon = None
    if battle is None or icon is None:
        return None
    return battle_release if battle >= icon else icon_release


def _replace_block(text, name, body):
    start = f"<!-- {name}:start -->"
    end = f"<!-- {name}:end -->"
    if text.count(start) != 1 or text.count(end) != 1:
        raise ValueError(f"document must contain exactly one {name} block")
    before, remainder = text.split(start, 1)
    _, after = remainder.split(end, 1)
    return before + start + "\n" + body.rstrip() + "\n" + end + after


def _write_text(path, value):
    original = path.read_text(encoding="utf-8")
    if original == value:
        return False
    path.write_text(value, encoding="utf-8")
    return True


def _update_json(path, engine_range, *, stable=False):
    data = json.loads(path.read_text(encoding="utf-8"))
    data["game_version"] = engine_range
    if stable:
        data["experimental"] = False
    return _write_text(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def _stable_readme(text, minimum):
    note = (
        f"> **Save States 0.1.0:** requires **Gen1Recomp {minimum} or newer**. "
        "The ordinary Pokémon `SAVE` remains an independent conventional backup.\n"
    )
    text, count = re.subn(
        r"(?m)^> \*\*Early access 0\.1\.0:\*\*[^\n]*(?:\n>[^\n]*)*\n?",
        note,
        text,
    )
    if count == 0 and note.strip() not in text:
        raise ValueError("README must contain one early-access or stable notice")
    if count > 1:
        raise ValueError("README must contain exactly one early-access notice")
    return re.sub(
        r"(?m)^- This early-access release remains `experimental`[^\n]*\n"
        r"(?:  [^\n]*\n)?",
        "",
        text,
    )


def _stable_index_description(text, minimum):
    text, count = re.subn(
        r"This is an experimental early-access release(?: for \*\*Gen1Recomp "
        r"v?\d+\.\d+\.\d+ or newer\*\*)?\.",
        f"This stable release requires **Gen1Recomp {minimum} or newer**.",
        text,
    )
    stable = f"This stable release requires **Gen1Recomp {minimum} or newer**."
    if count == 0 and stable not in text:
        raise ValueError("index description must contain one early-access or stable notice")
    if count > 1:
        raise ValueError("index description must contain one early-access notice")
    return text.replace(
        "Keep using the normal Pokémon SAVE as a conventional backup while this "
        "version\nremains experimental. The package contains no ROM or extracted "
        "game assets.",
        "The normal Pokémon SAVE remains an independent conventional backup. The "
        "package\ncontains no ROM or extracted game assets.",
    )


def promote(root, *, battle_release, icon_release):
    root = pathlib.Path(root)
    minimum = minimum_release(battle_release, icon_release)
    if minimum is None:
        return False
    engine_range = f">={minimum[1:]} <1.0.0"
    manifest_path = root / "manifest.json"
    current_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    current_minimum = current_manifest["game_version"].split()[0][2:]
    current_tag = "v" + current_minimum
    changed = False

    readme_path = root / "README.md"
    readme = readme_path.read_text(encoding="utf-8")
    readme = readme.replace(current_tag, minimum)
    readme = _stable_readme(readme, minimum)
    readme = render_status(
        readme, minimum=minimum, battle_state="merged",
        battle_release=battle_release, icon_state="merged",
        icon_release=icon_release,
    )
    readme = _replace_block(
        readme, "battle-feature-note",
        f"Battle START-menu access is included in Gen1Recomp **{battle_release} "
        "and newer** at the same safe decision boundaries used by battle checkpoints.",
    )
    readme = _replace_block(
        readme, "icon-feature-note",
        f"Party icons in state details are included in Gen1Recomp **{icon_release} "
        "and newer** through the same public composition path as the Party screen.",
    )
    changed |= _write_text(readme_path, readme)
    changed |= _update_json(manifest_path, engine_range, stable=True)

    card_path = root / "mod.card"
    card = card_path.read_text(encoding="utf-8")
    updated_card, count = RANGE.subn(engine_range, card)
    if count != 1:
        raise ValueError("mod.card must contain exactly one engine range")
    updated_card = re.sub(
        r'^\s*"early access:[^\n]*",\n',
        "", updated_card, flags=re.MULTILINE,
    )
    updated_card = re.sub(
        r'^\s*"battle START-menu access awaits[^\n]*#1077[^\n]*",\n',
        "", updated_card, flags=re.MULTILINE,
    )
    updated_card = re.sub(
        r'^\s*"Party icons[^\n]*#1079[^\n]*",\n',
        "", updated_card, flags=re.MULTILINE,
    )
    changed |= _write_text(card_path, updated_card)

    index = root / "index" / "MaxTomahawk@savestates"
    changed |= _update_json(index / "meta.json", engine_range, stable=True)
    description_path = index / "description.md"
    description = description_path.read_text(encoding="utf-8")
    description = description.replace(current_tag, minimum)
    description = _stable_index_description(description, minimum)
    description = _replace_block(
        description, "battle-feature-note",
        f"Battle START-menu access is included in Gen1Recomp **{battle_release} "
        "and newer** at supported decision points.",
    )
    description = _replace_block(
        description, "icon-feature-note",
        f"Party icons in state details are included in Gen1Recomp **{icon_release} "
        "and newer** through the public Party presentation contract.",
    )
    changed |= _write_text(description_path, description)
    return changed


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=pathlib.Path)
    parser.add_argument("--battle-release", required=True)
    parser.add_argument("--icon-release", required=True)
    args = parser.parse_args(argv)
    changed = promote(
        args.root, battle_release=args.battle_release,
        icon_release=args.icon_release,
    )
    print("Promoted released engine features" if changed else "Promotion is current")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
