# Upstream Audit

Status: Phase 0 evidence baseline

Audited: 2026-08-07

Engine: `bryanthaboi/gen1recomp` `dev` at `112120e8fe4ab03665e7e3eff761032451b36d8c`

Wiki: `bryanthaboi/gen1recomp.wiki` at `635e1e87d2e3b2e71c2276a60327aee7a24e57c9`

Index: `bryanthaboi/gen1recomp-mod-index` `main` at `17314bfc79e980fcc4fb75e2439bfae75cfa05c8`

This document distinguishes documented public API from private engine capability.
Absence statements apply to the pinned commits and must be rechecked after an
upstream update.

## Repository and tooling facts

- `dev` is the engine's default branch. `src/core/Version.lua` reports mod API 2,
  save format 4, and the working-tree engine version `0.0.0-dev`; release builds
  stamp the real engine version.
- `tools/modkit.py scaffold` supports an external `--dest`. Its current content
  scaffold emits `game_version: ">=0.0.0-dev <1.0.0"`, not the proposed
  `">=0.0.0-0 <2.0.0"`. It does not create tests, `mod.card`, or a changelog.
- `modkit validate` drives the real loader with ROM-free fixture data when imported
  data is absent. `lint` enforces the ROM-content rules. `pack` runs strict
  validation and lint and adds `.modkit/pack.json`.
- The generated release workflow creates `<id>-<version>.zip` with `manifest.json`
  at the archive root. Mod code is expected in its own repository.
- Mod tests use LuaJIT and the public SDK harness under `tests/modkit/`, normally
  from an engine checkout. Example suites load the mod through `T.sdk.loadMod` and
  assert behavior, not just loader success.

## Public mod surface

The authoritative statement is the wiki's `Reference-Mod-Object.md`: anything
outside the mod object, cataloged events/hooks, registries, schemas, and supported
requires is unsupported.

| Area | Verified public capability | Evidence |
| --- | --- | --- |
| Lifecycle | `game.ready` provides the sanctioned live `Game` reference | wiki `Concepts-Lifecycle.md`; `src/core/Game.lua:Game:load` |
| UI | `screens:register`, `mod.ui.push`, stable widgets, `insertBefore`/`insertAfter` | `src/ui/ModUI.lua`; `src/ui/Screens.lua`; `example_dexnav` |
| START menu | `ui.start_menu.items` decorates the returned descriptor list | `src/ui/StartMenu.lua:StartMenu.new`; wiki `Reference-Hooks.md` |
| Notifications | `render.hud(next, game, viewport)` draws non-modal screen-space UI after composition and before touch controls | `src/core/Game.lua:Game:draw`; `tests/engine/tool_mod_hooks.lua` |
| Options | `mod.options:define/get`; toggle, choice, number, and text rows persist in `options.lua` | `src/mods/Loader.lua:Loader:_api`; wiki `Concepts-Save-Model.md` |
| Per-save mod data | `mod.save:get/set` maps to `save.modData[modId]` and persists only with the vanilla progress save | same sources |
| Migrations | `mod.migrations:add(since, fn)` upgrades a mod's per-save shape | `src/core/SaveData.lua:SaveData.runMigrations` |
| Events | `map.entered/exited`, `player.warped`, `world.trainer_engaged`, `battle.started/turn_started/turn_ended/ended`, `script.started/ended`, save and screen events | wiki `Reference-Events.md`; emit sites in `src/` |
| Input | `input.step` hook and `mod.input` can inject the eight Game Boy buttons safely | `src/core/Game.lua:Game:step`; `src/mods/Loader.lua:Loader:_api` |
| World | `mod.world:current`, `warpTo`, flags, object toggles, scripts, and NPC helpers | `src/world/WorldAPI.lua`; wiki `Reference-Mod-Object.md` |
| Files | `mod:read` reads packaged files. Direct filesystem writes are permission-disclosed with `filesystem`; permissions are disclosure, not a sandbox | `src/mods/Manifest.lua`; wiki `Reference-Manifest.md` |

