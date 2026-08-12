# Cross-Mod Checkpoint Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove generic checkpoint behavior across mod-owned state classes and add one success-only lifecycle event so cooperating mods can rebuild derived runtime state.

**Architecture:** Keep rewind ownership in the engine: checkpoint records contain canonical `game.save` progress but exclude global options and every mod's independent `mod.storage`. Add only `checkpoint.restored` after verified commit; cooperating mods re-read their own public state and rebuild caches without exposing checkpoint payloads or private tables.

**Tech Stack:** LuaJIT, Gen1Recomp API 2 modkit fixtures, engine `ModRuntime` event bus, Markdown/RFC documentation, Make/modkit ROM-free packaging gates.

## Global Constraints

- Never special-case `SHINY_POKEMON` or access another mod's private tables.
- Never rewind global options or another mod's `mod.storage` automatically.
- Never serialize arbitrary Lua runtime state, controllers, LÖVE objects, or caches.
- Emit lifecycle only after successful differential verification; failures and rollback emit nothing.
- Preserve all #952/#986 validation, safe-boundary, RNG, and rollback guarantees.
- Keep upstream changes in a separate Gen1Recomp worktree/branch.
- Introduce no ROM, imported data, extracted asset, screenshot, save, or credential.

---

### Task 1: Prove the cross-mod lifecycle gap and state boundaries

**Files:**
- Create: `/home/max/src/gen1recomp-savestates-crossmod/tests/modkit/cases/checkpoint_cross_mod.lua`

**Interfaces:**
- Consumes: public `mod.checkpoints`, `mod.save`, `mod.storage`, `mod.options`, and `mod.events:on`.
- Produces: a public-facade regression suite covering overworld/battle metadata, independent storage, options, and runtime-cache reconciliation.

- [ ] **Step 1: Create the isolated upstream worktree**

Run:

```bash
git -C /home/max/src/gen1recomp worktree add \
  /home/max/src/gen1recomp-savestates-crossmod \
  -b feat/checkpoint-restore-event origin/dev
```

Expected: branch starts at audited `943ba5d` and both source checkouts remain clean.

- [ ] **Step 2: Add the public cooperating-mod fixture**

The fixture loads a probe whose entire integration is public:

```lua
return function(mod)
  local cachedStage = mod.save:get("stage", "unset")
  mod.exports.setStage = function(stage)
    mod.save:set("stage", stage)
    cachedStage = stage
  end
  mod.exports.cachedStage = function() return cachedStage end
  mod.events:on("checkpoint.restored", function(ev)
    cachedStage = mod.save:get("stage", "unset")
    mod.exports.lastRestore = {
      game = ev.game,
      kind = ev.kind,
      top = ev.game.stack:top(),
    }
  end)
end
```

Use engine-side data-only Pokémon records with `dvs` and `shiny`; do not copy or
load the external shiny mod. Add assertions for:

```lua
-- A is captured, game/mod state and metadata become B, restore returns A.
T.eq(game.save.party[1].shiny, true, "Pokemon metadata rewinds with progress")
T.eq(probe.cachedStage(), "A", "cooperating runtime cache rebuilds from mod.save")
T.same(storage:read(game, "history"), { generation = "B" },
  "independent mod.storage does not rewind")
T.eq(game.save.options.modOptions.probe.mode, "B",
  "global per-mod options do not rewind")
T.eq(probe.lastRestore.kind, "overworld", "restore event identifies final kind")
```

Repeat Pokémon metadata and event assertions for a supported wild battle, covering
the canonical player party and copied enemy Pokémon. Add invalid-format restore
assertions proving no event and no cache/state mutation.

- [ ] **Step 3: Run the new suite and verify the expected red result**

Run:

```bash
luajit tests/modkit/cases/checkpoint_cross_mod.lua
```

Expected: shiny-like metadata, `mod.save`, options, and `mod.storage` ownership
assertions pass; cache/event assertions fail because `checkpoint.restored` is not
yet emitted. Any different failure must be fixed in the fixture before production
code changes.

### Task 2: Add the minimal success-only checkpoint lifecycle event

**Files:**
- Modify: `/home/max/src/gen1recomp-savestates-crossmod/src/core/Checkpoint.lua`
- Modify: `/home/max/src/gen1recomp-savestates-crossmod/docs/modding.md`
- Modify: `/home/max/src/gen1recomp-savestates-crossmod/docs/rfcs/0004-runtime-checkpoints.md`
- Modify: `/home/max/src/gen1recomp-savestates-crossmod/docs/rfcs/0005-battle-runtime-checkpoints.md`

**Interfaces:**
- Consumes: successful `Checkpoint.restore` differential verification and existing `ModRuntime.emit` isolation.
- Produces: `checkpoint.restored` payload `{ game = game, kind = "overworld" | "battle" }`.

- [ ] **Step 1: Emit only after verified commit**

Replace the success return in `Checkpoint.restore` with:

