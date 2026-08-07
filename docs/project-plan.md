# Save States Living Project Plan

Status: active execution; Level A and supported Level B product slices implemented

Updated: 2026-08-07

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
  SAVE and recursively embedding the history.
- Exact stable-overworld restore is not currently a supported public mod action.
- Scripts are coroutine-driven; suspended scripts are unsafe.
- Battle state and gameplay RNG have no public serializable contract.
- Rebindable custom mod actions do not exist; START-menu operation remains the
  complete baseline until that optional seam lands.

The first battle/RNG statement above describes unmodified upstream. The stacked
Level B branch now implements the generic contract selected by the Gate D audit:
persistent ordinary wild/trainer decision-menu reconstruction plus exact LÖVE RNG,
while preserving explicit refusal for scripts and unsupported variants.

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
- Current `modkit pack` normalizes ZIP entries but embeds wall-clock
  `packed_at`, so its archive is not byte-reproducible despite the status text.
  A separate generic tooling fix now honors `SOURCE_DATE_EPOCH`; this repository
  independently rejects nonconforming metadata and compares two package builds.

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
- Level B: battle player-decision safe points after a complete battle field
  inventory and serializable RNG seam.
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
| M1 — Upstream proof/RFCs | Implement and specify scoped storage plus Level A checkpoint seams; keep candidates separate | local contracts and RFCs complete; focused suites, 1,000-run GC regression, and `./scripts/test.sh --quick` green; upstream review/release still required |
| M2 — Mod shell and pure core | Current modkit shell; injected adapters; snapshot schema/validation/index/retention/migrations | VERIFIED locally: pure behavior suite, real modkit load/lint, strict reproducible package and root listing |
| M3 — Level A prototype | Stable overworld capture/mutate/restore/re-capture | ENGINE CONTRACT VERIFIED: semantic differential recapture plus rejection/rollback tests; broader packaged fixture matrix remains before release |
| M4 — Quicksaves and recovery | Rolling quick history, newest quickload, transactional recovery, undo | VERIFIED in injected public-API service tests: A -> load B -> undo -> A; corruption and persistence failure paths covered |
| M5 — Native UX and slots | START rows, manager screens, ten permanent slots, rename/delete, HUD notifications, options | VERIFIED headlessly: second decorator coexistence, empty/unavailable states, generation-safe slot overwrite, disabled notifications, public widget close chain |
| M6 — Autosaves and robustness | Supported event triggers, cooldown/dedup, quarantine, compatibility, performance logging | IMPLEMENTED: location, ordinary trainer/wild start, optional after-battle deferral, synchronous capability-gated before-warp, stale-event expiry, dedup/retention, corrupt visibility, and opt-in phase timings; broader clean-runtime matrix remains |
| M7 — Battle beta | VERIFIED LOCALLY: field/RNG/continuation map plus persistent safe-point capture/restore | 133/133 engine suites; wild/trainer differential reconstruction; damage/crit/accuracy/AI/escape/encounter RNG replay; rollback and unsupported-phase tests green |
| M8 — Release readiness | Docs, clean package install, GitHub release, then index metadata PR | byte-identical source-date ZIP builds, clean install, validate/lint/tests, no private requires/ROM content, release asset resolves |

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
| `SAVESTATES-SP-01` scoped storage | VERIFIED locally; upstream review required | review-ready upstream PR #952 through `af00d6a`; 28/28 public API checks and full ROM-free suite green |
| `SAVESTATES-SP-02` Level A checkpoint | VERIFIED locally; upstream review required | review-ready upstream PR #952; 34/34 public API checks and differential rollback/content-rejection proof green; checkpoint identity exposes engine version for warning-grade compatibility |
| `SAVESTATES-SP-03` playthrough identity | VERIFIED locally; upstream review required | `726ed11` plus `49954ec`; 18/18 focused checks and 1,000 clean-process stress runs green |
| `SAVESTATES-SP-04` custom actions | CANDIDATE, non-blocking | START menu remains fully functional; propose only after Level A |
| `SAVESTATES-SP-05` battle/RNG | VERIFIED locally; stacked review required | `docs/battle-state-map.md`; branch `feat/mod-battle-checkpoints` through `5b3eed8`, review-ready stacked fork PR #1; persistent ordinary wild/trainer safe points, semantic continuations, exact RNG, legacy Level A compatibility |
| `SAVESTATES-SP-06` reproducible modkit package | VERIFIED locally; upstream review required | review-ready upstream PR #959 at `02fd21b`; `SOURCE_DATE_EPOCH`, invalid-input refusal, and byte-identity tests |
| HUD notifications | VERIFIED capability | implement in mod via `render.hud`; no upstream request |
| Core event triggers | VERIFIED PRODUCT SUPPORT | `map.entered`, ordinary trainer/wild `battle.started`, and optional `battle.ended` defer to matching safe kinds; enabled `player.warped` captures immediately before transition and never defers into the destination |

