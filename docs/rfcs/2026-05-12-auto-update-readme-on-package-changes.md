---
rfc: "2026-05-12-auto-update-readme-on-package-changes"
title: "Auto-update README when packages are added or removed"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-12"
drop_reason: ~
---

## Summary

The Packages table in `README.md` is maintained by hand and already drifts from reality (e.g. `sys-cluster/minikube` exists in the overlay but is missing from the table). This RFC introduces a deterministic generator script (`scripts/generate-readme-packages.sh`) plus a GitHub Actions workflow (`update-readme.yml`) that regenerates the table from each package's latest ebuild whenever ebuilds change on `main`, and a verification job on PRs that fails fast when a contributor edits the auto-generated region by hand. The README continues to be a regular markdown file — only the region between two HTML-comment markers is owned by the generator.

## Should we do this?

**Yes.** The overlay already runs an autonomous version-bump workflow (`auto-update.yml`) twice a week; PRs land without human prose review of the README. As more packages are added the manual table becomes increasingly likely to fall out of sync, and a stale README is the first thing a user sees. The fix is small: one bash script, one workflow, and two marker comments in the README. The script reads each package's latest ebuild `DESCRIPTION=` line directly from the filesystem (the authoritative source) — no cache regeneration or ebuild sourcing required. Risk surface is contained — the only state the generator owns is a single markdown table region.

## Current state

**Existing artefacts:**

- `README.md` lines 8-18 contain a hand-maintained `## Packages` table. The table currently lists 7 packages; the overlay actually contains 8 (`sys-cluster/minikube` is missing).
- Each ebuild declares a short, single-line `DESCRIPTION="..."` (required by EAPI 8; verified by `pkgcheck DescriptionCheck`). EAPI 8 requires `DESCRIPTION` to be a plain string with no variable expansion or command substitution.
- Each package has a `metadata.xml`. Some include `<longdescription>` (`app-containers/devpod`, `dev-util/exercism`) but most do not (`dev-python/mslex`, `dev-python/oslex`, `dev-util/ufbt`, `dev-util/worktrunk`, `net-mail/himalaya`, `sys-cluster/minikube`).
- The CI container image `ghcr.io/<owner>/gentoo-ci:latest` already has `dev-util/pkgcheck`, `dev-util/pkgdev`, and `app-misc/jq` installed (see `.github/Containerfile.ci`).
- `auto-update.yml` already opens commits against `main` via the GitHub API using a bot App token (`secrets.BOT_APP_ID`, `secrets.BOT_APP_PRIVATE_KEY`) so commits show as `Verified`.
- `verify.yml` runs on PRs and on `push: branches: [main]`; it has a `detect-changes` job that emits a JSON array of changed packages and a `verify` job that runs `bash scripts/verify-ebuild.sh "$PACKAGE"` per package in a container.

**Pain points:**

1. README already drifts — `sys-cluster/minikube` exists in the overlay but is unlisted.
2. Auto-update PRs only touch `<cat>/<pkg>/*.ebuild` and `Manifest`; nothing keeps the README in sync.
3. No contributor-facing signal when someone edits the table by hand vs. adding a package.
4. The hand-written descriptions in the table match each ebuild's `DESCRIPTION` line — not the verbose multi-paragraph `<longdescription>` — but that is an emergent convention, not enforced.

## Analysis / Options

### Source-of-truth for each row's description

