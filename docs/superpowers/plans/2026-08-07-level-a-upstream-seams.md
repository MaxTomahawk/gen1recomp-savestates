# Level A Upstream Seams Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add and prove the smallest generic Gen1Recomp public APIs needed for playthrough-isolated, persistent, stable-overworld checkpoints.

**Architecture:** Add opaque playthrough identity to engine save metadata, a namespaced data-only persistence facade routed through SaveData, and a stable-overworld checkpoint facade routed through Game. Each public surface is injected by Loader and tested through a real mod entry chunk; engine internals remain invisible to the mod.

**Tech Stack:** LuaJIT 2.1, LÖVE2D filesystem contracts, Gen1Recomp SaveSerializer, existing `tests.harness` and mod loader fixtures.

## Global Constraints

- Base every upstream branch on `bryanthaboi/gen1recomp` `dev` commit `112120e8fe4ab03665e7e3eff761032451b36d8c` or a freshly verified successor.
- Keep the public API additive, Mod API 2 compatible, and a no-op when no mod calls it.
- Existing mods require no migration.
- Distributable Save States code must not import private `src.*` modules.
- Never add ROM, imported cache, user save, credential, generated secret, or ROM-derived asset data.
- Every behavior follows observed RED, minimal GREEN, focused verification, relevant suite, then a coherent commit.
- Upstream API changes require RFC, no-mod parity test, public mod-API test, and reference documentation.

---

### Task 1: Isolated upstream branch and test baseline

**Files:**
- No product files changed.

**Interfaces:**
- Consumes: clean `/home/max/src/gen1recomp` at current `origin/dev`.
- Produces: `/home/max/src/gen1recomp-savestates-engine` on `feat/mod-state-checkpoints` and a recorded baseline.

- [ ] **Step 1: Create or verify the GitHub fork and remote**

Run `gh repo fork bryanthaboi/gen1recomp --clone=false --remote=false`, then add
`fork git@github.com:MaxTomahawk/gen1recomp.git` if absent.

- [ ] **Step 2: Create the isolated worktree**

Run `git worktree add /home/max/src/gen1recomp-savestates-engine -b feat/mod-state-checkpoints origin/dev` as `max`.

- [ ] **Step 3: Verify the ROM-free baseline**

Run:

```bash
luajit tests/mod_manifest_tests.lua
luajit tests/engine/save_slots.lua
python3 tools/modkit.py validate mods/examples/example_dexnav
```

Expected: all commands exit 0. Record tool versions and exact counts in the living
project plan.

### Task 2: Opaque playthrough identity

**Files:**
- Modify: `src/core/SaveData.lua`
- Modify: `src/core/Game.lua`
- Create: `tests/engine/playthrough_identity.lua`

**Interfaces:**
- Consumes: active game version and active SaveData slot routing.
- Produces: `SaveData.ensurePlaythroughId(save)` and
  `SaveData.newPlaythroughId()`; `save.meta.playthroughId` is a nonempty opaque
  string stable across reload and different for a new game.

- [ ] **Step 1: Write the failing identity tests**

Cover literal behaviors: two New Game records differ; saving and loading preserves
the id; a legacy save receives one stable id across two loads before a normal SAVE;
Red and Blue plus two active slots do not share migration identity. Use an injected
memfs and reset function so tests never touch user saves.

- [ ] **Step 2: Run the focused test and observe RED**

Run `luajit tests/engine/playthrough_identity.lua`.

Expected: failure because `ensurePlaythroughId` and the metadata field do not exist.

- [ ] **Step 3: Implement minimum identity behavior**

Generate identifiers without consuming the global gameplay RNG. Persist only the
legacy backfill mapping in `options.lua`, keyed by version and active slot/legacy
scope. Stamp a newly generated id directly into every user-created New Game save.
Call the ensure function before `Game:restoreSave` exposes a loaded playthrough.

- [ ] **Step 4: Verify GREEN and regressions**

Run:

```bash
luajit tests/engine/playthrough_identity.lua
luajit tests/engine/save_slots.lua
luajit tests/mod_save_tests.lua
```

Expected: all pass with zero failures.

- [ ] **Step 5: Commit**

Commit `feat: add opaque playthrough identity` with only identity implementation and
tests.

### Task 3: Scoped transactional mod storage

**Files:**
- Create: `src/mods/Storage.lua`
- Modify: `src/mods/Loader.lua`
- Create: `tests/mod_storage_tests.lua`

**Interfaces:**
- Consumes: `game.save.meta.playthroughId`, current game version, Loader mod id,
  SaveSerializer, and SaveData's routed persistence filesystem.
- Produces: `mod.storage:context/read/write/list/delete(game, ...)`, returning data
  or `nil/false, errorCode, humanMessage` without throwing on user data failures.

- [ ] **Step 1: Write failing public-API storage tests**

Load a synthetic API-2 mod through `Loader`. From its entry chunk call only
`mod.storage`. Prove a data-only roundtrip, deterministic list order, key traversal
rejection, different mod/game/playthrough isolation, corrupt-main recovery from
backup, replacement failure retaining the prior value, and delete affecting one
key. Also load no mods and prove no storage path or file is created.

- [ ] **Step 2: Run the focused test and observe RED**

Run `luajit tests/mod_storage_tests.lua`.

Expected: failure because `mod.storage` is nil.

