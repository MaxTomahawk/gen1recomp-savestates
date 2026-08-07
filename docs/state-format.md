# Snapshot Format 1

Format 1 is a deterministic data-only mod record around an opaque, separately
versioned Gen1Recomp checkpoint:

```lua
{
  format = 1,
  identity = {
    modId = "savestates",
    modVersion = "0.1.0",
    modApi = 2,
    engineVersion = "0.9.0-dev",
    gameVersion = "red",
    playthroughId = "opaque-engine-id",
  },
  metadata = {
    id = "q00000001",
    stateClass = "quick", -- quick | auto | slot | recovery
    trigger = "manual",
    createdAt = 0,
    label = nil,
    locationId = "PALLET_TOWN",
    locationName = "PALLET TOWN",
    stateKind = "overworld",
    fingerprint = "0123456789abcdef",
  },
  checkpoint = {
    -- Opaque engine-owned data-only checkpoint.
  },
}
```

## Identity

`gameVersion` and `playthroughId` must match the current public storage context
and the nested checkpoint identity. Mismatch is a hard rejection. `engineVersion`
must agree between wrapper and checkpoint; mismatch with the currently running
engine is warning-grade because patch releases are not assumed incompatible
without evidence.

The mod id is always `savestates`, and Mod API is 2. A copied state never becomes
loadable in another game or playthrough merely because its location/player name
matches.

## Metadata

Rolling ids are `q`/`a` plus an eight-digit monotonic sequence. Permanent ids are
`slot01` through `slot10`; recovery is `recovery`. `createdAt` is a nonnegative
timestamp supplied by the service clock. Custom slot labels are metadata only.

Canonical autosave triggers are `location_enter`, `trainer_battle_start`,
`wild_battle_start`, `battle_end`, and `before_warp`; `manual` is used for user
captures. A trigger is enabled only when its public event and subsequent safe
capture boundary have been proven.

`fingerprint` is optional outside autosaves. It summarizes canonical dynamic
progress for semantic duplicate detection and is never trusted for compatibility
or corruption validation.

## Data rules

Allowed values are finite numbers, strings, booleans, and recursively data-only
tables keyed by strings or positive integers. Functions, userdata, threads,
cycles, behavioral metatables, non-finite numbers, and nesting beyond 128 levels
are rejected. Static game databases and ROM-derived assets are not copied.

## Compatibility and migrations

Unknown future wrapper formats are rejected. Older formats run only explicitly
registered one-step migrations against a detached copy; every step must advance
exactly one format and return data-only output. Stored bytes are not implicitly
rewritten by a read migration.

The nested checkpoint has its own engine format and runtime-kind validator. Format
1 currently admits only `overworld`; battle and script checkpoint kinds require
separate proven engine contracts and do not become valid through wrapper migration.
