# Battle Boundary and Native HUD Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make real battle-start autosaves and START-menu access work at the first settled command decision, and place native Save States notifications at the physical top of every viewport without requiring Gen1 Modern UI.

**Architecture:** Gen1Recomp continues to own the single semantic battle-safety predicate. Real battle transitions must normalize completed presentation/queue markers before that predicate is evaluated; Save States continues to queue `battle.started` and consumes it only after `mod.checkpoints:inspect` reports the safe battle boundary. Native notifications move from the centered logical composition canvas to the existing public screen-space `render.hud` pass, while Modern UI remains an optional presentation owner.

**Tech Stack:** Lua/LuaJIT, LÖVE2D, Gen1Recomp mod API 2, upstream engine tests, Save States Lua tests, modkit validation/package gates.

## Global Constraints

- Distributable Save States code uses public Gen1Recomp APIs only.
- Do not weaken rejection of animations, action/message queues, forced decisions, unsupported variants, or unsafe scripts.
- Do not require Gen1 Modern UI for correct native notification placement.
- Preserve the current notification model, replacement/lifetime behavior, and Modern UI adapter contract.
- No ROM, generated ROM content, user save, credentials, or build artifacts enter Git.

---

### Task 1: Normalize the Real Battle Decision Boundary

**Files:**
- Modify: `/home/max/src/gen1recomp-battle-auxiliary/src/battle/BattleState.lua`
- Modify: `/home/max/src/gen1recomp-battle-auxiliary/tests/engine/battle_menu_auxiliary.lua`
- Test: `/home/max/src/gen1recomp-battle-auxiliary/tests/engine/battle_menu_auxiliary.lua`

**Interfaces:**
- Consumes: `BattleSafety.inspect(game, battle) -> true | nil, code, message`.
- Produces: a real intro-to-command transition whose completed transient fields are semantically idle and accepted by `BattleSafety.inspect`.

- [x] Add a regression that calls the real battle `enter()`/update transition rather than assigning `phase = "menu"` directly, then asserts checkpoint safety at the first ordinary player decision.
- [x] Run the focused test and confirm it fails with `battle_phase_busy` from completed transient markers.
- [x] Clear or normalize only completed queue/presentation markers when their lifecycle ends; retain nonterminal markers during unsafe phases.
- [x] Run the focused test and existing battle checkpoint/menu suites.
- [x] Commit the generic engine correction independently on `fix/battle-decision-settling` and publish PR #1087.

### Task 2: Prove Autosave and START Share the Correct Boundary

**Files:**
- Modify: `/home/max/src/gen1recomp-battle-auxiliary/tests/engine/battle_menu_auxiliary.lua`
- Modify: `/home/max/gen1recomp-savestates/tests/composition_test.lua`
- Modify if required: `/home/max/gen1recomp-savestates/src/autosave/AutoSaveController.lua`

**Interfaces:**
- Consumes: public `battle.started`, `input.step`, `mod.checkpoints:inspect`, and `battle.menu_auxiliary`.
- Produces: one queued autosave at the first safe command menu and one START auxiliary callback without turn/RNG advancement.

- [x] Extend the real battle regression to assert START reaches the public auxiliary hook only after the intro settles.
- [x] Add/adjust Save States integration coverage proving the queued request remains pending while unsafe and is captured at the first safe input boundary.
- [x] Confirm the new tests fail against the pre-fix boundary.
- [x] Implement no mod change because the public event-to-boundary test proved the existing queue correct.
- [x] Run focused wild/trainer tests and the scripted-battle integration suite.
- [x] Commit only genuine mod changes separately from engine work.

### Task 3: Draw Native Notifications in Screen Space

**Files:**
- Modify: `/home/max/gen1recomp-savestates/main.lua`
- Modify: `/home/max/gen1recomp-savestates/src/ui/Notification.lua`
- Modify: `/home/max/gen1recomp-savestates/tests/notification_test.lua`
- Modify: `/home/max/gen1recomp-savestates/tests/composition_test.lua`
- Modify: `/home/max/gen1recomp-savestates/tests/modern_ui_integration_test.lua`

**Interfaces:**
- Consumes: public `render.hud(next, game, viewport)` with window-space geometry.
- Produces: `Notification:drawNativeHud(Font, viewport)` that draws a centered native banner near the physical top and never duplicates a claimed Modern UI presentation.

- [x] Change tests to require `render.hud`, physical-top placement, centered title/detail, native fallback, and Modern UI suppression.
- [x] Run the focused tests and confirm the old `render.compose` implementation fails.
- [x] Replace the native `render.compose` wrapper with `render.hud`; use only provided viewport/window metrics and preserve `next` composition.
- [x] Draw the banner at a small top margin with deterministic scaling and clipping, before touch controls.
- [x] Run notification, composition, Modern UI, and QOL coexistence tests.
- [x] Commit the mod-side native HUD correction.

### Task 4: Integrate, Verify, Publish, and Package

**Files:**
- Modify: `/home/max/gen1recomp-savestates/docs/project-plan.md`
- Modify as evidence changes: `/home/max/gen1recomp-savestates/docs/upstream-audit.md`
- Modify: `/home/max/gen1recomp-savestates/docs/acceptance.md`
- Update generated ignored artifacts under `/home/max/gen1recomp-savestates/.artifacts/android-test/`.

**Interfaces:**
- Consumes: fresh upstream `dev`, independent title/scripted/UI contribution heads, Save States `feat/initial-savestates`.
- Produces: verified branches, review-ready upstream PR state, reproducible mod ZIP, parallel Android APK, and exact build evidence.

- [x] Base the independent battle-settling contribution on current upstream `dev` without discarding unpublished work.
- [x] Run focused engine suites, `./scripts/test.sh --quick`, and relevant modkit public-API suites.
- [x] Run `make check` and reproducible clean package validation for Save States against the coherent integration engine.
- [x] Update living documentation with exact heads and fresh outcomes.
- [ ] Commit and push coherent mod documentation changes.
- [x] Open or update focused upstream PRs; verify base, non-draft state, conflict-free GitHub mergeability, and CI.
- [ ] Build the parallel APK and installable Save States ZIP only after the coherent gates pass.
- [ ] Write exact SHAs, commands, results, application/signing compatibility, and hashes to `BUILD-INFO.txt` and `SHA256SUMS.txt`.
