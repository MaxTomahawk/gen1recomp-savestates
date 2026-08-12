# Development and Release Handoff

## Repository boundaries

The distributable mod lives in this repository and may use only the public mod
object. Generic engine work stays in separate Gen1Recomp worktrees:

- official v0.1.79 — scoped storage, overworld/battle checkpoints, deterministic
  RNG, title resume, scripted battle continuations, shared date/time, real battle
  settling, reproducible packaging, and success-only restore lifecycle;
- `feat/battle-menu-auxiliary` and `feat/mod-pokemon-icon` — remaining open,
  generic, independently reviewable enhancements tracked by PRs #1077 and #1079.

Never copy private engine modules into the mod. Never add a ROM, generated import,
user save, extracted asset, credential, or ROM-derived screenshot.

## Local checks

Use a checkout containing the public checkpoint branches:

```sh
make test
make validate GEN1RECOMP=/path/to/gen1recomp
make lint GEN1RECOMP=/path/to/gen1recomp
make clean-install-check GEN1RECOMP=/path/to/gen1recomp
make check GEN1RECOMP=/path/to/gen1recomp
```

The merged upstream modkit honors `SOURCE_DATE_EPOCH`. The package gate derives it
from the newest commit affecting shipped content, verifies `.modkit/pack.json`,
and compares two complete archive builds. An older or nonconforming modkit still
fails closed.

The ROM-free fixture proves loader/API behavior and packaging. In a private local
checkout that already has legally imported `data/generated/`, additionally run
upstream `./scripts/test.sh` and modkit validation with the imported base. Never
move that generated data into this repository or CI.

For a release-candidate clean-checkout proof, clone the published branch into a
new temporary directory and run the same `make check` command there. Record the
tested commit, workflow run, archive file count, and SHA-256 in
`docs/project-plan.md`; do not treat an uncommitted working-tree result as release
evidence.

## Release gate

Gen1Recomp v0.1.79 contains the complete core storage/checkpoint, title-resume,
scripted-battle, date/time, and battle-settling contracts. An experimental
0.1.0 prerelease may therefore be packaged and listed honestly against that exact
minimum. Physical Android acceptance of the complete development stack has now
been supplied by the project owner. Stable promotion waits only until #1077 and
#1079 ship together in an official engine release.

For the stable release:

1. Rebase/adapt against current official upstream and rerun its complete relevant
   test tiers.
2. Set the mod version and `mod.card` compatibility consistently, set
   `experimental` to `false`, and make `game_version` begin with the exact first
   supported released engine version.
3. Update README, compatibility documentation, and CHANGELOG to describe only the
   behavior still proven on that release.
4. Run `python3 tools/release_gate.py manifest.json vX.Y.Z`; it emits the exact
   official engine tag the workflow will validate.
5. Run `make check` against that tag and test the resulting ZIP from a fresh
   extracted install. Where private imported data is available, complete the
   clean runtime acceptance matrix as well.
6. Merge the reviewed mod branch and push the matching `vX.Y.Z` tag. The release
   workflow rechecks the exact minimum engine tag, publishes
   `savestates-X.Y.Z.zip`, and adds `sha256sums.txt`.
7. Verify the published asset resolves, imports through the launcher, and reports
   the same manifest version before preparing the index PR.

## Mod-index handoff

Index work belongs only in a separate checkout of
`bryanthaboi/gen1recomp-mod-index`, never in the mod package. After an installable
release exists, create `mods/MaxTomahawk@savestates/` containing only:

- `meta.json` with id/title/author/version, categories `QOL`, `UI`, and `TOOL`,
  the HTTPS source repository, `github`, summary, MIT license, and the exact final
  `api`, `profile`, `game_version`, `experimental`, permissions, dependencies,
  and conflicts copied from `manifest.json`;
- `description.md` matching the released feature set and safety limits;
- an optional thumbnail only if it is authored/distribution-safe.

Set `automatic_version_check` to true. Run:

```sh
node scripts/validate.mjs mods/MaxTomahawk@savestates
node scripts/build-index.mjs
```

The experimental 0.1.0 entry is submitted as upstream index PR #125 after its
installable prerelease resolved successfully. Subsequent mod
versions normally need no index PR because the index follows GitHub Releases.

## Engine feature release tracking

The scheduled `engine-feature-status.yml` workflow checks upstream PRs #1077 and
#1079 and resolves the first official release tag containing each merge commit.
While either feature is unreleased it updates only the marked README status.
Once both are released it opens a state-specific Save States promotion PR that:

- removes the pending dependency wording from the README and launcher handoff;
- records the exact release where each feature became available;
- raises `manifest.json`, `mod.card`, and the index handoff to the later of those
  two releases, which is the first engine release guaranteed to contain both;
- sets `experimental: false`, based on the recorded physical Android acceptance.

The workflow checks that the PR is same-repository and changes only allowlisted
promotion files, waits for the named `rom-free` PR check, and merges only after
that check succeeds. It creates the previously absent manifest tag (`v0.1.0`) at
the verified merge commit and explicitly dispatches the release workflow.
Existing mismatched tags, unexpected files, failed checks, or release-resolution
errors stop promotion without overwriting anything.

The exact metadata-only index files live under
`index/MaxTomahawk@savestates/` and are excluded from the mod ZIP. GitHub's
repository-scoped workflow token cannot safely write to a different upstream
repository. After reviewing the generated promotion PR, copy those two files to
the index fork and update/open its upstream PR. A dedicated fine-grained
cross-repository token could automate that final hop, but no broad personal token
is stored or silently granted by this project.
