---
rfc: "2026-05-12-auto-update-readme-on-package-changes"
title: "Auto-update README when packages are added or removed"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-12"
drop_reason: ~
---

## Summary

The Packages table in `README.md` is maintained by hand and already drifts from reality (e.g. `sys-cluster/minikube` exists in the overlay but is missing from the table). This RFC introduces a deterministic generator script (`scripts/generate-readme-packages.sh`) that regenerates the table from each package's latest ebuild. The `/ebuild-create`, `/ebuild-update`, and `/ebuild-remove` skills run this script as part of the PR they open, so the README update is visible in the diff and reviewed alongside the ebuild change. A CI `verify-readme` job fails any PR where the auto-generated region is out of date. No post-merge workflow writes to `main` directly. The README continues to be a regular markdown file — only the region between two HTML-comment markers is owned by the generator.

## Should we do this?

**Yes.** The overlay already runs an autonomous version-bump workflow (`auto-update.yml`) twice a week; PRs land without human prose review of the README. As more packages are added the manual table becomes increasingly likely to fall out of sync, and a stale README is the first thing a user sees. The fix is small: one bash script, skill integration in three places, and two marker comments in the README. The script reads each package's latest ebuild `DESCRIPTION=` line directly from the filesystem (the authoritative source) — no cache regeneration or ebuild sourcing required. Risk surface is contained — the only state the generator owns is a single markdown table region. No autonomous writes to `main` are needed; the README change travels in the same PR as the ebuild change, where it can be reviewed.

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

**Recommendation: skill-integrated `--write` at PR creation time, plus a PR-side `verify-readme` job that fails when the table is out of date.** Each of `/ebuild-create`, `/ebuild-update`, and `/ebuild-remove` runs `scripts/generate-readme-packages.sh --write` and stages the result before opening the PR. The README change is therefore part of the PR diff and is reviewed alongside the ebuild change. The CI check is a safety net for PRs that bypass the skills (e.g. manual ebuild edits). No post-merge writes to `main` are ever performed by this feature.

### Region delimitation in the README

| Option | Pros | Cons |
|--------|------|------|
| HTML comment markers `<!-- AUTO-GENERATED-PACKAGES:START -->` … `:END -->` | Invisible in rendered README; well-known convention (used by Prettier, `cog`, `markdown-table-tools`); robust against surrounding edits | Renders in some older markdown viewers as comments — acceptable |
| Replace the entire `README.md` | Avoids markers | Forfeits all hand-written prose (Usage, Contributing, License) — non-starter |
| Generate a separate `PACKAGES.md` and link from README | Clean separation | Users still see stale list in README unless we also remove the heading there — defeats the goal |

**Recommendation: HTML comment markers** around the existing table heading and contents (heading included, so the generator owns the full block including `## Packages`).

## Drawbacks

- **Marker comments visible in source.** A reader of `README.md`'s raw source sees the comments. They do not render in GitHub or `pandoc`.
- **The PR-side `--check` job adds ~1 minute to PRs.** Acceptable; it runs in the same container as `verify` and is unconditional (every non-superseded PR runs it).
- **Marker drift on hand-edits.** If a contributor accidentally deletes a marker, the generator fails noisily. Acceptable — this is a single-keyed assertion (exact-line match for each marker, count must equal 1).
- **PRs that bypass the skills will fail CI.** A manual PR that edits ebuilds directly without running the generator will fail `verify-readme`. The fix is to run `bash scripts/generate-readme-packages.sh` locally and commit the result — a one-command resolution. This is intentional: the CI failure is the signal that the skill should have been used.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `scripts/generate-readme-packages.sh` | Bash script: enumerate ebuilds from the filesystem, build markdown table from every package's `DESCRIPTION=` line, rewrite the `README.md` region between markers. Supports `--check` mode (exit 1 if README differs) and `--write` (default; rewrite README in place). |
| Modify | `.github/workflows/verify.yml` | Add a `verify-readme` job (after `detect-changes`, parallel to `verify`) that runs `bash scripts/generate-readme-packages.sh --check` on every non-superseded PR and fails the build if the README region is out of date. Update `promote:` to depend on both `verify` and `verify-readme`. |
| Modify | `README.md` | Wrap the existing `## Packages` heading and table in `<!-- AUTO-GENERATED-PACKAGES:START -->` … `<!-- AUTO-GENERATED-PACKAGES:END -->` markers. Add `sys-cluster/minikube` to fix the existing drift. |
| Modify | `.claude/skills/ebuild-create/SKILL.md` | After creating the ebuild files and before opening the PR, run `bash scripts/generate-readme-packages.sh --write` and stage `README.md`. |
| Modify | `.claude/skills/ebuild-update/SKILL.md` | After bumping the ebuild and before opening the PR, run `bash scripts/generate-readme-packages.sh --write` and stage `README.md`. |
| Create | `.claude/skills/ebuild-remove/SKILL.md` | New skill: remove an ebuild and its metadata, run `bash scripts/generate-readme-packages.sh --write`, stage `README.md`, open the PR. |
| Modify | `CLAUDE.md` | Add a one-paragraph note under the agent delegation table stating that the README package list is auto-generated and must not be hand-edited. Add `/ebuild-remove` to the delegation table. |
| Modify | `CONTRIBUTING.md` | Add a note under "Adding a New Package" and a new "Removing a Package" section explaining that the README table is updated by the skills and verified by CI. |

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