| Option | Pros | Cons |
|--------|------|------|
| Ebuild `DESCRIPTION=` of the latest version, read directly from the `.ebuild` file | Single line, always present, already enforced by `pkgcheck DescriptionCheck`, already matches existing README content, no cache regeneration, authoritative source (filesystem ebuilds, not a derived cache) | EAPI 8 forbids variable expansion in `DESCRIPTION`, so a simple grep+sed extraction is safe |
| `metadata.xml <longdescription>` | Pure XML — easy to parse with `xmllint` | Optional (6 of 8 current packages lack it); when present it is multi-paragraph prose, far too long for a table cell |
| `metadata.xml <description>` (the per-USE-flag element's parent) | Pure XML | Not part of the `pkgmetadata` schema as a top-level element; no current package has one |
| Portage `md5-cache` file `DESCRIPTION=` line | Already normalised by portage | The cache is **not** populated by `pkgcheck` (its `--cache` flag manages pkgcheck's own internal caches under `~/.cache/pkgcheck/`, not `metadata/md5-cache/`). Populating it requires `egencache --update --repo=<name>`, which adds dependency surface. The cache also drifts: a stale `media-sound/spotify-player-0.23.0` entry exists in `metadata/md5-cache/` with no corresponding ebuild, so using the cache as the enumeration source would silently include phantom packages. |

**Recommendation: ebuild `DESCRIPTION=` read directly from each package's latest `.ebuild` file.** The filesystem is the authoritative source of which packages exist. EAPI 8's `DESCRIPTION=` constraint (single-line plain string, no expansion, enforced by `pkgcheck DescriptionCheck`) makes a `grep -m1 '^DESCRIPTION=' <ebuild> | sed -E "s/^DESCRIPTION=(['\"])(.*)\1\$/\2/; s/^DESCRIPTION=//"` extraction reliable. The `<longdescription>` option is rejected because it is absent on most packages and far too long for a table cell when present. The `md5-cache` option is rejected because populating it requires `egencache` (not `pkgcheck`), and entries can be stale relative to the ebuild filesystem — using the cache as the enumeration source would silently include packages that no longer exist on disk.

### When to regenerate

| Option | Pros | Cons |
|--------|------|------|
| `push` to `main` with path filter `**/*.ebuild` | Fires exactly once after merge; simple; matches the project pattern of post-merge automation | Adds a small commit to `main` for every merge that adds/removes/renames packages |
| Inside `verify.yml`'s `promote` job after auto-update PR merges | Reuses the bot token | Only runs for auto-update branches; misses human PRs that add packages |
| As part of every PR's `verify` matrix | Catches drift before merge | Cannot push to PR branches that come from forks; introduces write surface on PRs |
| Local `pre-commit` hook | Free of CI cost | Easy to skip; not enforceable; the overlay has no other pre-commit infrastructure |

**Recommendation: post-merge `push` to `main` with path filter, plus a PR-side `verify-readme` job that fails (does not push) when the table is out of date.** The post-merge workflow is the only place that can fix drift autonomously. The PR-side check is non-mutating — it runs the generator with `--check` and fails the build if the output differs from the committed README, prompting the contributor to run the script locally. This pattern matches how `gofmt -d`, `prettier --check`, and `rustfmt --check` are used in CI. Only `.ebuild` files affect the table content, so `metadata.xml` changes are excluded from the trigger to avoid guaranteed no-op runs.

### Commit mechanism (post-merge)

| Option | Pros | Cons |
|--------|------|------|
| Direct `git push` from the workflow | Simplest | Commit is unsigned unless the workflow does the `gpg` dance |
| GitHub API tree/commit/ref calls with bot App token | Commit auto-signed by GitHub (`Verified` badge); matches existing `auto-update.yml` pattern | Adds ~20 lines of bash |
| Open a PR with the change | Human review possible | The change is mechanical — review adds no value; PR backlog noise; nothing else opens PRs to `main` for cosmetic state |

**Recommendation: GitHub API tree/commit/ref calls with bot App token, identical to `auto-update.yml`'s `Commit and push update branch` step.** This keeps the commit log uniform (all bot commits show `Verified` from `divoxx-bot[bot]`).

### Region delimitation in the README

| Option | Pros | Cons |
|--------|------|------|
| HTML comment markers `<!-- AUTO-GENERATED-PACKAGES:START -->` … `:END -->` | Invisible in rendered README; well-known convention (used by Prettier, `cog`, `markdown-table-tools`); robust against surrounding edits | Renders in some older markdown viewers as comments — acceptable |
| Replace the entire `README.md` | Avoids markers | Forfeits all hand-written prose (Usage, Contributing, License) — non-starter |
| Generate a separate `PACKAGES.md` and link from README | Clean separation | Users still see stale list in README unless we also remove the heading there — defeats the goal |

**Recommendation: HTML comment markers** around the existing table heading and contents (heading included, so the generator owns the full block including `## Packages`).

### Loop prevention

The workflow's path filter (`**/*.ebuild`) does **not** include `README.md`, so the bot's own commit (which only edits `README.md`) cannot retrigger the workflow. As a belt-and-braces safeguard, the workflow also short-circuits with `git diff --quiet README.md` after running the generator — no commit, no push.

## Drawbacks

- **One additional commit per package add/remove** on `main`. Mitigated by the no-op short-circuit when the table is already current; in steady state the overhead is one commit per real change.
- **Marker comments visible in source.** A reader of `README.md`'s raw source sees the comments. They do not render in GitHub or `pandoc`.
- **The PR-side `--check` job adds ~1 minute to PRs.** Acceptable; it runs in the same container as `verify` and is unconditional (every non-superseded PR runs it).
- **Marker drift on hand-edits.** If a contributor accidentally deletes a marker, the next generator run fails noisily. Acceptable — this is a single-keyed assertion (exact-line match for each marker, count must equal 1).
- **The bot pushes directly to `main`.** This bypasses the standard PR flow for the README region only. The risk is bounded: the generator is deterministic, the diff is mechanical, and the marker scope means the bot cannot touch any other file or any other section of the README.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `scripts/generate-readme-packages.sh` | Bash script: enumerate ebuilds from the filesystem, build markdown table from every package's `DESCRIPTION=` line, rewrite the `README.md` region between markers. Supports `--check` mode (exit 1 if README differs) and `--write` (default; rewrite README in place). |
| Create | `.github/workflows/update-readme.yml` | Post-merge workflow: on `push` to `main` with path filter on `**/*.ebuild`, run the generator, commit any change to `main` via GitHub API using the bot App token. |
| Modify | `.github/workflows/verify.yml` | Add a `verify-readme` job (after `detect-changes`, parallel to `verify`) that runs `bash scripts/generate-readme-packages.sh --check` on every non-superseded PR and fails the build if the README region is out of date. Update `promote:` to depend on both `verify` and `verify-readme`, requiring `success` from each — when either is `skipped` (because the run is superseded), the cascade skips `promote` and no PR is promoted without verification. |
| Modify | `README.md` | Wrap the existing `## Packages` heading and table in `<!-- AUTO-GENERATED-PACKAGES:START -->` … `<!-- AUTO-GENERATED-PACKAGES:END -->` markers. Add `sys-cluster/minikube` to fix the existing drift; the first workflow run after this RFC's merge normalises any remaining description drift. |
| Modify | `.github/workflows/debug-ci-failure.yml` | Extend the `workflows:` list at the top of the file to include `"Update README"` so failures of the new workflow are also auto-debugged. |
| Modify | `CLAUDE.md` | Add a one-paragraph note under the agent delegation table stating that the README package list is auto-generated and must not be hand-edited, and add the new workflow to the Repository Structure tree. |
| Modify | `CONTRIBUTING.md` | Add a one-paragraph note under "Adding a New Package" explaining that the README table updates automatically; do not edit it by hand. |

### Steps

#### Step 1 — Create `scripts/generate-readme-packages.sh`

Create the file at `scripts/generate-readme-packages.sh` (relative to overlay root) with mode `0755`. Full contents:

```bash
#!/usr/bin/env bash
# generate-readme-packages.sh — Regenerate the auto-generated Packages section
# of README.md from each package's latest ebuild DESCRIPTION= line.
#
# Usage:
#   generate-readme-packages.sh                # default: --write
#   generate-readme-packages.sh --write        # rewrite README.md in place
#   generate-readme-packages.sh --check        # exit 1 if README.md would change
#
# Exit codes:
#   0  README.md is up to date (--check) or was rewritten (--write)
#   1  README.md is out of date (--check only)
#   2  Hard error (no ebuilds found, malformed markers, etc.)

set -euo pipefail

MODE="${1:---write}"
case "$MODE" in
    --write|--check) ;;
    *) echo "Usage: $0 [--write|--check]" >&2; exit 2 ;;
esac

die() { echo "ERROR: $*" >&2; exit 2; }

# Locate overlay root (mirror of verify-ebuild.sh).
find_overlay_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/profiles/repo_name" ]] && { echo "$dir"; return 0; }
        dir="$(dirname "$dir")"
    done
    return 1
}

OVERLAY_ROOT=""
[[ -n "${GITHUB_WORKSPACE:-}" && -f "$GITHUB_WORKSPACE/profiles/repo_name" ]] && \
    OVERLAY_ROOT="$GITHUB_WORKSPACE"
if [[ -z "$OVERLAY_ROOT" ]]; then
    OVERLAY_ROOT=$(find_overlay_root "$PWD") || die "Could not locate overlay root"
fi

README="$OVERLAY_ROOT/README.md"
[[ -f "$README" ]] || die "README.md not found at $README"

START='<!-- AUTO-GENERATED-PACKAGES:START -->'
END='<!-- AUTO-GENERATED-PACKAGES:END -->'

# Each marker must appear exactly once in README.md, on its own line.
# Use awk with exact-line matching (consistent with the awk replacement below).
START_COUNT=$(awk -v s="$START" '$0 == s {n++} END {print n+0}' "$README")
END_COUNT=$(awk -v v="$END" '$0 == v {n++} END {print n+0}' "$README")
[[ "$START_COUNT" == "1" ]] || die "Expected exactly 1 START marker line in README.md, found $START_COUNT"
[[ "$END_COUNT"   == "1" ]] || die "Expected exactly 1 END marker line in README.md, found $END_COUNT"

# Single tempdir for all intermediate files; cleaned on exit.
TMPDIR_RUN=$(mktemp -d)
trap 'rm -rf "$TMPDIR_RUN"' EXIT

ROWS_FILE="$TMPDIR_RUN/rows"
BLOCK_FILE="$TMPDIR_RUN/block"
NEW_README="$TMPDIR_RUN/README.md.new"

# Enumerate every ebuild in the overlay. Layout is <category>/<package>/<pkg>-<ver>.ebuild,
# so a depth-3 find captures exactly the ebuild files.
declare -A LATEST_PATH=()
declare -A LATEST_VER=()

while IFS= read -r ebuild_file; do
    # Path is "$OVERLAY_ROOT/<category>/<package>/<file>.ebuild".
    rel="${ebuild_file#"$OVERLAY_ROOT/"}"
    category="${rel%%/*}"
    rest="${rel#*/}"
    pkg="${rest%%/*}"
    file="${rest##*/}"
    # Strip ".ebuild" and the leading "<pkg>-" to recover the version.
    # The package name comes from the directory (authoritative), not regex on the filename,
    # so package names containing "-<digit>" (PMS-legal) work correctly.
    base="${file%.ebuild}"
    [[ "$base" == "$pkg-"* ]] || die "Ebuild filename '$file' does not start with '$pkg-' in $rel"
    ver="${base#"$pkg-"}"
    [[ -n "$ver" ]] || die "Empty version derived from '$file' in $rel"

    atom="$category/$pkg"
    prev_ver="${LATEST_VER[$atom]:-}"
    if [[ -z "$prev_ver" ]]; then
        LATEST_VER[$atom]="$ver"
        LATEST_PATH[$atom]="$ebuild_file"
    else
        # Pick the highest version. GNU sort -V handles "_pN" and "-rN" correctly
        # for the versions currently used in this overlay.
        winner=$(printf '%s\n%s\n' "$prev_ver" "$ver" | LC_ALL=C sort -V | tail -n 1)
        if [[ "$winner" == "$ver" && "$winner" != "$prev_ver" ]]; then
            LATEST_VER[$atom]="$ver"
            LATEST_PATH[$atom]="$ebuild_file"
        fi
    fi
done < <(find "$OVERLAY_ROOT" -mindepth 3 -maxdepth 3 -name '*.ebuild' -type f -not -path '*/.git/*')

(( ${#LATEST_PATH[@]} > 0 )) || die "No ebuilds found under $OVERLAY_ROOT"

# Extract DESCRIPTION= from each picked ebuild. EAPI 8 requires a single-line
# plain string with no variable expansion (enforced by pkgcheck DescriptionCheck),
# so a single grep+sed pass is reliable.
for atom in "${!LATEST_PATH[@]}"; do
    ebuild_file="${LATEST_PATH[$atom]}"
    desc=$(grep -m1 '^DESCRIPTION=' "$ebuild_file" | sed -E "s/^DESCRIPTION=(['\"])(.*)\1\$/\2/; s/^DESCRIPTION=//")
    [[ -n "$desc" ]] || die "DESCRIPTION empty for $atom in $ebuild_file"
    # Escape pipe characters so the markdown table doesn't break.
    desc_escaped="${desc//|/\\|}"
    printf '%s\t%s\n' "$atom" "$desc_escaped" >> "$ROWS_FILE"
done

[[ -s "$ROWS_FILE" ]] || die "No rows produced from ebuilds under $OVERLAY_ROOT"

# Render the auto-generated block. Sort deterministically and locale-independently.
{
    echo "$START"
    echo "## Packages"
    echo
    echo "| Package | Description |"
    echo "|---------|-------------|"
    while IFS=$'\t' read -r atom desc; do
        printf '| `%s` | %s |\n' "$atom" "$desc"
    done < <(LC_ALL=C sort -t $'\t' -k1,1 "$ROWS_FILE")
    echo "$END"
} > "$BLOCK_FILE"

# Rewrite the README between the markers, in-place, atomic.
# The awk END block guards against an unclosed block (missing END marker after START).
awk -v block_file="$BLOCK_FILE" -v start="$START" -v end="$END" '
    BEGIN {
        while ((getline line < block_file) > 0) {
            block = block (block ? "\n" : "") line
        }
        close(block_file)
        if (block == "") {
            print "ERROR: block file was empty or unreadable" > "/dev/stderr"
            exit 2
        }
        in_block = 0
    }
    {
        if ($0 == start) {
            print block
            in_block = 1
            next
        }
        if ($0 == end) {
            in_block = 0
            next
        }
        if (!in_block) print
    }
    END {
        if (in_block) {
            print "ERROR: END marker not found after START marker in README.md" > "/dev/stderr"
            exit 2
        }
    }
' "$README" > "$NEW_README"

if cmp -s "$README" "$NEW_README"; then
    [[ "$MODE" == "--check" ]] && echo "README.md is up to date." >&2
    exit 0
fi

if [[ "$MODE" == "--check" ]]; then
    echo "ERROR: README.md is out of date. Run 'bash scripts/generate-readme-packages.sh' and commit the result." >&2
    diff -u "$README" "$NEW_README" >&2 || true
    exit 1
fi

mv "$NEW_README" "$README"
echo "Updated $README" >&2
exit 0
```

After writing the file, run `chmod +x scripts/generate-readme-packages.sh`. Verify the script syntax by running `bash -n scripts/generate-readme-packages.sh` from the overlay root; expected output: nothing, exit 0.

#### Step 2 — Add markers to `README.md`

In `README.md`, replace the existing `## Packages` block (lines 8-18). The replacement preserves the heading and table inside two HTML-comment markers, and adds the `sys-cluster/minikube` row that the current README is missing.

Existing content to remove (current lines 8-18):

```markdown
## Packages

| Package | Description |
|---------|-------------|
| `app-containers/devpod` | Client-only tool for reproducible dev environments via devcontainer.json |
| `dev-python/mslex` | Windows-compatible shell lexer (shlex for cmd.exe) |
| `dev-python/oslex` | OS-aware shell lexer (wraps mslex on Windows, shlex elsewhere) |
| `dev-util/exercism` | CLI client for exercism.io — learning programming through practice |
| `dev-util/ufbt` | Micro Flipper Build Tool — SDK for Flipper Zero app development |
| `dev-util/worktrunk` | CLI for git worktree management, designed for running AI agents in parallel |
| `net-mail/himalaya` | CLI email client |
```

New content (seeded with the current ebuild `DESCRIPTION=` values and wrapped in markers; minor drift between this seed and the ebuilds at merge time will be normalised by the first workflow run on `main`):

```markdown
<!-- AUTO-GENERATED-PACKAGES:START -->
## Packages

| Package | Description |
|---------|-------------|
| `app-containers/devpod` | Client-only tool for reproducible dev environments via devcontainer.json |
| `dev-python/mslex` | shlex for Windows — Windows-compatible shell lexing and quoting |
| `dev-python/oslex` | OS-independent wrapper for shlex and mslex |
| `dev-util/exercism` | CLI client for exercism.io - learning programming through practice |
| `dev-util/ufbt` | Compact tool for building and debugging applications for Flipper Zero |
| `dev-util/worktrunk` | CLI for git worktree management, designed for running AI agents in parallel |
| `net-mail/himalaya` | CLI to manage emails |
| `sys-cluster/minikube` | Local kubernetes clusters for learning and development |
<!-- AUTO-GENERATED-PACKAGES:END -->
```

The first workflow run after this RFC's merge will normalise any description drift between this seed and the live ebuilds — this is expected behaviour and produces at most one small commit on `main`.

#### Step 3 — Create `.github/workflows/update-readme.yml`

Create the file at `.github/workflows/update-readme.yml` (relative to overlay root). Full contents:

```yaml
name: Update README

on:
  push:
    branches:
      - main
    paths:
      - '**/*.ebuild'
  workflow_dispatch:        # allow manual trigger for backfill/testing

permissions:
  contents: write

concurrency:
  group: update-readme-main
  cancel-in-progress: false

jobs:
  regenerate:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/${{ github.repository_owner }}/gentoo-ci:latest
    steps:
      - name: Generate bot token
        id: bot-token
        uses: tibdex/github-app-token@v2
        with:
          app_id: ${{ secrets.BOT_APP_ID }}
          private_key: ${{ secrets.BOT_APP_PRIVATE_KEY }}

      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ steps.bot-token.outputs.token }}
          ref: main

      - name: Configure git
        env:
          REPO: ${{ github.repository }}
          BOT_TOKEN: ${{ steps.bot-token.outputs.token }}
          BOT_APP_ID: ${{ secrets.BOT_APP_ID }}
        run: |
          set -euo pipefail
          git config --global --add safe.directory "$GITHUB_WORKSPACE"
          git config --global user.name "divoxx-bot[bot]"
          git config --global user.email "${BOT_APP_ID}+divoxx-bot[bot]@users.noreply.github.com"
          git remote set-url origin "https://x-access-token:${BOT_TOKEN}@github.com/${REPO}.git"

      - name: Regenerate README packages section
        run: bash scripts/generate-readme-packages.sh --write

      - name: Detect change
        id: changes
        run: |
          set -euo pipefail
          if git diff --quiet README.md; then
            echo "updated=false" >> "$GITHUB_OUTPUT"
          else
            echo "updated=true" >> "$GITHUB_OUTPUT"
          fi

      - name: Commit and push via GitHub API
        if: steps.changes.outputs.updated == 'true'
        env:
          REPO: ${{ github.repository }}
          BOT_TOKEN: ${{ steps.bot-token.outputs.token }}
        run: |
          set -euo pipefail

          PARENT_SHA=$(git rev-parse HEAD)
          BASE_TREE=$(git rev-parse "HEAD^{tree}")

          # Build a tree entry containing only the updated README.md blob.
          TMPJSON=$(mktemp)
          base64 -w0 < README.md | jq -Rs '{"encoding":"base64","content":.}' > "$TMPJSON"
          BLOB_SHA=$(GH_TOKEN="$BOT_TOKEN" gh api "repos/$REPO/git/blobs" \
              --method POST --input "$TMPJSON" --jq '.sha')
          rm -f "$TMPJSON"

          ENTRIES=$(jq -n --arg sha "$BLOB_SHA" \
              '[{"path":"README.md","mode":"100644","type":"blob","sha":$sha}]')

          NEW_TREE=$(jq -n \
              --arg base_tree "$BASE_TREE" \
              --argjson tree "$ENTRIES" \
              '{"base_tree": $base_tree, "tree": $tree}' | \
              GH_TOKEN="$BOT_TOKEN" gh api "repos/$REPO/git/trees" \
                  --method POST --input - --jq '.sha')

          NEW_COMMIT=$(jq -n \
              --arg message "docs: regenerate README packages table" \
              --arg tree "$NEW_TREE" \
              --arg parent "$PARENT_SHA" \
              '{"message": $message, "tree": $tree, "parents": [$parent]}' | \
              GH_TOKEN="$BOT_TOKEN" gh api "repos/$REPO/git/commits" \
                  --method POST --input - --jq '.sha')

          GH_TOKEN="$BOT_TOKEN" gh api "repos/$REPO/git/refs/heads/main" \
              --method PATCH -f sha="$NEW_COMMIT"

          echo "Pushed README update as commit $NEW_COMMIT"
```

#### Step 4 — Add `verify-readme` job and update `promote` in `.github/workflows/verify.yml`

In `.github/workflows/verify.yml`, make two changes:

**4a.** Insert the following job block immediately before the existing `promote:` job, at the same indentation level as the `verify:` job. The `verify-readme` job runs on every non-superseded PR, regardless of whether `.ebuild` files changed — the check exists specifically to catch PRs that edit the auto-generated region without touching ebuilds, so it must not be gated on `has_changes`:

```yaml
  verify-readme:
    needs: detect-changes
    if: needs.detect-changes.outputs.should_skip != 'true'
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/${{ github.repository_owner }}/gentoo-ci:latest
    steps:
      - uses: actions/checkout@v4

      - name: Check README packages table is current
        run: bash scripts/generate-readme-packages.sh --check
```

**4b.** In the `promote:` job, replace its existing `needs:` and `if:` lines with the following block. Without `always()`, GitHub Actions cascades a `skipped` result from any `needs` job to this job — so when `should_skip=true` causes both `verify` and `verify-readme` to skip, `promote` is also skipped, correctly preventing promotion without verification:

```yaml
  promote:
    needs: [verify, verify-readme]
    if: |
      startsWith(github.head_ref || github.ref_name, 'auto-update/') &&
      needs.verify.result == 'success' &&
      needs.verify-readme.result == 'success'
```

The rest of `promote:` (its `runs-on`, `steps`, etc.) is unchanged.

#### Step 5 — Extend `.github/workflows/debug-ci-failure.yml`

In `.github/workflows/debug-ci-failure.yml`, modify the `workflows:` list at the top (current lines 4-9) so failures of the new workflow are auto-debugged by the ci-debugger agent. Replace the existing block:

```yaml
  workflow_run:
    workflows:
      - "Build CI Image"
      - "Auto-Update Ebuilds"
      - "Verify Ebuilds"
    types:
      - completed
```

with:

```yaml
  workflow_run:
    workflows:
      - "Build CI Image"
      - "Auto-Update Ebuilds"
      - "Verify Ebuilds"
      - "Update README"
    types:
      - completed
```

No other changes are required in this file — the existing `Resolve context` step already handles any `workflow_run.name` generically.

#### Step 6 — Update `CLAUDE.md`

In `CLAUDE.md`, locate the **Agent Delegation** section (which contains a markdown table whose last row is `| Debug a CI workflow failure | ci-debugger | (invoked automatically by debug-ci-failure.yml) |`). Add the following paragraph as a new block immediately after that table, before any subsequent content:

```markdown
**Auto-generated content:** The `## Packages` section of `README.md`, delimited by `<!-- AUTO-GENERATED-PACKAGES:START -->` and `<!-- AUTO-GENERATED-PACKAGES:END -->` markers, is regenerated automatically by `.github/workflows/update-readme.yml`. Never hand-edit that region — change a package's `DESCRIPTION=` in its ebuild instead. The `verify-readme` job in `verify.yml` fails any PR whose region diverges from what `scripts/generate-readme-packages.sh` would produce.
```

Also in `CLAUDE.md`, add `update-readme.yml` to the `.github/workflows/` listing in the `## Repository Structure` section. The new line (in alphabetical order between `auto-update.yml` and `build-image.yml`) is:

```
│   ├── auto-update.yml          # Daily upstream version check and bump
│   ├── build-image.yml          # Weekly CI container image build
→   │   ├── update-readme.yml        # Regenerate README packages table on ebuild changes
```

Insert it between `auto-update.yml` and `build-image.yml` in the tree, maintaining the same formatting as existing entries.

#### Step 7 — Update `CONTRIBUTING.md`

In `CONTRIBUTING.md`, locate the section heading `## Adding a New Package` (currently line 32) and its numbered list (currently lines 34-40). The list's last item is `7. **Submit a PR** — the verify CI runs automatically.`

Immediately after that numbered list and before the existing line `If you use Claude Code, the `/ebuild-create <url>` skill automates steps 2–6.`, insert this blockquote as a new paragraph (with one blank line above and below to keep markdown rendering correct):

```markdown
> **Note:** You do not need to edit `README.md`. The Packages table is regenerated automatically by the `update-readme.yml` workflow when your PR merges, sourcing each row's text from the ebuild's `DESCRIPTION=` line. The verify workflow's `verify-readme` job runs `scripts/generate-readme-packages.sh --check` on your PR and fails if the auto-generated region differs from what the script would regenerate — if you see that failure, run `bash scripts/generate-readme-packages.sh` locally and commit the result.
```

#### Step 8 — Local sanity check

Before opening the PR for this RFC's implementation, run these commands from the overlay root and confirm the listed expected output. Each command must be run inside the CI container or in an environment that has a recent GNU coreutils (for `sort -V`).

1. `bash -n scripts/generate-readme-packages.sh`
   - Expected: no output, exit code 0. Failure means a syntax error in Step 1's script.
2. `bash scripts/generate-readme-packages.sh --check`
   - Expected: exit code 0 if the seeded `README.md` from Step 2 already matches the ebuilds; exit code 1 with a unified diff otherwise. If the latter, run `bash scripts/generate-readme-packages.sh --write` to normalise and commit the result alongside the RFC's implementation PR.
3. Temporarily edit `dev-util/exercism/exercism-3.5.8.ebuild`: change `DESCRIPTION="CLI client for exercism.io - learning programming through practice"` to `DESCRIPTION="TEMP TEST"`. Run `bash scripts/generate-readme-packages.sh --check`.
   - Expected: exit code 1; stderr contains `README.md is out of date.` and a unified diff showing the row for `dev-util/exercism` changing from the original description to `TEMP TEST`. Revert the temporary edit before proceeding.
4. After reverting Step 8.3's edit, run `bash scripts/generate-readme-packages.sh --write`.
   - Expected: exit code 0, no `Updated` line printed (the script prints `Updated …` only when bytes actually changed), `git diff README.md` reports no changes.
5. Temporarily delete the END marker line from `README.md` and run `bash scripts/generate-readme-packages.sh --check`.
   - Expected: exit code 2; stderr contains `Expected exactly 1 END marker line in README.md, found 0`. Restore the marker before proceeding.

#### Step 9 — Verify the workflows on a feature branch

Push the implementation branch to GitHub. Then:

1. On the open PR, confirm that the GitHub Actions tab shows a `Verify Ebuilds / verify-readme` check, and that it passes (or fails with the expected `--check` diff if any ebuild's `DESCRIPTION=` does not match the README region).
2. Confirm that the `Update README` workflow does **not** appear on the PR — it is gated to `push: branches: [main]`.
3. After the PR is merged into `main` via the project's standard merge-commit flow, open the Actions tab and locate the new `Update README` run.
   - Expected outcome A (this RFC's own merge, no drift between seed and ebuilds): the workflow runs, the `Detect change` step sets `updated=false`, and the `Commit and push via GitHub API` step is skipped. The run is green and no commit appears on `main`.
   - Expected outcome B (this RFC's own merge with seed drift, OR a subsequent merge that adds a new package or changes a `DESCRIPTION=` line): the workflow runs, the `Detect change` step sets `updated=true`, the `Commit and push via GitHub API` step creates one commit on `main` with message `docs: regenerate README packages table` authored by `divoxx-bot[bot]`, marked `Verified` by GitHub.

### Validation against requirements

- **R1: README reflects state of `main` at all times.** Covered by Steps 3 + 4. The post-merge workflow runs on every relevant push; the PR-side check prevents merging out-of-date state.
- **R2: Description from authoritative per-package source.** Covered by Step 1 reading `DESCRIPTION=` directly from each package's latest ebuild on disk.
- **R3: No human intervention required.** Covered by Step 3 — the workflow commits via the bot App token. The bot is already configured (used by `auto-update.yml`).
- **R4: Idempotent — bot never loops.** Covered by Step 3's path filter (`**/*.ebuild` only — not `README.md` and not `metadata.xml`) plus the `git diff --quiet README.md` no-op short-circuit.
- **R5: Contributor signal on hand-edit attempts.** Covered by Step 4 — the `verify-readme` job runs `--check` on every non-superseded PR, regardless of which files changed, so a PR that edits only the auto-generated region is still caught.
- **R6: First merge of this RFC leaves the overlay in a consistent state.** Covered by Step 2 — `README.md` is pre-populated with the current ebuild descriptions. Any drift between seed and live ebuilds at merge time is normalised by the first workflow run on `main`, producing at most one small bot commit.

## Risks and open questions

### Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| An ebuild's `DESCRIPTION=` line uses an unexpected quoting style (escaped quotes, line continuations) | Very low | EAPI 8 forbids variable expansion and command substitution in `DESCRIPTION`; `pkgcheck DescriptionCheck` enforces it. The script's grep+sed handles `DESCRIPTION="..."`, `DESCRIPTION='...'`, and unquoted strings. A future violation would be caught by `pkgcheck` before reaching `main`. |
| Bot push to `main` rejected by branch protection | Medium | The bot App must be in the branch protection bypass list. This is already the case (it is used by `auto-update.yml` to push branches and by `verify.yml`'s `promote` step to mark PRs ready). If a future hardening removes that bypass, the workflow will fail noisily; the fix is to re-add the bot to the bypass list or switch to opening a PR. |
| Race between two near-simultaneous merges to `main` | Low | The `concurrency.group: update-readme-main` setting serialises invocations of this workflow only. If another commit lands on `main` between this run's checkout (which fixes `PARENT_SHA`) and its PATCH to `refs/heads/main`, the PATCH fails with a non-fast-forward error and the run fails. The next ebuild merge to `main` retriggers the workflow and succeeds. For a low-traffic overlay this is acceptable. |
| Marker accidentally removed from README during merge conflict resolution | Low | The script's hard assertions (exact-line marker count must equal 1, awk `END` block detects an unclosed block) make the next run fail loudly. Fix is to restore the markers — recoverable from git history. |
| `DESCRIPTION` contains a literal `\|` character | Very low | Script escapes `\|` to `\\|` before emitting the row. |
| `DESCRIPTION` contains a literal backtick | Very low | The atom (left column) is in backticks; the description (right column) is plain text. No backtick escaping needed for current ebuilds; if a future ebuild includes one, markdown renders the substring inside the backticks as a code span — acceptable. |
| Two ebuild files for the same package have differing `DESCRIPTION` lines (e.g. during a version bump) | Possible | Script picks the highest version via `LC_ALL=C sort -V` and uses its `DESCRIPTION`. This is the intended behaviour — the README shows the description of the current/latest version. |
| Version comparison via `sort -V` mis-orders an unusual Gentoo version string (e.g. complex `_pre`/`_p`/`-r` combinations) | Low | `sort -V` handles `_pN` and `-rN` correctly for every version currently used in this overlay. If a future ebuild introduces a version that `sort -V` mis-orders, the failure mode is the README listing a non-latest version's description — caught by the PR-side `--check` job, fixable by switching to portage's `vercmp` in the script. |
| A package directory exists but has no ebuilds (e.g. mid-removal commit) | Low | `find -mindepth 3 -maxdepth 3 -name '*.ebuild'` only matches actual `.ebuild` files. Empty package directories are invisible. |
| Stale entries in `metadata/md5-cache/` (e.g. `media-sound/spotify-player-0.23.0` with no on-disk ebuild) leak into the table | Eliminated | The script no longer reads `metadata/md5-cache/`. Enumeration is from the filesystem ebuild list. |

### Open questions

None. Every design choice has a concrete resolution above. The workflow is small (one script + one workflow + three small workflow edits + two docs edits), the dependencies are already in place (bot App token, CI container), and the failure modes are bounded.

## Relationship to other RFCs

This is the first RFC in `docs/rfcs/` (the directory is otherwise empty). It does not depend on any prior RFC. Future RFCs that add new automated content to `README.md` should reuse the same marker pattern (`<!-- AUTO-GENERATED-<NAME>:START -->` … `:END -->`) and may share the bash region-rewrite logic from `scripts/generate-readme-packages.sh`.
