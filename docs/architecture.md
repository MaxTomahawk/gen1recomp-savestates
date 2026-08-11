# Architecture

## Compatibility boundary

The distributable mod talks only to Gen1Recomp's public Mod API 2. `main.lua`
bootstraps `src/ModuleLoader.lua` through `mod:read` and Lua `load`; every sibling
module follows the same installed-mod filesystem path. No distributable file
imports private `src.*` engine modules.

The Level A engine dependency landed in upstream PR
[`bryanthaboi/gen1recomp#952`](https://github.com/bryanthaboi/gen1recomp/pull/952),
with Level B battle/RNG reconstruction merged separately in upstream PR
[`bryanthaboi/gen1recomp#986`](https://github.com/bryanthaboi/gen1recomp/pull/986):

- `mod.storage` owns physical persistence routing, game/playthrough/mod
  isolation, restricted serialization, staged writes, verification, and backup
  recovery.
- `mod.checkpoints` owns runtime safety inspection, semantic capture, strict
  content/identity validation, controller reconstruction, result verification,
  and in-memory rollback.

The mod treats the returned checkpoint as opaque data. It adds product metadata
and history semantics without copying engine controllers, registries, scripts,
renderer state, or static ROM-derived content.

Cross-mod ownership follows the same semantic boundary. Canonical `game.save`
progress, every mod's `save.modData`, and data-only metadata on canonical records
rewind. Independent `mod.storage`, current options, and arbitrary mod runtime
state do not. Merged upstream PR #993 adds only a success-only
`checkpoint.restored` invalidation boundary so cooperating mods can rebuild
progress-derived caches after final verified reconstruction. Save States never
enumerates another mod's private state or storage. See
`docs/cross-mod-compatibility.md`.

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

`inspect -> capture -> preview/fingerprint -> Snapshot.new -> validate -> write payload -> publish index`

`DataOnly` rejects functions, userdata, threads, cycles, behavioral metatables,
non-finite numbers, excessive depth, and unsupported keys. `Snapshot` copies the
opaque engine checkpoint and attaches format-1 identity/metadata. The validator
returns another detached copy and hard-rejects wrong game/playthrough, inconsistent
checkpoint identity/kind, corrupt metadata, and unsupported runtime kinds. Engine
version mismatch remains warning-grade.

`Canonical` and `Fingerprint` derive a deterministic 64-bit semantic fingerprint
from checkpoint dynamic progress. The fingerprint is deduplication metadata, not a
security checksum or a substitute for full validation.

`Preview` derives a small capture-time summary from the public detached checkpoint
save and public content registries: play time, badges, and up to six party
name/level/current-HP/maximum-HP rows. It is optional descriptive metadata, never
restore input; unavailable display data warns without sacrificing a valid
checkpoint.

## Index and retention

The index contains metadata and logical payload ids only, including optional
capture-time previews. Quick and auto histories are newest-first; their ids are
monotonic. Ten permanent slot numbers point at unique `sNN_sequence` payload
generations. Overwrite publishes a new generation before cleaning the previous
one, so a failed publication cannot destroy the indexed slot. Recovery uses its
own fixed key. Slots/recovery never enter rolling retention. Browsing a list reads
only this index; opening one detail performs the single payload validation read.

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

After that verified engine commit, `checkpoint.restored` is the generic
cross-mod reconciliation point. It is not emitted for validation failure,
reconstruction failure, or rollback. The event cannot participate in the
transaction and carries no snapshot payload; subscribers observe the already
restored canonical world and rebuild only their own derived runtime state.

No UI callback throws for expected user-data or I/O failures. Structured error
codes flow to logging and native notifications/screens. Capability refusals and
incompatible user data are warning-grade; persistence, restore, and unexpected
public-API failures are error-grade with the original remediation message.

## Native UX and events

The existing START descriptor list is decorated after downstream mods return.
Registered public widget factories provide histories, state actions,
ten slots, pinning, rename/delete, undo, and settings visibility. Load/save-slot
actions close their known public widget chain before checkpoint inspection; no
private state-stack operation is used. Actions stay first in their compact menu;
the capture-time location, trigger, age, runtime kind, compatibility, and party
preview live in a read-only scrolling detail screen. History headings are visual
date rows, never selection targets. Detail metadata is collision-split using
public font metrics; Pokémon are whole selectable two-line icon blocks. The icon
is delegated to the engine's public Party icon presenter so content registrations,
asset overrides, and `pokemon.icon` hooks keep composing. The settings summary
mirrors every public product option and links to the MODS editor.
Destructive history and slot actions route through a registered, default-NO
native confirmation and update their source list only after storage succeeds.

Notifications are one replace-in-place model drawn through `render.compose` on
the engine's public 160x144 `uiCanvas`; they
never become an updating screen or consume A/B input. Success types honor their
save/load toggles, while safety and persistence failures remain visible.
Text is measured with the active public font, long details are fitted to the
18-tile interior, and the one required long title wraps at a word boundary. The
banner uses the complete logical top row rather than physical Android coordinates.
This follows the native UI-pass strategy used by QoL location banners and lets
the engine own Android scaling and touch-control composition. Headless geometry
tests cover that contract; portrait/landscape device
presentation remains a manual release-acceptance check.

`gen1_modern_ui` is an optional ordering dependency only. Save States publishes
its `gen1ModernUi` v1 contract with data-only history/details screen models and a
single source-owned `transient.model`, and
registers it through the other mod's public export when available. The model
contains only the active notification id/title/detail/severity. Modern UI owns
theme, responsive safe-area layout, and drawing; Save States keeps content,
replacement, expiry, and all gameplay actions. Its classic banner is skipped
only while the public presenter explicitly claims the source, so absence,
disablement, incompatibility, or presenter failure falls back cleanly. The
native classic banner uses the logical top edge while Modern UI's QOL location
banner remains a separate bottom card; neither mod reads the other's private
state. Date/time presentation similarly delegates to the public engine formatter;
the global options stay current across checkpoint restore and the mod uses a
portable DMY/24-hour fallback on older hosts.

The autosave fingerprint hashes canonical progress but deliberately removes only
`playTime` and `startMenuIndex`. Those presentation counters would otherwise make
two gameplay-equivalent states different on every capture; coordinates, party,
inventory, boxes, money, Pokédex, flags, object/trainer state, and other mod data
remain significant.

`map.entered`, ordinary/scripted `battle.started`, and optional `battle.ended` events
enqueue semantic requests. An `input.step` wrapper retries at most one request per
fixed tick and calls the service only after `mod.checkpoints:inspect` proves the
matching overworld or battle boundary. A battle-start request expires when the
runtime leaves battle, preventing a later overworld save from carrying the wrong
trigger. If a stale overworld request is ahead of a battle request, every leading
runtime mismatch is discarded in that same pre-input tick so the first safe
battle decision is not missed. `player.warped` is different: it fires synchronously before transition
mutation, so enabled before-warp capture runs immediately with the live game
cached at the current `input.step`. It is never deferred into the destination.

Opt-in debug timings use the monotonic LÖVE clock. The service measures checkpoint
capture, deterministic wrapper serialization and byte size, state/recovery writes,
and checkpoint restore. Size serialization and timing logs are bypassed entirely
unless `DEBUG TIMINGS` is enabled.
