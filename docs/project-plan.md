# Save States Living Project Plan

Status: active execution; Level A, Level B, and cross-mod restore lifecycle
merged upstream; mobile preview/history/battle-autosave pass verified; required
title, battle-entry, scripted-battle, icon, and date/time contributions in review

Updated: 2026-08-11

Product owner: MaxTomahawk

Mod id: `savestates`

## Product outcome

Deliver a production-quality native Gen1Recomp mod that preserves vanilla SAVE
while adding rolling quicksaves, event-based autosaves, ten permanent slots,
one-level undo-load recovery, native menus, replace-in-place notifications,
settings, durable playthrough isolation, corruption handling, and deterministic
battle safe-point restoration. Unsupported runtime phases must be rejected with a
clear reason, never approximated or silently saved.

## Evidence baseline

The controlling upstream facts are in `docs/upstream-audit.md`, pinned to the
commits named there. Key conclusions:

- Native UI decoration, registered screens, options, semantic events, and HUD
  notifications are available publicly now.
- Current public UI lacked only two small presentation contracts needed by the
  approved mobile UX: canonical detached Party icons and shared local timestamp
  formatting. Focused review-ready PRs #1079 and #1080 now provide them without
  checkpoint/storage authority.
- `mod.save` cannot be the savestate store without coupling quicksaves to vanilla
  SAVE and recursively embedding the history; merged `mod.storage` is the
  independent playthrough-scoped public store selected for the product.
- Merged `mod.checkpoints` supplies exact settled-overworld capture and restore.
- Scripts are coroutine-driven. Arbitrary suspended scripts remain unsafe, but
  built-in scripted battle commands can be reconstructed from a narrow semantic
  command/result descriptor without serializing a coroutine.
- Merged Level B checkpoints supply supported battle reconstruction and exact
  gameplay RNG replay.
- Cross-mod progress ownership is now explicit: `game.save`/`mod.save` rewinds;
  independent `mod.storage`, options, and arbitrary runtime state do not.
- Rebindable custom mod actions do not exist; START-menu operation remains the
  complete baseline until that optional seam lands.

Upstream PR #986 is merged and implements the generic contract selected by the
Gate D audit: persistent ordinary wild/trainer decision-menu reconstruction plus
exact LÖVE RNG, while preserving explicit refusal for scripts and unsupported
variants. The focused cross-mod audit found and upstream merged the minimal
success-only post-restore invalidation event for cooperating mods with
progress-derived runtime caches through PR #993.

The approved design is recorded in
`docs/superpowers/specs/2026-08-07-native-savestates-design.md`. Completed focused
execution plans remain under `docs/superpowers/plans/` as durable design and test
history; current work is governed by this living plan and acceptance matrix.

## Corrected specification assumptions

- Upstream's current START menu ends in `QUIT`, not `EXIT`, and has conditional
  `LINK` and `MODS` rows. Decoration will anchor before `OPTION` and preserve all
  other mods and conditional rows.
- Current save format is 4. The mod's own snapshot format may start at 1 but must
  not be confused with `save.meta.format`.
- Current scaffold range is `>=0.0.0-dev <1.0.0`; the release manifest floor will
  target the first engine release containing required public seams.
- `render.compose` on the public logical 160x144 UI canvas is sufficient for
  native non-blocking notifications; Android scaling remains engine-owned.
- Location and battle lifecycle events already exist. They request autosaves but
  do not themselves prove a safe capture instant.
- Current modkit can scaffold externally. The proposed tree is a responsibility
  map, not a required filename map.
- Mod-index `repo` requires an HTTPS URL, while `github` uses `owner/repo`.
- Playthrough identity must be lazy. Creating, loading, or normally saving a game
  with no storage/checkpoint caller leaves progress bytes unchanged; the first
  public call allocates identity and persists only the legacy slot mapping until
  the next normal SAVE.
- The deterministic recursive save writer must run outside LuaJIT traces. A
  1,000-process GC stress run reproduced zero corruption after this boundary;
  compiled recursion intermittently emitted an invalid empty nested identity map.
- The public storage context now includes the current engine version. This makes
  the specified warning-grade engine compatibility status available while
  browsing histories, before recovery capture or live restore begins.
