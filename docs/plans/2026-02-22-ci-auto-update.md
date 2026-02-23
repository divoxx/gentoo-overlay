# CI Auto-Update Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Two GitHub Actions workflows — one that verifies changed ebuilds on every push/PR and promotes passing draft PRs, and one that daily checks upstream for new versions and opens draft PRs.

**Architecture:** `verify.yml` uses a dynamic matrix over changed ebuilds, runs the `ebuild-verifier` agent via Claude Code CLI inside a `gentoo/stage3:amd64` container, and promotes the PR from draft to ready when all checks pass. `auto-update.yml` uses a dynamic matrix over all packages, runs the `ebuild-updater` agent (verification skipped), commits new ebuilds + pruned old ones to a branch, and opens a draft PR — which `verify.yml` then picks up automatically.

**Tech Stack:** GitHub Actions, `gentoo/stage3:amd64` Docker image, Claude Code CLI (`@anthropic-ai/claude-code`), `pkgdev`, `pkgcheck`, `gh` CLI (pre-installed on ubuntu runners), `GITHUB_TOKEN` (built-in), `ANTHROPIC_API_KEY` (secret).

---

## Reference

Design doc: `docs/plans/2026-02-22-ci-auto-update-design.md`

Agents used:
- `.claude/agents/ebuild-verifier.md` — tools: Read, Bash, Glob, Grep
- `.claude/agents/ebuild-updater.md` — tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, WebSearch

Skills used (for interactive reference only — CI invokes agents directly via Claude):
- `.claude/skills/ebuild-verify/SKILL.md`
- `.claude/skills/ebuild-update/SKILL.md`

---

## Task 1: Create verify.yml — triggers, permissions, and skeleton

**Files:**
- Create: `.github/workflows/verify.yml`

**Step 1: Create the directory**

```bash
mkdir -p .github/workflows
```

**Step 2: Write the file**

```yaml
name: Verify Ebuilds

on:
  push:
    branches-ignore:
      - main
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write

jobs:
  # jobs added in subsequent tasks
```

**Step 3: Commit**

```bash
git add .github/workflows/verify.yml
git commit -m "ci: add verify.yml skeleton"
```

---

## Task 2: Add detect-changes job to verify.yml

**Files:**
- Modify: `.github/workflows/verify.yml`

This job finds which `category/package` dirs have changed ebuilds and outputs them as a JSON array for the matrix job.

**Step 1: Append the job**

Replace the `# jobs added in subsequent tasks` comment with:

```yaml
jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      packages: ${{ steps.detect.outputs.packages }}
      has_changes: ${{ steps.detect.outputs.has_changes }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Detect changed ebuilds
        id: detect
        run: |
          if [ "${{ github.event_name }}" = "pull_request" ]; then
            BASE="origin/${{ github.base_ref }}"
            CHANGED=$(git diff --name-only "$BASE"...HEAD)
          else
            CHANGED=$(git diff --name-only HEAD~1 HEAD)
          fi

          PACKAGES=$(echo "$CHANGED" \
            | grep '\.ebuild$' \
            | awk -F/ '{print $1"/"$2}' \
            | sort -u \
            | jq -R -s -c 'split("\n") | map(select(length > 0))')

          echo "packages=$PACKAGES" >> "$GITHUB_OUTPUT"

          if [ "$PACKAGES" = "[]" ] || [ -z "$PACKAGES" ]; then
            echo "has_changes=false" >> "$GITHUB_OUTPUT"
          else
            echo "has_changes=true" >> "$GITHUB_OUTPUT"
          fi
```

**Step 2: Commit**

```bash
git add .github/workflows/verify.yml
git commit -m "ci: add change detection job to verify.yml"
```

---

## Task 3: Add verify matrix job to verify.yml

**Files:**
- Modify: `.github/workflows/verify.yml`

This job runs inside a Gentoo container, installs tooling, invokes the `ebuild-verifier` agent via Claude Code CLI, and exits non-zero if verification fails.

**Step 1: Append the job after `detect-changes`**

```yaml
  verify:
    needs: detect-changes
    if: needs.detect-changes.outputs.has_changes == 'true'
    runs-on: ubuntu-latest
    container:
      image: gentoo/stage3:amd64
    strategy:
      matrix:
        package: ${{ fromJson(needs.detect-changes.outputs.packages) }}
      fail-fast: false

    steps:
      - uses: actions/checkout@v4

      - name: Sync Portage tree
        run: emerge-webrsync -q

      - name: Install Gentoo tooling
        run: emerge --getbinpkg --quiet-build dev-util/pkgdev dev-util/pkgcheck

      - name: Install Node.js
        run: emerge --getbinpkg --quiet-build dev-lang/nodejs

      - name: Install Claude Code CLI
        run: npm install -g @anthropic-ai/claude-code

      - name: Run ebuild-verifier
        id: verify
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          OUTPUT=$(claude --print \
            --allowedTools "Task,Read,Bash,Glob,Grep" \
            "Use the ebuild-verifier agent to run full verification for ${{ matrix.package }}. \
            Regenerate the Manifest if needed, run pkgcheck QA scan, and build through the \
            compile phase without installing. Report results.")

          echo "$OUTPUT"

          if echo "$OUTPUT" | grep -q "Overall: PASS"; then
            echo "result=pass" >> "$GITHUB_OUTPUT"
          else
            echo "result=fail" >> "$GITHUB_OUTPUT"
            exit 1
          fi
```