The START menu currently contains conditional `POKéDEX`, `POKéMON`, `ITEM`, the
player-name row, `SAVE`, `OPTION`, conditional `LINK`, conditional `MODS`, and
`QUIT`. The proposed fixed list ending in `EXIT` is obsolete. Save States should
insert `QUICKSAVE` then `STATES` before `OPTION`, preserving all other rows.

## Persistence and identity

`SaveData` uses deterministic, data-only Lua serialization with a restricted
parser and staged main/tmp/bak recovery. Red, Blue, and Yellow progress are
separate, and current upstream also has multiple vanilla save slots under
`saves/<version>/<slot>.lua`.

Important limitations:

- `mod.save` is not an independent store. It aliases the active live save's
  `modData` and is flushed by vanilla save writing. Forcing that write from a
  quicksave would also change the vanilla SAVE checkpoint.
- A whole `game.save` copied into `mod.save` would recursively include the
  savestate collection and grow without bound.
- `SaveData.activeSlot(version)` exists privately, but no public mod API exposes
  an opaque active playthrough/slot identity.
- There is no public namespaced transactional blob/file store tied to the active
  game version and playthrough. Raw `love.filesystem` is possible with the
  declared `filesystem` permission, but it bypasses portable-mode routing and
  supplies no engine-owned playthrough scope.

Conclusion: production persistence and isolation need a small generic upstream
per-mod storage/profile seam, or a consciously limited filesystem implementation.
The selected product design uses the upstream seam; it will not make portable-mode
and identity correctness somebody else's problem.

## Overworld runtime and scripts

The canonical persistent state is `game.save`; `SaveData.newGame` includes game
version, player/trainer data, flags, inventory, PC items, party/boxes, money,
defeated trainers, Pokédex, heal/outdoor state, and mod data. Most gameplay mutates
this table directly.

Coordinates and facing are copied from the live player only by private
`OverworldState:captureSave`. Private `Game:restoreSave` runs migrations and
validation, adopts mod storage, applies options, clears the state stack, and
re-enters the overworld. `mod.world:current` exposes map/x/y/facing, but public
`warpTo` performs a normal animated warp and fires map scripts; it is not an
equivalent restore operation.

`OverworldController:setMap` reconstructs the runtime map, NPCs, renderer, camera,
music, forced movement, darkness, follower state, and map-enter behavior. This
supports the proposed semantic reconstruction model and argues against serializing
controller objects.

`ScriptRunner` is coroutine-driven. It stores a suspended Lua coroutine and
blocking commands yield/resume it. Foreground and up to four parallel runners can
exist; killing a parallel runner does not emit a balancing `script.ended` event.
Therefore counting public script events is not a reliable snapshot-safety oracle,
and coroutine stack serialization is not viable.

Current public API has no:

- stable-overworld safe-point query;
- data-only progress capture that includes all required live semantic fields;
- validated, quiescent progress restore operation;
- resumable script checkpoint representation.

Gate A conclusion: an exact, public-API-only Level A implementation is **blocked**
on a generic stable-runtime checkpoint seam. Direct calls to
`OverworldState:captureSave`, `Game:restoreSave`, state-stack methods, or runner
internals would violate the distribution rule.

## Events and autosave timing

The required semantic triggers largely exist:

- location: `map.entered`;
- trainer pre-battle intent: `world.trainer_engaged`;
- initialized battle: `battle.started` with `kind`;
- after turn/battle: `battle.turn_ended` and `battle.ended`;
- warp observation: `player.warped`, with `map.exited`/`map.entered` around load.

However, `map.entered` fires inside `setMap` before the map `onEnter` script and
before queued scripts drain. Battle events expose the live battle object, not a
serializable checkpoint. Events are sufficient to request an autosave, but the
capture must be deferred until the new public capability reports a safe boundary.

## Battle and RNG