- Merged PR #959 makes current `modkit pack` honor `SOURCE_DATE_EPOCH`, including
  `.modkit/pack.json`, so repeat builds are byte-reproducible. This repository
  still rejects nonconforming metadata and compares two package builds.
- The indexed shiny mod stores both its behaviorally meaningful `mon.shiny`
  marker and Gen 2-compatible `mon.dvs` in canonical Pokémon records, not private
  durable storage. Those records already roundtrip in overworld and supported
  battle checkpoints. The general rule and fake-mod integration proof are
  documented in `docs/cross-mod-compatibility.md`; Save States has no per-mod
  adapter layer.

## Chosen architecture

### Repository split

- This repository owns the distributable mod, pure data model, storage adapter,
  services, screens, tests, docs, packaging, and releases.
- Any engine/API work lives in a separate `gen1recomp` fork worktree and focused
  branches. No private engine code is copied into the mod.

### State pipeline

All user-visible state classes use one pipeline:

`capability -> capture -> normalize -> validate -> encode -> verified store -> index`

Load uses:

`read -> decode -> migrate -> validate identity/capability -> capture recovery -> restore -> verify`

Snapshots are deterministic data-only records. Runtime controllers, functions,
userdata, coroutines, LÖVE objects, metatables, and static ROM-derived databases
are excluded. Persistent progress is copied without the savestates storage
namespace to prevent recursion. Runtime payloads are tagged by capability kind.

### Storage and identity

The implemented Level A design is an upstream-provided, namespaced per-mod store
scoped by an opaque active game-version/playthrough identity. It routes through
standard and portable persistence backends and supports verified replacement
without rewriting the vanilla progress checkpoint. Identity is allocated only on
first use. The mod owns its snapshot schema, index, retention, quarantine, and
recovery semantics on top of that primitive.

### Runtime support levels

- Level A: stable overworld only, reconstructed through a public semantic
  checkpoint API. This is the first functional gate.
- Level B: ordinary wild/trainer player-decision safe points through the merged
  semantic battle/RNG checkpoint contract.
- Level C: suspended scripts remain rejected unless upstream later introduces
  explicit data checkpoints.
- Arbitrary-frame state is not on the v1 critical path.

### UI and events

The mod decorates `ui.start_menu.items`, registers its manager screens, and draws
notifications through `render.compose` on the logical UI canvas. Semantic events enqueue autosave requests;
capture occurs only when the runtime capability facade confirms a stable point.
No timer-based autosave loop is used. No hardcoded hotkey is stolen.

## Milestones and gates

| Milestone | Outcome | Exit verification |
| --- | --- | --- |
| M0 — Project baseline | Governance, audit, living plan, remote, feature branch | pinned sources, clean diff review, planning commit pushed |
| M1 — Upstream Level A/tooling | Scoped storage, stable-overworld checkpoints, playthrough identity, reproducible packaging | MERGED: PR #952 and PR #959; focused suites, 1,000-run GC regression, and full ROM-free suite green; official release still required |
| M2 — Mod shell and pure core | Current modkit shell; injected adapters; snapshot schema/validation/index/retention/migrations | VERIFIED locally: pure behavior suite, real modkit load/lint, strict reproducible package and root listing |
| M3 — Level A prototype | Stable overworld capture/mutate/restore/re-capture | ENGINE CONTRACT VERIFIED: semantic differential recapture plus rejection/rollback tests; broader packaged fixture matrix remains before release |
| M4 — Quicksaves and recovery | Rolling quick history, newest quickload, transactional recovery, undo | VERIFIED in injected public-API service tests: A -> load B -> undo -> A; corruption and persistence failure paths covered |
| M5 — Native UX and slots | START rows, manager screens, ten permanent slots, rename/delete, HUD notifications, options | VERIFIED headlessly: second decorator coexistence, empty/unavailable states, generation-safe slot overwrite, disabled notifications, public widget close chain |
| M6 — Autosaves and robustness | Supported event triggers, cooldown/dedup, quarantine, compatibility, performance logging | IMPLEMENTED: location, ordinary trainer/wild start, optional after-battle deferral, synchronous capability-gated before-warp, stale-event expiry, dedup/retention, corrupt visibility, and opt-in phase timings; broader clean-runtime matrix remains |
| M7 — Battle beta | MERGED: field/RNG/continuation map plus persistent safe-point capture/restore | PR #986; wild/trainer differential reconstruction; damage/crit/accuracy/AI/escape/encounter RNG replay; rollback and unsupported-phase tests green |
| M8 — Cross-mod compatibility | Generic rewind ownership, real shiny case, cooperating/passive fake mods, lifecycle proof | MERGED: PR #993 as `ee891fb8`; 46/46 public cross-mod checks; `mod.save` rewinds, storage/options do not, shiny-style metadata roundtrips in overworld/battle |
| M9 — Rich preview metadata | Capture-time play time, badge, and party summaries in index metadata | VERIFIED locally: optional format-1 preview, strict validation, lazy index browsing, grouped date headings, read-only metric-safe details, engine-owned Party icons, and source-provenance pin/rename |
| M10 — Release readiness | Docs, clean package install, GitHub release, then index metadata PR | byte-identical source-date ZIP builds, clean install, validate/lint/tests, no private requires/ROM content, release asset resolves |

