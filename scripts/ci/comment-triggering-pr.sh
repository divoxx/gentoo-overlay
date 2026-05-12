#!/usr/bin/env bash
# Post a comment on the open PR for HEAD_BRANCH, if one exists.
# Silently exits 0 if no open PR is found — callers treat this as best-effort.
#
# Env vars:
#   REPO          - GitHub repository (owner/name)
#   HEAD_BRANCH   - Branch that triggered the CI failure
#   COMMENT_BODY  - Comment text (markdown)

set -euo pipefail

: "${REPO:?REPO must be set}"
: "${HEAD_BRANCH:?HEAD_BRANCH must be set}"
: "${COMMENT_BODY:?COMMENT_BODY must be set}"

PR_NUMBER=$(gh pr list \
    --head "$HEAD_BRANCH" \
    --state open \
    --json number \
    --repo "$REPO" \
    -q '.[0].number // empty')

if [[ -z "$PR_NUMBER" ]]; then
    echo "No open PR for branch '$HEAD_BRANCH' in $REPO — skipping comment" >&2
    exit 0
fi

gh pr comment "$PR_NUMBER" \
    --repo "$REPO" \
    --body "$COMMENT_BODY"

echo "Commented on PR #$PR_NUMBER" >&2
