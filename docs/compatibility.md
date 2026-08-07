# Compatibility

## Required engine capability

The development package currently targets the additive public APIs in upstream
PR [`bryanthaboi/gen1recomp#952`](https://github.com/bryanthaboi/gen1recomp/pull/952).
It is not a supported player release until those contracts are merged into a
released engine and `manifest.json` can name that release as its minimum.

## Supported now

- Matching game version and opaque playthrough identity.
- Snapshot wrapper format 1 and engine overworld checkpoint format 1.
- Settled overworld control with the overworld as the top screen.
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
- Battles, until a separate battle checkpoint contract is implemented and proven.
- Title/new-game states without an identified active playthrough.

The manager closes its known native widget chain before a load or live slot save.
Manual requests made through exports while a phase is unsafe return a structured
reason and leave runtime/storage untouched.

## Autosave trigger support

`location_enter` is implemented by deferring `map.entered` until a stable Level A
boundary. `battle_end` is implemented when its option is enabled and likewise
waits for stable overworld return. Trainer/wild battle-start and before-warp
settings are not subscribed yet: capturing them after the fact would silently
misrepresent the requested semantic point.

## Matrix

| State | Result |
| --- | --- |
| Same game and playthrough, wrapper format 1, overworld kind | loadable |
| Different Red/Blue/Yellow identity | rejected: `wrong_game` |
| Different playthrough | rejected: `wrong_playthrough` |
| Unknown future wrapper format | rejected: `unsupported_format` |
| Registered older wrapper format | migrated on a detached copy |
| Engine version differs | loadable with `engine_version_mismatch` warning |
| Missing/corrupt payload | retained and shown unavailable |
| Unsupported runtime kind | rejected: `unsupported_runtime_kind` |

Battle and script support will be added only by extending this matrix with
differential and deterministic replay evidence.