**Step 2: Commit**

```bash
git add .github/workflows/verify.yml
git commit -m "ci: add verification matrix job to verify.yml"
```

---

## Task 4: Add draft promotion job to verify.yml

**Files:**
- Modify: `.github/workflows/verify.yml`

This job runs after all matrix jobs pass and promotes the PR from draft to ready for review.

**Step 1: Append the job after `verify`**

```yaml
  promote:
    needs: verify
    if: |
      github.event_name == 'pull_request' &&
      github.event.pull_request.draft == true
    runs-on: ubuntu-latest
    steps:
      - name: Mark PR ready for review
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh pr ready ${{ github.event.pull_request.number }} --repo ${{ github.repository }}
```

**Step 2: Commit**

```bash
git add .github/workflows/verify.yml
git commit -m "ci: add draft promotion job to verify.yml"
```

---

## Task 5: Smoke-test verify.yml

Push the workflow file to a test branch with a small change to an existing ebuild (e.g. add/remove a blank line) to trigger the matrix.

**Step 1: Create a test branch**

```bash
git checkout -b test/verify-workflow
```

**Step 2: Touch an ebuild to mark it as changed**

```bash
echo "" >> dev-python/mslex/mslex-1.3.0.ebuild
```

**Step 3: Commit and push**

```bash
git add dev-python/mslex/mslex-1.3.0.ebuild
git commit -m "test: trigger verify workflow"
git push origin test/verify-workflow
```

**Step 4: Open a draft PR targeting main**

```bash
gh pr create --draft --title "test: verify workflow" --base main \
  --body "Testing the verify.yml workflow. Delete after confirming."
```

**Step 5: Check the Actions run**

Go to the repo's Actions tab. Confirm:
- `detect-changes` outputs `["dev-python/mslex"]`
- `verify` matrix runs one job for `dev-python/mslex`
- `verify` job exits 0 and output contains `Overall: PASS`
- `promote` job runs and PR transitions from draft to ready

**Step 6: Clean up**

```bash
gh pr close <number>
git checkout main
git branch -D test/verify-workflow
git push origin --delete test/verify-workflow
```

---

## Task 6: Create auto-update.yml — triggers, permissions, and package listing

**Files:**
- Create: `.github/workflows/auto-update.yml`

**Step 1: Write the file**

```yaml
name: Auto-Update Ebuilds

on:
  schedule:
    - cron: '0 6 * * *'   # 06:00 UTC daily
  workflow_dispatch:        # allow manual trigger for testing

permissions:
  contents: write
  pull-requests: write

jobs:
  list-packages:
    runs-on: ubuntu-latest
    outputs:
      packages: ${{ steps.list.outputs.packages }}
    steps:
      - uses: actions/checkout@v4

      - name: List overlay packages
        id: list
        run: |
          PACKAGES=$(find . -name "*.ebuild" -not -path "./.git/*" \
            | awk -F/ '{print $2"/"$3}' \
            | sort -u \
            | jq -R -s -c 'split("\n") | map(select(length > 0))')
          echo "packages=$PACKAGES" >> "$GITHUB_OUTPUT"
```

**Step 2: Commit**

```bash
git add .github/workflows/auto-update.yml
git commit -m "ci: add auto-update.yml with package listing job"
```

---

## Task 7: Add update matrix job to auto-update.yml

**Files:**
- Modify: `.github/workflows/auto-update.yml`

This job runs the `ebuild-updater` agent (skipping verification), then handles cleanup, commit, and draft PR creation.

**Step 1: Append the job after `list-packages`**

