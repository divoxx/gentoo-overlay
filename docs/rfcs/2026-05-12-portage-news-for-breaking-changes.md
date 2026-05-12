---
rfc: "2026-05-12-portage-news-for-breaking-changes"
title: "Portage news items for breaking changes and high-care updates"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-12"
drop_reason: ~
---

## Summary

Add a GLEP 42 portage news system to `divoxx-overlay` so users syncing the overlay see operator-readable notices for breaking changes and updates that require manual care. News items live under `metadata/news/<YYYY-MM-DD>-<slug>/` and are delivered to users automatically by Portage after `emaint sync -r divoxx-overlay`. News creation is human-authored, not bot-authored: the `ebuild-updater` agent flags candidate updates as newsworthy in the auto-update PR, and a separate `/news-add` skill lets the maintainer write the item by hand. News items are committed unsigned (Portage does not enforce GLEP 42 signing for third-party overlays). A lightweight pkgcheck-style linter (`scripts/news-lint.sh`) runs in CI to catch malformed news items before merge.

## Should we do this?

**Yes.** Three concrete drivers:

1. **Existing risk surface.** The overlay already ships packages where breaking changes are plausible: `app-containers/devpod` (config format changes between minor versions), Go and Rust binaries where CLI flags or daemon protocols can change, `dev-util/worktrunk` which is pre-1.0 (any minor bump can break). Today, users discover breakage only by running the new version.
2. **Cost is small and bounded.** News items are flat text files. The format is fully specified by GLEP 42. Portage already handles delivery — no new infrastructure to operate.
3. **It scales with the overlay's automation strategy.** Auto-update PRs already fetch upstream release notes (`auto-update.yml` writes `/tmp/pr-changelog.txt`). Extending the agent to flag newsworthy-looking release notes adds one classification step to existing work.

The alternative — relying on users to read GitHub release notes themselves — does not work in practice for a Gentoo overlay. Users sync, emerge, and only notice breakage after the fact.

## Current state

### What exists today

- Overlay name `divoxx-overlay`, EAPI 8, `~amd64` only, masters = gentoo.
- `metadata/layout.conf` declares thin manifests with `sign-manifests = false`. No `metadata/news/` directory exists.
- Two ways changes land:
  - **Manual PR** — human writes the PR, runs `bash scripts/verify-ebuild.sh <atom>`, opens the PR.
  - **Automated PR** — `auto-update.yml` runs the `ebuild-updater` Claude agent on a schedule (Sundays and Wednesdays 06:20 UTC). The agent bumps the version, regenerates the Manifest, fetches release notes into `/tmp/pr-changelog.txt`, and opens a draft PR via the bot identity (`divoxx-bot[bot]`). The PR is promoted to ready when `verify.yml` passes.
- `verify.yml` runs `pkgcheck scan` + `ebuild ... compile install` for every changed ebuild. It does not scan anything under `metadata/news/`.
- `debug-ci-failure.yml` plus the `ci-debugger` agent auto-fixes failures on auto-update branches.
- Bot identity: `divoxx-bot[bot]` via a GitHub App. The bot has a `BOT_APP_ID` secret and `BOT_APP_PRIVATE_KEY`. GitHub-API-authored commits are auto-signed via GitHub's web flow (shows as Verified), but the bot does not hold a PGP key.
- Maintainer identity: Rodrigo Kochenburger, `divoxx@gmail.com`. The maintainer has a personal PGP key but does not push directly from CI.

### What is missing

- No mechanism to deliver "you must do X before installing this update" messages to users.
- No place to record historical breaking changes for users who skipped versions.
- No CI guard against malformed news items, broken `Display-If-Installed` atoms, or wrong date strings.
- No documented decision rule for "is this update newsworthy?".

### Constraints inherited from GLEP 42

- News items must live under `metadata/news/<YYYY-MM-DD>-<slug>/`.
- Each item is a directory containing at least one `.txt` file. Translations are optional sibling files (`<slug>.<lang>.txt`); this RFC ships English-only.
- File must be UTF-8 with `\n` line endings, ASCII headers, lines no longer than 79 chars in the body (recommended, not enforced by Portage).
- Required headers: `Title`, `Author`, `Content-Type` (always `text/plain`), `Posted` (`YYYY-MM-DD`), `Revision` (integer, starts at 1, increments on edits).
- Optional headers: `News-Item-Format` (defaults to `1.0`; `2.0` permits non-strict bodies — we use `1.0`), `Display-If-Installed`, `Display-If-Profile`, `Display-If-Keyword`. All `Display-If-*` headers can appear multiple times; conditions are OR-within-header, AND-across-headers.
- GLEP 42 specifies `.asc` detached signatures for items in the *Gentoo* repository. Portage itself does not verify signatures and `eselect news` does not block unsigned items. For third-party overlays, signing is optional. We omit signing.

### How news reaches users

Once committed and pushed to `main`, the news item ships with the overlay. The user-facing flow:

1. User runs `emaint sync -r divoxx-overlay` (or `emerge --sync` if the overlay is in their `repos.conf` with `auto-sync = yes`).
2. Portage updates the local overlay tree, including any new files under `metadata/news/`.
3. Portage compares the items against the user's read history at `/var/lib/gentoo/news/news-divoxx-overlay.unread`. New items that satisfy all `Display-If-*` filters are appended.
4. Next `emerge` invocation prints a banner: `* IMPORTANT: N news items need reading for repository 'divoxx-overlay'.`
5. User runs `eselect news list -r divoxx-overlay` to see the list and `eselect news read <number>` to display one. After reading, the item moves to `news-divoxx-overlay.read`.

