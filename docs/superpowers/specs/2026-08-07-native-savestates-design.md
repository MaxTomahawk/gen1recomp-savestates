# Native Save States Design

Status: approved for autonomous execution by the active product goal

Date: 2026-08-07

## Purpose

Save States is a native Gen1Recomp tool mod. It preserves the normal Pokémon
SAVE flow while providing rolling quick and automatic checkpoints, ten permanent
slots, and one-level undo-load. It restores only runtime boundaries the engine
can reconstruct and verify; it never serializes Lua execution stacks, renderer
objects, controller instances, functions, userdata, or ROM-derived databases.

This design refines the supplied product specification against the pinned facts
in `docs/upstream-audit.md`. `docs/project-plan.md` remains the living status and
milestone ledger.

## Architectural decision

Use two repositories with one compatibility boundary:

- `MaxTomahawk/gen1recomp-savestates` contains only distributable public-API mod
  code, pure data logic, tests, documentation, and packaging.
- Focused branches of `MaxTomahawk/gen1recomp` add generic public primitives that
  are unavailable today. Engine changes remain additive, backward-compatible,
  inactive without callers, and separately reviewable.

The mod owns product semantics. The engine owns only runtime facts and persistence
routing that a mod cannot safely infer.

## Required public engine primitives

### Opaque playthrough identity

Every playthrough that uses storage/checkpoint tooling receives an engine-generated
opaque identifier in save metadata. Allocation is lazy: New Game, normal load, and
normal SAVE remain byte-compatible until the first public tool call. Existing saves
receive a stable, independently persisted migration identity until the next normal
SAVE writes it into the save. A fresh New Game in the same launcher slot cannot
reuse the previous mapping. Identity is not derived solely from player name, map,
or a timestamp and does not consume gameplay RNG.

The mod sees identity through the public checkpoint/storage context, not private
slot ids. A copied checkpoint remains associated with its original playthrough;
starting a new game in the same vanilla slot cannot expose the old collection.

### Scoped transactional storage

`mod.storage` is a data-only key/value store scoped to:

`engine persistence root / game version / playthrough id / mod id`

It follows standard and portable persistence routing. Keys use conservative path
segments and cannot escape the namespace. Values pass the engine's restricted
serializer. Writes use staged main/tmp/bak copies, verify bytes by decoding them,
and retain a last-known-good payload. Reads recover from tmp/bak. The surface is:

```lua
local context, code, message = mod.storage:context(game)
local ok, code, message = mod.storage:write(game, key, data)
local data, code, message = mod.storage:read(game, key)
local keys, code, message = mod.storage:list(game, prefix)
local ok, code, message = mod.storage:delete(game, key)
```

No method rewrites the vanilla progress save. No filesystem permission is needed
by the consuming mod.

### Stable overworld checkpoint

`mod.checkpoints` owns runtime safety inspection and semantic reconstruction:

```lua
local capability = mod.checkpoints:inspect(game)
local checkpoint, code, message = mod.checkpoints:capture(game)
local ok, code, message = mod.checkpoints:restore(game, checkpoint)
```

`inspect` initially reports only `kind = "overworld"`. Capture requires the
overworld controller to own input with no transition, modal state, foreground or
parallel script, queued script movement, trainer engagement, emote, warp, battle,
or partial controller mutation. Rejections use stable codes such as
`not_in_playthrough`, `not_overworld`, `screen_busy`, `transition_busy`, and
`script_busy`.

Capture deep-copies canonical progress after synchronizing live map, coordinates,
facing, and surfing. It preserves current settings separately so loading a state
does not rewind display, input, audio, or mod-option preferences. The checkpoint
is a versioned, data-only engine record containing identity, persistent progress,
and semantic overworld position.

Restore validates format, game, playthrough, map/content references, and runtime
capability before mutation. It rebuilds the overworld through engine-owned
operations. If reconstruction throws, the engine attempts to restore the
pre-operation checkpoint and reports a failure instead of exposing a partial
load. The product service still writes its own durable recovery state before a
load, because process failure cannot be rolled back in memory.

