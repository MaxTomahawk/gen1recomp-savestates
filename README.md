# Save States

Save States adds native rolling quicksaves, event-based autosaves and permanent
save slots to Gen1Recomp without replacing the normal Pokémon save system.

> Development status: technical preview. The repository is not yet a supported
> player release; the manifest remains experimental until the implemented feature
> set passes clean-package verification against a released engine API.

## Features

The current development package provides rolling overworld quicksaves, newest and
selected-state loading, deferred location/after-battle autosaves, ten permanent
renameable slots, pinning, durable undo-load recovery, native START and manager
screens, configurable history/notification options, and non-modal notifications.
Storage is isolated by game and opaque playthrough identity. Battle checkpoints
remain a separately gated implementation phase.

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

## Auto Saves

Location entry requests are deferred until stable overworld control. Optional
after-battle requests likewise wait for the battle and follow-up script to finish.
Cooldown, semantic duplicate replacement, and chronological retention are active.

## Save Slots

Ten permanent, renameable slots are outside rolling retention. Each overwrite
uses a new payload generation so failed index publication leaves the old slot
loadable.

## Undo Last Load

Every supported load first captures, writes, and re-reads one durable recovery
checkpoint. Undo restores it without overwriting it.

## Settings

History limits, autosave triggers, and save/load notification toggles use the
native MODS manager. The STATES settings screen reports current values and points
to that public edit path.

## Hotkeys

No global key is hijacked. START-menu operation remains the supported baseline
until Gen1Recomp exposes public rebindable mod actions.

## Compatibility

Snapshot format, engine compatibility, and exact supported runtime phases are
tracked in `docs/compatibility.md` as implementation lands.

## Known Limitations

- Suspended scripts, transitions, menus, and partial animations are not safe
  overworld checkpoints.
- Trainer/wild battle-start and before-warp triggers are visible as planned
  settings but are not activated until a matching safe checkpoint kind exists.
- Battle restoration is not claimed until a separate state inventory and
  deterministic RNG contract pass differential tests.
- Arbitrary-frame emulator-style snapshots are not promised.

## State Safety

The design uses data-only snapshots, strict identity/content validation,
verified replacement, durable recovery before load, and engine-owned semantic
runtime reconstruction. Corrupt or incompatible data must never execute or
partially mutate a live game.

## Development

Read `AGENTS.md`, `docs/project-plan.md`, and `docs/upstream-audit.md` first.
Canonical commands are documented in `Makefile` as they become available.

No ROM, imported cache, user save, credential, generated secret, or extracted
game asset belongs in this repository.

## License

MIT. See `LICENSE`.
