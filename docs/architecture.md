# Architecture

## Compatibility boundary

The distributable mod talks only to Gen1Recomp's public Mod API 2. `main.lua`
bootstraps `src/ModuleLoader.lua` through `mod:read` and Lua `load`; every sibling
module follows the same installed-mod filesystem path. No distributable file
imports private `src.*` engine modules.

The Level A engine dependency is proposed in upstream PR
[`bryanthaboi/gen1recomp#952`](https://github.com/bryanthaboi/gen1recomp/pull/952),
with Level B battle/RNG reconstruction in stacked draft
[`MaxTomahawk/gen1recomp#1`](https://github.com/MaxTomahawk/gen1recomp/pull/1):

- `mod.storage` owns physical persistence routing, game/playthrough/mod
  isolation, restricted serialization, staged writes, verification, and backup
  recovery.
- `mod.checkpoints` owns runtime safety inspection, semantic capture, strict
  content/identity validation, controller reconstruction, result verification,
  and in-memory rollback.

The mod treats the returned checkpoint as opaque data. It adds product metadata
and history semantics without copying engine controllers, registries, scripts,
renderer state, or static ROM-derived content.

## Composition

`main.lua` loads and initializes the complete core before publishing
`mod.exports.apiVersion`, `snapshotFormat`, and `supportedStateKinds`. A missing,
invalid, or throwing local module produces a mod-attributed error and publishes no
partial compatibility surface.

Pure modules are dependency-injected factories where they need a sibling. Tests
load the same files directly; modkit validation exercises the installed Loader
path. This split keeps unit tests independent of private engine code while the
package uses the public filesystem facade.

## Capture pipeline

The gameplay service uses this ordered boundary:

`inspect -> capture -> fingerprint -> Snapshot.new -> validate -> write payload -> publish index`

`DataOnly` rejects functions, userdata, threads, cycles, behavioral metatables,
non-finite numbers, excessive depth, and unsupported keys. `Snapshot` copies the
opaque engine checkpoint and attaches format-1 identity/metadata. The validator
returns another detached copy and hard-rejects wrong game/playthrough, inconsistent
checkpoint identity/kind, corrupt metadata, and unsupported runtime kinds. Engine
version mismatch remains warning-grade.

`Canonical` and `Fingerprint` derive a deterministic 64-bit semantic fingerprint
from checkpoint dynamic progress. The fingerprint is deduplication metadata, not a
security checksum or a substitute for full validation.

## Index and retention

The index contains metadata and logical payload ids only. Quick and auto histories
are newest-first; their ids are monotonic. Ten permanent slot numbers point at
unique `sNN_sequence` payload generations. Overwrite publishes a new generation
before cleaning the previous one, so a failed publication cannot destroy the
indexed slot. Recovery uses its own fixed key. Slots/recovery never enter rolling
retention.

Retention returns oldest rolling ids to remove. Autosave deduplication applies the
same trigger/context cooldown first, then replaces the newest same-trigger/map/
fingerprint entry, otherwise appending.

## Persistence transactions

Each public-storage key already has verified main/tmp/backup generations. The mod
adds cross-key ordering:

- Create: write and validate payload first; publish its index reference second.
- Delete: publish an index without the reference first; delete payload second.
- Publication failure leaves the previous valid index and an enumerable orphan
  payload.
- Cleanup failure leaves the new index authoritative and reports an enumerable
  orphan payload.
- Recovery uses a fixed independent key and is never part of rolling history.

A missing first-run index becomes an empty format-1 index. A physically present
but unreadable index is `bad_index`, not silently treated as first run. Missing or
corrupt indexed payloads remain unavailable and untouched for diagnosis/recovery.

## Restore and recovery

The product service validates and migrates the selected snapshot, confirms the
current capability, capture and durably verify `recovery`, then call
`mod.checkpoints:restore`. Engine reconstruction performs its own complete
validation, recapture comparison, and in-memory rollback. Undo loads the fixed
recovery key without overwriting it.

No UI callback throws for expected user-data or I/O failures. Structured error
codes flow to logging and native notifications/screens.

## Native UX and events

The existing START descriptor list is decorated after downstream mods return.
Registered `ListMenu`/`NamingScreen` factories provide histories, state actions,
ten slots, pinning, rename/delete, undo, and settings visibility. Load/save-slot
actions close their known public widget chain before checkpoint inspection; no
private state-stack operation is used.

Notifications are one replace-in-place model drawn through `render.hud`; they
never become an updating screen or consume A/B input. Success types honor their
save/load toggles, while safety and persistence failures remain visible.

`map.entered`, ordinary `battle.started`, and optional `battle.ended` events
enqueue semantic requests. An `input.step` wrapper retries at most one request per
fixed tick and calls the service only after `mod.checkpoints:inspect` proves the
matching overworld or battle boundary. A battle-start request expires when the
runtime leaves battle, preventing a later overworld save from carrying the wrong
trigger. `player.warped` is different: it fires synchronously before transition
mutation, so enabled before-warp capture runs immediately with the live game
cached at the current `input.step`. It is never deferred into the destination.

Opt-in debug timings use the monotonic LÖVE clock. The service measures checkpoint
capture, deterministic wrapper serialization and byte size, state/recovery writes,
and checkpoint restore. Size serialization and timing logs are bypassed entirely
unless `DEBUG TIMINGS` is enabled.
