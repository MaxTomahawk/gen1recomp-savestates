# Review-ready upstream contribution handoffs

Prepared: 2026-08-10

The connected GitHub integration can push to `MaxTomahawk/gen1recomp-savestates`
but returned HTTP 403 `Resource not accessible by integration` for cross-repository
pull-request creation. These are review-ready local/fork branches; this document
provides exact titles, bases, bodies, and compare URLs for manual publication.

## Gen1Recomp: title checkpoint resume

| Field | Value |
| --- | --- |
| Fork branch | `MaxTomahawk/gen1recomp:feat/mod-title-checkpoint-resume` |
| Head | `3f25dde11f6b85148a72efbb42525e5ba618e572` |
| Base | `bryanthaboi/gen1recomp:dev` at `943ba5dcbfa62cf831e881684857ffd4867fe774` |
| Title | `feat(mods): resume selected checkpoints from title` |
| Open PR | <https://github.com/bryanthaboi/gen1recomp/compare/dev...MaxTomahawk:feat/mod-title-checkpoint-resume?expand=1> |

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

No normal Pokémon save is created. NEW GAME stays a fresh identity, options stay
current, and failures leave a usable title session. This branch deliberately
remains independent of `checkpoint.restored`; the combined integration stack
proves the existing lifecycle is emitted exactly once when PR #993 is present.

## Verification

- `./scripts/test.sh --quick` — 139/139 engine suites, 8/8 modkit suites.
- Title selected-context, no-first-normal-save, corruption, recovery, cross-slot,
  cross-game, mod-save rebinding, and no-mod parity coverage are included.
- ROM-derived Tier 3 is skipped because no generated/imported game data is in
  the public worktree.
```

## Gen1Recomp: battle menu auxiliary action

| Field | Value |
| --- | --- |
| Fork branch | `MaxTomahawk/gen1recomp:feat/battle-menu-auxiliary` |
| Head | `016b0b967b0da2f5e4f72a27970824eb440ffeb7` |
| Base | `bryanthaboi/gen1recomp:dev` at `943ba5dcbfa62cf831e881684857ffd4867fe774` |
| Title | `feat(mods): add battle menu auxiliary action` |
| Open PR | <https://github.com/bryanthaboi/gen1recomp/compare/dev...MaxTomahawk:feat/battle-menu-auxiliary?expand=1> |

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
- `./scripts/test.sh --quick` — 140/140 engine suites, 7/7 modkit suites.
- ROM-derived Tier 3 is skipped because no generated/imported game data is in
  the public worktree.
```

## Gen1 Modern UI: source transient presentation

No `MaxTomahawk/gen1-modern-ui` fork currently exists, so create that fork first,
then push local branch `feat/source-transient-notifications` at
`62642c490382e7ad9aaa29b5a4ca6ee80e0ed53c` and open:

<https://github.com/ArmstrongThomas/gen1-modern-ui/compare/main...MaxTomahawk:feat/source-transient-notifications?expand=1>

| Field | Value |
| --- | --- |
| Base | `ArmstrongThomas/gen1-modern-ui:main` at `847e7b9ce1afca473da43c050ed34da05a30a0d0` |
| Title | `feat: present source transient notices` |

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
