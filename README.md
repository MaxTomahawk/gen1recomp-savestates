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

When the optional Gen1 Modern UI compatibility extension is installed and
enabled, Save States keeps its own notification timing and content but lets that
mod present the banner in its active theme and touch-safe layout. Without it,
Save States uses the native Gen1-style banner. No other mod's private theme or
runtime state is read.

## Installation

No public release is available yet. ROM-free CI validates current upstream
`dev`; the Android development bundle additionally combines the review-ready
title-resume and battle-menu branches recorded in the project plan.

## Quick Start

Open START after overworld movement has settled. `QUICKSAVE` captures immediately;
`STATES` opens histories, slots, undo, and current settings. Vanilla `SAVE` is
unchanged. The development stack also adds `SAVE STATES` to the title menu: it
browses only the selected existing playthrough and can resume a compatible saved
state without silently creating a normal Pokémon save.

## START Menu

The mod decorates the existing menu through the public hook; it does not rebuild
or replace vanilla or other-mod rows.

## Title Menu

`SAVE STATES` is inserted before `NEW GAME` on the native title menu. It reuses
the same quick, auto, and slot histories but does not offer live capture,
overwrite, or undo: title has no safe live runtime to snapshot. Loading delegates
to the engine's validated title-resume transaction; pinning, renaming, and
deleting remain durable operations inside the selected Save States namespace.
This currently requires the unpublished development engine contract described in
the project plan and is not yet part of a released compatibility promise.

`CONTINUE LATEST` defaults to ON. When enabled, the existing title `CONTINUE`
row selects the newest valid progress point for that selected playthrough: a
normal Pokémon save or an eligible quick, auto, or permanent-slot checkpoint.
The original capture time decides; pinning and renaming never make an older
checkpoint newer, and recovery is never selected automatically. An exact-time
tie intentionally keeps the native normal save. Invalid, wrong-playthrough, and
implausibly future-dated checkpoints are skipped. Turning it OFF leaves vanilla
`CONTINUE` unchanged while explicit title `SAVE STATES` loading remains available.

## Quick Saves

`QUICKSAVE` writes a rolling history. The exported quickload command selects the
newest valid entry; the manager can inspect, load, pin, or delete older entries.
History defaults to captured `PLAY TIME`; `DATE/TIME` and relative `AGE` are
available in settings. Previewless legacy records fall back to age. Each state
detail shows location, trigger, absolute captured date/time, runtime kind, and
current compatibility before presenting mutating actions. New captures also show
their captured play time, badges, and up to six party members as a name row plus
a level/current-HP/maximum-HP row. These are descriptive previews, not restore
data; older states without them remain usable. State and slot deletes use a
native confirmation that defaults to NO.

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

Ten permanent slots with native names up to 12 characters are outside rolling
retention. Each overwrite uses a new payload generation so failed index
publication leaves the old slot loadable. Pinning preserves the source
checkpoint's capture time, semantic trigger, and preview. Empty slots save
immediately with their generated `SLOT NN` label; rename is an explicit optional
action. Overwriting directly or pinning onto an occupied slot requires an explicit
confirmation that defaults to NO.

## Undo Last Load

Every supported load first captures, writes, and re-reads one durable recovery
checkpoint. Undo restores it without overwriting it.

## Settings

History limits, history-time presentation, autosave triggers, `CONTINUE LATEST`,
save/load notification toggles, and opt-in debug timings use the native MODS
manager. The STATES settings screen reports current values and points to that
public edit path. Debug timing logs report
capture, deterministic serialization/size, persistence, recovery-write, and
restore costs without doing the extra size serialization while disabled.

## Hotkeys

No global key is hijacked. START-menu operation remains the supported baseline
until Gen1Recomp exposes public rebindable mod actions.

## Compatibility

Snapshot format, engine compatibility, and exact supported runtime phases are
tracked in `docs/compatibility.md`. What rewinds across other installed mods and
how cooperating mods rebuild derived state is documented in
`docs/cross-mod-compatibility.md`.

## Known Limitations

- Suspended scripts, transitions, menus, and partial animations are not safe
  overworld checkpoints.
- Battle checkpoints support ordinary single-player wild/trainer player-decision
  menus. Link, Safari, ghost, demo, fishing/static-origin, scripted, forced-action,
  message, queue, and animation phases are rejected.
- The development battle manager needs the review-ready generic
  `battle.menu_auxiliary` engine branch until it is merged and released.
- Other mods' canonical `mod.save` progress rewinds, while independent
  `mod.storage`, options, and arbitrary runtime state do not. Progress-derived
  runtime caches require the generic post-restore cooperation contract.
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

Current upstream `dev` already contains source-date reproducible packaging.
Repository-only release and upstream handoff details live in
`docs/development.md`.

No ROM, imported cache, user save, credential, generated secret, or extracted
game asset belongs in this repository.

## License

MIT. See `LICENSE`.