The overlay maintainer's job ends at "committed and pushed." Everything from step 2 onward is automatic.

## Analysis / Options

Three distinct design questions, each with a recommendation. The space of "do nothing" is the alternative for each.

### Question 1 — Who authors the news item?

**Recommendation: maintainer authors; the bot only flags.**

The `ebuild-updater` agent identifies newsworthiness during auto-update and writes a hint into the PR description. The maintainer writes the actual news item by hand (or with `/news-add`) before merging the PR.

Rationale: newsworthiness is a judgement call about user impact, not a mechanical property of a version bump. Examples that look the same at the version level but differ at the user level:

- `worktrunk` 0.42.x → 0.43.0: looks like a normal minor bump. Release notes say "config file path moved from `~/.config/worktrunk` to XDG_CONFIG_HOME". Newsworthy.
- `worktrunk` 0.43.0 → 0.43.1: patch bump, no behavioural change. Not newsworthy.
- `worktrunk` 0.43.1 → 0.49.0: large version jump but every intermediate release was internal refactoring. Probably not newsworthy.

Letting the bot author the item invites two failure modes: (a) noise — news for every breaking-looking but actually-fine release, training users to ignore news; (b) silent miss — bot doesn't notice a change that the release notes failed to highlight. A human-in-the-loop approach catches both. The bot's job is to surface candidates loudly in the PR body so the maintainer doesn't miss them.

Door stays open: if the agent's classification proves reliable over time, we can promote it from "flag in PR" to "draft a news item in the PR" without changing file layout. The decision is reversible.

### Question 2 — Signing strategy

**Recommendation: do not sign news items.**

GLEP 42 requires `.asc` signatures for the *official Gentoo tree*. Portage does not enforce signatures for third-party overlays — `eselect news` and Portage's news delivery path read `.txt` files unconditionally and do not verify `.asc` even when present. (Portage's news loader globs `*.txt` and ignores sibling `.asc` files for non-Gentoo repos.)

For a single-maintainer overlay:

- The bot has no PGP key and creating one for an automated identity raises its own questions (where to store, how to rotate, how to revoke).
- The maintainer's personal key is not on the CI runner.
- Signing only the maintainer-authored items would create two classes of news with no consumer ever checking the difference.

We document in `CONTRIBUTING.md` that news items are unsigned and that this is acceptable per GLEP 42 for third-party overlays. If a future scenario demands signing (e.g. multi-maintainer governance), the door stays open: signatures are additive and can be added without breaking existing items.

### Question 3 — Newsworthiness criteria

**Recommendation: a short, written rubric in `CONTRIBUTING.md`.** The rubric is also embedded in the `ebuild-updater` agent prompt so it can apply the same criteria when flagging.

An update is newsworthy when at least one of the following is true for users of any installed version:

1. **Config / state migration required.** Config file format changed, config path moved, on-disk state schema changed, or a one-time migration command must be run.
2. **Breaking CLI or API change.** A flag, subcommand, environment variable, exit code, or protocol changed in a way that breaks scripts or downstream callers.
3. **Removed or renamed USE flag.** A user-facing USE flag was removed or renamed in this overlay.
4. **Renamed or removed package.** A package was renamed, moved between categories, or removed.
5. **Security-relevant default change.** A security-relevant default changed (e.g. TLS verification disabled by default → enabled, or a credential store moved).
6. **Cross-package implication.** A bump in one package requires action on a different package the user has installed (e.g. plugin ABI break).

Mere "new features" or "performance improvement" are not newsworthy by themselves. Patch bumps are presumed not newsworthy unless they revert or introduce one of the above.

### Drawbacks

- **Maintainer burden.** Every newsworthy update needs a hand-written item. Real cost but bounded — most updates are not newsworthy, and the rubric keeps the bar high.
- **Bot-authored hints can be wrong.** False positives create noise in PRs (the maintainer ignores the hint); false negatives miss a real breaking change. The mitigation is the rubric being explicit and the linter catching structural problems, not the agent being perfect.
- **No signatures.** Anyone with commit access can ship a news item. For a single-maintainer overlay this is the same trust surface as the ebuilds themselves; not a regression. If the threat model later changes, signing can be added without breaking existing items.
- **News items are a one-way channel.** Users see them once via `eselect news read` and they are gone from the default view. A user who skips reading news can still be surprised. There is no way to "force" news consumption short of FEATURES-controlled blocking, which is out of scope for an overlay.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `metadata/news/.gitkeep` | Force the directory to exist in git even when empty |
| Create | `scripts/news-lint.sh` | Validate every news item under `metadata/news/` for GLEP 42 conformance and overlay rules |
| Create | `scripts/news-new.sh` | Scaffold a new news item directory + `.txt` from arguments |
| Create | `.claude/skills/news-add/SKILL.md` | Skill entrypoint: `/news-add <category/name> [slug]` that runs the scaffolder, opens the file for editing, and prompts the user for the body |
| Create | `.github/workflows/news-lint.yml` | CI workflow that runs `scripts/news-lint.sh` on every PR that touches `metadata/news/` and on every push to `main` |
| Modify | `CONTRIBUTING.md` | Add a "News Items" section: when to write one, the rubric, how to file one (the skill), the unsigned-overlay note |
| Modify | `CLAUDE.md` | Add `/news-add` to the Agent Delegation table |
| Modify | `.claude/agents/ebuild-updater.md` | Add step "10 Classify newsworthiness" between Write Changelog and Report Results; write the verdict and rationale into `/tmp/pr-newsworthy.txt` |
| Modify | `.github/workflows/auto-update.yml` | After the agent runs, read `/tmp/pr-newsworthy.txt` if present and prepend a "News review needed" header to the PR body |

