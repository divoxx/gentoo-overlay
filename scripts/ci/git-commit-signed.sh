#!/usr/bin/env bash
# Create a GitHub-API commit for all currently staged git changes.
# Commits created via the GitHub API are automatically signed (Verified) by GitHub.
#
# Env vars:
#   REPO       - GitHub repository (owner/name)
#   BOT_TOKEN  - GitHub App token with contents:write permission
#   MESSAGE    - Commit message
#   BRANCH     - Target branch (defaults to current local branch)
#   FORCE      - If "true", force-update the ref even if it diverged

set -euo pipefail

: "${REPO:?REPO must be set}"
: "${BOT_TOKEN:?BOT_TOKEN must be set}"
: "${MESSAGE:?MESSAGE must be set}"
BRANCH="${BRANCH:-$(git branch --show-current)}"
FORCE="${FORCE:-false}"

ENTRIES='[]'
while IFS=$'\t' read -r status file new_file; do
  if [[ "$status" == "D" ]]; then
    ENTRIES=$(echo "$ENTRIES" | jq \
      --arg path "$file" \
      '. + [{"path": $path, "mode": "100644", "type": "blob", "sha": null}]')
  elif [[ "$status" == R* ]]; then
    ENTRIES=$(echo "$ENTRIES" | jq \
      --arg path "$file" \
      '. + [{"path": $path, "mode": "100644", "type": "blob", "sha": null}]')
    MODE=$(git ls-files --stage "$new_file" | awk '{print $1}')
    TMPJSON=$(mktemp)
    base64 -w0 < "$new_file" | jq -Rs '{"encoding":"base64","content":.}' > "$TMPJSON"
    BLOB_SHA=$(GH_TOKEN="$BOT_TOKEN" gh api "repos/$REPO/git/blobs" \
      --method POST --input "$TMPJSON" --jq '.sha')
    rm -f "$TMPJSON"
    ENTRIES=$(echo "$ENTRIES" | jq \
      --arg path "$new_file" --arg mode "$MODE" --arg sha "$BLOB_SHA" \
      '. + [{"path": $path, "mode": $mode, "type": "blob", "sha": $sha}]')
  else
    MODE=$(git ls-files --stage "$file" | awk '{print $1}')
    TMPJSON=$(mktemp)
    base64 -w0 < "$file" | jq -Rs '{"encoding":"base64","content":.}' > "$TMPJSON"
    BLOB_SHA=$(GH_TOKEN="$BOT_TOKEN" gh api "repos/$REPO/git/blobs" \
      --method POST --input "$TMPJSON" --jq '.sha')
    rm -f "$TMPJSON"
    ENTRIES=$(echo "$ENTRIES" | jq \
      --arg path "$file" --arg mode "$MODE" --arg sha "$BLOB_SHA" \
      '. + [{"path": $path, "mode": $mode, "type": "blob", "sha": $sha}]')
  fi
done < <(git diff --cached --name-status)

PARENT_SHA=$(git rev-parse HEAD)
BASE_TREE=$(git rev-parse "HEAD^{tree}")

NEW_TREE=$(jq -n \
  --arg base_tree "$BASE_TREE" \
  --argjson tree "$ENTRIES" \
  '{"base_tree": $base_tree, "tree": $tree}' | \
  GH_TOKEN="$BOT_TOKEN" gh api "repos/$REPO/git/trees" \
    --method POST --input - --jq '.sha')

NEW_COMMIT=$(jq -n \
  --arg message "$MESSAGE" \
  --arg tree "$NEW_TREE" \
  --arg parent "$PARENT_SHA" \
  '{"message": $message, "tree": $tree, "parents": [$parent]}' | \
  GH_TOKEN="$BOT_TOKEN" gh api "repos/$REPO/git/commits" \
    --method POST --input - --jq '.sha')

if GH_TOKEN="$BOT_TOKEN" gh api "repos/$REPO/git/refs/heads/$BRANCH" &>/dev/null; then
  GH_TOKEN="$BOT_TOKEN" gh api "repos/$REPO/git/refs/heads/$BRANCH" \
    --method PATCH -F force="$FORCE" -f sha="$NEW_COMMIT"
else
  GH_TOKEN="$BOT_TOKEN" gh api "repos/$REPO/git/refs" \
    --method POST -f ref="refs/heads/$BRANCH" -f sha="$NEW_COMMIT"
fi

echo "$NEW_COMMIT"
