#!/usr/bin/env python3
"""Fail closed when a modkit archive is not source-date reproducible."""

import argparse
from datetime import datetime, timezone
import json
import pathlib
import sys
import zipfile


class GateError(ValueError):
    pass


def expected_timestamp(epoch):
    try:
        value = int(epoch)
        if value < 0:
            raise ValueError
        return datetime.fromtimestamp(value, timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
    except (TypeError, ValueError, OverflowError, OSError) as error:
        raise GateError("source epoch must be a nonnegative Unix timestamp") from error


def validate(path, epoch):
    expected = expected_timestamp(epoch)
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            if names.count(".modkit/pack.json") != 1:
                raise GateError("archive must contain exactly one .modkit/pack.json")
            metadata = json.loads(archive.read(".modkit/pack.json"))
    except GateError:
        raise
    except (OSError, zipfile.BadZipFile, KeyError, json.JSONDecodeError) as error:
        raise GateError(f"could not read package metadata: {error}") from error
    if not isinstance(metadata, dict) or metadata.get("packed_at") != expected:
        actual = metadata.get("packed_at") if isinstance(metadata, dict) else None
        raise GateError(
            f"pack.json packed_at is {actual!r}; expected {expected!r}"
        )
    return True


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=pathlib.Path)
    parser.add_argument("source_epoch")
    args = parser.parse_args(argv)
    try:
        validate(args.archive, args.source_epoch)
    except GateError as error:
        print(f"package gate: {error}", file=sys.stderr)
        return 2
    print(f"Verified source-date package metadata: {args.archive}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