Any description drift between this seed and the live ebuilds will be caught by the `verify-readme` CI job on the implementation PR itself, so it can be corrected before merge.

#### Step 3 — Add `verify-readme` job and update `promote` in `.github/workflows/verify.yml`

In `.github/workflows/verify.yml`, make two changes:

**3a.** Insert the following job block immediately before the existing `promote:` job, at the same indentation level as the `verify:` job. The `verify-readme` job runs on every non-superseded PR, regardless of whether `.ebuild` files changed — the check exists specifically to catch PRs that edit the auto-generated region without touching ebuilds, so it must not be gated on `has_changes`:

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

**3b.** In the `promote:` job, replace its existing `needs:` and `if:` lines with the following block. Without `always()`, GitHub Actions cascades a `skipped` result from any `needs` job to this job — so when `should_skip=true` causes both `verify` and `verify-readme` to skip, `promote` is also skipped, correctly preventing promotion without verification:

```yaml
  promote:
    needs: [verify, verify-readme]
    if: |
      startsWith(github.head_ref || github.ref_name, 'auto-update/') &&
      needs.verify.result == 'success' &&
      needs.verify-readme.result == 'success'
```

The rest of `promote:` (its `runs-on`, `steps`, etc.) is unchanged.

#### Step 4 — Integrate README update into `/ebuild-create`, `/ebuild-update`, and `/ebuild-remove`

Each skill opens a PR. Before opening the PR, each skill must regenerate the README. Add the following step to the relevant `SKILL.md` files, in the section that stages files for commit — immediately before the PR-creation step:

**For `/ebuild-create` and `/ebuild-update`** (`.claude/skills/ebuild-create/SKILL.md` and `.claude/skills/ebuild-update/SKILL.md`): add a step after the ebuild and Manifest are staged:

> Run `bash scripts/generate-readme-packages.sh --write` from the overlay root. Stage `README.md` alongside the ebuild files. If the script exits non-zero, surface the error and abort — do not open the PR with a stale README.

**For `/ebuild-remove`** (`.claude/skills/ebuild-remove/SKILL.md`, a new skill defined in Step 5 below): README regeneration is built into the skill's workflow — see that step.

The generator is idempotent: if `DESCRIPTION=` did not change (e.g. a Manifest-only bump), the script runs and exits 0 without modifying `README.md`, and `git diff README.md` is empty — no extra diff noise in the PR.

#### Step 5 — Create `.claude/skills/ebuild-remove/SKILL.md`

Create the file at `.claude/skills/ebuild-remove/SKILL.md`. Full contents:

```markdown
# Ebuild Remove Skill

Remove a package from the overlay, update the README, and open a PR.

## Invocation

`/ebuild-remove <category/name>`

## Behavior

1. Verify the package directory `<category>/<name>/` exists in the overlay root. Abort with a clear error if not.
2. List all files that will be deleted: every `.ebuild`, `metadata.xml`, and `Manifest` under `<category>/<name>/`. Show the list to the user and ask for confirmation before proceeding.
3. Delete the package directory.
4. Run `bash scripts/generate-readme-packages.sh --write` from the overlay root to remove the package's row from the README. Stage `README.md`.
5. Consider whether a portage news item is required — see the newsworthiness rubric in `CONTRIBUTING.md` → "News Items". Packages with installed users (any package in this overlay qualifies) generally warrant a news item when removed. Ask the user: "Does this removal need a news item? (y/n)" If yes, run `/news-add <category/name> <slug>` inline.
6. Stage the deleted files and any news item created.
7. Open a PR with title `remove: <category/name>` and a body that lists the removed files and notes whether a news item was included.

## Rules

- Never remove files outside `<category>/<name>/` and `metadata/news/`.
- Never skip the confirmation step (step 2).
- Always regenerate the README before opening the PR.
- Do not modify any other ebuild or the `metadata/layout.conf`.
```

