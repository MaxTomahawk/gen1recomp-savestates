# Upstream Audit

Status: refreshed after merged Level A, Level B, packaging, and cross-mod
lifecycle contributions

Audited: 2026-08-12

Engine: `bryanthaboi/gen1recomp` `dev` at `49d094b14d9e3986313a1f02126db08ac0dc43e9`

Official compatibility baseline: `v0.1.79` at
`04490c9b9ad03b814f297793dd7a950dad7c3adf`

Wiki: `bryanthaboi/gen1recomp.wiki` at `635e1e87d2e3b2e71c2276a60327aee7a24e57c9`

Index: `bryanthaboi/gen1recomp-mod-index` `main` at
`47f94004f36f18d915c16e9b349d30cd5891d96c`

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
| Notifications | `render.hud(next, game, viewport)` is the public screen-space UI pass after the centered game canvas and before touch controls; its viewport/scale/DPI context permits a native logical box at the physical top without guessing Android pixels | `src/core/Game.lua:Game:draw`; `tests/engine/tool_mod_hooks.lua`; QoL `qol_feature_location_banners` |
| Options | `mod.options:define/get`; toggle, choice, number, and text rows persist in `options.lua` | `src/mods/Loader.lua:Loader:_api`; wiki `Concepts-Save-Model.md` |
| Per-save mod data | `mod.save:get/set` maps to `save.modData[modId]` and persists only with the vanilla progress save | same sources |
| Independent tool storage | `mod.storage:context/write/read/list/delete` is data-only, verified, portable-aware, and scoped by game/playthrough/mod | `src/mods/Storage.lua`; `docs/modding.md`; RFC 0003 |
| Runtime checkpoints | `mod.checkpoints:inspect/capture/restore` supports strict settled-overworld and ordinary wild/trainer player-decision reconstruction | `src/core/Checkpoint.lua`; `docs/modding.md`; RFC 0004 and RFC 0005 |
| Migrations | `mod.migrations:add(since, fn)` upgrades a mod's per-save shape | `src/core/SaveData.lua:SaveData.runMigrations` |
| Events | `map.entered/exited`, `player.warped`, `world.trainer_engaged`, `battle.started/turn_started/turn_ended/ended`, `script.started/ended`, save and screen events; merged PR #993 adds success-only `checkpoint.restored` | wiki `Reference-Events.md`; emit sites in `src/`; PR #993 |
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

It deliberately does not provide a general resumable coroutine representation.
The separate scripted-battle contribution proves a narrower safe contract for
built-in battle commands: stable script id/program counter/context plus a one-use
semantic battle result can rebuild a fresh runner without serializing a Lua stack.
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

Merged PR #986 extends the opaque public checkpoint facade to settled ordinary
wild/trainer player-decision menus. The engine captures only data-only semantic
battle progress, reconstructs a fresh controller and continuation, restores the
LÖVE gameplay RNG stream, validates supported content/origin/phase, verifies by
differential recapture, and rolls back failures. Scripts, active queues,
animations, forced choices, link/Safari/ghost/demo battles, and unsupported
origins remain rejected. The complete field classification remains in
`docs/battle-state-map.md`.

The public mod never imports `BattleState` or the RNG implementation. The engine
owns both reconstruction and deterministic replay.

## Cross-mod checkpoint ownership

The indexed `masterwebx@SHINY_POKEMON` implementation was inspected directly at
`masterwebx/gen1recomp-shiny-pokemon` commit
`2141b2ed35f4261d7306d8bb4d66a8c50e87125f`. It represents shiny identity with
two data-only fields on a plain Pokémon record: `isShinyMon` accepts a true
`mon.shiny` marker first, or derives status from the Gen 2 predicate over
`mon.dvs`. `applyShinyToMon` writes both fields and recalculates stats/HP. It
stores no shiny identity in `mod.save` or `mod.storage`.

Canonical party/box/daycare and battle Pokémon records are copied wholesale by
the checkpoint formats, and `SaveData.validate` preserves extra data-only fields.
Shiny-style DVs/metadata therefore roundtrip generically with their Pokémon and
game progress in overworld and supported battles. No mod-id special case is
needed. The optional Wilds of Kanto integration was also inspected at
`masterwebx/overworld-spawn-mod` commit
`866bbdf5afa771bfeacbb3bb639cddd9b5c171cd`; its overworld encounter entities are
runtime-only and should rebuild, not become canonical save payloads.

The resulting ownership contract is:

- `game.save`, including every loaded mod's `save.modData`, rewinds;
- `mod.storage` and current global/per-mod options do not rewind;
- mod-added data-only fields on canonical progress records rewind with them;
- arbitrary mod runtime state is never serialized;
- derived runtime/cache state rebuilds from restored public canonical state.

Existing restore code rebinds loaded mods' `mod.save` tables but suppresses normal
save/map/battle lifecycle side effects. The public-API-only
`checkpoint_cross_mod` suite proved the minimal correction now merged in PR #993:
`checkpoint.restored` emits only after final differential verification, with
`{ game, kind }`, and never on validation/reconstruction failure or rollback.
Independent storage/options remain unchanged. Full user/mod-author rules are in
`docs/cross-mod-compatibility.md`.

## Input, UI, and notifications

- There is no public API for a mod to register a new rebindable action. The binding
  system knows only the eight Game Boy buttons. `mod.input` injects those buttons;
  it does not define actions. Hotkeys remain optional until an additive custom
  action API exists.
