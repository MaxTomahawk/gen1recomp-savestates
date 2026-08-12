#!/usr/bin/env python3
"""Fail-closed validation for the automated stable-promotion transaction."""

import argparse
import json
import pathlib


REPOSITORY = "MaxTomahawk/gen1recomp-savestates"
BRANCH_PREFIX = "automation/engine-feature-status-"
ALLOWED_FILES = {
    "README.md",
    "manifest.json",
    "mod.card",
    "index/MaxTomahawk@savestates/meta.json",
    "index/MaxTomahawk@savestates/description.md",
}


def validate_pr(pr):
    if pr.get("state") != "OPEN" or pr.get("isDraft") is not False:
        raise ValueError("promotion PR must be open and non-draft")
    if pr.get("baseRefName") != "main":
        raise ValueError("promotion PR must target main")
    if not str(pr.get("headRefName", "")).startswith(BRANCH_PREFIX):
        raise ValueError("promotion PR has an unexpected head branch")
    owner = (pr.get("headRepositoryOwner") or {}).get("login")
    name = (pr.get("headRepository") or {}).get("name")
    repository = f"{owner}/{name}" if owner and name else None
    if repository != REPOSITORY:
        raise ValueError("promotion PR must come from the same repository")

    files = {entry.get("path") for entry in pr.get("files", [])}
    unexpected = sorted(files - ALLOWED_FILES)
    missing = sorted(ALLOWED_FILES - files)
    if unexpected:
        raise ValueError(f"unexpected promotion file: {unexpected[0]}")
    if missing:
        raise ValueError(f"missing promotion file: {missing[0]}")

    checks = [
        check for check in pr.get("statusCheckRollup", [])
        if check.get("name") == "stable-rom-free"
    ]
    if len(checks) != 1:
        raise ValueError("promotion requires exactly one stable-rom-free check")
    check = checks[0]
    if check.get("status") != "COMPLETED" or check.get("conclusion") != "SUCCESS":
        raise ValueError("stable-rom-free check must complete successfully")
    return True


def tag_decision(existing_sha, merge_sha):
    if not merge_sha:
        raise ValueError("promotion merge commit is missing")
    if not existing_sha:
        return "create"
    if existing_sha == merge_sha:
        return "current"
    raise ValueError("stable tag already points at a different commit")


def main(argv=None):
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    validate = commands.add_parser("validate-pr")
    validate.add_argument("path", type=pathlib.Path)
    tag = commands.add_parser("tag-decision")
    tag.add_argument("existing_sha")
    tag.add_argument("merge_sha")
    args = parser.parse_args(argv)
    if args.command == "validate-pr":
        validate_pr(json.loads(args.path.read_text(encoding="utf-8")))
        print("promotion PR is safe and green")
    else:
        print(tag_decision(args.existing_sha or None, args.merge_sha))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
