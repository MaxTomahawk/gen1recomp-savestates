#!/usr/bin/env python3
"""Update only the reviewable engine-feature status block in README.md."""

import argparse
import pathlib
import re


START = "<!-- engine-feature-status:start -->"
END = "<!-- engine-feature-status:end -->"
TAG = re.compile(r"^v\d+\.\d+\.\d+$")


def _tag(value):
    if not isinstance(value, str) or not TAG.fullmatch(value):
        raise ValueError(f"{value!r} is not an official release tag")
    return value


def _feature(label, pull, state, release, fallback=None):
    if release:
        text = f"- **{label}:** available in **{_tag(release)} and newer**."
    elif state == "merged":
        text = (
            f"- **{label}:** merged upstream; awaiting the first official "
            "Gen1Recomp release that contains it."
        )
    else:
        text = (
            f"- **{label}:** awaiting merge of [#{pull}]"
            f"(https://github.com/bryanthaboi/gen1recomp/pull/{pull}) and "
            "a subsequent official Gen1Recomp release."
        )
    if fallback:
        text += " " + fallback
    return text


def render(text, *, minimum, battle_release=None, icon_release=None,
           battle_state="open", icon_state="open"):
    minimum = _tag(minimum)
    if text.count(START) != 1 or text.count(END) != 1:
        raise ValueError("README must contain exactly one status block")
    before, remainder = text.split(START, 1)
    _, after = remainder.split(END, 1)
    block = "\n".join([
        START,
        "### Engine feature availability",
        "",
        f"Save States requires **Gen1Recomp {minimum} or newer**.",
        "",
        _feature("Battle START menu", 1077, battle_state, battle_release),
        _feature(
            "Party icons in state details", 1079, icon_state, icon_release,
            "Text-only party details remain available while icon support is pending.",
        ),
        END,
    ])
    return before + block + after


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("readme", type=pathlib.Path)
    parser.add_argument("--minimum", required=True)
    parser.add_argument("--battle-state", choices=("open", "merged"), default="open")
    parser.add_argument("--battle-release")
    parser.add_argument("--icon-state", choices=("open", "merged"), default="open")
    parser.add_argument("--icon-release")
    args = parser.parse_args(argv)
    original = args.readme.read_text(encoding="utf-8")
    updated = render(
        original, minimum=args.minimum, battle_state=args.battle_state,
        battle_release=args.battle_release, icon_state=args.icon_state,
        icon_release=args.icon_release,
    )
    if updated == original:
        print("README engine feature status is current")
        return 0
    args.readme.write_text(updated, encoding="utf-8")
    print("Updated README engine feature status")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
