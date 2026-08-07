# Save States

Save States adds native rolling quicksaves, event-based autosaves and permanent
save slots to Gen1Recomp without replacing the normal Pokémon save system.

> Development status: technical preview. The repository is not yet a supported
> player release; the manifest remains experimental until the implemented feature
> set passes clean-package verification against a released engine API.

## Features

The current development package provides rolling overworld and supported battle
safe-point quicksaves, newest and selected-state loading, deferred location,
battle-start, and after-battle autosaves, ten permanent renameable slots, pinning,
durable undo-load recovery, native START and manager screens, configurable
history/notification options, and non-modal notifications. Storage is isolated
by game and opaque playthrough identity.

## Installation

No public release is available yet. Development validation currently targets the
focused Gen1Recomp public-API branch linked from the project plan.

## Quick Start

Open START after overworld movement has settled. `QUICKSAVE` captures immediately;
`STATES` opens histories, slots, undo, and current settings. Vanilla `SAVE` is
unchanged.

## START Menu

The mod decorates the existing menu through the public hook; it does not rebuild
or replace vanilla or other-mod rows.

## Quick Saves

`QUICKSAVE` writes a rolling history. The exported quickload command selects the
newest valid entry; the manager can inspect, load, pin, or delete older entries.
Each state detail shows location, trigger, relative creation time, runtime kind,
and current compatibility before presenting mutating actions. State and slot
deletes use a native confirmation that defaults to NO.

## Auto Saves

Location entry requests are deferred until stable overworld control. Ordinary
wild/trainer starts defer through the intro and capture at the first proven player
decision menu; an unsupported/scripted battle expires rather than later saving a
mislabeled overworld state. Optional after-battle requests wait for stable return.
Optional before-warp capture runs synchronously at the public `player.warped`
pre-transition event and fails closed if that exact boundary is not checkpoint-safe.
Cooldown, semantic duplicate replacement, and chronological retention are active.
Play time and the remembered START-menu cursor are excluded from the semantic
fingerprint; gameplay progress, party, inventory, flags, and position remain
significant.

## Save Slots

Ten permanent, renameable slots are outside rolling retention. Each overwrite
uses a new payload generation so failed index publication leaves the old slot
loadable. Overwriting directly or pinning onto an occupied slot requires an
explicit confirmation that defaults to NO.

## Undo Last Load

Every supported load first captures, writes, and re-reads one durable recovery
checkpoint. Undo restores it without overwriting it.

## Settings

History limits, autosave triggers, save/load notification toggles, and opt-in
debug timings use the native MODS manager. The STATES settings screen reports
current values and points to that public edit path. Debug timing logs report
capture, deterministic serialization/size, persistence, recovery-write, and
restore costs without doing the extra size serialization while disabled.

## Hotkeys

No global key is hijacked. START-menu operation remains the supported baseline
until Gen1Recomp exposes public rebindable mod actions.

## Compatibility

Snapshot format, engine compatibility, and exact supported runtime phases are
tracked in `docs/compatibility.md` as implementation lands.

## Known Limitations

- Suspended scripts, transitions, menus, and partial animations are not safe
  overworld checkpoints.
- Battle checkpoints support ordinary single-player wild/trainer player-decision
  menus. Link, Safari, ghost, demo, fishing/static-origin, scripted, forced-action,
  message, queue, and animation phases are rejected.
- Arbitrary-frame emulator-style snapshots are not promised.

## State Safety

The design uses data-only snapshots, strict identity/content validation,
verified replacement, durable recovery before load, and engine-owned semantic
runtime reconstruction. Corrupt or incompatible data must never execute or
partially mutate a live game.

## Development

Read `AGENTS.md`, `docs/project-plan.md`, and `docs/upstream-audit.md` first.
Run the complete ROM-free behavior, validation, lint, reproducibility, package,
and clean-install gate with:

```sh
make check GEN1RECOMP=/path/to/gen1recomp
```

Until the source-date modkit fix is available in that checkout, pass its
review branch explicitly with `MODKIT=/path/to/modkit.py`. Repository-only
release and upstream handoff details live in `docs/development.md`.

No ROM, imported cache, user save, credential, generated secret, or extracted
game asset belongs in this repository.

## License

MIT. See `LICENSE`.
