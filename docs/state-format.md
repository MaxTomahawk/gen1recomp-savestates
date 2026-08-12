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
    stateKind = "overworld", -- overworld | battle
    fingerprint = "0123456789abcdef",
    contextKey = nil,
    slot = nil,
    preview = {
      playTime = 16620,
      badgeCount = 1,
      badgeTotal = 8,
      party = {
        { name = "SPARKY", level = 22, hp = 45, maxHp = 57 },
      },
    },
  },
  checkpoint = {
    -- Opaque engine-owned data-only checkpoint.
  },
}
```

## Identity

`gameVersion` and `playthroughId` must match the current public storage context
and the nested checkpoint identity. Mismatch is a hard rejection. The public
storage context also reports the current `engineVersion`; the wrapper and nested
checkpoint must agree with one another, while mismatch with the currently running
engine is warning-grade because patch releases are not assumed incompatible
without evidence. Histories expose that warning before the player chooses LOAD.

The mod id is always `savestates`, and Mod API is 2. A copied state never becomes
loadable in another game or playthrough merely because its location/player name
matches.

## Metadata

Rolling ids are `q`/`a` plus an eight-digit monotonic sequence. Permanent payload
generations are `sNN_` plus the same monotonic sequence; `metadata.slot` binds a
generation to logical slot 1 through 10. A stable slot number therefore survives
while each overwrite remains cross-key transactional. Recovery is `recovery`.
`createdAt` is a nonnegative timestamp supplied by the service clock. Custom slot
labels are metadata only.

Canonical autosave triggers are `location_enter`, `trainer_battle_start`,
`wild_battle_start`, `battle_end`, and `before_warp`; `manual` is used for user
captures. A trigger is enabled only when its public event and subsequent safe
capture boundary have been proven.

`fingerprint` is optional outside autosaves. It summarizes canonical dynamic
progress for semantic duplicate detection and is never trusted for compatibility
or corruption validation. `contextKey` distinguishes cooldown contexts that share
a map.

`preview` is optional descriptive capture-time metadata kept in the index as well
as the payload. It records only play time, badge progress, and zero through six
party rows with display name, level, current HP, and maximum HP. It never carries
status, moves, DVs, or other gameplay state; the nested checkpoint remains the
only restore authority. A present preview is strictly data-only and validated.
Snapshots written before previews existed may omit it and remain valid Format 1
records. Histories and slots browse index metadata without decoding every payload;
the selected detail validates its payload before showing compatibility actions.

Direct slot saves derive a fresh preview. Pinning and rename preserve the source
preview and original capture provenance exactly, including an absent legacy
preview. Slot labels remain independently player-authored metadata.

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
1 admits `overworld` and the engine's proven `battle` safe-point kind. Script and
unknown kinds remain rejected and do not become valid through wrapper migration.
