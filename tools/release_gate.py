#!/usr/bin/env python3
"""Validate a releasable mod manifest and emit its exact engine tag."""

import json
import re
import sys


SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
MINIMUM = re.compile(r"^\s*>=\s*(\d+\.\d+\.\d+)(?:\s|$)")


def fail(message):
    print(f"release gate: {message}", file=sys.stderr)
    return 2


def main(argv):
    if len(argv) != 3:
        return fail("usage: release_gate.py MANIFEST TAG")
    path, tag = argv[1], argv[2]
    try:
        with open(path, encoding="utf-8") as handle:
            manifest = json.load(handle)
    except (OSError, ValueError) as error:
        return fail(f"could not read manifest: {error}")

    version = str(manifest.get("version", ""))
    if not SEMVER.fullmatch(version):
        return fail("manifest version must be X.Y.Z")
    expected = "v" + version
    if tag != expected:
        return fail(f"release tag {tag!r} does not match {expected!r}")
    if manifest.get("experimental") is not False:
        return fail("release manifest must set experimental to false")

    game_range = str(manifest.get("game_version", ""))
    minimum = MINIMUM.match(game_range)
    if not minimum or "dev" in game_range:
        return fail(
            "game_version must begin with an exact released minimum such as "
            "'>=0.1.79'"
        )

    print("engine_ref=v" + minimum.group(1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
