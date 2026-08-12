# Automatic Stable Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically remove Save States' experimental status and publish stable `v0.1.0` only after one official Gen1Recomp release contains #1077 and #1079.

**Architecture:** Extend the existing release-resolution script and scheduled workflow instead of adding a second source of compatibility truth. A generated same-repository PR remains the transaction boundary; automation merges it only after an allowlisted diff and successful `rom-free` check, then creates the immutable tag and explicitly dispatches the existing release workflow.

**Tech Stack:** Python `unittest`, GitHub Actions YAML, GitHub CLI/API, Make/modkit.

## Global Constraints

- Preserve snapshot format 1 and all runtime behavior.
- Never promote from a branch, prerelease, draft, or non-semver engine ref.
- Never overwrite an existing tag or bypass a failed/pending CI check.
- Keep the mod-index handoff out of the distributable ZIP.
- Do not add a cross-repository credential.

---

### Task 1: Stable metadata promotion

**Files:**
- Modify: `tests/engine_release_promotion_test.py`
- Modify: `tools/promote_engine_features.py`
- Modify: `README.md`
- Modify: `docs/development.md`
- Modify: `docs/project-plan.md`

**Interfaces:**
- Consumes: `promote(root, battle_release=..., icon_release=...) -> bool`
- Produces: a stable manifest/card/index handoff with the later official release minimum.

- [ ] Add assertions that promotion sets manifest and index `experimental` to `false` and removes early-access copy.
- [ ] Run the focused test and confirm the current preservation behavior fails.
- [ ] Implement the minimum stable promotion behavior without changing format or runtime code.
- [ ] Run focused tests and confirm green.
- [ ] Update living documentation to identify official engine inclusion as the remaining automated gate.

### Task 2: Fail-closed PR merge and tag orchestration

**Files:**
- Create: `tests/stable_promotion_workflow_test.py`
- Modify: `.github/workflows/engine-feature-status.yml`
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: the generated state-specific promotion PR and GitHub `stable-rom-free` check.
- Produces: merged stable metadata at `main`, immutable `v0.1.0`, and an explicit release workflow dispatch.

- [ ] Add a static workflow contract test for allowlisted files, same-repository PR validation, named successful CI requirement, collision refusal, recovery, and explicit dispatch.
- [ ] Run the focused test and confirm it fails against the current review-only workflow.
- [ ] Implement resumable auto-merge/tag/dispatch with bounded CI polling.
- [ ] Add `workflow_dispatch` support to the existing release workflow.
- [ ] Run workflow-contract and YAML parse tests until green.

### Task 3: Complete verification and publication

**Files:**
- Modify only if verification exposes a defect.

**Interfaces:**
- Consumes: Tasks 1-2.
- Produces: reviewed automation on repository `main`.

- [ ] Run all promotion/status Python tests.
- [ ] Simulate a two-release promotion twice and verify stable/idempotent output.
- [ ] Run `make check GEN1RECOMP=/home/max/src/gen1recomp-v0.1.79`.
- [ ] Validate the exact index handoff through the real index validator/builder.
- [ ] Commit, push, open a non-draft PR, wait for GitHub CI, and merge only when green and conflict-free.
- [ ] Dispatch the watcher once on `main`; with #1077/#1079 unreleased it must make no promotion.
