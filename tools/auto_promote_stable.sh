#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${PROMOTION_BRANCH:?PROMOTION_BRANCH is required}"
: "${STABLE_TAG:?STABLE_TAG is required}"

repo="${GITHUB_REPOSITORY:-MaxTomahawk/gen1recomp-savestates}"
paths=(
  README.md
  manifest.json
  mod.card
  index/MaxTomahawk@savestates/meta.json
  index/MaxTomahawk@savestates/description.md
)

find_pr() {
  local state="$1"
  gh pr list --repo "$repo" --head "$PROMOTION_BRANCH" --state "$state" \
    --json number --jq '.[0].number // empty'
}

finish_release() {
  local merge_sha="$1" existing decision
  if ! existing="$(gh api "repos/$repo/git/ref/tags/$STABLE_TAG" \
      --jq '.object.sha' 2>/dev/null)"; then
    existing=
  fi
  decision="$(python3 tools/stable_promotion_gate.py tag-decision \
    "$existing" "$merge_sha")"
  if [ "$decision" = create ]; then
    gh api --method POST "repos/$repo/git/refs" \
      -f "ref=refs/tags/$STABLE_TAG" -f "sha=$merge_sha" >/dev/null
  fi
  if ! gh release view "$STABLE_TAG" --repo "$repo" >/dev/null 2>&1; then
    gh workflow run release.yml --repo "$repo" --ref "$STABLE_TAG"
  fi
}

if git diff --quiet -- "${paths[@]}"; then
  merged_pr="$(find_pr merged)"
  if [ -z "$merged_pr" ]; then
    echo "Stable metadata is current, but no merged promotion PR proves its origin." >&2
    exit 1
  fi
  merge_sha="$(gh pr view "$merged_pr" --repo "$repo" \
    --json mergeCommit --jq '.mergeCommit.oid // empty')"
  python3 tools/release_gate.py manifest.json "$STABLE_TAG" >/dev/null
  finish_release "$merge_sha"
  exit 0
fi

open_pr="$(find_pr open)"
if [ -n "$open_pr" ]; then
  head_sha="$(gh pr view "$open_pr" --repo "$repo" \
    --json headRefOid --jq .headRefOid)"
  git fetch origin "$PROMOTION_BRANCH"
  if ! git diff --quiet "$head_sha" -- "${paths[@]}"; then
    echo "Existing promotion PR does not match freshly resolved release state." >&2
    exit 1
  fi
  pr_number="$open_pr"
else
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git switch -c "$PROMOTION_BRANCH"
  git add "${paths[@]}"
  git commit -m "release: promote Save States 0.1.0"
  git push -u origin "$PROMOTION_BRANCH"
  head_sha="$(git rev-parse HEAD)"
  pr_url="$(gh pr create --repo "$repo" --base main \
    --head "$PROMOTION_BRANCH" --title "release: promote Save States 0.1.0" \
    --body "Promotes Save States after verifying that official Gen1Recomp releases contain #1077 and #1079. The generated change selects the later first-containing release as the minimum, removes the experimental marker, and is eligible for automatic merge only after the exact ROM-free/package/index gate succeeds.")"
  pr_number="${pr_url##*/}"
fi

# This check represents the exact-minimum make/index gate completed earlier in
# the same fail-closed job. It is attached only after every command succeeded.
gh api --method POST "repos/$repo/check-runs" \
  -f name=stable-rom-free -f "head_sha=$head_sha" -f status=completed \
  -f conclusion=success \
  -f 'output[title]=Stable promotion gate passed' \
  -f 'output[summary]=Exact released-engine checks, packaging, and index validation passed.' \
  >/dev/null

gh pr view "$pr_number" --repo "$repo" \
  --json state,isDraft,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,files,statusCheckRollup \
  > .promotion-pr.json
python3 tools/stable_promotion_gate.py validate-pr .promotion-pr.json
gh pr merge "$pr_number" --repo "$repo" --squash --delete-branch

merge_sha="$(gh pr view "$pr_number" --repo "$repo" \
  --json state,mergeCommit --jq \
  'if .state == "MERGED" then .mergeCommit.oid else empty end')"
if [ -z "$merge_sha" ]; then
  echo "Promotion PR did not produce a merge commit." >&2
  exit 1
fi
finish_release "$merge_sha"