No existing ebuilds, manifests, or `metadata/layout.conf` are touched. `metadata/news/` is a peer of `metadata/md5-cache/` and `metadata/layout.conf` — no `layout.conf` change is required for Portage to find news items; it discovers them by convention. `verify.yml` is not modified — the new `news-lint.yml` is an independent workflow with its own `paths` filter; branch protection adding it as a required check is a one-time UI configuration outside the scope of this RFC's code changes.

### Steps

Steps are ordered for incremental landability. Each step is independently mergeable.

#### Step 1 — Add the news directory placeholder and CONTRIBUTING update

Files: `metadata/news/.gitkeep`, `CONTRIBUTING.md`.

1. Create an empty file at `metadata/news/.gitkeep` (content: zero bytes). The presence of `.gitkeep` keeps the directory in git.
2. Append a new top-level section to `CONTRIBUTING.md` after the "Quality Gates" section and before "Commit Messages":

~~~markdown
## News Items

This overlay uses [GLEP 42](https://www.gentoo.org/glep/glep-0042.html) portage news to notify users of breaking changes. News items live under `metadata/news/<YYYY-MM-DD>-<slug>/` and are delivered to users automatically after `emaint sync -r divoxx-overlay`. Users read them with `eselect news read` or see a banner on the next `emerge`.

### When to write a news item

Write a news item when at least one of the following is true for users of any currently installed version:

1. **Config or state migration required** — config file format changed, path moved, on-disk schema changed, or a one-time command must be run.
2. **Breaking CLI or API change** — a flag, subcommand, environment variable, exit code, or protocol changed in a way that breaks user scripts or downstream callers.
3. **Removed or renamed USE flag** — a user-facing USE flag was removed or renamed in this overlay.
4. **Renamed or removed package** — a package was renamed, moved between categories, or removed.
5. **Security-relevant default change** — a security-relevant default changed.
6. **Cross-package implication** — a bump in one package requires action on a different installed package.

New features and pure performance improvements are not newsworthy. Patch bumps are presumed not newsworthy unless they introduce or revert one of the above.

### How to write a news item

Use the `/news-add <category/name> [slug]` skill (Claude Code) or run the scaffolder directly:

```bash
bash scripts/news-new.sh <category/name> <short-slug>
```

This creates `metadata/news/<YYYY-MM-DD>-<slug>/<YYYY-MM-DD>-<slug>.txt` pre-populated with the required headers. Edit the body, then commit the file in the same PR as the ebuild change that requires it. The `news-lint` CI job validates the item on every PR.

### `Display-If-Installed` restriction

This overlay's linter currently accepts only bare `category/name` atoms in the `Display-If-Installed` header — full GLEP 42 dependency atoms with version operators (e.g. `>=app-containers/devpod-0.4.0`, `<cat/pkg-1.2`) are **not** supported. Rationale: bare atoms are simpler to validate (a `category/name` directory must exist in the overlay) and cover every news item authored to date. If a version-bounded notice is ever needed, relax the linter and document the syntax in this section. The linter will reject any non-bare atom with a clear error pointing here.

### Signing

News items in this overlay are **not** GPG-signed. GLEP 42 requires signatures only for the official Gentoo tree; Portage does not verify signatures for third-party overlays. This is intentional and acceptable for a single-maintainer overlay.
~~~

3. No other CONTRIBUTING changes in this step.
4. Commit message: `docs: add news item authoring guide to CONTRIBUTING`.

Expected post-state: `metadata/news/` exists, CONTRIBUTING has a "News Items" section.

#### Step 2 — Scaffolder script

File: `scripts/news-new.sh`.

Create the script with the following exact contents:

```bash
#!/usr/bin/env bash
# news-new.sh — Scaffold a GLEP 42 news item for divoxx-overlay.
#
# Usage:
#   news-new.sh <category/name> <slug>
#   news-new.sh app-containers/devpod config-format-change
#
# Creates: metadata/news/<YYYY-MM-DD>-<slug>/<YYYY-MM-DD>-<slug>.txt
# Pre-populates GLEP 42 headers. The user fills in the body.
# Prints the path of the created file on success.

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -eq 2 ]] || die "Usage: $0 <category/name> <slug>"

ATOM="$1"
SLUG="$2"
CATEGORY="${ATOM%%/*}"
NAME="${ATOM##*/}"

[[ "$CATEGORY" != "$ATOM" && -n "$CATEGORY" && -n "$NAME" ]] || \
    die "Invalid atom '$ATOM'. Expected category/name (e.g. app-containers/devpod)"

# Slug rule: lowercase ASCII letters, digits, and hyphens; 3..40 chars;
# must start and end with a letter or digit; no consecutive hyphens.
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$ ]] || \
    die "Invalid slug '$SLUG'. Use lowercase letters, digits, hyphens; 3..40 chars; must start and end with a letter or digit."
[[ "$SLUG" =~ -- ]] && die "slug must not contain consecutive hyphens: $SLUG"

# Locate overlay root (same logic as verify-ebuild.sh).
find_overlay_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/profiles/repo_name" ]] && { echo "$dir"; return 0; }
        dir="$(dirname "$dir")"
    done
    return 1
}

OVERLAY_ROOT=$(find_overlay_root "$PWD") || die "Could not locate overlay root"

# Verify the target package directory exists. This guards against typos —
# Display-If-Installed pointing at a nonexistent overlay package is a CI
# failure later, but failing early is friendlier.
[[ -d "$OVERLAY_ROOT/$CATEGORY/$NAME" ]] || \
    die "Package directory not found: $OVERLAY_ROOT/$CATEGORY/$NAME"

DATE=$(date -u +%Y-%m-%d)
DIR="$OVERLAY_ROOT/metadata/news/${DATE}-${SLUG}"
FILE="$DIR/${DATE}-${SLUG}.txt"

[[ ! -e "$DIR" ]] || die "News item already exists: $DIR"

mkdir -p "$DIR"

cat > "$FILE" <<EOF
Title: <one-line summary, max 79 chars>
Author: Rodrigo Kochenburger <divoxx@gmail.com>
Content-Type: text/plain
Posted: ${DATE}
Revision: 1
News-Item-Format: 1.0
Display-If-Installed: ${CATEGORY}/${NAME}

<Replace this paragraph with what changed and why the user needs to act.>

<Optional: include a "How to migrate" section with exact commands.>

<Optional: link to upstream release notes or migration guide.>
EOF

echo "$FILE"
```

5. `chmod +x scripts/news-new.sh`.
6. Commit message: `chore: add scripts/news-new.sh to scaffold news items`.

Sanity check (run locally, not part of the commit):

```bash
bash scripts/news-new.sh app-containers/devpod test-slug
# Expected output: <overlay>/metadata/news/2026-05-12-test-slug/2026-05-12-test-slug.txt
# Then: rm -rf metadata/news/2026-05-12-test-slug
```

#### Step 3 — Linter script

File: `scripts/news-lint.sh`.

Create the script with the following exact contents:

```bash
#!/usr/bin/env bash
# news-lint.sh — Validate GLEP 42 news items in this overlay.
#
# Usage:
#   news-lint.sh                 # scan all items under metadata/news/
#   news-lint.sh path/to/item.txt  # scan a single file
#
# Exits 0 if all items pass, 1 on any failure. Prints a per-item report.

set -euo pipefail

die()  { echo "ERROR: $*" >&2; exit 1; }
fail() { echo "  FAIL: $*"; FAILS=$((FAILS+1)); }
pass() { echo "  ok:   $*"; }

REQUIRED_HEADERS=(Title Author Content-Type Posted Revision)
ALLOWED_HEADERS=(Title Author Translator Content-Type Posted Revision \
    News-Item-Format Display-If-Installed Display-If-Keyword Display-If-Profile)

# Locate overlay root.
find_overlay_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/profiles/repo_name" ]] && { echo "$dir"; return 0; }
        dir="$(dirname "$dir")"
    done
    return 1
}

OVERLAY_ROOT=$(find_overlay_root "$PWD") || die "Could not locate overlay root"
NEWS_DIR="$OVERLAY_ROOT/metadata/news"

# Collect files to scan.
if [[ $# -ge 1 ]]; then
    FILES=("$@")
else
    if [[ ! -d "$NEWS_DIR" ]]; then
        echo "No metadata/news/ directory — nothing to lint."
        exit 0
    fi
    mapfile -t FILES < <(find "$NEWS_DIR" -mindepth 2 -maxdepth 2 -name '*.txt' | sort)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No news items found — nothing to lint."
    exit 0
fi

FAILS=0
ITEM_RE='^([0-9]{4})-([0-9]{2})-([0-9]{2})-[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'

for FILE in "${FILES[@]}"; do
    # Reset per-iteration state unconditionally at the top so prior-iteration
    # data cannot leak in via early `continue` paths that skip cleanup.
    unset SEEN VALUES
    declare -A SEEN=()
    declare -A VALUES=()

    [[ -f "$FILE" ]] || { fail "$FILE: not a regular file"; continue; }
    echo
    echo "Linting: $FILE"

    # 1. Directory and file naming.
    DIR=$(dirname "$FILE")
    DIR_BASE=$(basename "$DIR")
    FILE_BASE=$(basename "$FILE" .txt)

    if [[ "$DIR_BASE" =~ $ITEM_RE ]] && [[ ! "$DIR_BASE" =~ -- ]]; then
        pass "directory name matches YYYY-MM-DD-<slug>"
    else
        fail "directory name '$DIR_BASE' does not match YYYY-MM-DD-<slug> (slug: 3..40 chars, no leading/trailing or consecutive hyphens)"
    fi

    if [[ "$FILE_BASE" == "$DIR_BASE" ]]; then
        pass "filename matches directory"
    else
        fail "filename '$FILE_BASE.txt' does not match directory '$DIR_BASE'"
    fi

    # 2. Encoding: UTF-8, LF line endings, no CRLF.
    if grep -q $'\r' "$FILE"; then
        fail "file contains CR (\\r) — must be LF-only"
    else
        pass "LF line endings"
    fi

    if iconv -f UTF-8 -t UTF-8 "$FILE" >/dev/null 2>&1; then
        pass "valid UTF-8"
    else
        fail "not valid UTF-8"
    fi

    # 3. Separate header block from body. First blank line is the boundary.
    if ! grep -q '^$' "$FILE"; then
        fail "no blank line separating headers from body"
        continue
    fi

    HEADER_BLOCK=$(awk '/^$/ {exit} {print}' "$FILE")
    BODY_BLOCK=$(awk 'found {print} /^$/ {found=1}' "$FILE")

    # 4. Header presence and format.
    while IFS= read -r LINE; do
        [[ -z "$LINE" ]] && continue
        if [[ "$LINE" =~ ^([A-Za-z-]+):[[:space:]]*(.*)$ ]]; then
            H="${BASH_REMATCH[1]}"
            V="${BASH_REMATCH[2]}"
            # Trim trailing whitespace from the captured value so downstream
            # comparisons (Content-Type, Posted, Revision) aren't fooled by
            # an author who left stray spaces after the value.
            V="${V%"${V##*[![:space:]]}"}"
            # Multi-valued: Display-If-* may repeat. Others must not.
            if [[ "$H" == Display-If-* ]]; then
                VALUES["${H}__${SEEN[$H]:-0}"]="$V"
                SEEN["$H"]=$(( ${SEEN[$H]:-0} + 1 ))
            else
                if [[ -n "${SEEN[$H]:-}" ]]; then
                    fail "duplicate header: $H"
                fi
                SEEN["$H"]=1
                VALUES["$H"]="$V"
            fi
        else
            fail "malformed header line: $LINE"
        fi
    done <<< "$HEADER_BLOCK"

    # 5. Required headers present.
    for H in "${REQUIRED_HEADERS[@]}"; do
        if [[ -n "${SEEN[$H]:-}" ]]; then
            pass "required header present: $H"
        else
            fail "missing required header: $H"
        fi
    done

    # 6. No unknown headers.
    for H in "${!SEEN[@]}"; do
        OK=0
        for A in "${ALLOWED_HEADERS[@]}"; do
            [[ "$A" == "$H" ]] && { OK=1; break; }
        done
        [[ $OK -eq 1 ]] || fail "unknown header: $H"
    done

    # 7. Content-Type must be text/plain.
    if [[ "${VALUES[Content-Type]:-}" == "text/plain" ]]; then
        pass "Content-Type is text/plain"
    else
        fail "Content-Type must be exactly 'text/plain', got '${VALUES[Content-Type]:-<missing>}'"
    fi

    # 8. Posted matches the directory date prefix.
    if [[ "$DIR_BASE" =~ $ITEM_RE ]]; then
        DIR_DATE="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
        if [[ "${VALUES[Posted]:-}" == "$DIR_DATE" ]]; then
            pass "Posted matches directory date"
        else
            fail "Posted header '${VALUES[Posted]:-<missing>}' does not match directory date '$DIR_DATE'"
        fi
    fi

    # 9. Revision must be a positive integer.
    if [[ "${VALUES[Revision]:-}" =~ ^[1-9][0-9]*$ ]]; then
        pass "Revision is a positive integer"
    else
        fail "Revision must be a positive integer, got '${VALUES[Revision]:-<missing>}'"
    fi

    # 10. Each Display-If-Installed atom must point at a real package in this overlay.
    COUNT=${SEEN[Display-If-Installed]:-0}
    if [[ $COUNT -gt 0 ]]; then
        for ((i=0; i<COUNT; i++)); do
            ATOM="${VALUES[Display-If-Installed__$i]}"
            if [[ ! "$ATOM" =~ ^[a-z0-9][a-z0-9+_.-]*/[a-zA-Z0-9][a-zA-Z0-9+_.-]*$ ]]; then
                fail "Display-If-Installed: only bare 'category/name' atoms are supported (version operators not yet implemented); got: $ATOM"
                continue
            fi
            if [[ -d "$OVERLAY_ROOT/$ATOM" ]]; then
                pass "Display-If-Installed package exists: $ATOM"
            else
                fail "Display-If-Installed points at unknown package: $ATOM"
            fi
        done
    fi

    # 11. Body is non-empty.
    if [[ -z "$(echo "$BODY_BLOCK" | tr -d '[:space:]')" ]]; then
        fail "news item body is empty"
    else
        pass "body is non-empty"
    fi

    # 12. No placeholder strings left over from the scaffolder (anywhere in the
    # file — Title placeholder lives in the header block, body placeholders
    # in the body block).
    if grep -qE '<(Replace|Optional|one-line)' "$FILE"; then
        fail "file still contains scaffolder placeholders (<Replace...>, <Optional...>, <one-line...>)"
    else
        pass "no scaffolder placeholders"
    fi
done

echo
if [[ $FAILS -gt 0 ]]; then
    echo "FAIL: $FAILS lint failure(s)"
    exit 1
fi
echo "OK: all news items pass"
```

7. `chmod +x scripts/news-lint.sh`.
8. Sanity check locally before commit:

```bash
# With no news items it should succeed:
bash scripts/news-lint.sh
# Expected: "No news items found — nothing to lint."

# Scaffold a test item and lint it:
bash scripts/news-new.sh app-containers/devpod test-slug
bash scripts/news-lint.sh
# Expected: FAIL (scaffolder placeholders, empty body) — proves the linter rejects un-edited stubs.
# Clean up:
rm -rf metadata/news/$(date -u +%Y-%m-%d)-test-slug
```

9. Commit message: `chore: add scripts/news-lint.sh for GLEP 42 news validation`.

#### Step 4 — News lint CI workflow

File: `.github/workflows/news-lint.yml`.

Create the workflow with the following exact contents:

```yaml
name: News Lint

on:
  pull_request:
    types: [opened, synchronize, reopened]
  push:
    branches:
      - main

concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.ref_name }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  news-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Verify iconv is available
        run: |
          set -euo pipefail
          command -v iconv >/dev/null || { echo "iconv missing"; exit 1; }

      - name: Run news lint
        run: |
          set -euo pipefail
          bash scripts/news-lint.sh
```

10. The workflow runs on Ubuntu (no Gentoo container needed — the linter is pure bash + iconv + grep, all present on `ubuntu-latest`). The workflow runs on every PR (no `paths:` filter) so that, if it is configured as a required status check, PRs that touch no news files still receive the required status — the linter exits 0 in roughly five seconds when `metadata/news/` is empty, so the cost is negligible.
11. Commit message: `ci: add news-lint workflow`.

Branch-protection follow-up (documentation only — outside this RFC's code changes): after the workflow lands and produces at least one successful run on `main`, add `news-lint / news-lint` to the required-status-checks list for `main` via repository Settings → Branches → Branch protection rules. This is a one-time UI configuration.

#### Step 5 — Update the ebuild-updater agent to flag newsworthiness

File: `.claude/agents/ebuild-updater.md`.

Insert a new step 10 between the existing step 9 ("Write Changelog") and the previously-numbered step 10 ("Report Results"), and renumber the existing "Report Results" step from 10 to 11. Insert at the position immediately after the existing `### 9. Write Changelog` subsection ends and before `### 10. Report Results` (which becomes `### 11. Report Results`) begins. The exact insertion follows — note the use of `~~~` fences in the inserted prose to avoid clashing with the outer ` ``` ` fence in this RFC:

```markdown
### 10. Classify Newsworthiness

After writing the changelog (or determining there is none), classify whether this update is **newsworthy** per `CONTRIBUTING.md` → "News Items" → "When to write a news item".

Write the classification to `/tmp/pr-newsworthy.txt` as exactly one of:

~~~
NEWSWORTHY
<one-paragraph rationale: which rule(s) the update triggers, and what user action is required>
~~~

~~~
NOT_NEWSWORTHY
<one-line rationale, e.g. "patch bump, internal refactor only">
~~~

~~~
UNKNOWN
release notes unavailable — maintainer should inspect upstream and decide
~~~

The first line of the file MUST be exactly `NEWSWORTHY`, `NOT_NEWSWORTHY`, or `UNKNOWN`. Subsequent lines are free-form rationale. The auto-update workflow reads only the first line for branching and pipes the rest into the PR body verbatim.

**Rules for choosing NEWSWORTHY:**

1. **Config or state migration required** — config file format changed, path moved, on-disk schema changed, or a one-time command must be run.
2. **Breaking CLI or API change** — a flag, subcommand, environment variable, exit code, or protocol changed in a way that breaks user scripts.
3. **Removed or renamed USE flag.**
4. **Renamed or removed package.**
5. **Security-relevant default change.**
6. **Cross-package implication.**

Be conservative — when in doubt, mark `NEWSWORTHY` and let the human decide. Do **not** write the news item yourself — the maintainer authors it with `/news-add`.

Do not skip writing the file. The auto-update workflow reads it and adjusts the PR body accordingly. If the file is absent, the workflow defaults to no newsworthy block.
```

12. Commit message: `feat(ebuild-updater): classify newsworthiness of upstream bumps`.

#### Step 6 — Wire the auto-update workflow to surface the newsworthy hint

File: `.github/workflows/auto-update.yml`.

Modify the "Open draft PR" step so it reads `/tmp/pr-newsworthy.txt` and prepends a "News review needed" block to the PR body when the classification is `NEWSWORTHY` or `UNKNOWN`. The full replacement block — substituting the existing body-construction logic from `CHANGELOG=""` through the `gh pr create` invocation — is:

```bash
          CHANGELOG=""
          if [ -f /tmp/pr-changelog.txt ]; then
            CHANGELOG=$(cat /tmp/pr-changelog.txt)
          fi

          NEWSWORTHY_BLOCK=""
          if [ -f /tmp/pr-newsworthy.txt ]; then
            VERDICT=$(head -1 /tmp/pr-newsworthy.txt)
            RATIONALE=$(tail -n +2 /tmp/pr-newsworthy.txt)
            # Guard against an agent that wrote only the verdict line with no
            # rationale — an empty RATIONALE would render as a single "> " in
            # the alert block below, producing a malformed quote.
            if [ -z "$RATIONALE" ]; then
              RATIONALE="(no additional rationale)"
            fi
            case "$VERDICT" in
              NEWSWORTHY)
                QUOTED_RATIONALE=$(echo "$RATIONALE" | sed 's/^/> /')
                NEWSWORTHY_BLOCK=$(printf '> [!IMPORTANT]\n> **News item review needed.** The ebuild-updater agent flagged this bump as potentially newsworthy:\n>\n%s\n>\n> Before merging, decide whether to add a news item using `/news-add %s <slug>` (or skip if the agent over-flagged).' \
                  "$QUOTED_RATIONALE" "$PACKAGE")
                ;;
              UNKNOWN)
                NEWSWORTHY_BLOCK=$(printf '> [!NOTE]\n> The ebuild-updater agent could not classify newsworthiness for this bump (no release notes). Maintainer should inspect upstream and decide whether a news item is needed.')
                ;;
              NOT_NEWSWORTHY|*)
                NEWSWORTHY_BLOCK=""
                ;;
            esac
          fi

          # Compose body: newsworthy block first, then header, then optional changelog, then footer.
          BODY_HEADER="Automated upstream version bump for \`$PACKAGE\`."
          BODY_FOOTER=$(printf '%s\n\n%s' \
            "Verification will run automatically via the verify workflow. The PR will be promoted from draft to ready when all checks pass." \
            "Generated with [Claude Code](https://claude.com/claude-code)")

          if [ -n "$NEWSWORTHY_BLOCK" ] && [ -n "$CHANGELOG" ]; then
            BODY=$(printf '%s\n\n%s\n\n## What changed\n\n%s\n\n%s' \
              "$NEWSWORTHY_BLOCK" "$BODY_HEADER" "$CHANGELOG" "$BODY_FOOTER")
          elif [ -n "$NEWSWORTHY_BLOCK" ]; then
            BODY=$(printf '%s\n\n%s\n\n%s' "$NEWSWORTHY_BLOCK" "$BODY_HEADER" "$BODY_FOOTER")
          elif [ -n "$CHANGELOG" ]; then
            BODY=$(printf '%s\n\n## What changed\n\n%s\n\n%s' "$BODY_HEADER" "$CHANGELOG" "$BODY_FOOTER")
          else
            BODY=$(printf '%s\n\n%s' "$BODY_HEADER" "$BODY_FOOTER")
          fi

          gh pr create \
            --draft \
            --title "auto-update: $PACKAGE" \
            --body "$BODY" \
            --base main \
            --head "$BRANCH" \
            --repo "$REPO"
