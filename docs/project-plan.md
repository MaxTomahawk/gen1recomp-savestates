# Save States Living Project Plan

Status: active execution; Level A and Level B merged upstream; cross-mod restore
lifecycle submitted

Updated: 2026-08-08

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
- `mod.save` cannot be the savestate store without coupling quicksaves to vanilla
  SAVE and recursively embedding the history; merged `mod.storage` is the
  independent playthrough-scoped public store selected for the product.
- Merged `mod.checkpoints` supplies exact settled-overworld capture and restore.
- Scripts are coroutine-driven; suspended scripts are unsafe.
- Merged Level B checkpoints supply supported battle reconstruction and exact
  gameplay RNG replay.
- Cross-mod progress ownership is now explicit: `game.save`/`mod.save` rewinds;
  independent `mod.storage`, options, and arbitrary runtime state do not.
- Rebindable custom mod actions do not exist; START-menu operation remains the
  complete baseline until that optional seam lands.

Upstream PR #986 is merged and implements the generic contract selected by the
Gate D audit: persistent ordinary wild/trainer decision-menu reconstruction plus
exact LÖVE RNG, while preserving explicit refusal for scripts and unsupported
variants. The focused cross-mod audit found one remaining public lifecycle gap;
draft PR #993 adds only a success-only post-restore invalidation event for
cooperating mods with progress-derived runtime caches.

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
- `render.hud` is sufficient for non-blocking notifications; no toast engine patch
  is planned.
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
notifications through `render.hud`. Semantic events enqueue autosave requests;
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
| M8 — Cross-mod compatibility | Generic rewind ownership, real shiny case, cooperating/passive fake mods, lifecycle proof | PR #993 draft; 46/46 public cross-mod checks; `mod.save` rewinds, storage/options do not, shiny-style metadata roundtrips in overworld/battle |
| M9 — Release readiness | Docs, clean package install, GitHub release, then index metadata PR | byte-identical source-date ZIP builds, clean install, validate/lint/tests, no private requires/ROM content, release asset resolves |

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
| `SAVESTATES-SP-07` cross-mod restore lifecycle | VERIFIED and submitted | draft PR #993 at `aa3b2a1`; success-only `checkpoint.restored`, 46/46 public fake-mod/shiny-style checks, no storage/options rewind, no event on failure/rollback |
| HUD notifications | VERIFIED capability | implement in mod via `render.hud`; no upstream request |
| Core event triggers | VERIFIED PRODUCT SUPPORT | `map.entered`, ordinary trainer/wild `battle.started`, and optional `battle.ended` defer to matching safe kinds; enabled `player.warped` captures immediately before transition and never defers into the destination |

## Current execution boundary

The active product goal authorizes autonomous implementation. Official upstream
`dev` is pinned at `943ba5dcbfa62cf831e881684857ffd4867fe774`; index `main` is
pinned at `6f7eb4ad249bb6ca3080ce485be6a8053861a624`. Level A
storage/overworld checkpoints, Level B battle/RNG checkpoints, and reproducible
modkit packages are merged through PRs #952, #986, and #959. The distributable mod
composes its Level A services entirely through `mod:read`, `mod.storage`,
`mod.checkpoints`, registered screens, hooks, events, options, and HUD drawing.

Gate D and its merged Level B implementation are recorded in
`docs/battle-state-map.md`. The focused cross-mod audit is complete in
`docs/cross-mod-compatibility.md`; its minimal lifecycle seam is branch
`feat/checkpoint-restore-event` at `aa3b2a1`, submitted as draft upstream PR #993.
The mod test workflow pins that exact public-contract branch. The remaining
external product gate is review, merge, and official release of the complete
checkpoint contract; the release workflow stays fail-closed against that exact
future tag.

Latest verification (2026-08-08):

- Official `dev` baseline `./scripts/test.sh --quick` — 139/139 engine and 7/7
  modkit suites before the cross-mod patch.
- Cross-mod public SDK suite — expected red 33/42 before the lifecycle event,
  then 46/46 after the minimal change. Existing public checkpoint suite remains
  53/53 and meta coverage remains 178/178.
- `./scripts/test.sh --quick` at upstream branch `aa3b2a1` — 139/139 engine and
  8/8 modkit suites; ROM-derived T3 correctly skipped without imported data.

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