Milestones are sequencing boundaries, not permission to claim incomplete features.
If an upstream dependency blocks one lane, continue every independent pure-mod,
test, documentation, or packaging task that remains valid.

## Verification policy

- Every behavior change follows red -> observed expected failure -> minimal green ->
  focused suite -> relevant suite.
- No milestone advances on stale evidence. Record exact commands and outputs in the
  commit/PR or a repository evidence note when the result is not self-evident.
- Level A and Level B use normalized differential roundtrips, not field-presence
  assertions alone.
- Every load failure is injected before release: persistence, decode, validation,
  identity, map/content reference, recovery capture, restore, missing index/payload.
- Packaging is tested from a generated archive with files at the archive root.
- The final release is tested in a clean Gen1Recomp install, not only from source.

## Current blockers and decisions

| Item | State | Decision / next evidence |
| --- | --- | --- |
| `SAVESTATES-SP-01` scoped storage | MERGED | upstream PR #952 at `cd0ace2`; 28/28 public API checks and full ROM-free suite green |
| `SAVESTATES-SP-02` Level A checkpoint | MERGED | upstream PR #952; 34/34 public API checks and differential rollback/content-rejection proof green; checkpoint identity exposes engine version for warning-grade compatibility |
| `SAVESTATES-SP-03` playthrough identity | MERGED | upstream PR #952; 18/18 focused checks and 1,000 clean-process stress runs green |
| `SAVESTATES-SP-04` custom actions | CANDIDATE, non-blocking | START menu remains fully functional; propose only after Level A |
| `SAVESTATES-SP-05` battle/RNG | MERGED | `docs/battle-state-map.md`; upstream PR #986 at `983bea6`; persistent ordinary wild/trainer safe points, semantic continuations, exact RNG, Level A compatibility |
| `SAVESTATES-SP-06` reproducible modkit package | MERGED | upstream PR #959 at `5b6dfed`; `SOURCE_DATE_EPOCH`, invalid-input refusal, and byte-identity tests |
| `SAVESTATES-SP-07` cross-mod restore lifecycle | MERGED | PR #993 as `ee891fb8`; success-only `checkpoint.restored`, 46/46 public fake-mod/shiny-style checks, no storage/options rewind, no event on failure/rollback |
| `SAVESTATES-SP-08` rich previews | VERIFIED MOD-SIDE | Public `checkpoint.save`, public content registries, and index metadata are sufficient; no upstream seam proposed |
| Generic complete-playthrough transfer | NON-BLOCKING FUTURE WORK | Fresh review found no competing PR; issue #949 is raw `.sav`, #977 is Android sync permissions; not part of Save States 0.1.0 |
| HUD notifications | VERIFIED capability | implemented in mod via `render.compose` logical UI pass; no upstream request |
| Core event triggers | VERIFIED PRODUCT SUPPORT | `map.entered`, ordinary trainer/wild `battle.started`, and optional `battle.ended` defer to matching safe kinds; enabled `player.warped` captures immediately before transition and never defers into the destination |
| `SAVESTATES-SP-11` detached Party icon presentation | REVIEW-READY | PR #1079 (`ccb5358`), public `mod.ui.PokemonIcon`, 149/149 engine + 10/10 modkit suites and green CI |
| `SAVESTATES-SP-12` shared date/time presentation | REVIEW-READY | PR #1080 (`2c8c800`), global device/DMY/MDY/YMD + 12/24h options and read-only `mod.datetime`; 150/150 engine + 10/10 modkit suites and green CI |

