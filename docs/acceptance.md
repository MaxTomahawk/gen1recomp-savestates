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
| Rolling manual quicksaves and configured retention | Verified | Service, retention, index, and transaction failure tests; defaults are 50 Quick + 50 Auto with choices through 100. Worst-case fixture measurement is about 23 MiB logical for 100 fully populated late-game records. |
| Newest valid quickload; corrupt newest falls back safely | Verified | Service tests cover empty, valid, corrupt-newest, all-invalid, and identity cases. |
| Browse/load/pin/delete quick and auto histories | Verified | Native screen tests keep load/pin/delete immediately reachable; a separately paged detail screen covers preview/status, empty/unavailable rows, confirmation, and count refresh. |
| Rich capture-time state previews | Verified | Strict data-only preview tests cover time, badges, 0–6 party members, nickname/species fallback, HP/fainted state, no status, battle/overworld capture, legacy absence, malformed metadata, source-provenance pin/rename, lazy index browsing, default play-time history plus date/age modes, non-selectable date headings, absolute creation time, metric-safe detail rows, two-row whole-Pokémon selection, and public Party-icon delegation. |
| Event-based location/trainer/wild autosaves | Verified | Public event composition plus runtime-kind deferral/stale-request tests; the composed mod writes independent trainer and wild records on the first safe battle input boundary even with stale location work ahead; no timer autosave. Scripted continuation safety remains engine-tested separately. |
| Optional after-battle and synchronous before-warp saves | Verified | Controller/service tests; `player.warped` timing is documented from the public emit site. |
| Cooldown, semantic duplicate replacement, retention | Verified | Fingerprint/deduplicator/service tests; presentation-only counters are excluded. |
| Ten permanent slots with load/overwrite/rename/delete | Verified | Service/UI tests; generation-safe overwrite, failed-publication preservation, 12-character native labels, metadata-only rename, source-provenance-preserving pin, and default-NO confirmation for direct or pin-driven replacement. |
| Durable one-level recovery and undo-load | Verified | A -> load B -> undo -> A tests; recovery is written/re-read before restore and not overwritten by undo. |
| Native non-modal replace-in-place notifications | Verified headlessly | HUD model/draw tests cover toggles, replacement, expiry, fitting/wrapping, failures, compatibility warnings, and screen-space placement one logical tile below the physical viewport top. Physical portrait/landscape/touch-control presentation remains manual acceptance. |
| Configurable histories, autosave triggers, notifications | Verified | Public option schema and metric-fit settings-summary tests cover all product options. Date/time format is a global engine preference, not rewound mod state. |
| Persistence across restarts | Verified at API/storage layer | Public storage fresh-decode, main/tmp/backup recovery, and process-independent checkpoint reconstruction tests. Final packaged runtime restart is part of the private release acceptance pass. |
| Game/playthrough isolation | Verified | Hard wrapper/checkpoint validation plus upstream active-slot/new-game/playthrough storage tests. |
| Corrupt and incompatible records never mutate runtime | Verified | Data-only/schema/migration/store tests; unavailable-row cleanup; upstream content/map/position validation and rollback tests. |
| Settled overworld restoration | Verified and merged upstream | Public facade differential recapture includes coordinates/facing, party, inventory/PC items/boxes, money, Pokédex, flags, trainers, and object toggles; upstream PR #952 is merged. |
| Deterministic supported battle restoration | Verified and merged upstream | Ordinary wild/trainer player-decision reconstruction, switched/fainted party fidelity, rollback, and exact damage/crit/accuracy/AI/escape/encounter RNG replay; PR #986 is merged. |
| Cross-mod canonical progress remains consistent | Verified on merged upstream `dev` | Real shiny implementation audit plus public fake/cooperating mods: core progress, `mod.save`, and shiny-style Pokémon metadata rewind in overworld/battle; independent storage/options do not; subscriber cache rebuilds after verified restore. |
| Safe scripted trainer/story battle checkpoints | Prepared on review branch | Built-in battle commands reconstruct from a validated data-only `script_battle` descriptor; 20/20 focused checks and combined-stack tests pass without coroutine serialization. Opaque/unsafe scripts remain rejected. |
| Unsafe scripts/transitions/menus/animations/battle phases rejected | Verified | Public checkpoint capability and exclusion tests; compatibility docs name every supported boundary and the narrow semantic scripted-battle exception. |
| Manual battle quicksave UX | Prepared on review branches | Generic `battle.menu_auxiliary` provides START entry only at proven decision boundaries. PR #1087 fixes the real completed-intro settling defect without relaxing safety; focused real wild/trainer/scripted integration and 152/152 ROM-free engine suites pass. Official release remains gated on merge/release. |
| No private engine dependency in distributed mod | Verified | Source boundary inspection found no private `src.*` require, raw filesystem, state-stack, process, package, or debug access; sibling source loads use public `mod:read`, and real modkit load/lint passes. |
| ROM-free CI, tests, lint, reproducible package | Verified | Fresh combined integration proves 152/152 engine and 12/12 modkit suites. Save States proves 1029/1029 Lua checks, 7/7 Python checks, validate/lint, byte-identical 35-file ZIP builds plus pack manifest, and clean extracted-install validation. |
| Exact released-engine compatibility | Prepared | Release gate derives/checks out the manifest's exact minimum official tag. Manifest intentionally remains experimental/dev until upstream APIs ship. |
| Clean ROM-backed player acceptance | Blocked externally/private-data gate | No ROM/generated data is committed or available here. Run the documented private imported-base/runtime matrix before public stable release. |
| Installable GitHub Release | Blocked externally | Tag workflow intentionally refuses preview metadata; requires official upstream API release and final manifest range. |
| Mod-index listing | Prepared, submission blocked | Local staging branch `prep/savestates-index` at `37321c5` passes targeted validation with zero warnings and remains intentionally unpushed; policy requires an installable GitHub Release first. |

## External release gates

1. Merge and official release of the title-resume, battle auxiliary,
   scripted-battle, detached-icon, shared-date/time, and real-battle-settling
   contracts.
   The cross-mod lifecycle (#993), Level A, Level B, and source-date modkit fix
   are already merged into `dev`.
2. Private clean-runtime acceptance using legally imported game data.
3. Final non-experimental manifest/version range, reviewed merge, tag, release
   asset verification, then index PR.

These gates do not reduce the product scope. Every independent distributable-mod,
test, documentation, and packaging component remains active work until this matrix
shows no locally resolvable gap.
