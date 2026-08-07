# Save States

Save States adds native rolling quicksaves, event-based autosaves and permanent
save slots to Gen1Recomp without replacing the normal Pokémon save system.

> Development status: technical preview. The repository is not yet a supported
> player release; the manifest remains experimental until the implemented feature
> set passes clean-package verification against a released engine API.

## Features

The finished product will provide rolling quicksaves, event-driven autosaves, ten
permanent slots, recovery/undo-load, native menus, configurable notifications,
strict playthrough isolation, and deterministic restoration at supported runtime
boundaries. Features are documented as available only after their tests and
package verification are recorded in `docs/project-plan.md`.

## Installation

No public release is available yet. Development validation currently targets the
focused Gen1Recomp public-API branch linked from the project plan.

## Quick Start

Player instructions will be added when the first complete packaged build is
verified. Vanilla SAVE remains unchanged throughout development.

## START Menu

The final mod decorates the existing menu through the public hook; it does not
rebuild or replace vanilla rows.

## Quick Saves

Planned: rolling manual history with newest-state quickload.

## Auto Saves

Planned: semantic event triggers followed by capture only at a proven-safe
runtime boundary.

## Save Slots

Planned: ten permanent, renameable slots outside rolling retention.

## Undo Last Load

Planned: one durable recovery checkpoint captured before every load.

## Settings

Planned: history limits, autosave triggers, and save/load notification toggles.

## Hotkeys

No global key is hijacked. START-menu operation remains the supported baseline
until Gen1Recomp exposes public rebindable mod actions.

## Compatibility

Snapshot format, engine compatibility, and exact supported runtime phases are
tracked in `docs/compatibility.md` as implementation lands.

## Known Limitations

- Suspended scripts, transitions, menus, and partial animations are not safe
  overworld checkpoints.
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