`BattleState` is a large mutable state machine. Its stable player decision phase is
`phase == "menu"` with an empty action/message pipeline, but that phase and its
many fields are private implementation, not a public import/export contract.
Battle events expose observations and modification hooks; none exports or restores
a battle snapshot.

Battle logic injects `self.rng`, but it currently wraps global
`love.math.random`. Encounters and multiple overworld systems also call
`love.math.random` directly; trainer ID creation and OT stamping also use
`math.random`/global random sources. Link battles have a separate deterministic
Park-Miller stream. No public serializable gameplay RNG state exists.

Battle restoration is therefore deferred behind two proven upstream needs:

1. a generic battle safe-point export/import contract;
2. one engine-owned serializable gameplay RNG stream, with no-mod parity tests.

The battle-state inventory remains a mandatory gate before proposing field shapes.

## Input, UI, and notifications

- There is no public API for a mod to register a new rebindable action. The binding
  system knows only the eight Game Boy buttons. `mod.input` injects those buttons;
  it does not define actions. Hotkeys remain optional until an additive custom
  action API exists.
- Full menu screens are supported. `ListMenu` supplies an empty-state sentence,
  but custom product copy will require a small screen wrapper rather than accepting
  its hardcoded `Nothing here.` everywhere.
- A non-modal replace-in-place toast is implementable today through `render.hud`;
  no upstream toast API is required for the initial product.

## Manifest, packaging, and index corrections

- The manifest should be regenerated from the current scaffold and then changed to
  category `TOOL`, `github: "MaxTomahawk/gen1recomp-savestates"`, and
  `experimental: true` until user validation. The final engine range must be based
  on the first released upstream seams, not today's dev placeholder.
- A `filesystem` permission is unnecessary if the planned scoped-storage seam
  lands; `engine_internals` is never acceptable for the distributable mod.
- The index folder is `mods/MaxTomahawk@savestates/` and contains metadata only.
  `meta.json.repo` must be the full HTTPS URL; the proposed `owner/repo` value is
  invalid for that field. `github` remains `owner/repo`.
- Index submission waits for a real installable GitHub Release and copies final
  manifest compatibility/permission fields exactly.

## Proven upstream capability gaps

| Candidate | Requested capability | Current public surface | Private proof | Smallest generic direction | Required upstream evidence |
| --- | --- | --- | --- | --- | --- |
| `SAVESTATES-SP-01` | Playthrough-scoped durable state payloads independent of vanilla SAVE | `mod.save` is embedded; raw filesystem is unscoped | `SaveData` knows active version/slot and portable persistence FS | Namespaced per-mod storage scoped to active playthrough, with verified replace/read/delete/list | failure injection, portable/standard parity, cross-slot isolation, no-mod parity |
| `SAVESTATES-SP-02` | Safe Level A capture/restore | read access to `game`, `mod.world:current/warpTo`; no checkpoint API | `OverworldState:captureSave`, `Game:restoreSave`, `SaveData.validate` | Data-only stable-overworld capability/capture/restore facade that reconstructs runtime and rejects unsafe phases | roundtrip equivalence, malformed input, restore rollback/recovery, event ordering, no-mod parity |
| `SAVESTATES-SP-03` | Stable profile identity | generated per-save mod data only; no active slot id | `SaveData.activeSlot` and versioned slot registry | Opaque identity returned by storage/checkpoint context, not mutable slot internals | new/load/switch/delete slot isolation tests |
| `SAVESTATES-SP-04` | Rebindable quick actions | GB-button injection only | core `Input`/`BindingsMenu` fixed action list | Additive mod action registry integrated with bindings UI | keyboard/pad/rebind/conflict/no-mod tests |
| `SAVESTATES-SP-05` | Deterministic battle restore | battle events/hooks only | `BattleState` mutable fields; global random use | Serializable engine RNG plus battle safe-point export/import, proposed only after inventory | RNG parity/differential battle suite and no-mod parity |

These are prerequisites, not pre-approved engine changes. Each remains a candidate
until its spike and RFC prove the exact delta.
