#!/usr/bin/env bash
# Open a fix PR and print its URL to stdout.
#
# Env vars:
#   REPO          - GitHub repository (owner/name)
#   FIX_BRANCH    - Head branch for the PR
#   PR_TITLE      - PR title
#   PR_BODY       - PR body (markdown)
#   BASE_BRANCH   - (optional) base branch; defaults to "main"

set -euo pipefail

: "${REPO:?REPO must be set}"
: "${FIX_BRANCH:?FIX_BRANCH must be set}"
: "${PR_TITLE:?PR_TITLE must be set}"
: "${PR_BODY:?PR_BODY must be set}"

BASE="${BASE_BRANCH:-main}"

gh pr create \
    --title "$PR_TITLE" \
    --body "$PR_BODY" \
    --base "$BASE" \
    --head "$FIX_BRANCH" \
    --repo "$REPO"
