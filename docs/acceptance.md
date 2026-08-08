# Product Acceptance Matrix

Status vocabulary:

- **Verified** — current repository/branch evidence directly exercises the behavior.
- **Prepared** — implementation is complete, but an external release/runtime gate
  prevents final player validation.
- **Blocked externally** — cannot truthfully complete until upstream publishes the
  required public API or an installable release exists.

| Player outcome / invariant | State | Current evidence / remaining proof |
| --- | --- | --- |
| Vanilla `SAVE` remains unchanged | Verified | Public START hook decorates after `next`; coexistence test retains `SAVE`, other-mod rows, `OPTION`, and `QUIT`. |
| `QUICKSAVE` and `STATES` appear natively | Verified | `tests/start_menu_test.lua`; real modkit loader validation. |
| Rolling manual quicksaves and configured retention | Verified | Service, retention, index, and transaction failure tests. |
| Newest valid quickload; corrupt newest falls back safely | Verified | Service tests cover empty, valid, corrupt-newest, all-invalid, and identity cases. |
| Browse/load/pin/delete quick and auto histories | Verified | Native screen tests including empty and unavailable rows, detail status, confirmation, and count refresh. |
| Event-based location/trainer/wild autosaves | Verified | Public event composition plus runtime-kind deferral/stale-request tests; no timer autosave. |
| Optional after-battle and synchronous before-warp saves | Verified | Controller/service tests; `player.warped` timing is documented from the public emit site. |
| Cooldown, semantic duplicate replacement, retention | Verified | Fingerprint/deduplicator/service tests; presentation-only counters are excluded. |
| Ten permanent slots with load/overwrite/rename/delete | Verified | Service/UI tests; generation-safe overwrite, failed-publication preservation, 12-character native labels, metadata-only rename, source-provenance-preserving pin, and default-NO confirmation for direct or pin-driven replacement. |
| Durable one-level recovery and undo-load | Verified | A -> load B -> undo -> A tests; recovery is written/re-read before restore and not overwritten by undo. |
| Native non-modal replace-in-place notifications | Verified | HUD model/draw tests cover toggles, replacement, expiry, fitting/wrapping, failures, and compatibility warnings. |
| Configurable histories, autosave triggers, notifications | Verified | Public option schema and settings-summary tests cover all product options. |
| Persistence across restarts | Verified at API/storage layer | Public storage fresh-decode, main/tmp/backup recovery, and process-independent checkpoint reconstruction tests. Final packaged runtime restart is part of the private release acceptance pass. |
| Game/playthrough isolation | Verified | Hard wrapper/checkpoint validation plus upstream active-slot/new-game/playthrough storage tests. |
| Corrupt and incompatible records never mutate runtime | Verified | Data-only/schema/migration/store tests; unavailable-row cleanup; upstream content/map/position validation and rollback tests. |
| Settled overworld restoration | Verified and merged upstream | Public facade differential recapture includes coordinates/facing, party, inventory/PC items/boxes, money, Pokédex, flags, trainers, and object toggles; upstream PR #952 is merged. |
| Deterministic supported battle restoration | Verified and merged upstream | Ordinary wild/trainer player-decision reconstruction, switched/fainted party fidelity, rollback, and exact damage/crit/accuracy/AI/escape/encounter RNG replay; PR #986 is merged. |
| Cross-mod canonical progress remains consistent | Verified on upstream branch | Real shiny implementation audit plus public fake/cooperating mods: core progress, `mod.save`, and shiny-style Pokémon metadata rewind in overworld/battle; independent storage/options do not; subscriber cache rebuilds after verified restore. |
| Unsafe scripts/transitions/menus/animations/battle phases rejected | Verified | Public checkpoint capability and exclusion tests; compatibility docs name every supported boundary. |
| Manual battle quicksave UX | Accurately limited | No public custom action or battle-menu decorator exists. Default battle-start autosaves are user-accessible; cooperating mods may call the public export at later safe decisions. |
| No private engine dependency in distributed mod | Verified | Source boundary inspection found no private `src.*` require, raw filesystem, state-stack, process, package, or debug access; sibling source loads use public `mod:read`, and real modkit load/lint passes. |
| ROM-free CI, tests, lint, reproducible package | Verified | 755/755 Lua checks, 7/7 Python release/package-gate tests, modkit validate/lint, two byte-identical 28-file ZIP builds plus pack manifest, and fresh-clone/fresh-extracted-install checks at package head `8358ae7`; archive SHA-256 `4d95869e1583059e1fdf14438323dcbf70c43b8dcee7745dec119a3f57410a15`; Actions runs `31247517995` and `31247519521` pass that exact head. |
| Exact released-engine compatibility | Prepared | Release gate derives/checks out the manifest's exact minimum official tag. Manifest intentionally remains experimental/dev until upstream APIs ship. |
| Clean ROM-backed player acceptance | Blocked externally/private-data gate | No ROM/generated data is committed or available here. Run the documented private imported-base/runtime matrix before public stable release. |
| Installable GitHub Release | Blocked externally | Tag workflow intentionally refuses preview metadata; requires official upstream API release and final manifest range. |
| Mod-index listing | Prepared, submission blocked | Local staging branch `prep/savestates-index` at `37321c5` passes targeted validation with zero warnings and remains intentionally unpushed; policy requires an installable GitHub Release first. |

## External release gates

1. Official acceptance of cross-mod lifecycle PR #993 and an engine release that
   contains the complete checkpoint contract. Level A, Level B, and the
   source-date modkit fix are already merged into `dev`.
2. Private clean-runtime acceptance using legally imported game data.
3. Final non-experimental manifest/version range, reviewed merge, tag, release
   asset verification, then index PR.

These gates do not reduce the product scope. Every independent distributable-mod,
test, documentation, and packaging component remains active work until this matrix
shows no locally resolvable gap.