- Full menu screens are supported. `ListMenu` supplies an empty-state sentence,
  but custom product copy will require a small screen wrapper rather than accepting
  its hardcoded `Nothing here.` everywhere.
- A non-modal replace-in-place toast is implementable today through
  `render.hud` on the public screen-space HUD pass;
  no upstream toast API is required for the initial product.
- Detached checkpoint preview rows cannot safely call private Party UI. PR #1079
  adds a narrow presentation-only public delegate so icon packs/hooks retain the
  exact engine-owned resolution path.
- Timestamp formatting is broader engine configuration rather than Save States
  progress. PR #1080 keeps it in `options.lua`, exposes only formatted strings to
  mods, and preserves DMY/24-hour behavior where a device process locale is absent.

## Manifest, packaging, and index corrections

- The early-access manifest uses category `TOOL`, GitHub update metadata,
  `experimental: true`, and the verified official range `>=0.1.79 <1.0.0`.
  Stable promotion remains gated on final ROM/device acceptance and released
  #1077/#1079 enhancements.
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
| `SAVESTATES-SP-05` | Deterministic battle restore | **Merged:** ordinary wild/trainer decision-menu `mod.checkpoints` with engine-owned RNG | `BattleState` mutable fields; global random use | Implemented as opaque battle safe-point/RNG extension in PR #986 | differential/RNG/rollback suites plus current 139/139 engine and 7/7 modkit baseline |
| `SAVESTATES-SP-07` | Let another mod reconcile progress-derived runtime state after restore | **Merged:** success-only `checkpoint.restored`; restore rebinds `mod.save` | `Checkpoint.restore` suppresses ordinary load/map/battle events; runtime caches remain private | Implemented without storage rewind or checkpoint payload | 46/46 public cross-mod checks; current upstream ROM-free integration 150/150 engine and 10/10 modkit suites |
| `SAVESTATES-SP-08` | Title-safe selected storage, first-state normal anchor, and checkpoint resume | **Released in v0.1.79:** PR #1076 | title fresh skeleton cannot safely resolve existing storage or bootstrap runtime | Narrow selected-playthrough facade; no enumeration, hidden SAVE simulation, or raw paths | 40/40 focused title checks, two-process cold restart, full quick suite |
| `SAVESTATES-SP-09` | START tool entry at a safe battle decision | **Open PR #1077:** `battle.menu_auxiliary` | ordinary battle command loop privately owns START | Composable semantic auxiliary action sharing checkpoint safety predicate | 13/13 focused checks, 158/158 engine and 14/14 modkit suites; GitHub CI green |
| `SAVESTATES-SP-10` | Safe scripted trainer/story battle checkpoint | **Released in v0.1.79:** PR #1078 | runner is coroutine-backed but known built-in command boundary is reconstructable | Persist script id/pc/context and one-use result, never coroutine/stack | focused and full integration suites green |
| `SAVESTATES-SP-11` | Render detached checkpoint party previews through the same icon composition as Party UI | **Open PR #1079:** `mod.ui.PokemonIcon.draw` | `PartyMenu.drawIcon` already owns content icons, asset overrides, and `pokemon.icon` hook composition | Validate `{species,hp,maxHp}` and delegate presentation only | 14/14 public API checks; 157/157 engine and 15/15 modkit suites; GitHub CI green |
| `SAVESTATES-SP-12` | Consistent device/fallback date-time presentation across engine and mods | **Released in v0.1.79:** PR #1080 | options are engine-owned and must remain current across restore; Lua exposes process locale only where platform supplies it | DEVICE/process-locale formatter with DMY/24-hour fallback and explicit DMY/MDY/YMD + 12/24h overrides | focused and full integration suites green |
| `SAVESTATES-SP-13` | Make real completed battle intros satisfy the existing safe-decision contract | **Released in v0.1.79:** PR #1087 | real wild/trainer intros retained non-semantic completed markers although the action queue and presentation had drained | Normalize only completed transition state; keep the strict shared `BattleSafety` predicate unchanged | 18/18 focused real-intro checks and full integration suite green |

The table records both landed and remaining seams. Optional custom actions remain
a future candidate; Level A, Level B, packaging, and the cross-mod lifecycle are
merged public behavior.

## Merged and proposed public extensions

- PR #952 is merged at `cd0ace2`: `mod.storage`, lazy playthrough identity, and
  settled-overworld `mod.checkpoints` are now official `dev` APIs. Storage context
  is `{ engineVersion, gameVersion, playthroughId }`; engine version is advisory,
  while game/playthrough remain hard isolation boundaries.
- PR #986 is merged at `983bea6`: the opaque checkpoint facade supports settled
  ordinary wild/trainer decision menus, semantic continuation reconstruction,
  and exact LÖVE RNG restoration.
- PR #993 is merged as `ee891fb8` from head `aa3b2a1`. It adds only the
  success-only generic lifecycle described above. Its public cross-mod suite
  passes 46/46; current upstream integration passes 150/150 engine and 10/10
  modkit suites.
- `SAVESTATES-SP-04` custom actions remains unimplemented and non-blocking. The
  complete product remains operable through native START-menu rows; no global key
  is intercepted.
- PR #959 is merged at `5b6dfed`: official `modkit pack` honors standard
  `SOURCE_DATE_EPOCH`, rejects invalid epochs before writing, and proves
  byte-identical archives.

Official tag v0.1.79 is the early-access compatibility target. The manifest stays
experimental until #1077/#1079 reach an official release and final ROM-backed and
physical-device acceptance passes.
