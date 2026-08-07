# Save States Living Project Plan

Status: active execution; M1 upstream Level A seams in progress

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

The approved design is recorded in
`docs/superpowers/specs/2026-08-07-native-savestates-design.md`. Milestones are
executed through focused plans under `docs/superpowers/plans/`; the current plan is
`2026-08-07-level-a-upstream-seams.md`.

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

The target design is an upstream-provided, namespaced per-mod store scoped by an
opaque active game-version/playthrough identity. It must route through standard and
portable persistence backends and support verified replacement without rewriting
the vanilla progress checkpoint. The mod owns its snapshot schema, index,
retention, quarantine, and recovery semantics on top of that primitive.

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
| M1 — Upstream proof/RFCs | Prove and specify scoped storage plus Level A checkpoint seams; keep candidates separate | failing public-API tests, exact RFCs, no-mod parity plan, upstream tests green before PR |
| M2 — Mod shell and pure core | Current modkit shell; injected adapters; snapshot schema/validation/index/retention/migrations | ROM-free loader, lint, red-green unit tests, package listing |
| M3 — Level A prototype | Stable overworld capture/mutate/restore/re-capture | normalized A equals A2 across outdoor, indoor, route, party, inventory, flags, objects, trainer state |
| M4 — Quicksaves and recovery | Rolling quick history, newest quickload, transactional recovery, undo | failure-injection tests; A -> load B -> undo -> A; restart persistence |
| M5 — Native UX and slots | START rows, manager screens, ten permanent slots, rename/delete, HUD notifications, options | second decorator coexistence, empty states, disabled notifications, menu recovery |
| M6 — Autosaves and robustness | Supported event triggers, cooldown/dedup, quarantine, compatibility, performance logging | unsafe phases never capture; corrupt/missing payloads remain recoverable; measured timings/sizes |
| M7 — Battle beta | Complete battle map, safe-point capture/restore, deterministic gameplay RNG | differential wild/trainer matrix and exact repeated action results after reload |
| M8 — Release readiness | Docs, clean package install, GitHub release, then index metadata PR | clean ZIP install, validate/lint/tests, no private requires/ROM content, release asset resolves |

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
| `SAVESTATES-SP-01` scoped storage | PLANNED | public `mod.storage` contract defined; test-first implementation is M1 Task 3 |
| `SAVESTATES-SP-02` Level A checkpoint | PLANNED, Gate A blocker | public `mod.checkpoints` contract defined; acceptance and rollback tests precede implementation |
| `SAVESTATES-SP-03` playthrough identity | PLANNED | engine-owned opaque id plus stable legacy mapping; M1 Task 2 |
| `SAVESTATES-SP-04` custom actions | CANDIDATE, non-blocking | START menu remains fully functional; propose only after Level A |
| `SAVESTATES-SP-05` battle/RNG | CANDIDATE, post-Level-A | complete battle-state map before API or implementation |
| HUD notifications | VERIFIED capability | implement in mod via `render.hud`; no upstream request |
| Core event triggers | VERIFIED capability | defer requested autosaves until confirmed safe point |

## Current execution boundary

The active product goal authorizes autonomous implementation. M1 is being executed
in a separate upstream worktree. Mod implementation will begin with pure modules
after the Level A public contracts have failing acceptance tests; it will not use
private engine imports as a temporary shortcut.