## Mod architecture

The mod wraps an engine checkpoint in snapshot format 1:

```lua
{
  format = 1,
  identity = {
    modId = "savestates",
    modVersion = "0.1.0",
    modApi = 2,
    engineVersion = "...",
    gameVersion = "red",
    playthroughId = "...",
  },
  metadata = {
    id = "...",
    stateClass = "quick" | "auto" | "slot" | "recovery",
    trigger = "manual" | "location_enter" | "trainer_battle_start"
      | "wild_battle_start" | "battle_end" | "before_warp",
    createdAt = 0,
    label = nil,
    locationId = "...",
    locationName = "...",
    stateKind = "overworld" | "battle",
  },
  checkpoint = { -- opaque versioned engine data-only record
  },
}
```

Responsibility boundaries:

- `Snapshot` and `SnapshotValidator`: construction, schema, compatibility.
- `StateStore`: public-storage adapter and verified index/payload transactions.
- `StateIndex` and `Retention`: ordering, permanent slots, rolling histories.
- `SaveStateService`: capture, recovery-before-load, restore, undo, notifications.
- `AutoSaveController`: safe deferred event requests, cooldown, deduplication.
- registered UI screens: root, lists, details/actions, slots, settings.
- HUD notification controller: replace-in-place, non-modal, option-aware.

The state index and each snapshot payload are separate keys. Index updates occur
only after a payload write verifies. Deletion removes the index reference first,
then the payload; an orphan is recoverable by storage enumeration. Corrupt payloads
are retained and marked unavailable rather than executed or silently discarded.

## User flow

The START menu is decorated after every earlier wrapper and inserts `QUICKSAVE`
then `STATES` immediately before the current `OPTION` descriptor. Vanilla `SAVE`,
conditional rows, and other mod rows remain untouched.

Quicksave captures immediately when safe. Quickload chooses the newest compatible
quick state only. Every load first persists a recovery snapshot; failure to create
recovery refuses the load. Undo restores recovery without overwriting it.

Semantic events enqueue autosave requests. The controller waits for a confirmed
safe fixed-step boundary and never uses a periodic timer as its trigger. Same
trigger/context within five seconds is ignored. The newest semantic duplicate is
replaced when trigger, map, and persistent fingerprint agree.

## Battle extension

Battle support is a later engine contract, not an expansion of the overworld
record. Before proposing it, `docs/battle-state-map.md` must classify every mutable
battle field. The initial boundary is the player decision menu with an empty
message/action/animation pipeline. A battle checkpoint must include an engine-owned
serializable gameplay RNG state and pass differential action/reload tests. Mid-
animation and suspended-script states remain unsupported for v1.

## Failure handling

User callbacks return structured errors and log remediation; they do not throw.
Decode, schema, identity, capability, missing content, persistence, recovery, and
restore failures are distinct. No live state mutates before complete validation.
The UI always remains escapable and describes why an entry is unavailable.

## Verification strategy

- Pure modules use strict red-green-refactor tests under LuaJIT.
- Engine public surfaces have both no-mod parity and public-mod API tests.
- Level A uses capture A -> mutate B -> restore A -> capture A2 and compares a
  normalized A with A2 across outdoor, indoor, route, party, inventory, flags,
  object toggles, defeated trainers, exact coordinates, facing, and surfing.
- Persistence tests inject failures at tmp write, main write, verification read,
  decode, missing index, missing payload, and delete.
- Package verification runs current modkit validation, lint, pack, archive-root
  inspection, private-require scans, and ROM-derived-content checks.
- Release completion requires a fresh installed ZIP against an engine release that
  contains the required public seams.

## Explicit non-goals for v1

- Arbitrary-frame snapshots.
- Suspended coroutine or cutscene restoration.
- Mid-animation battle restoration.
- Undeclared direct filesystem access or private `src.*` imports in the mod.
- Replacing vanilla SAVE or treating a savestate as a vanilla save slot.
