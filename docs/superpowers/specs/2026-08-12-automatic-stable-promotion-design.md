# Automatic Stable Promotion Design

## Outcome

Promote Save States 0.1.0 from early access to stable without a routine manual
merge once an official Gen1Recomp release contains both upstream PR #1077 and
#1079. The promotion removes `experimental`, records that exact engine release
as the minimum, removes pending-feature wording, tags the promoted merge as
`v0.1.0`, and starts the existing reproducible release workflow.

## Safety boundary

The scheduled engine-feature workflow remains fail-closed. It may promote only
when both PR merge commits are ancestors of official `vX.Y.Z` tags and chooses
the later first-containing release. Before merging its generated PR it requires
the repository's `stable-rom-free` pull-request check to complete successfully. It
must never overwrite an existing tag, merge a PR with unexpected changed files,
or publish when the manifest remains experimental.

Physical Android acceptance is considered supplied by the user's completed
testing of the coherent development stack. The remaining compatibility gate is
therefore machine-verifiable official engine release inclusion.

## Flow

1. The daily/manual watcher resolves #1077 and #1079 and their first official
   containing release tags.
2. Once both exist, the promotion script updates README, manifest, `mod.card`,
   changelog-facing status, and the checked-in index handoff. It sets every
   distributable/index `experimental` field to `false`.
3. The watcher creates or resumes one state-specific promotion PR.
4. It verifies the PR is same-repository, has only the allowlisted promotion
   files, and waits for the `rom-free` check to succeed.
5. It squash-merges the PR, verifies the resulting merge commit, creates the
   previously absent `v0.1.0` tag at that commit, and dispatches the release
   workflow explicitly. Explicit dispatch is required because GitHub suppresses
   most workflow recursion caused by `GITHUB_TOKEN` events.
6. The release workflow re-runs the exact official-minimum ROM-free gate and
   publishes the deterministic ZIP and checksums. Its existing release gate
   rejects any experimental manifest or mismatched tag/version.

## Recovery and idempotence

An interrupted watcher resumes an already-open state-specific PR. If the PR was
merged but tagging failed, a later run verifies the promoted main state and may
create only the missing matching tag. Existing mismatched tags, failed CI,
unexpected files, unresolved release tags, or conflicting PR state stop the
automation without mutation.

## Index boundary

The mod repository maintains an exact metadata-only index handoff with
`experimental: false` and the released minimum. Its repository-scoped Actions
token cannot write another repository. Updating upstream index PR #125 therefore
requires either a workflow installed in the MaxTomahawk index fork or a narrowly
scoped cross-repository token; no broad token is introduced in this change.

## Verification

- TDD unit coverage for stable-field promotion and idempotence.
- Static/fixture coverage for PR allowlisting, CI gating, tag collision refusal,
  explicit release dispatch, and interrupted-run recovery.
- Full `make check` against the current released baseline before merge.
- GitHub Actions run on the feature PR before merging this automation.
