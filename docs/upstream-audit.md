# Upstream Audit

Status: refreshed after merged Level A and packaging contributions

Audited: 2026-08-08

Engine: `bryanthaboi/gen1recomp` `dev` at `cab62ff7b340ba29ee212487fd9944fa636974a8`

Wiki: `bryanthaboi/gen1recomp.wiki` at `635e1e87d2e3b2e71c2276a60327aee7a24e57c9`

Index: `bryanthaboi/gen1recomp-mod-index` `main` at `682272bb5b2c48b6552be4aa692681f38a825edf`

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
  validation and lint and adds `.modkit/pack.json`. Merged PR #959 makes
  `SOURCE_DATE_EPOCH` control `packed_at`, rejects invalid epochs before output,
  and tests byte-identical repeated packages. Wall-clock behavior remains only
  when callers do not request a reproducible build.
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
| Independent tool storage | `mod.storage:context/write/read/list/delete` is data-only, verified, portable-aware, and scoped by game/playthrough/mod | `src/mods/Storage.lua`; `docs/modding.md`; RFC 0003 |
| Runtime checkpoints | `mod.checkpoints:inspect/capture/restore` supports strict settled-overworld semantic reconstruction | `src/core/Checkpoint.lua`; `docs/modding.md`; RFC 0004 |
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

`mod.save` retains these important limitations:

- `mod.save` is not an independent store. It aliases the active live save's
  `modData` and is flushed by vanilla save writing. Forcing that write from a
  quicksave would also change the vanilla SAVE checkpoint.
- A whole `game.save` copied into `mod.save` would recursively include the
  savestate collection and grow without bound.
- Physical launcher-slot identity remains private by design.

Current conclusion: merged `mod.storage` supplies the selected production seam.
Its context exposes only `{ engineVersion, gameVersion, playthroughId }`; logical
keys are mod-scoped, values are restricted data-only tables, writes are staged and
decode-verified, reads recover valid temporary/backup generations, and persistence
uses the engine's standard or portable backend. No filesystem permission or
private slot/path access is required by the mod.

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

`ScriptRunner` remains coroutine-driven. It stores a suspended Lua coroutine and
blocking commands yield/resume it. Foreground and up to four parallel runners can
exist; killing a parallel runner does not emit a balancing `script.ended` event.
Therefore counting public script events is not a reliable snapshot-safety oracle,
and coroutine stack serialization is not viable.

Merged `mod.checkpoints` now provides the stable-overworld query, detached
data-only capture, and validated quiescent reconstruction that were previously
missing. It requires the overworld topmost, stationary tile control, and no
transition, menu, script, queued script movement, or partial field animation.
Restore validates identity/content/position before mutation, preserves current
options, suppresses ordinary entry/load side effects, verifies by recapture, and
rolls back in memory on failure.

It deliberately does not provide a resumable script checkpoint representation.
Direct controller/state-stack/runner access remains unsupported and unnecessary.
Gate A conclusion is now **GO on merged public API**; an official release tag is
still required before the distributable manifest can declare compatibility.

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

Battle restoration still depends on two proven upstream needs not present in
official `dev`:

1. a generic battle safe-point export/import contract;
2. one engine-owned serializable gameplay RNG stream, with no-mod parity tests.

The completed battle-state inventory and implementation are submitted as focused
upstream PR #986.

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
| `SAVESTATES-SP-01` | Playthrough-scoped durable state payloads independent of vanilla SAVE | **Merged:** `mod.storage` | `SaveData` owns active version/slot and portable persistence FS | Implemented as namespaced verified data-only storage | 28/28 public storage checks plus engine suite |
| `SAVESTATES-SP-02` | Safe Level A capture/restore | **Merged:** overworld `mod.checkpoints` | `OverworldState:captureSave`, checkpoint reconstruction, `SaveData.validate` | Implemented as semantic capability/capture/restore facade | 34/34 public checks, differential equivalence, rollback/content rejection |
| `SAVESTATES-SP-03` | Stable profile identity | **Merged:** opaque `playthroughId` in storage/checkpoint context | private slot registry remains hidden | Implemented lazy opaque identity | new/load/switch/delete isolation and 1,000-process regression |
| `SAVESTATES-SP-04` | Rebindable quick actions | GB-button injection only | core `Input`/`BindingsMenu` fixed action list | Additive mod action registry integrated with bindings UI | keyboard/pad/rebind/conflict/no-mod tests |
| `SAVESTATES-SP-05` | Deterministic battle restore | overworld-only checkpoint API in official `dev` | `BattleState` mutable fields; global random use | Implemented battle safe-point/RNG extension in PR #986 | 137/137 engine, 7/7 modkit, differential/RNG/rollback suites |

The table records both landed and remaining seams. Only custom actions and the
battle/RNG extension remain candidates for further upstream action; Level A and
packaging are merged public behavior.

## Merged and proposed public extensions

- PR #952 is merged at `cd0ace2`: `mod.storage`, lazy playthrough identity, and
  settled-overworld `mod.checkpoints` are now official `dev` APIs. Storage context
  is `{ engineVersion, gameVersion, playthroughId }`; engine version is advisory,
  while game/playthrough remain hard isolation boundaries.
- `feat/mod-battle-checkpoints` through `12b6ef6` extends that opaque checkpoint
  facade at settled ordinary wild/trainer decision menus, including semantic
  continuation reconstruction and exact LÖVE RNG restoration. It is submitted as
  official upstream PR #986. The rebased quick suite passes 137/137 engine and
  7/7 modkit suites; battle restore passes 43/43 and the public checkpoint facade
  passes 53/53. All upstream CI checks currently pass.
- `SAVESTATES-SP-04` custom actions remains unimplemented and non-blocking. The
  complete product remains operable through native START-menu rows; no global key
  is intercepted.
- PR #959 is merged at `5b6dfed`: official `modkit pack` honors standard
  `SOURCE_DATE_EPOCH`, rejects invalid epochs before writing, and proves
  byte-identical archives.

Merged `dev` is still not a released compatibility target. The manifest remains
experimental until PR #986 lands, the complete public APIs ship in an upstream
release, and the final range can name that version honestly.
