# Review-ready upstream contribution handoffs

Prepared: 2026-08-12

SSH git pushed all Gen1Recomp branches to `MaxTomahawk/gen1recomp`. Rechecking
the execution history showed that earlier successful contributions used the
root user's authenticated GitHub CLI, not the cross-repository GitHub app. The
same `gh pr create` path opened the contributions on 2026-08-11. GitHub reports
the two remaining non-draft PRs mergeable and clean; current checks are recorded
per PR. The other Save States engine prerequisites are merged and released in
Gen1Recomp v0.1.79.

## Gen1Recomp: title checkpoint resume

| Field | Value |
| --- | --- |
| Fork branch | `MaxTomahawk/gen1recomp:feat/mod-title-checkpoint-resume` |
| Merge | `3aaaf9936e67d4fac1c48c20d10af7313f57a40b` |
| Released | Gen1Recomp `v0.1.79` |
| Title | `feat(mods): resume selected checkpoints from title` |
| PR | [#1076](https://github.com/bryanthaboi/gen1recomp/pull/1076) — merged |

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
| Head | `238af263d6b345c627b3b9e1489b85734f8e899e` |
| Base | `bryanthaboi/gen1recomp:dev` at `49d094b14d9e3986313a1f02126db08ac0dc43e9` |
| Title | `feat(mods): add battle menu auxiliary action` |
| PR | [#1077](https://github.com/bryanthaboi/gen1recomp/pull/1077) — open, non-draft, mergeable/clean, 15/15 checks |

```markdown
## Summary

Adds public `battle.menu_auxiliary`, a generic semantic tool action invoked by
START only at an already-settled supported player-decision boundary, including
the validated built-in scripted origins from RFC 0005.

- Reuses the same public battle safety predicate as persistent checkpoints.
- Returns to native input when no handler accepts the action, preserving no-mod
  behavior and unsafe phases.
- Contains handler exceptions and exposes neither `BattleState` internals nor
  raw keyboard/controller/touch state to mods.
- Documents deterministic multi-handler ordering and adds public SDK coverage.

This is a reusable boundary for tool mods; it contains no Save States policy or
serialization behavior.

Merged PR #1087 supplies the real-runtime settling fix; this API deliberately
shares the unchanged checkpoint-safety predicate.

## Verification

- `luajit tests/engine/battle_menu_auxiliary.lua` — 13/13.
- Integration with PR #1087: real wild/trainer intros reach the safe boundary
  and START dispatches without consuming a command or advancing RNG.
- `luajit tests/modkit/cases/checkpoints.lua` — 58/58.
- `./scripts/test.sh --quick` — 158/158 engine suites, 14/14 modkit suites.
- ROM-derived Tier 3 is skipped because no generated/imported game data is in
  the public worktree.
```

## Gen1Recomp: settle real battle decisions

| Field | Value |
| --- | --- |
| Fork branch | `MaxTomahawk/gen1recomp:fix/battle-decision-settling` |
| Merge | `20e0692486c7a63a91d3dd90774163aff126da8e` |
| Released | Gen1Recomp `v0.1.79` |
| Title | `fix: settle real battle checkpoint decisions` |
| PR | [#1087](https://github.com/bryanthaboi/gen1recomp/pull/1087) — merged |

Real wild/trainer intros drained their action queue but retained completed
`afterQueue`, insertion, wait, and intro-slide markers. The existing strict
checkpoint predicate correctly treated those markers as busy, which blocked
both queued battle autosaves and the public START auxiliary action in real play
while synthetic tests that assigned `phase = "menu"` passed.

The patch normalizes only completed markers during the existing transition into
the command menu. It does not weaken any active-animation, queue, forced-choice,
origin, or script exclusion. Focused real-intro boundary checks pass 18/18;
`./scripts/test.sh --quick` passes 149/149 engine and 9/9 modkit suites; GitHub
CI is green. This repair merged before the dependent integration was refreshed.

## Gen1Recomp: scripted battle checkpoints

| Field | Value |
| --- | --- |
| Fork branch | `MaxTomahawk/gen1recomp:feat/scripted-battle-checkpoints` |
| Merge | `af33c6e810c31f5dce3aadda41c7e1de11f0f5ca` |
| Released | Gen1Recomp `v0.1.79` |
| Title | `feat(mods): checkpoint scripted battle decisions` |
| PR | [#1078](https://github.com/bryanthaboi/gen1recomp/pull/1078) — merged |

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
- Integration with PR #1087: a real scripted trainer intro reaches the safe
  boundary, captures/restores, and exposes the generic START action.
- Combined current-dev integration — 152/152 engine suites and 12/12 modkit suites.
- ROM-derived Tier 3 is skipped because no generated/imported game data is in
  the public worktree.
```

## Gen1Recomp: canonical detached Pokémon icons

| Field | Value |
| --- | --- |
| Fork branch | `MaxTomahawk/gen1recomp:feat/mod-pokemon-icon` |
| Head | `29a2b9a1232eff4517f6764417f2e09c9c47735a` |
| Base | `bryanthaboi/gen1recomp:dev` at `49d094b14d9e3986313a1f02126db08ac0dc43e9` |
| Title | `feat(mods): expose canonical Pokémon icon presentation` |
| PR | [#1079](https://github.com/bryanthaboi/gen1recomp/pull/1079) — open, non-draft, mergeable/clean, CI green |

The public `mod.ui.PokemonIcon.draw` accepts only detached
`{species,hp,maxHp}` data plus presentation flags and delegates to the native
Party icon resolver. Content icon registrations, sprite assets, and
`pokemon.icon` hooks therefore compose without exposing PartyMenu or live
Pokémon records. Focused checks pass 14/14; `./scripts/test.sh --quick` passes
157/157 engine and 15/15 modkit suites after current-dev conflict resolution;
GitHub CI is green and ROM-derived Tier 3 is unavailable.

## Gen1Recomp: shared local date and time

| Field | Value |
| --- | --- |
| Fork branch | `MaxTomahawk/gen1recomp:feat/device-date-time` |
| Merge | `e8eccfd4df73beec8f88b3454f1265e55b902f17` |
| Released | Gen1Recomp `v0.1.79` |
| Title | `feat(mods): add shared local date and time formatting` |
| PR | [#1080](https://github.com/bryanthaboi/gen1recomp/pull/1080) — merged |

Global DEVICE/DMY/MDY/YMD and DEVICE/12h/24h choices live in `options.lua`,
so checkpoint restore never rewinds them. The read-only `mod.datetime` facade
returns formatted strings only. DEVICE follows the process time locale where
the target exposes one and otherwise deliberately falls back to DMY/24-hour.
`./scripts/test.sh --quick` passes 150/150 engine and 10/10 modkit suites;
ROM-derived Tier 3 is unavailable.

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
