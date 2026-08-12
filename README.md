# Save States

Save States adds native rolling quicksaves, event-based autosaves and permanent
save slots to Gen1Recomp without replacing the normal Pokémon save system.

> **Early access 0.1.0:** the core mod is installable on **Gen1Recomp v0.1.79
> or newer**. It remains marked experimental until the final physical Android
> and private ROM-backed acceptance pass is complete. Saves are versioned and
> validated, but keep using the normal Pokémon `SAVE` command for a conventional
> backup as well.

<!-- engine-feature-status:start -->
### Engine feature availability

Save States requires **Gen1Recomp v0.1.79 or newer**.

- **Battle START menu:** awaiting merge of [#1077](https://github.com/bryanthaboi/gen1recomp/pull/1077) and a subsequent official Gen1Recomp release.
- **Party icons in state details:** awaiting merge of [#1079](https://github.com/bryanthaboi/gen1recomp/pull/1079) and a subsequent official Gen1Recomp release. Text-only party details remain available while icon support is pending.
<!-- engine-feature-status:end -->

## Features

- Rolling Quick Saves and Auto Saves, with 50 of each retained by default.
- Ten permanent, renameable save slots that retention never removes.
- One-level `UNDO LAST LOAD` recovery before every supported load.
- Stable overworld and deterministic battle decision-point restoration.
- Event-driven autosaves for locations, wild battles and trainer battles.
- Title-menu browsing and loading, including a New Game saved before the first
  manual Pokémon `SAVE`.
- `CONTINUE LATEST`, which chooses the newest valid normal save or savestate.
- Capture-time details for location, date, play time, badges and the full party.
- Corrupt and incompatible records are shown safely and skipped for automatic
  loading.
- Native menus, confirmation screens, settings and non-blocking notifications.
- Red, Blue and Yellow histories are isolated by game and playthrough.

## Installation

1. Update Gen1Recomp to **v0.1.79 or newer**.
2. Download `savestates-0.1.0.zip` from this repository's Releases page. Do not
   extract it.
3. In Gen1Recomp, open **MODS**, choose **Import mod .zip**, select the file and
   enable **Save States**.
4. Restart or reload mods if the launcher asks you to.

No ROM, game assets or player save is included in the package. Gen1Recomp's
normal ROM importer remains unchanged.

## Quick Start

The three main commands are:

- **QUICKSAVE** in the in-game START menu: capture immediately and return to play.
- **STATES** in the in-game START menu: browse, load, pin, rename and delete.
- **SAVE STATES** on the title menu: browse or resume the selected playthrough
  after a restart.

The vanilla **SAVE** command is still present and still means the ordinary
Pokémon save.

## START and Title Menus

Save States decorates the existing menus through public mod hooks, so it does not
replace vanilla rows or additions from other mods.

The title manager can browse Quick Saves, Auto Saves and permanent slots for the
currently selected playthrough. It can load, inspect, pin, rename and delete, but
it cannot capture a new state because no live gameplay boundary exists at title.
Opening it is read-only with respect to playthrough identity.

If the first successful savestate is created before any normal Pokémon save, the
engine creates one verified initial progress anchor from that same checkpoint.
This happens once so the playthrough remains discoverable after a cold restart.
Later savestates do not rewrite the normal save; ordinary `SAVE` and Save States
then progress independently.

`CONTINUE LATEST` is ON by default. Title `CONTINUE` compares the original
capture time of valid Quick Saves, Auto Saves and directly captured permanent
slots with the normal save timestamp. The newest progress point wins; an exact
tie keeps the normal save. Pinning or renaming does not make an older state newer,
and recovery is never an automatic candidate. With the setting OFF, vanilla
`CONTINUE` behavior is unchanged.

## Quick Saves

`QUICKSAVE` captures the current supported boundary and adds it to a rolling
history. The newest valid Quick Save is the quickload target. In the manager, an
older entry can be loaded, pinned to a permanent slot or deleted.

Quick and Auto histories are grouped beneath non-selectable date headings.
History rows can show captured play time, local date/time or relative age.

## Auto Saves

Autosaves are triggered by meaningful events, never by a periodic timer.

- **Location entry:** requested on entry, then captured when overworld control is
  stable.
- **Wild or trainer battle:** requested at battle start, then captured at the
  first supported player decision after the intro settles.
- **After battle:** optional; waits for stable overworld control.
- **Before warp:** optional; captures only when that exact pre-transition
  boundary is safe.

Supported built-in trainer and story battle commands use a semantic continuation
that can be reconstructed without serializing Lua coroutines. Opaque scripts and
unsafe battle phases fail closed. A five-second cooldown, semantic duplicate
replacement and chronological retention prevent noisy histories.

## Battle States

Battle checkpoints are safe points, not arbitrary animation frames. Supported
states are settled single-player wild/trainer decision menus, including validated
built-in scripted trainer/story battles. Restoring also restores the gameplay RNG,
so repeating the same choice produces the same random sequence.

<!-- battle-feature-note:start -->
The pending engine PR #1077 adds START-menu access at those same safe battle
decisions. Until an official release contains it, battle-start autosaves and
loading battle states still work, but the Save States manager cannot be opened
from the battle command menu itself.
<!-- battle-feature-note:end -->

## Save Slots

Ten permanent slots sit outside Quick/Auto retention. Saving to an empty slot is
immediate and uses `SLOT NN`; renaming is optional. Occupied slots can be loaded,
overwritten, renamed or deleted. Pinning copies an existing Quick/Auto state while
preserving its original capture time and provenance. Overwrite and delete prompts
default to **NO**.

## State Details

Details show the captured location, trigger, absolute creation date/time,
checkpoint kind, compatibility, play time, badges and up to six Pokémon with
captured name, level and HP. These previews come from capture-time data and never
substitute current live values.

<!-- icon-feature-note:start -->
On v0.1.79, party rows are fully readable as text. Pending PR #1079 adds the same
public icon composition used by the Party screen; once released, compatible icon
mods can affect the preview through that shared public contract.
<!-- icon-feature-note:end -->

Missing preview data in older states degrades gracefully and never makes the
restore payload corrupt.

## Undo Last Load

Before every supported load, Save States captures, writes and verifies one
recovery state. `UNDO LAST LOAD` restores it without first overwriting it. Only
one level of undo is guaranteed.

## Settings

Settings are edited through Gen1Recomp's MODS options screen.

| Setting | Default | Choices / effect |
| --- | --- | --- |
| Quick Save History | 50 | 1, 3, 5, 10, 15, 20, 30, 50, 75 or 100 |
| Auto Save History | 50 | 5, 10, 20, 30, 50, 75 or 100 |
| History Time | Play Time | Play Time, Date/Time or Age |
| Auto: Location Entry | On | Save after stable location entry |
| Auto: Trainer Battle | On | Save at the first supported trainer decision |
| Auto: Wild Battle | On | Save at the first supported wild decision |
| Auto: After Battle | Off | Save after returning safely from battle |
| Auto: Before Warp | Off | Save at a safe pre-warp boundary |
| Save Notifications | On | Show save success/failure notices |
| Load Notifications | On | Show load and undo notices |
| Continue Latest | On | Compare normal-save and savestate chronology |
| Debug Timings | Off | Log capture, serialization, storage and restore timing |

Date headings and absolute timestamps use Gen1Recomp's device/DMY/MDY/YMD and
12/24-hour preferences. If the device formatter is unavailable, the fallback is
`DD-MM-YYYY` with 24-hour time.

## Compatibility and Safety

Snapshot format 1 stores data only: no functions, userdata, threads, metatables,
LÖVE objects, engine controllers or ROM databases. The engine validates game,
playthrough, content and checkpoint capability before mutating live state.
Writes use staged verification and recovery; corrupt records cannot execute.

Unsupported phases include transitions, ordinary menus, partial animations,
message/action queues, forced decisions, faint replacement, link/Safari/ghost/
demo battles and opaque suspended scripts. They report that saving is currently
unsafe instead of creating a partial state.

Another mod's canonical `mod.save` progress and data-only Pokémon metadata rewind
with the game. Independent `mod.storage`, current options and arbitrary in-memory
caches do not. This avoids rewinding settings or another tool's independent
history.

## Storage Size

Measured serialized wrappers were about 2.6 KiB for an early overworld state and
232–235 KiB for an intentionally heavy late-game state with all twelve boxes
filled. One hundred such worst-case records are roughly 23 MiB before the
engine's crash-recovery witnesses; normal playthrough states are usually smaller.

## Known Limitations

- Battle START and Party-icon availability are recorded in the engine feature
  table near the top of this README.
- Arbitrary-frame emulator snapshots and suspended-coroutine restoration are not
  claimed.
- This early-access release remains `experimental` until final ROM-backed and
  physical-device acceptance is complete.

## Development

Run the complete ROM-free behavior, validation, lint, reproducibility, package
and clean-install gate with:

```sh
make check GEN1RECOMP=/path/to/gen1recomp
```

No ROM, imported cache, user save, credential, generated secret or extracted
game asset belongs in this repository.

## License

MIT. See [LICENSE](LICENSE).