## Current execution boundary

The active product goal authorizes autonomous implementation. Official upstream
`dev` is pinned at `79ed37699ebb9dd5de5e839d23bd12b2719e4cca`; index `main` is
pinned at `6f7eb4ad249bb6ca3080ce485be6a8053861a624`. Level A
storage/overworld checkpoints, Level B battle/RNG checkpoints, and reproducible
modkit packages are merged through PRs #952, #986, and #959. The distributable mod
composes its Level A services entirely through `mod:read`, `mod.storage`,
`mod.checkpoints`, registered screens, hooks, events, options, and HUD drawing.

Gate D and its merged Level B implementation are recorded in
`docs/battle-state-map.md`. The focused cross-mod audit is complete in
`docs/cross-mod-compatibility.md`; its minimal lifecycle seam is branch
`feat/checkpoint-restore-event` at `aa3b2a1`, merged as `ee891fb8` through PR #993.
The mod test workflow now uses the merged public contract. The remaining
external product gate is review, merge, and official release of the complete
checkpoint contract; the release workflow stays fail-closed against that exact
future tag.

### Historical title/resume investigation — 2026-08-10

Historical freshness note: the then-current official `dev` was
`943ba5dcbfa62cf831e881684857ffd4867fe774`; candidate PR #993 remained open,
non-draft, and pinned at
`aa3b2a18ec06d844f42be873278c5232628376fa`. The only overlapping public UI PR
found, #1023, exposes battle render-visibility predicates only; it does not
provide a safe battle auxiliary action or command-boundary input hook. The
separate lifecycle PR #1037 does not provide title/playthrough resolution or
checkpoint bootstrapping.

The title hook `ui.title_menu.items` is public and sufficient to add a native
`SAVE STATES` row. It is intentionally insufficient to browse or load history:
`mod.storage` binds only to the active `game.save`, and its first call can
allocate an identity. At title, `Game:load` creates a fresh save skeleton;
`SaveData.ensurePlaythroughId` deliberately treats that object as fresh and
must not reuse the selected slot's former identity. In addition,
`mod.checkpoints:restore` deliberately requires a live supported overworld or
battle runtime and rejects title as `not_overworld`. Therefore a title manager
implemented only in mod code would either mint/select the wrong identity or
need private persistence/checkpoint internals. It is not an acceptable route.

Next ordered work is:

1. Add a minimal public-facing engine regression that reproduces a registered
   New Game playthrough with durable tool storage/checkpoint data but no normal
   Pokémon save, then proves that title has no non-mutating way to resolve and
   resume it today.
2. From that proof, design and test the narrowest generic selected-playthrough
   title context plus validated checkpoint bootstrap transaction. It must keep
   explicit New Game fresh, preserve current options, reject corrupt data before
   live mutation, and leave a usable title state on failure. This is an engine
   responsibility; the mod will own title rows, history browsing, and the
   `CONTINUE LATEST` policy only after the generic public mechanism exists.
3. Independently improve the mod's logical-viewport UI: compact/paged preview
   details, a capture-time/relative-time display choice only if it improves
   browsing, and a HUD banner geometry that avoids touch-control overlap using
   the public logical viewport. The first mobile usability slice is complete:
   actions now remain at the top of compact state/slot menus, rich information
   is in a paged read-only `STATE DETAILS` view, and `render.compose` uses the full logical
   top banner rather than bottom physical-pixel guesses. 803 Lua checks plus
   package/clean-install gates are green; physical Android presentation remains
   a manual acceptance test. These improvements do not wait for title bootstrap.
4. Re-audit battle entry only after the title primitive is proven. If no public
   command-boundary auxiliary action exists then, open a separate focused
   generic engine seam; #1023 is not that seam.

