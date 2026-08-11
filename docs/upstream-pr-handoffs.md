# Review-ready upstream contribution handoffs

Prepared: 2026-08-11

SSH git pushed all Gen1Recomp branches to `MaxTomahawk/gen1recomp`. Rechecking
the execution history showed that earlier successful contributions used the
root user's authenticated GitHub CLI, not the cross-repository GitHub app. The
same `gh pr create` path opened all three contributions on 2026-08-11. GitHub
reports each non-draft PR mergeable and clean with 15/15 checks complete.

## Gen1Recomp: title checkpoint resume

| Field | Value |
| --- | --- |
| Fork branch | `MaxTomahawk/gen1recomp:feat/mod-title-checkpoint-resume` |
| Head | `4db97164bb6a48f0de10d1ebc841dc42b1a6d0cf` |
| Base | `bryanthaboi/gen1recomp:dev` at `79ed37699ebb9dd5de5e839d23bd12b2719e4cca` |
| Title | `feat(mods): resume selected checkpoints from title` |
| PR | [#1076](https://github.com/bryanthaboi/gen1recomp/pull/1076) — open, non-draft, mergeable/clean, 15/15 checks |

```markdown
## Summary

Adds a narrow, generic title-safe path for tool mods to resume a validated
checkpoint that belongs to the launcher-selected existing playthrough.

- `mod.storage:selected(game)` exposes only the selected playthrough's own
  namespaced storage context without allocating an identity or enumerating
  slots/playthroughs.
- `mod.checkpoints:resume(game, checkpoint)` validates and semantically
  bootstraps overworld or supported battle checkpoints from title.
- The selected normal-save chronology is available as metadata only, so source
  mods can make policy decisions without reading canonical save data.
- `mod.checkpoints:ensureNormalSave` may create one validated ordinary progress
  anchor after a tool has durably committed its first checkpoint. It is
  idempotent and never rewrites an existing normal save.

NEW GAME stays a fresh identity, options stay current, and failures leave a usable
title session. Because `checkpoint.restored`
is now merged in the base, a title resume emits that success-only lifecycle event
exactly once after the same final verification boundary as live restore.

## Verification

- `./scripts/test.sh --quick` — 149/149 engine suites, 10/10 modkit suites.
- `tests/engine/title_checkpoint_cold_restart.sh` — PASS across two real processes.
- Title selected-context, no-first-normal-save, corruption, recovery, cross-slot,
  cross-game, mod-save rebinding, and no-mod parity coverage are included.
- ROM-derived Tier 3 is skipped because no generated/imported game data is in
  the public worktree.
```

## Gen1Recomp: battle menu auxiliary action

| Field | Value |
| --- | --- |
| Fork branch | `MaxTomahawk/gen1recomp:feat/battle-menu-auxiliary` |
| Head | `59725c0ead3c761b7e6c4fbf977e15531819f285` |
| Base | `bryanthaboi/gen1recomp:dev` at `79ed37699ebb9dd5de5e839d23bd12b2719e4cca` |
| Title | `feat(mods): add battle menu auxiliary action` |
| PR | [#1077](https://github.com/bryanthaboi/gen1recomp/pull/1077) — open, non-draft, mergeable/clean, 15/15 checks |

```markdown
## Summary

Adds public `battle.menu_auxiliary`, a generic semantic tool action invoked by
START only at an already-settled ordinary wild/trainer player-decision boundary.

- Reuses the same public battle safety predicate as persistent checkpoints.
- Returns to native input when no handler accepts the action, preserving no-mod
  behavior and unsafe phases.
- Contains handler exceptions and exposes neither `BattleState` internals nor
  raw keyboard/controller/touch state to mods.
- Documents deterministic multi-handler ordering and adds public SDK coverage.

This is a reusable boundary for tool mods; it contains no Save States policy or
serialization behavior.

## Verification

- `luajit tests/engine/battle_menu_auxiliary.lua` — 10/10.
- `luajit tests/engine/battle_checkpoint_boundary.lua` — 13/13.
- `luajit tests/modkit/cases/checkpoints.lua` — 58/58.
- `./scripts/test.sh --quick` — 150/150 engine suites, 9/9 modkit suites.
- ROM-derived Tier 3 is skipped because no generated/imported game data is in
  the public worktree.
```

## Gen1Recomp: scripted battle checkpoints

| Field | Value |
| --- | --- |
| Fork branch | `MaxTomahawk/gen1recomp:feat/scripted-battle-checkpoints` |
| Head | `882763cfe1dc42714908b5d16018811f00a64b70` |
| Base | `bryanthaboi/gen1recomp:dev` at `79ed37699ebb9dd5de5e839d23bd12b2719e4cca` |
| Title | `feat(mods): checkpoint scripted battle decisions` |
| PR | [#1078](https://github.com/bryanthaboi/gen1recomp/pull/1078) — open, non-draft, mergeable/clean, 15/15 checks |

```markdown
## Summary

Extends persistent battle checkpoints to built-in scripted trainer/story battle
commands at the existing settled player-decision boundary.

- Captures a detached data-only `script_battle` origin containing stable script
  identity, program counter, command context, and continuation metadata.
- Reconstructs a fresh ScriptRunner at that known command with a one-use semantic
  battle result, preserving the normal wrapper tail and post-battle branches.
- Never serializes a coroutine, Lua stack, function, controller, or live NPC.
- Rejects opaque callbacks, non-data-only rows, missing NPC context, concurrent
  scripts, unsupported variants, and every non-settled battle phase.
- Keeps checkpoint format 1 and existing ordinary battle behavior unchanged.

## Verification

- `luajit tests/engine/scripted_battle_checkpoints.lua` — 20/20.
- `./scripts/test.sh --quick` — 150/150 engine suites, 9/9 modkit suites.
- Combined current-dev integration with title and auxiliary branches — 151/151
  engine suites and 10/10 modkit suites.
- ROM-derived Tier 3 is skipped because no generated/imported game data is in
  the public worktree.
```

## Gen1 Modern UI: source transient presentation

| Field | Value |
| --- | --- |
| Base | `ArmstrongThomas/gen1-modern-ui:main` at `847e7b9ce1afca473da43c050ed34da05a30a0d0` |
| Title | `feat: present source transient notices` |
| Head | `9aebcb8ae1152b1efd8f48034a87069d6d564fa9` |
| PR | [#13](https://github.com/ArmstrongThomas/gen1-modern-ui/pull/13) — open, non-draft, mergeable/clean |

```markdown
## Summary

Extends the existing public Gen1 Modern UI v1 source-adapter contract with an
optional, data-only `transient.model` and
`isTransientPresentationActive(owner)` fallback signal.

Source mods retain notification content, replacement, and expiry. Gen1 Modern
UI owns theme, responsive safe-viewport layout, touch-safe placement, and
drawing. The renderer accepts no source draw callback, private theme lookup,
checkpoint payload, service object, or writable storage handle. It bounds
visible notices and uses deterministic owner ordering.

When Modern UI is absent, disabled, malformed, or the source model fails, the
source sees no active claim and retains its own native HUD fallback.

## Verification

- `npx --yes luaparse -q mods/gen1_modern_ui/main.lua`.
- `python3 <gen1recomp>/tools/modkit.py validate --repo <gen1recomp> --base fixture mods/gen1_modern_ui`.
- `python3 <gen1recomp>/tools/modkit.py lint --repo <gen1recomp> mods/gen1_modern_ui`.
- LÖVE 11.4 `tests/compose_suppression` — PASS, including public source
  transient registration, disabled fallback, malformed-model rejection, and
  ordinary adapter lifecycle coverage.
```
