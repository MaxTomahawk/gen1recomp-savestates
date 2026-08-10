# Compatibility

## Required engine capability

The development package uses the additive Level A APIs merged by upstream PR
[`bryanthaboi/gen1recomp#952`](https://github.com/bryanthaboi/gen1recomp/pull/952)
plus the merged Level B battle/RNG extension in upstream PR
[`bryanthaboi/gen1recomp#986`](https://github.com/bryanthaboi/gen1recomp/pull/986).
The focused cross-mod audit proved one remaining generic lifecycle need, proposed
as success-only `checkpoint.restored` in upstream ready-for-review PR
[`bryanthaboi/gen1recomp#993`](https://github.com/bryanthaboi/gen1recomp/pull/993).
Title browsing/resume additionally depends on the unpublished generic
selected-playthrough/title-checkpoint contract under local engine review. It is
not a supported player release until every required public contract ships in an
official engine release and `manifest.json` can name that release as its minimum.

## Supported now

- Matching game version and opaque playthrough identity.
- Snapshot wrapper format 1 and engine checkpoint format 1.
- Settled overworld control with the overworld as the top screen.
- Settled ordinary wild/trainer player-decision menus with a reconstructable
  engine-owned continuation.
- Exact semantic progress plus map, tile coordinates, facing, and surfing state.
- Reconstruction with engine validation, recapture comparison, rollback, and
  preservation of the current global options.
- Engine-version differences as a visible warning rather than an automatic hard
  rejection; game/playthrough/format mismatches remain hard failures.

## Rejected runtime phases

- Any menu or other screen above the overworld.
- Movement between tiles.
- Map transitions and partial field animations.
- Active, queued, or parallel scripts and scripted movement.
- Battle intro/messages/queues, HP tweens, animations, forced player actions,
  faint processing, link/Safari/ghost/demo variants, fishing/static origins,
  mod-defined completion closures, and battles suspending a script coroutine.
- Arbitrary title/new-game capture. The development title manager can only
  browse the engine-selected existing playthrough and resume a validated stored
  checkpoint through the dedicated engine transaction; it never captures a
  title screen or turns a fresh New Game skeleton into progress.

The manager closes its known native widget chain before a load or live slot save.
Manual requests made through exports while a phase is unsafe return a structured
reason and leave runtime/storage untouched.

There is no public rebindable mod action or battle-command decoration hook. Manual
quicksave is therefore an overworld START-menu action. Default battle-start
autosaves provide the native player path into supported battle restoration; the
public export can also capture later decision points for cooperating mods.

## Autosave trigger support

`location_enter` defers `map.entered` until a stable Level A boundary.
`trainer_battle_start` and `wild_battle_start` defer `battle.started` until the
first Level B player-decision boundary; requests expire if the battle ends or
proves unsupported. `battle_end` waits for stable overworld return when enabled.
`before_warp` captures synchronously inside the public `player.warped` event,
which is emitted after destination resolution but before transition mutation.
It is discarded rather than deferred when capability inspection rejects that
exact source-map boundary.

## Matrix

| State | Result |
| --- | --- |
| Same game and playthrough, wrapper format 1, overworld kind | loadable |
| Same game and playthrough, supported battle safe point | loadable with exact gameplay RNG |
| Different Red/Blue/Yellow identity | rejected: `wrong_game` |
| Different playthrough | rejected: `wrong_playthrough` |
| Unknown future wrapper format | rejected: `unsupported_format` |
| Registered older wrapper format | migrated on a detached copy |
| Engine version differs | loadable with `engine_version_mismatch` warning |
| Format-1 snapshot without preview | loadable; legacy detail omits preview rows |
| Present malformed preview metadata | rejected as `corrupt_preview` before mutation |
| Missing/corrupt payload | retained and shown unavailable |
| Unsupported runtime kind | rejected: `unsupported_runtime_kind` |
| Title history with no selected existing playthrough | browsable only as a clean unavailable/empty state; no identity is minted |
| Title load on the development engine contract | validated selected-playthrough bootstrap; no recovery or normal SAVE is created |
| Title `CONTINUE LATEST` ON | newest valid quick/auto/slot capture competes with normal `savedAt`; normal save wins an exact tie |
| Title `CONTINUE LATEST` OFF | exact native normal-save CONTINUE behavior; title history remains explicitly loadable |
| Recovery checkpoint | never an automatic title-CONTINUE candidate |

Suspended script and arbitrary-frame support require separate future contracts.

## Other installed mods

Checkpoint restore rewinds `game.save`, including all loaded mods' `mod.save` /
`save.modData` and data-only mod metadata embedded in canonical Pokémon or game
records. It does not rewind another mod's independent `mod.storage`, global or
per-mod options, or arbitrary Lua runtime state. Cooperating mods may rebuild
progress-derived caches after the success-only restore lifecycle event.

The full ownership matrix, shiny-mod case study, and tested cooperation examples
are in [Cross-Mod Checkpoint Compatibility](cross-mod-compatibility.md).