```yaml
  update:
    needs: list-packages
    runs-on: ubuntu-latest
    container:
      image: gentoo/stage3:amd64
    strategy:
      matrix:
        package: ${{ fromJson(needs.list-packages.outputs.packages) }}
      fail-fast: false

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Sync Portage tree
        run: emerge-webrsync -q

      - name: Install Gentoo tooling
        run: emerge --getbinpkg --quiet-build dev-util/pkgdev dev-util/pkgcheck

      - name: Install Node.js
        run: emerge --getbinpkg --quiet-build dev-lang/nodejs

      - name: Install Claude Code CLI
        run: npm install -g @anthropic-ai/claude-code

      - name: Configure git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git remote set-url origin \
            "https://x-access-token:${{ secrets.GITHUB_TOKEN }}@github.com/${{ github.repository }}.git"

      - name: Run ebuild-updater
        id: update
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          claude --print \
            --allowedTools "Task,Read,Write,Edit,Bash,Glob,Grep,WebFetch,WebSearch" \
            "Use the ebuild-updater agent to check for upstream updates and bump the ebuild \
            for ${{ matrix.package }} if a newer version exists. Do not run pkgcheck or \
            build verification — those are handled by a separate CI workflow."

      - name: Check for changes
        id: changes
        run: |
          if git diff --quiet && git diff --cached --quiet; then
            echo "updated=false" >> "$GITHUB_OUTPUT"
          else
            echo "updated=true" >> "$GITHUB_OUTPUT"
          fi

      - name: Prune old versions (keep 5 most recent)
        if: steps.changes.outputs.updated == 'true'
        run: |
          CATEGORY=$(echo "${{ matrix.package }}" | cut -d/ -f1)
          NAME=$(echo "${{ matrix.package }}" | cut -d/ -f2)
          cd "$CATEGORY/$NAME"

          # sort -V handles dotted-numeric version ordering
          EXCESS=$(ls *.ebuild | sort -V | head -n -5)
          if [ -n "$EXCESS" ]; then
            echo "$EXCESS" | xargs rm -f
            pkgdev manifest
          fi

      - name: Commit and push update branch
        if: steps.changes.outputs.updated == 'true'
        id: push
        run: |
          CATEGORY=$(echo "${{ matrix.package }}" | cut -d/ -f1)
          NAME=$(echo "${{ matrix.package }}" | cut -d/ -f2)
          BRANCH="auto-update/${CATEGORY}-${NAME}"

          git checkout -b "$BRANCH"
          git add -A
          git commit -m "auto-update: bump ${{ matrix.package }}"
          git push origin "$BRANCH" --force-with-lease

          echo "branch=$BRANCH" >> "$GITHUB_OUTPUT"

      - name: Open draft PR (skip if one already exists)
        if: steps.changes.outputs.updated == 'true'
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          BRANCH="${{ steps.push.outputs.branch }}"

          EXISTING=$(gh pr list \
            --head "$BRANCH" \
            --state open \
            --json number \
            --repo "${{ github.repository }}" \
            -q '.[0].number')

          if [ -n "$EXISTING" ]; then
            echo "PR #$EXISTING already open for $BRANCH — skipping"
            exit 0
          fi

          gh pr create \
            --draft \
            --title "auto-update: ${{ matrix.package }}" \
            --body "Automated upstream version bump for \`${{ matrix.package }}\`.

Verification will run automatically via the verify workflow. The PR will be promoted from draft to ready when all checks pass.

🤖 Generated with [Claude Code](https://claude.com/claude-code)" \
            --base main \
            --head "$BRANCH" \
            --repo "${{ github.repository }}"
```

**Step 2: Commit**

```bash
git add .github/workflows/auto-update.yml
git commit -m "ci: add update matrix job to auto-update.yml"
```

---

## Task 8: Smoke-test auto-update.yml

Trigger the workflow manually and confirm it runs cleanly.

**Step 1: Push to main**

```bash
git push origin main
```

**Step 2: Trigger manually**

```bash
gh workflow run auto-update.yml --repo divoxx/gentoo-overlay
```

**Step 3: Watch the run**

```bash
gh run list --workflow=auto-update.yml --repo divoxx/gentoo-overlay --limit 1
gh run watch --repo divoxx/gentoo-overlay   # use the run ID from above
```

**Expected behavior:**
- `list-packages` outputs the 3 packages as a JSON array
- `update` spawns 3 parallel jobs
- For each package with no upstream update: job exits cleanly, no PR created
- For each package with an update: new ebuild committed, old versions pruned, draft PR opened
- Each draft PR triggers `verify.yml` automatically
- Passing PRs get promoted from draft to ready for review

**Step 4: Verify idempotency**

Trigger `auto-update.yml` a second time. Confirm no duplicate PRs are created for branches that already have open PRs.

```bash
gh workflow run auto-update.yml --repo divoxx/gentoo-overlay
gh run watch --repo divoxx/gentoo-overlay
```

Expected: jobs that already have open PRs log "PR already open — skipping" and exit 0.

---

## Secrets to Configure

Before the workflows can run, add the following secret in the repo settings
(`Settings → Secrets and variables → Actions → New repository secret`):

| Name | Value |
|---|---|
| `ANTHROPIC_API_KEY` | Your Anthropic API key |

`GITHUB_TOKEN` is provided automatically by GitHub Actions — no configuration needed.
