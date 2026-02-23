# CI Auto-Update Design

## Overview

Two GitHub Actions workflows automate ebuild maintenance for the overlay:

1. **`verify.yml`** — runs on every push and PR, verifies changed ebuilds, promotes passing draft PRs to ready for review.
2. **`auto-update.yml`** — runs on a daily schedule, checks each package for upstream updates, opens draft PRs for any new versions found.

## Workflows

### verify.yml

**Trigger:** push to any branch, pull_request

**Steps:**

1. Detect which `category/package` directories have changed ebuilds compared to the base branch (or previous commit on a direct push).
2. If no ebuilds changed, exit early.
3. Fan out a matrix job — one per changed package — each running inside a `gentoo/stage3:amd64` container.
4. Each matrix job installs Gentoo tooling via `emerge --getbinpkg` (`pkgdev`, `pkgcheck`), installs Node.js and Claude Code CLI, then runs `/ebuild-verify` for the package using the `ebuild-verifier` agent.
5. After the matrix: if all jobs passed **and** the workflow is running in a PR context **and** the PR is currently a draft → mark the PR ready for review via the GitHub API (`GITHUB_TOKEN`).

### auto-update.yml

**Trigger:** daily schedule (e.g. `cron: '0 6 * * *'`)

**Steps:**

1. List all `category/package` directories in the overlay that contain at least one `.ebuild` file.
2. Fan out a matrix job — one per package — each running inside a `gentoo/stage3:amd64` container.
3. Each matrix job:
   a. Installs Gentoo tooling (`pkgdev`, `pkgcheck`) and Claude Code CLI.
   b. Invokes the `ebuild-updater` agent with an explicit instruction to **skip verification** (pkgcheck and compile phase) — those are handled by `verify.yml`.
   c. If no new upstream version is found: exits cleanly, no PR.
   d. If a new version is found:
      - Creates the new ebuild.
      - Removes old versions, keeping the **5 most recent** (by Gentoo version ordering).
      - Regenerates the Manifest (`pkgdev manifest`).
      - Commits to a branch named `auto-update/<category>-<name>`.
      - Opens a **draft PR** targeting `main`.
4. The push to the update branch automatically triggers `verify.yml`, which handles QA and promotion.

## Promotion Flow

```
daily job finds new upstream version
  → new ebuild created, old versions pruned (keep 5)
    → draft PR opened: auto-update/<category>-<name>
      → verify.yml triggered by the push
        → matrix: ebuild-verifier runs per changed package
          ├── all pass → PR promoted to ready for review
          └── any fail → PR stays draft (needs manual attention)
```

## Verification Scope

The `ebuild-updater` agent already performs pkgcheck and compile-phase verification as part of its standard workflow. In the CI context this is redundant and wasteful — `verify.yml` handles it.

**Convention:** the `auto-update.yml` invocation appends to its prompt:

> Do not run pkgcheck or build verification — those are handled by a separate CI workflow.

The skills themselves (`ebuild-create`, `ebuild-update`) are unchanged and continue to include full verification for interactive use.

## Container Strategy

Both workflows use `gentoo/stage3:amd64` (official image, updated regularly by the Gentoo project). Tools are installed at job startup via `emerge --getbinpkg` (binary packages — no compilation). Required packages:

- `dev-util/pkgdev`
- `dev-util/pkgcheck`
- `net-libs/nodejs` (for Claude Code CLI)

Claude Code CLI is installed via `npm install -g @anthropic-ai/claude-code`.

## Secrets Required

| Secret | Used by | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | both workflows | Claude Code CLI authentication |
| `GITHUB_TOKEN` | both workflows | creating branches, PRs, promoting draft status (built-in) |

## Idempotency

If `auto-update.yml` runs and a branch `auto-update/<category>-<name>` already exists with an open PR (e.g. from a previous day's run that hasn't been merged), the job skips creating a duplicate PR. It checks for an existing open PR for that branch before pushing.

## Old Version Cleanup

When a new ebuild version is added, the job removes the oldest ebuilds beyond the 5-version limit. Removal order follows Gentoo version ordering (not filesystem order). The Manifest is regenerated after removal.
