# Rich Checkpoint Previews Implementation Plan

> **For agentic workers:** Execute this plan with test-first behavior checks and
> small coherent commits. The 2026-08-09 steering update supplies the approved
> design; do not reopen architecture unless newer local/upstream evidence
> contradicts it.

**Goal:** Add validated capture-time playtime, badge, and six-Pokémon preview
metadata to Save States, surfaced through native lazy-inspected details.

**Architecture:** A pure `Preview` module builds and validates descriptive data
from public checkpoint save records. Snapshot/index validation accepts missing
legacy previews but rejects malformed present previews. The service captures
previews once, preserves them across pin/rename, and lazily reads a selected
payload only for detail actions.

**Tech stack:** LuaJIT, public Mod API 2 `mod.content` registries,
`mod.checkpoints`, `mod.storage`, native `ListMenu`, existing Lua test harness.

## Global constraints

- Keep wrapper format 1: preview is optional, data-only metadata.
- Do not use private engine modules or runtime controller objects in mod code.
- Do not display status, moves, DVs, or current-live state as preview data.
- Do not read every checkpoint payload while listing histories or slots.
- Preserve manual labels and source capture preview through pin/rename.
- Portability and wiki publication are non-blocking, separate work.

### Task 1: Pure preview model and validators

**Files:** Create `src/state/Preview.lua`; modify snapshot/index factories and
their tests.

- [ ] Write pure tests for play time, 0/1/6 party members, nickname/species
  fallback, badge count/total, fainted HP, status omission, and malformed data.
- [ ] Run the new test and observe failure because `Preview` does not exist.
- [ ] Implement detached preview capture and one reusable optional-preview
  validator; inject it into snapshot and index validation.
- [ ] Run focused preview/snapshot/index tests, then commit.

### Task 2: Capture and provenance service behavior

**Files:** Modify `main.lua`, `src/service/SaveStateService.lua`,
`src/state/Snapshot.lua`; extend service tests.

- [ ] Write failing service tests covering overworld/battle capture fidelity,
  old metadata without preview, direct slot capture, pin, and rename provenance.
- [ ] Run focused service test and observe the missing preview behavior.
- [ ] Build preview from public content registry data at capture and preserve
  source preview exactly for pin/rename.
- [ ] Run focused service tests, then commit.

### Task 3: Lazy index browsing and native details

**Files:** Modify `src/service/SaveStateService.lua`, `src/ui/ScreenRegistry.lua`;
extend service/UI tests.

- [ ] Write failing tests proving history/slot listing performs no state-payload
  reads, selected detail performs one validation read, and native state/slot
  details show all preview rows when present.
- [ ] Run focused tests and observe the eager-read behavior fail.
- [ ] Add lazy `inspectState` and render compact preview details with existing
  paged `ListMenu`; legacy/no-preview details remain useful.
- [ ] Run focused service/UI tests, then commit.

### Task 4: Documentation and release evidence

**Files:** Modify `README.md`, `docs/state-format.md`, `docs/architecture.md`,
`docs/compatibility.md`, `docs/project-plan.md`, `docs/acceptance.md`,
`CHANGELOG.md`, and packaging source list if required.

- [ ] Document optional preview metadata, legacy degradation, lazy reads, and
  manual-label behavior without claiming device-transfer support.
- [ ] Run `make check` against the exact required upstream branch, inspect the
  generated archive root, then commit.

## Deferred handoffs

- After verified #993 merge: refresh `dev`, record merge SHA, re-run cross-mod
  suites, update stale pending wording, and complete wiki event/API handoff.
- Portability remains a generic, non-blocking engine follow-up. Fresh overlap
  review found no competing implementation; no branch or PR is opened here.