- [ ] **Step 3: Implement the storage module and Loader facade**

Accept keys composed of nonempty alphanumeric, `_`, `-`, and `/` segments; reject
`.` and `..`. Route through SaveData's standard/portable persistence selection.
Encode with SaveSerializer, stage `.tmp`, decode-verify it, preserve `.bak`, write
and decode-verify main, then remove tmp. Read main/tmp/bak in that order and promote
the first valid record. Recursively enumerate only the caller's scope.

- [ ] **Step 4: Verify GREEN and loader parity**

Run:

```bash
luajit tests/mod_storage_tests.lua
luajit tests/mod_manifest_tests.lua
luajit tests/parity_portable_mods.lua
```

Expected: all pass with zero failures.

- [ ] **Step 5: Commit**

Commit `feat: add playthrough-scoped mod storage` with only storage implementation
and tests.

### Task 4: Stable-overworld checkpoint facade

**Files:**
- Create: `src/core/Checkpoint.lua`
- Modify: `src/core/Game.lua`
- Modify: `src/mods/Loader.lua`
- Create: `tests/mod_checkpoint_tests.lua`

**Interfaces:**
- Consumes: live `Game`, `OverworldController:captureSave`, StateStack, SaveData
  validation, opaque playthrough identity, and merged Data.
- Produces: `mod.checkpoints:inspect/capture/restore(game, ...)` with checkpoint
  format 1 and stable error codes.

- [ ] **Step 1: Write failing inspect/capture public-API tests**

Through a synthetic mod, prove a stable overworld reports capturable; title,
battle/modal top state, transition, foreground script, parallel script, script
movement, engagement, and emote return their expected refusal codes. Prove capture
is data-only, synchronizes exact map/x/y/facing/surfing, deep-copies progress, and
does not change live progress or global options.

- [ ] **Step 2: Observe RED**

Run `luajit tests/mod_checkpoint_tests.lua`.

Expected: failure because `mod.checkpoints` is nil.

- [ ] **Step 3: Implement inspect and capture**

Keep all private state inspection in `Checkpoint.lua`. The Loader closure only
binds ownership and forwards the public calls. Return structured failures rather
than throwing for ordinary runtime refusal.

- [ ] **Step 4: Verify inspect/capture GREEN**

Run `luajit tests/mod_checkpoint_tests.lua` and confirm the capture cases pass.

- [ ] **Step 5: Add failing restore and rollback tests**

Prove capture A -> mutate map/position/money/party/flags -> restore A -> capture A2
has equal normalized records. Add wrong format/game/playthrough, invalid map,
unsafe current runtime, injected reconstruction throw, and unchanged current
settings cases. The injected throw must leave A-current recapturable after rollback.

- [ ] **Step 6: Observe restore RED**

Run `luajit tests/mod_checkpoint_tests.lua`.

Expected: restore cases fail because restoration is not implemented.

- [ ] **Step 7: Implement validated transactional restore**

Validate the entire checkpoint before mutation, capture an in-memory rollback
checkpoint, preserve current options, rebuild the overworld through Game-owned
operations, and on exception restore the rollback checkpoint before returning
`restore_failed`.

- [ ] **Step 8: Verify GREEN and gameplay parity**

Run:

```bash
luajit tests/mod_checkpoint_tests.lua
luajit tests/mod_world_tests.lua
luajit tests/run_tests.lua
```

Expected: all pass with zero failures.

- [ ] **Step 9: Commit**

Commit `feat: expose stable overworld checkpoints to mods` with checkpoint code and
tests only.

### Task 5: RFC, reference documentation, and upstream gate

**Files:**
- Create: `docs/rfcs/0003-playthrough-storage.md`
- Create: `docs/rfcs/0004-runtime-checkpoints.md`
- Modify: `docs/modding.md`
- Modify in the wiki checkout: `Reference-Mod-Object.md`
- Modify in the wiki checkout: `Concepts-Save-Model.md`

**Interfaces:**
- Consumes: the tested API exactly as implemented.
- Produces: upstream-reviewable contracts, migration statement, parity evidence,
  and generated docs with no implementation/spec drift.

- [ ] **Step 1: Write exact RFCs from the green contracts**

Each RFC states motivation, decision amended, exact signatures/payload/error codes,
call sites, existing-mod migration (`Nothing`), no-mod parity, public mod-API test,
and deprecation status.

- [ ] **Step 2: Update public reference documentation**

Document `mod.storage` and `mod.checkpoints`, safety boundaries, persistence scope,
and error behavior. Run the actual generator if schema-backed pages change.

- [ ] **Step 3: Run the complete relevant verification**

Run the focused tests from Tasks 2-4, `luajit tests/mod_manifest_tests.lua`,
`luajit tests/mod_world_tests.lua`, `luajit tests/run_tests.lua`, and the current
documentation generator/checks. Record exact exit results.

- [ ] **Step 4: Audit the branch**

Run `git diff origin/dev...HEAD --check`, inspect every changed file, scan for ROM
content/secrets, and verify no existing public surface changed behavior.

- [ ] **Step 5: Commit and push the RFC/docs milestone**

Commit `docs: specify mod storage and checkpoint APIs`, push the focused fork
branch, and update `docs/project-plan.md` in the mod repository with exact commits,
test evidence, and any evidence-driven contract correction.