The first title-resume implementation is now on the separate engine branch
`feat/mod-title-checkpoint-resume` (subsequently independently rebased on
current `dev`). It
adds only a non-allocating selected-playthrough storage facade and a separate,
validated title checkpoint bootstrap transaction. Its 29-check public mod SDK
test covers a no-normal-SAVE restart, successful event emission, post-install
failure recovery to title, option preservation, and explicit-New-Game identity
separation; the full public quick suite is 139/139 engine and 9/9 modkit suites.
It is pushed to the MaxTomahawk fork but deliberately not yet submitted while
the mod title-manager integration and broader failure matrix are completed. The
mod routes title screens through the selected facade, never shows recovery as a
title target, and exposes only durable pin/rename/delete operations alongside
validated loads. `CONTINUE LATEST` is now mod-side policy with default ON: it
compares only the selected facade's normal-save timestamp with original valid
quick/auto/slot capture times, rejects implausibly future metadata, skips corrupt
or incompatible records and gives native normal SAVE exact-time ties. A first
successfully committed checkpoint now requests one engine-validated ordinary
progress anchor only when the playthrough has never had a Pokémon SAVE; later
savestates do not rewrite it.

### Current integration branches — 2026-08-11

- Save States `feat/initial-savestates` carries the verified mobile UX commits
  `5fae204` and `46eb95e` plus synchronized product documentation on top of
  published `a8df5c4`; it adds default-ON
  `CONTINUE LATEST`, battle-manager entry through the proposed generic safe
  decision-boundary action, optional public Modern UI notification presentation
  with a native fallback, and captured play-time/date/age history presentation
  with metric-safe two-row details. The current pass adds non-selectable grouped
  date headings, whole-Pokémon Party-style icon rows, centered top notices,
  50/50 defaults (choices through 100), and same-tick stale-request removal at
  the first safe battle boundary.
- Generic title resume is independently rebased on `dev` at `4db9716`
  (`feat/mod-title-checkpoint-resume`): 149/149 engine and 10/10 modkit suites
  passed; Tier 3 was skipped because no legal generated data is present. Its
  title resume publishes the merged #993 lifecycle only after final verification.
- Generic battle auxiliary action is independently based on `dev` at
  `59725c0` (`feat/battle-menu-auxiliary`): 150/150 engine and 9/9 modkit
  suites passed; Tier 3 was skipped for the same reason.
- Generic scripted-battle checkpointing is independently based on `dev` at
  `882763c` (`feat/scripted-battle-checkpoints`): 20/20 focused checks and the
  150/150 engine plus 9/9 modkit quick stack pass without serializing coroutine
  state or changing checkpoint format 1.
