# Compatibility

## Required engine capability

Save States 0.1.0 requires **Gen1Recomp v0.1.79 or newer**. That official
release contains the additive Level A APIs merged by upstream PR
[`bryanthaboi/gen1recomp#952`](https://github.com/bryanthaboi/gen1recomp/pull/952)
plus the merged Level B battle/RNG extension in upstream PR
[`bryanthaboi/gen1recomp#986`](https://github.com/bryanthaboi/gen1recomp/pull/986).
The focused cross-mod audit proved the need for the success-only
`checkpoint.restored` lifecycle, now merged through upstream PR
[`bryanthaboi/gen1recomp#993`](https://github.com/bryanthaboi/gen1recomp/pull/993).
The same release contains title browsing/resume (#1076), semantic scripted battle
checkpoints (#1078), shared date/time formatting (#1080), and real battle-decision
settling (#1087).

Two conditional enhancements remain under review. PR #1077 adds START-menu entry
at an already-supported battle safe point; without it, battle-start autosaves and
battle-state loading still work but the manager cannot open from the command menu.
PR #1079 adds canonical Party icons to detached details; without it, the complete
captured party remains readable as text. Neither is required to decode or restore
snapshot format 1.

## Supported now

- Matching game version and opaque playthrough identity.
- Snapshot wrapper format 1 and engine checkpoint format 1.
- Settled overworld control with the overworld as the top screen.
- Settled ordinary wild/trainer player-decision menus with a reconstructable
  engine-owned continuation.
- Settled built-in scripted trainer/story battle decision menus when the engine
  can express the active script command and its continuation as validated,
  data-only semantic state.
- Exact semantic progress plus map, tile coordinates, facing, and surfing state.
- Reconstruction with engine validation, recapture comparison, rollback, and
  preservation of the current global options.
- Engine-version differences as a visible warning rather than an automatic hard
  rejection; game/playthrough/format mismatches remain hard failures.

## Rejected runtime phases

- Any menu or other screen above the overworld.
- Movement between tiles.
- Map transitions and partial field animations.
- Active, queued, or parallel scripts and scripted movement, except the narrow
  supported built-in battle-command suspension described above.
- Battle intro/messages/queues, HP tweens, animations, forced player actions,
  faint processing, link/Safari/ghost/demo variants, fishing/static origins,
  mod-defined completion closures, opaque script rows/callbacks, missing script
  NPC context, and scripted battles without a proven semantic continuation.
- Arbitrary title/new-game capture. The development title manager can only
  browse the engine-selected existing playthrough and resume a validated stored
  checkpoint through the dedicated engine transaction; it never captures a
  title screen or turns a fresh New Game skeleton into progress.

The manager closes its known native widget chain before a load or live slot save.
Manual requests made through exports while a phase is unsafe return a structured
reason and leave runtime/storage untouched.

There is no public rebindable mod action. When an engine release contains #1077,
the manager uses generic `battle.menu_auxiliary` to open from START only at
supported player-decision boundaries. Default battle-start autosaves remain
available without it.

## Autosave trigger support

`location_enter` defers `map.entered` until a stable Level A boundary.
`trainer_battle_start` and `wild_battle_start` defer `battle.started` until the
first Level B player-decision boundary; requests expire if the battle ends or
proves unsupported. A stale overworld request ahead of a battle request is removed
in the same pre-input tick, allowing the battle capture at the first safe command
menu. `battle_end` waits for stable overworld return when enabled.
`before_warp` captures synchronously inside the public `player.warped` event,
which is emitted after destination resolution but before transition mutation.
It is discarded rather than deferred when capability inspection rejects that
exact source-map boundary.

## Matrix

| State | Result |
| --- | --- |
| Same game and playthrough, wrapper format 1, overworld kind | loadable |
| Same game and playthrough, supported ordinary or semantic scripted battle safe point | loadable with exact gameplay RNG |
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
| First savestate before Pokémon SAVE | checkpoint/history commits first, then one verified ordinary progress anchor is created; later savestates never rewrite it |
| Title load on the development engine contract | validated selected-playthrough bootstrap; no recovery or normal SAVE rewrite is performed |
| Title `CONTINUE LATEST` ON | newest valid quick/auto/slot capture competes with normal `savedAt`; normal save wins an exact tie |
| Title `CONTINUE LATEST` OFF | exact native normal-save CONTINUE behavior; title history remains explicitly loadable |
| Recovery checkpoint | never an automatic title-CONTINUE candidate |

Arbitrary suspended scripts and arbitrary-frame support remain unsupported. The
scripted-battle contract records a stable script id/program counter plus a
one-use semantic battle result; it never serializes the Lua coroutine or stack.

## Other installed mods

Checkpoint restore rewinds `game.save`, including all loaded mods' `mod.save` /
`save.modData` and data-only mod metadata embedded in canonical Pokémon or game
records. It does not rewind another mod's independent `mod.storage`, global or
per-mod options, or arbitrary Lua runtime state. Cooperating mods may rebuild
progress-derived caches after the success-only restore lifecycle event.

The full ownership matrix, shiny-mod case study, and tested cooperation examples
are in [Cross-Mod Checkpoint Compatibility](cross-mod-compatibility.md).