#### Step 6 — Update `CLAUDE.md`

In `CLAUDE.md`, locate the **Agent Delegation** section. Add the following row to the delegation table immediately after the `ebuild-updater` row:

```markdown
| Remove an existing package | `ebuild-remover` | `/ebuild-remove <category/name>` |
```

Add the following paragraph immediately after the delegation table:

```markdown
**Auto-generated content:** The `## Packages` section of `README.md`, delimited by `<!-- AUTO-GENERATED-PACKAGES:START -->` and `<!-- AUTO-GENERATED-PACKAGES:END -->` markers, is managed by `scripts/generate-readme-packages.sh`. Never hand-edit that region — the skills update it automatically. The `verify-readme` job in `verify.yml` fails any PR whose region is out of date.
```

#### Step 7 — Update `CONTRIBUTING.md`

In `CONTRIBUTING.md`, under "Adding a New Package", immediately after the numbered workflow list, insert:

```markdown
> **Note:** You do not need to edit `README.md`. The `/ebuild-create` skill updates it automatically. If you open a PR manually, run `bash scripts/generate-readme-packages.sh` locally and commit the result — the `verify-readme` CI job will fail the PR if the table is out of date.
```

Add a new section "Removing a Package" after "Adding a New Package":

```markdown
## Removing a Package

Use the `/ebuild-remove <category/name>` skill. It deletes the package directory, removes the row from `README.md`, prompts for a portage news item, and opens the PR.

If you remove a package manually, run `bash scripts/generate-readme-packages.sh` and commit the result before opening the PR.
```

#### Step 8 — Local sanity check (unchanged from original)

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

#### Step 9 — Verify on a feature branch

Push the implementation branch to GitHub. Then:

1. On the open PR, confirm that the GitHub Actions tab shows a `Verify Ebuilds / verify-readme` check, and that it passes (the seeded `README.md` from Step 2 should already match the ebuilds on disk).
2. As an end-to-end test, run `/ebuild-create` or `/ebuild-update` on a package in a separate worktree. Confirm that the resulting PR includes a `README.md` diff with the updated row. Confirm that `verify-readme` passes on that PR without any manual intervention.

### Validation against requirements

- **R1: README reflects state of `main` at all times.** Covered by Step 4 (skills regenerate at PR time) + Step 3 (CI blocks any PR that skips regeneration). PRs that bypass the skills will fail `verify-readme` and cannot merge stale.
- **R2: Description from authoritative per-package source.** Covered by Step 1 reading `DESCRIPTION=` directly from each package's latest ebuild on disk.
- **R3: No autonomous writes to `main`.** Satisfied by design — the skills write the README update into the PR branch before opening the PR. The CI check only fails, never writes.
- **R4: Idempotent — no spurious diffs.** The generator short-circuits (`cmp -s`) when the README is already current, so a `DESCRIPTION=`-unchanged bump produces no README diff in the PR.
- **R5: Contributor signal on hand-edit attempts.** Covered by Step 3 — the `verify-readme` job runs `--check` on every non-superseded PR, regardless of which files changed, so a PR that edits only the auto-generated region by hand is caught.
- **R6: First merge of this RFC leaves the overlay in a consistent state.** Covered by Step 2 — `README.md` is pre-populated with the current ebuild descriptions. The `verify-readme` CI job on the implementation PR itself will catch any drift before merge.

## Risks and open questions

### Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| An ebuild's `DESCRIPTION=` line uses an unexpected quoting style (escaped quotes, line continuations) | Very low | EAPI 8 forbids variable expansion and command substitution in `DESCRIPTION`; `pkgcheck DescriptionCheck` enforces it. The script's grep+sed handles `DESCRIPTION="..."`, `DESCRIPTION='...'`, and unquoted strings. A future violation would be caught by `pkgcheck` before reaching `main`. |
| Marker accidentally removed from README during merge conflict resolution | Low | The script's hard assertions (exact-line marker count must equal 1, awk `END` block detects an unclosed block) make the next CI run fail loudly. Fix is to restore the markers — recoverable from git history. |
| Skill bypassed by a manual PR | Low | `verify-readme` catches this at CI time. The contributor sees a clear error message and a one-command fix. No data is lost; the PR simply cannot merge until the README is current. |
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