- Canonical detached Party icon presentation is independently based on `dev` at
  `ccb5358` ([#1079](https://github.com/bryanthaboi/gen1recomp/pull/1079));
  149/149 engine and 10/10 modkit suites plus all GitHub checks pass.
- Shared device/fallback date-time presentation is independently based on `dev`
  at `2c8c800` ([#1080](https://github.com/bryanthaboi/gen1recomp/pull/1080));
  150/150 engine and 10/10 modkit suites plus all GitHub checks pass. DEVICE uses
  the process locale where present and safely falls back to DMY/24-hour elsewhere.
- Fresh audit pins `dev` at `79ed376`; #993 is merged as `ee891fb8` (PR head
  `aa3b2a1`). #1023 provides
  battle render visibility only, not a command-boundary input seam.
- All three required engine branches are pushed and published upstream through
  the authenticated GitHub CLI path recovered from the prior execution history:
  title resume [#1076](https://github.com/bryanthaboi/gen1recomp/pull/1076),
  battle auxiliary [#1077](https://github.com/bryanthaboi/gen1recomp/pull/1077),
  and scripted battles [#1078](https://github.com/bryanthaboi/gen1recomp/pull/1078).
  All are open, non-draft, mergeable/clean, and pass 15/15 GitHub checks.
- Gen1 Modern UI was freshly cloned at `847e7b9` (0.8.4). Its public v1
  screen-adapter contract covers standard ListMenu/OptionsMenu screens, but it
  has no public data-only transient notification surface. Modern notifications
  need a focused Modern UI extension, never private theme access or an engine patch.

### Modern UI transient compatibility — 2026-08-11

- The required public presentation seam is implemented in the isolated Gen1
  Modern UI branch `feat/source-transient-notifications` at `9aebcb8`.
  It extends the existing v1 adapter contract with an optional data-only
  `transient.model`, a bounded deterministic presenter, and the public
  `isTransientPresentationActive(owner)` fallback signal. It introduces no
  engine dependency and exposes no source draw callback, checkpoint payload,
  writable storage, or private theme state.
- Save States now publishes/explicitly registers that optional adapter, declares
  `gen1_modern_ui` as an optional ordering dependency, and draws its native
  banner only when Modern UI does not publicly claim presentation. The current
  QOL location banner remains independently composed: native Save States stays
  at the logical top, Modern UI source transients use its touch-safe top panel,
  and Modern UI's QOL location card stays at the lower safe region.
- Focused evidence: Modern UI `compose_suppression` LÖVE smoke test passes;
  syntax plus modkit validate/lint pass. Save States notification model,
  adapter fallback, composition registration, and all repository behavior tests
  pass against the local combined engine stack. The generic extension is
  published as [Gen1 Modern UI PR #13](https://github.com/ArmstrongThomas/gen1-modern-ui/pull/13),
  open, non-draft, and mergeable/clean.

### Current coherent development integration — 2026-08-11

- The current integration worktree is `integration/savestates-ui` at `a492da1`
  over current `dev` `79ed376`,
  with merged #993 `ee891fb8`, title resume `4db9716`, battle auxiliary action
  `59725c0`, semantic scripted-battle checkpoints `882763c`, Party icons
  `ccb5358`, and date/time `2c8c800`. Title
  `Checkpoint.resume` emits
  `checkpoint.restored` exactly once only after final verified installation,
  directly in the title-resume contribution because the lifecycle contract is
  part of its merged base; no integration-only lifecycle patch remains.
- Fresh evidence against that exact stack: `./scripts/test.sh --quick` passes
  152/152 engine and 12/12 modkit suites (including 46/46 cross-mod, 40/40 title
  context, the real two-process cold-restart check, 10/10 battle-menu, and 20/20
  scripted-battle checks, 14/14 Party-icon, and 8/8 public date-time checks);
  Tier 3 is correctly skipped without imported/generated data. `make check` at
  the current Save States working tree passes 1020/1020 Lua
  behavior checks, 7/7 Python checks, modkit validate/lint, byte-identical 34-file
  ZIP builds plus pack metadata, and clean extracted-install validation.
- Serialized wrapper measurements are 2.56 KiB early and 232–235 KiB for an
  intentionally full late-game overworld/battle fixture; 100 such heavy states
  total about 23 MiB logical before physical recovery witnesses.
- The parallel Android development build uses package
  `com.theboisclub.pokemonred.savestates.test`, versionCode `20260812`, and the
  same debug certificate as the previous parallel test versionCode `20260811`.
  Its game payload intentionally retains engine `0.0.0-dev`, while Android owns
  the independent app version. This both preserves in-place test updates and
  satisfies unmodified Gen1 Modern UI's documented development-version range.
  The APK, Save States package, and patched Modern UI package pass their ROM-free
  build/archive gates; physical Android and ROM-backed behavior remain manual.

Verification for this pass is new evidence, not inherited counts: focused
title/playthrough/bootstrap and battle-entry tests, affected mod behavior tests,
the full public engine quick suite, the complete mod gate, and a rebuilt Android
bundle after these features formed one coherent stack. Physical Android geometry
and ROM-backed behavior remain explicit manual acceptance gates.

Latest verification (2026-08-08):

- Mod `make check GEN1RECOMP=/home/max/src/gen1recomp-savestates-crossmod` at
  preview handoff `cfb164e` — 803/803 Lua checks, 7/7 Python checks, modkit
  validate/lint, byte-identical source-date package builds, and clean
  extracted-install validation. The archive has 30 distributable files plus
  `.modkit/pack.json`; SHA-256 is
  `458c2a1ee867a776b92a0b7dd44ef5365a4ad0d517d186cc9e73212a38c18c8b`.
  GitHub Actions runs `31295564952` and `31295563244` passed that exact head.
  The initial package gate correctly caught an accidentally included new test;
  `.modkitignore` now explicitly excludes it.

- Official `dev` baseline `./scripts/test.sh --quick` — 139/139 engine and 7/7
  modkit suites before the cross-mod patch.
- Cross-mod public SDK suite — expected red 33/42 before the lifecycle event,
  then 46/46 after the minimal change. Existing public checkpoint suite remains
  53/53 and meta coverage remains 178/178.
- `./scripts/test.sh --quick` at upstream branch `aa3b2a1` — 139/139 engine and
  8/8 modkit suites; ROM-derived T3 correctly skipped without imported data.
- Mod `make check GEN1RECOMP=/home/max/src/gen1recomp-savestates-crossmod` at
  cross-mod audit head `6b76cbd5127c28d2a987783b6c7544400de1602c` — 755/755
  Lua checks, 7/7 Python checks, modkit validate/lint, two byte-identical package
  builds, and clean extracted-install validation. The package has 29
  distributable files plus `.modkit/pack.json` and SHA-256
  `f4a02c1c59ec248fab5d28121510753c6f2c573f857dcb5b0a5ce76b11a15458`.
  GitHub Actions run `31255626794` passes the same exact head.

- `luajit tests/engine/playthrough_identity.lua` — 18/18.
- identity test in 1,000 fresh LuaJIT processes — 1,000/1,000.
- `luajit tests/modkit/cases/storage.lua` — 28/28.
- `luajit tests/modkit/cases/checkpoints.lua` — 34/34, including invalid-content rejection before mutation.
- `luajit tests/engine/save_slots.lua` — 78/78.
- `luajit tests/mod_save_tests.lua` — 132/132.
- Historical pre-merge Level B `./scripts/test.sh --quick` — 137/137 engine suites
  and 7/7 modkit suites;
  ROM-derived T3 correctly skipped because no imported data is present.
- Mod `make check GEN1RECOMP=/home/max/src/gen1recomp-savestates-engine` —
  616/616 Lua behavior checks across composition, modules, snapshots, migrations,
  index/retention, quick/auto/slot/recovery services, native screens, notifications,
  event deferral, fingerprints/deduplication, and transaction failure recovery;
  modkit validate/lint and reproducible 49-file package root verification pass.
- Level B focused suites — battle boundary 13/13, capture 29/29, continuation 17/17,
  restore/determinism/failure rollback 43/43, public checkpoints 53/53 including
  real public-facade battle differential roundtrip, switched/fainted-party
  fidelity, and complete overworld-progress fidelity.
- Mod `make check GEN1RECOMP=/home/max/src/gen1recomp-savestates-battle` —
  755/755 Lua behavior checks plus 7/7 Python release/package-gate tests; modkit
  validate/lint and reproducible 28-file
  package root verification plus a clean extracted-install pass with battle
  support enabled. This includes semantic autosave fingerprinting, fitted native
  notifications, live manager counts, default-NO destructive-action confirmation,
  structured diagnostics, pre-load engine-version warnings, and exact-minimum
  release-engine selection. Permanent-slot rename preserves the original
  checkpoint time/context; pinning preserves source capture provenance; and every
  occupied-slot replacement defaults to NO. Native slot naming accepts the
  documented 12-character `BEFORE MISTY` label without leaving the canvas.
- The same `make check` passed from a fresh clone of published product head
  `8358ae7661830bb04d3bc9e896d30df66435f79d`; two consecutive package
  builds were byte-identical. The archive SHA-256 was
  `4d95869e1583059e1fdf14438323dcbf70c43b8dcee7745dec119a3f57410a15`,
  the resulting archive contains 28 distributable files plus
  `.modkit/pack.json`, and a clean extracted install validates and lints.
- GitHub Actions `Test` runs `31247517995` and `31247519521` completed
  successfully at exact repository head `8358ae7661830bb04d3bc9e896d30df66435f79d`.
  All checkout steps use the current Node-24 `actions/checkout@v6`, eliminating
  the runner's Node-20 deprecation warning. The preview release gate was exercised
  directly and
  correctly refused publication because `experimental` remains `true`.
- A source-boundary audit found no private `src.*` require, raw filesystem,
  state-stack, process, package, or debug dependency in distributable Lua. The
  only require is LuaJIT's standard `bit` module; sibling source loads use the
  public `mod:read` facade and were exercised by the real modkit loader.
- Mod-index metadata is staged but intentionally unpushed on
  `prep/savestates-index` at `37321c5`; targeted validation passes with zero
  warnings. Current index `main` is `6f7eb4a`; the staging branch must be rebased
  and refreshed from the final release manifest, then submitted only after an
  installable release exists.
- The newest official engine tag remains `v0.1.75`, which predates the merged
  checkpoint APIs. Preview metadata and publication therefore remain fail-closed.