```lua
if restored and equalData(restored, validated) then
  if ModRuntime.wants("checkpoint.restored") then
    ModRuntime.emit("checkpoint.restored", {
      game = game,
      kind = validated.kind,
    })
  end
  return true
end
```

Do not emit before validation, during reconstruction, or after rollback.

- [ ] **Step 2: Run the focused suite and verify green**

Run:

```bash
luajit tests/modkit/cases/checkpoint_cross_mod.lua
luajit tests/modkit/cases/checkpoints.lua
luajit tests/engine/gate_meta_coverage.lua
```

Expected: all checks pass; catalog/meta coverage discovers the new literal event
site automatically.

- [ ] **Step 3: Document the exact public contract**

Add the event example and ownership matrix to `docs/modding.md`. Amend RFC 0004
and RFC 0005 so successful overworld and battle restore respectively emit after
verification, with no migration and no ordinary lifecycle replay.

- [ ] **Step 4: Run full upstream verification and commit**

Run:

```bash
./scripts/test.sh --quick
```

Expected: every ROM-free engine and modkit suite passes; ROM-derived T3 remains
skipped when generated data is absent.

Commit:

```bash
git add src/core/Checkpoint.lua tests/modkit/cases/checkpoint_cross_mod.lua \
  docs/modding.md docs/rfcs/0004-runtime-checkpoints.md \
  docs/rfcs/0005-battle-runtime-checkpoints.md
git commit -m "feat(mods): signal verified checkpoint restores"
```

### Task 3: Publish the Save States compatibility contract

**Files:**
- Create: `docs/cross-mod-compatibility.md`
- Modify: `docs/compatibility.md`
- Modify: `docs/architecture.md`
- Modify: `docs/upstream-audit.md`
- Modify: `docs/project-plan.md`
- Modify: `docs/acceptance.md`
- Modify: `README.md`
- Modify: `Makefile`
- Modify: `.modkitignore`

**Interfaces:**
- Consumes: verified upstream test results and the source-pinned shiny/Wilds audit.
- Produces: packaged user/mod-author guidance and refreshed release evidence.

- [ ] **Step 1: Write the seven-class compatibility matrix**

`docs/cross-mod-compatibility.md` must identify what rewinds, what remains current,
the effect of mismatched ownership, and the public reconciliation pattern:

```lua
mod.events:on("checkpoint.restored", function(ev)
  cachedQuestStage = mod.save:get("quest_stage", 0)
  rebuildRuntimeFor(ev.game, ev.kind)
end)
```

Include the shiny 1.0.8 case and state explicitly that support derives from plain
Pokémon records, not a hardcoded mod id. Explain that Wilds spawn records are
runtime-only and must be rebuilt.

- [ ] **Step 2: Integrate the contract into release documentation**

Link the new document from README, architecture, and compatibility. Refresh pins
to official `dev` containing merged #986. Add the lifecycle seam as a proved
release prerequisite rather than claiming all mods are automatically compatible.
Add the new packaged document to `PACKAGE_SOURCES`; keep internal spec/plan files
excluded through `.modkitignore`.

- [ ] **Step 3: Verify docs and packaging, then commit**

Run:

```bash
git diff --check
make check GEN1RECOMP=/home/max/src/gen1recomp-savestates-crossmod
```

Expected: all Lua/Python checks, modkit validate/lint, reproducible package, archive
root, and clean extracted install pass.

Commit:

```bash
git add README.md Makefile .modkitignore docs
git commit -m "docs: define cross-mod checkpoint compatibility"
```

### Task 4: Publish and verify both handoffs

**Files:**
- Modify only evidence fields in `docs/project-plan.md` and `docs/acceptance.md` after exact committed checks.

**Interfaces:**
- Consumes: committed upstream/mod heads, clean-clone package SHA, and GitHub Actions.
- Produces: review-ready generic upstream PR plus updated Save States draft PR.

- [ ] **Step 1: Push the upstream branch and open a focused PR**

Push `feat/checkpoint-restore-event` to the MaxTomahawk fork and open a PR against
`bryanthaboi/gen1recomp:dev`. The body must include the reproduced stale-cache gap,
event timing/payload, storage/options non-rewind behavior, shiny-like overworld and
battle roundtrips, and full suite results.

- [ ] **Step 2: Push the mod branch and verify Actions**

Push `feat/initial-savestates`, wait for both push and PR Test workflows at the
exact head, and require success.

- [ ] **Step 3: Verify a clean published clone**

Clone the published mod branch into a fresh temporary directory and run:

```bash
make check GEN1RECOMP=/home/max/src/gen1recomp-savestates-crossmod
sha256sum .artifacts/savestates-0.1.0.zip
```

Expected: the same archive hash as the working checkout and a clean extracted
install. Record the exact head, SHA-256, upstream suite counts, and Actions run ids
in non-packaged evidence docs.

- [ ] **Step 4: Update both PR handoffs and stop only at real external gates**

Update the upstream and mod PR bodies with exact evidence. Remaining external
gates are upstream review/merge/release of the generic event and private ROM-backed
acceptance; neither justifies weakening or silently omitting the contract.
