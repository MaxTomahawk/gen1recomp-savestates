# Development and Release Handoff

## Repository boundaries

The distributable mod lives in this repository and may use only the public mod
object. Generic engine work stays in separate Gen1Recomp worktrees:

- official `dev` — merged scoped storage, settled-overworld checkpoints, battle
  safe points/RNG restoration, source-date reproducible modkit packaging, and
  the success-only cross-mod restore lifecycle from PR #993;
- `feat/mod-title-checkpoint-resume`, `feat/battle-menu-auxiliary`, and
  `feat/scripted-battle-checkpoints` —
  review-ready generic contracts required only by the development title/battle
  manager flows until they are merged and released.

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

A public tag remains prohibited until the title-resume, battle auxiliary, and
scripted-battle contracts, together with the complete checkpoint API, are included in an official
Gen1Recomp release. The cross-mod lifecycle, Level A, Level B, and the
source-date modkit fix are already merged into `dev`.
Then:

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

Open the index PR only after the release ZIP is installable. Subsequent mod
versions normally need no index PR because the index follows GitHub Releases.