## Current execution boundary

The active product goal authorizes autonomous implementation. The official
upstream/index refs were refreshed on 2026-08-07 and remain `112120e`/`17314bf`.
The Level A public
contracts are implemented in `/home/max/src/gen1recomp-savestates-engine` on
`feat/mod-state-checkpoints`, based on upstream `112120e`; the focused branch is
published as review-ready PR #952 through `af00d6a`. Upstream merge/release remains the
M1 external gate. The distributable mod now composes its Level A services entirely
through `mod:read`, `mod.storage`, `mod.checkpoints`, registered screens, hooks,
events, options, and HUD drawing. Gate D and its Level B implementation are
complete locally in `docs/battle-state-map.md` and the separate stacked upstream
branch `feat/mod-battle-checkpoints`, published as review-ready fork PR #1 through
`5b3eed8`. Independent release hardening and clean-package coverage are complete;
the active lane is requirement traceability plus prepared (unsubmitted) index
metadata, followed by upstream review adaptation and exact release compatibility
once both public seams have an official release.

Packaging reconnaissance also found and corrected a separate upstream modkit
reproducibility defect. The focused branch `feat/reproducible-mod-packages` is
published through `02fd21b` as review-ready upstream PR #959. Level A PR #952 is
also review-ready, with its body reconciled to the final engine-version context;
the Level B dependent change remains review-ready in stacked fork PR #1 until its
base lands. The mod test workflow pins tooling separately from the runtime API
branch; the release workflow remains fail-closed against the exact official tag.

Latest verification (2026-08-07):

- `luajit tests/engine/playthrough_identity.lua` — 18/18.
- identity test in 1,000 fresh LuaJIT processes — 1,000/1,000.
- `luajit tests/modkit/cases/storage.lua` — 28/28.
- `luajit tests/modkit/cases/checkpoints.lua` — 34/34, including invalid-content rejection before mutation.
- `luajit tests/engine/save_slots.lua` — 78/78.
- `luajit tests/mod_save_tests.lua` — 132/132.
- `./scripts/test.sh --quick` — 129/129 engine suites and 7/7 modkit suites;
  ROM-derived T3 correctly skipped because no imported data is present.
- Mod `make check GEN1RECOMP=/home/max/src/gen1recomp-savestates-engine` —
  616/616 Lua behavior checks across composition, modules, snapshots, migrations,
  index/retention, quick/auto/slot/recovery services, native screens, notifications,
  event deferral, fingerprints/deduplication, and transaction failure recovery;
  modkit validate/lint and reproducible 49-file package root verification pass.
- Stacked Level B `./scripts/test.sh --quick` — 133/133 engine suites and 7/7
  modkit suites; battle boundary 13/13, capture 29/29, continuation 17/17,
  restore/determinism/failure rollback 43/43, public checkpoints 53/53 including
  real public-facade battle differential roundtrip, switched/fainted-party
  fidelity, and complete overworld-progress fidelity.
- Mod `make check GEN1RECOMP=/home/max/src/gen1recomp-savestates-battle
  MODKIT=/home/max/src/gen1recomp-modkit-reproducible/tools/modkit.py` —
  749/749 Lua behavior checks plus 7/7 Python release/package-gate tests; modkit
  validate/lint and reproducible 28-file
  package root verification plus a clean extracted-install pass with battle
  support enabled. This includes semantic autosave fingerprinting, fitted native
  notifications, live manager counts, default-NO destructive-action confirmation,
  structured diagnostics, pre-load engine-version warnings, and exact-minimum
  release-engine selection. Permanent-slot rename preserves the original
  checkpoint time/context, and every occupied-slot replacement defaults to NO.
- The same `make check` passed from a fresh clone of published head
  `4e86238851a90132ddda3e8a0c2f0c70d5225dc0`; two consecutive package
  builds were byte-identical. The archive SHA-256 was
  `73fbf8baedc5bd0c16d22b9c7b1fa1142a4eebffdb16e7f9bd37664964ffd739`,
  the resulting archive contains 28 distributable files plus
  `.modkit/pack.json`, and a clean extracted install validates and lints.
- GitHub Actions `Test` run `31195868937` completed successfully for that exact
  source-date packaging head. The preview release gate was also exercised
  directly and
  correctly refused publication because `experimental` remains `true`.
- A source-boundary audit found no private `src.*` require, raw filesystem,
  state-stack, process, package, or debug dependency in distributable Lua. The
  only require is LuaJIT's standard `bit` module; sibling source loads use the
  public `mod:read` facade and were exercised by the real modkit loader.
- Mod-index metadata is staged but intentionally unpushed on
  `prep/savestates-index` at `37321c5`; targeted validation passes with zero
  warnings. It must be refreshed from the final release manifest and submitted
  only after an installable release exists.
