#!/usr/bin/env bash
# Create a GitHub tracking issue and print its URL to stdout.
#
# Env vars:
#   REPO          - GitHub repository (owner/name)
#   ISSUE_TITLE   - Issue title
#   ISSUE_BODY    - Issue body (markdown)
#   ISSUE_LABEL   - (optional) label to apply; skipped if label doesn't exist

set -euo pipefail

: "${REPO:?REPO must be set}"
: "${ISSUE_TITLE:?ISSUE_TITLE must be set}"
: "${ISSUE_BODY:?ISSUE_BODY must be set}"

LABEL_ARGS=()
if [[ -n "${ISSUE_LABEL:-}" ]]; then
    # Check label exists before attempting to apply it.
    if gh label list --repo "$REPO" --json name -q '.[].name' | grep -qx "$ISSUE_LABEL"; then
        LABEL_ARGS=(--label "$ISSUE_LABEL")
    else
        echo "Warning: label '$ISSUE_LABEL' does not exist in $REPO — skipping" >&2
    fi
fi

gh issue create \
    --title "$ISSUE_TITLE" \
    --body "$ISSUE_BODY" \
    "${LABEL_ARGS[@]}" \
    --repo "$REPO"