```

13. The four-arm `if/elif/elif/else` handles every combination of (newsworthy block present, changelog present). No other change to `auto-update.yml`.
14. The `case` arm `NOT_NEWSWORTHY|*` is intentional: the `|*` catch-all ensures any unexpected verdict (or empty file) collapses to "no block." Pre-existing PRs continue to render the same way they did before this change when `/tmp/pr-newsworthy.txt` is absent.
15. Commit message: `ci: surface newsworthiness classification in auto-update PR body`.

#### Step 7 — `/news-add` skill

File: `.claude/skills/news-add/SKILL.md`.

Create with these exact contents:

~~~markdown
# News Add Skill

Scaffold and edit a GLEP 42 portage news item for divoxx-overlay.

## Invocation

`/news-add <category/name> [slug]`

- `<category/name>`: the package atom this news item is about. Used as `Display-If-Installed` so only users with this package installed see the item.
- `[slug]`: optional short kebab-case identifier for the file name. If omitted, prompt the user for one. Slug rule: lowercase letters/digits/hyphens, 3..40 chars, must start and end with a letter or digit, no consecutive hyphens.

## Behavior

1. Verify the working directory is inside divoxx-overlay (locate `profiles/repo_name` walking up from `$PWD`).
2. If no slug was provided, ask the user for one. Validate it against `^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$` (and reject consecutive hyphens) before proceeding.
3. Run `bash scripts/news-new.sh <category/name> <slug>` and capture the printed path in a variable `FILE`.
4. Read the scaffolded file. Show the user the current contents.
5. Ask the user for:
   - **Title** (one line, max 79 chars).
   - **What changed** (one paragraph describing the breaking change or required action).
   - **Migration steps** (optional — commands or instructions).
   - **References** (optional — URLs to upstream release notes or migration guides).
6. Replace the placeholders in the file using the Edit tool:
   - `<one-line summary, max 79 chars>` → user-provided title.
   - The line `<Replace this paragraph with what changed and why the user needs to act.>` → user-provided "What changed" paragraph.
   - The line `<Optional: include a "How to migrate" section with exact commands.>` → user-provided migration steps if any, otherwise delete the line entirely.
   - The line `<Optional: link to upstream release notes or migration guide.>` → user-provided references if any, otherwise delete the line entirely.
7. Run `bash scripts/news-lint.sh "$FILE"` to validate the single item.
8. If lint fails, show the user the failures and ask whether to retry (re-prompt for the failing fields) or open the file for manual editing.
9. On lint success, print the file path and remind the user to `git add` and commit it as part of the same PR as the change that requires the notice.

## Rules

- Do **not** sign the news item — this overlay does not use GPG signatures.
- Do **not** create the file outside `metadata/news/`.
- Do **not** modify any other news item.
- Do **not** invent additional headers beyond what the scaffolder provides.
- Do **not** edit `scripts/news-new.sh` or `scripts/news-lint.sh` from inside this skill.
~~~

16. Commit message: `feat: add /news-add skill for authoring news items`.

#### Step 8 — Update CLAUDE.md delegation table

File: `CLAUDE.md`.

Modify the Agent Delegation table at the end of the file. Add one row to the existing table, keeping the others in place. Insert this row immediately after the "Debug a CI workflow failure" row:

```markdown
| Author a portage news item | (none — direct skill) | `/news-add <category/name> [slug]` |
```

17. Commit message: `docs: add /news-add to agent delegation table`.

### Step ordering

Steps 1–4 are foundation (directory, scaffolder, linter, CI). Steps 5–8 are the human-in-the-loop integration (agent flagging, auto-update PR enhancement, skill, doc). Recommended PR plan:

- **PR 1**: Steps 1 + 2 + 3 + 4 (foundation: directory, scaffolder, linter, CI workflow).
- **PR 2**: Steps 5 + 6 (agent flagging + auto-update wire-up).
- **PR 3**: Steps 7 + 8 (skill + doc).

Each PR is independently revertible. After PR 1 lands, the maintainer can already author news items by hand. PRs 2 and 3 add convenience.

### Acceptance criteria

The implementation is complete when:

1. `bash scripts/news-new.sh app-containers/devpod test` creates a scaffold under `metadata/news/<today>-test/<today>-test.txt` with all required GLEP 42 headers.
2. `bash scripts/news-lint.sh` exits 0 with output `No news items found — nothing to lint.` when `metadata/news/` is empty (after removing the test scaffold).
3. `bash scripts/news-lint.sh` exits 1 with at least one `FAIL` line when run against an un-edited scaffold (proves placeholders are rejected).
4. `bash scripts/news-lint.sh` exits 0 when run against a fully-filled-in news item with valid headers and a real overlay package in `Display-If-Installed`.
5. The `News Lint` workflow runs on a PR that adds a file under `metadata/news/**` and blocks merge if the linter fails.
6. A manual run of `auto-update.yml` (via `workflow_dispatch`) on a package produces a draft PR whose body contains either a `> [!IMPORTANT]` newsworthy block, a `> [!NOTE]` unknown block, or no news block — depending on the verdict the agent writes to `/tmp/pr-newsworthy.txt`.
7. `/news-add app-containers/devpod some-slug` scaffolds, prompts for content, writes the file, runs the linter, and exits cleanly with a green report in Claude Code.

## Risks and open questions

### Risks

1. **Bot mis-classification.** The `ebuild-updater` agent may mark routine bumps as `NEWSWORTHY` or miss real breaking changes. Mitigation: the rubric is explicit; the PR description makes the verdict visible; the maintainer is in the loop on every merge. If false-positive rate becomes high, refine the agent prompt with examples.
2. **Maintainer skip.** A busy maintainer merges an auto-update PR without reading the newsworthy block and never writes the news item. Mitigation: the `> [!IMPORTANT]` block is hard to miss in GitHub's PR UI; merge cadence is low enough that scanning PR bodies is feasible. Not a hard guard — accepted residual risk.
3. **Linter false negatives.** Bash + grep validation cannot detect every GLEP 42 nuance (e.g. semantic correctness of `Display-If-Profile` regexes). Mitigation: scope is intentionally limited to structural validation. Semantic errors surface to users via `eselect news`; they are recoverable by editing the item and bumping `Revision`.
4. **Stale Display-If-Installed.** If a package is later renamed or removed, an existing news item's `Display-If-Installed` atom becomes stale. The item silently never displays. Mitigation: the linter re-runs on every PR including those that rename or remove packages, so the failure surfaces at the time of removal. The fix is to amend the news item in the same PR.
5. **Item bodies become outdated.** Migration commands or URLs in old news items can rot. Mitigation: bump `Revision` and edit the body when the item is amended (GLEP 42 supports this — Portage re-shows items whose `Revision` increased). This is out of scope for the initial RFC; a future `CONTRIBUTING.md` sub-bullet can document the revision workflow when the first revision happens.

### Open questions

1. **Should news items be required on the same PR as the change, or can they land separately?** Recommendation: same PR. CI cannot enforce this (the linter validates structure, not coupling), but the rubric in CONTRIBUTING says "in the same PR." Reconsider if the maintainer finds this too restrictive.
2. **Should the linter check for `Title` length and body line width (79 chars)?** Recommendation: not in the initial cut. Add as a follow-up only if early news items show width problems on `eselect news read`.
3. **Should we accept news items pertaining to packages outside the overlay (e.g. a `Display-If-Installed: net-fs/samba` notice about a global config interaction)?** Recommendation: not initially. The linter rejects `Display-If-Installed` atoms not present in this overlay. If a cross-overlay news need arises, relax the linter check to skip the existence check for atoms whose category is not present under the overlay root (i.e. trust the atom is a Gentoo-tree package) or invoke `portageq match-all` from a Gentoo container in CI.
4. **News item retention policy.** The overlay never deletes old news items. Over years this could accumulate. Recommendation: revisit only when the count exceeds 50; until then, keep them all (historical record).

## Security Considerations

News items are user-visible text shipped by an overlay the user has explicitly opted into. The relevant threats:

1. **Malicious news content** — phishing links, instructions to run dangerous commands. Mitigation: news items are committed and reviewed in the same PR workflow as ebuilds. Anyone with commit access to the overlay can ship a news item; this is the same trust surface as the ebuilds themselves. Not a regression.
2. **Cross-site injection via news text** — `eselect news read` and Portage's news viewer render plain text without HTML/scripting interpretation. No XSS vector. Body content type is constrained to `text/plain` and the linter enforces it.
3. **Information leakage** — news items are public (they ship in the public overlay). Do not include private URLs, credentials, internal hostnames, or maintainer contact details beyond what is already on the public ebuilds. The linter does not enforce this — relies on PR review.
4. **Signature gap** — we ship unsigned news items, so a downstream user who installs this overlay from a mirror has no cryptographic assurance the news matches upstream. This is the same gap as the rest of the overlay (Manifest checksums are not signed either; `sign-manifests = false` in `layout.conf`). Documented openly in CONTRIBUTING. Users who require stronger guarantees should not use third-party overlays from untrusted mirrors regardless.

## Relationship to other RFCs

None. This is the first RFC in `docs/rfcs/` and stands alone. It does depend on the existing CI infrastructure (`auto-update.yml`, `verify.yml`, `debug-ci-failure.yml`) but does not modify their core paths beyond the addition described in Step 6.

Future RFCs that could build on this one:

- An RFC introducing a multi-maintainer model would likely also introduce GPG signing of news items and Manifests together. This RFC explicitly leaves that door open by not committing to an "unsigned forever" position — only "unsigned for now."
- An RFC adding a packages-changelog page would naturally consume the news directory as a structured source.
