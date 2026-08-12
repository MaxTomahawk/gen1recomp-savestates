# Save States Engineering Agreement

The product specification describes the desired player experience and researched
hypotheses. It is not an instruction to preserve proposed APIs, filenames, or
architecture when current upstream evidence supports a better design.

## Startup order

Before changing code, read:

1. `docs/project-plan.md` — living scope, architecture, milestones, and gates.
2. `docs/upstream-audit.md` — pinned upstream facts and public-API boundaries.
3. The current task or goal supplied by the user.

Refresh the upstream audit when its pinned commits change. Update the living plan
whenever evidence changes architecture, milestone order, blockers, or verification.

## Product and API rules

- Preserve the product goal: native quicksaves, autosaves, permanent slots,
  recovery, UI, compatibility handling, persistence, and proven safe restoration.
- Investigate current upstream code, tests, wiki, modkit, packaging, and index
  schemas instead of guessing or relying on remembered APIs.
- Distributable mod code must use documented public APIs and declared permissions.
  It must not `require("src.*")` outside upstream's explicitly supported require
  allowlist or mutate undocumented engine internals.
- Do not claim arbitrary-frame, battle, menu, transition, or suspended-script
  support without differential tests proving state equivalence.
- If an upstream seam is necessary, prove the gap first. Keep engine work in a
  separate upstream worktree/branch and make the smallest generic, additive,
  backward-compatible API change with an RFC, no-mod parity test, public-API test,
  and documentation.
- Never hide a missing capability by silently reducing the product.

## Delivery discipline

- Use test-driven development for behavior: write a focused failing test, verify
  the expected failure, implement the minimum behavior, then run focused and
  relevant suites.
- Test behavior and failure recovery, not private implementation details.
- Make small coherent commits only after fresh verification.
- Keep a recoverable transaction boundary around every state write and load.
- Treat snapshots and save files as untrusted data; validate before live mutation.
- Keep the vanilla SAVE flow semantically independent from savestate persistence.
- Do not commit ROMs, imported caches, extracted assets, personal saves,
  credentials, generated secrets, or ROM-derived screenshots.
- Preserve unrelated user changes and keep files usable by the `max` account.

## Repository layout

Keep repository-wide policy and packaging files at the root. Put product and
operational documentation in `docs/`, mod source in `src/`, sanitized fixtures and
tests in `tests/`, and legally distributable authored assets in `assets/`. Adapt
module layout to the real loader and test harness rather than forcing the initial
proposal's tree.

Canonical commands use `Makefile`. Set `GEN1RECOMP` to a current upstream checkout
that contains the public APIs required by the active milestone (the default is the
sibling `../gen1recomp`):

- `make test` — all repository Lua behavior tests.
- `make validate` — current modkit loader validation against the ROM-free fixture.
- `make lint` — ROM-derived-content and distribution-policy lint.
- `make package-check` — strict modkit package plus archive-root inspection.
- `make check` — the complete ROM-free local gate.

The package output lives under hidden `.artifacts/`, which modkit excludes from
subsequent package inputs. Run imported-base validation only in a private checkout
that already has legally obtained generated data; never add that data here.

## Reporting

Substantive reports must end with: capability audit, changes made, derived work,
remaining approval gates, sources checked, and model/effort recommendation.
