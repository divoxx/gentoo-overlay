# Architecture

<!--
ARCHITECTURE scope: system design reference — the "how and why it's built this way."
Update this file when:
  - A package is added or removed from the overlay
  - A workflow is added, renamed, or its trigger/behaviour changes
  - A design decision is made or reversed (update the Decisions table)
  - A new external dependency or service is introduced

Not here: setup/quickstart                   → README.md
          dev workflow, commit conventions   → docs/CONTRIBUTING.md
          non-obvious session learnings      → docs/BEST_PRACTICES.md
-->

## Overview

A personal Gentoo package overlay providing 7 packages across 4 categories. The overlay is fully automated: versions are bumped by a Claude Code agent on a schedule, verified by a dedicated CI pipeline, and CI failures are auto-debugged by a second Claude Code agent. All bot commits go through the GitHub API to receive GitHub's automatic "Verified" signature without needing GPG keys in CI.

## Packages

| Package | Category | Description |
|---------|----------|-------------|
| `devpod` | `app-containers` | Dev container runtime |
| `mslex` | `dev-python` | Windows-style shell quoting for Python |
| `oslex` | `dev-python` | OS-appropriate shell quoting for Python |
| `exercism` | `dev-util` | Exercism CLI |
| `ufbt` | `dev-util` | Flipper Zero build tool |
| `worktrunk` | `dev-util` | Git worktree manager |
| `himalaya` | `net-mail` | CLI email client |
| `minikube` | `sys-cluster` | Local Kubernetes cluster tool |

## Components

### CI Container (`ghcr.io/divoxx/gentoo-ci:latest`)

**Purpose:** Pre-synced Portage environment with all tools needed to verify and update ebuilds.
**Location:** `.github/Containerfile.ci`
**Built from:** `gentoo/stage3:amd64-systemd` (cold) or existing `gentoo-ci:latest` (incremental)
**Contains:** Portage tree (synced at build time), `pkgdev`, `pkgcheck`, `gh`, `git`, `go`, `rust-bin`, `jq`

The incremental build strategy (pulling the existing image and using it as the build base) means the Portage tree stays relatively fresh between weekly rebuilds and sync time in CI is minimal.

### Workflows

#### `build-image.yml` — CI Container Build

**Triggers:** Sunday 03:00 UTC (weekly) · push to `main` on `Containerfile.ci` changes · manual dispatch
**Purpose:** Keeps the CI container image fresh with an updated Portage tree and tool versions.
**Flow:** Pull existing image (for incremental build) → build via buildah → push `latest` + date-tagged image to `ghcr.io/divoxx/gentoo-ci`.

Runs before `auto-update.yml` (03:00 vs 06:20) so the update jobs always get a fresh Portage tree.

#### `auto-update.yml` — Automated Version Bumps

**Triggers:** Sunday 06:20 UTC · Wednesday 06:20 UTC · manual dispatch
**Purpose:** Checks every package for upstream releases and opens draft PRs for any that have new versions.
**Flow:**
1. List all packages in the overlay
2. Matrix: one job per package, running in `gentoo-ci` container
3. Sync Portage tree
4. Run `ebuild-updater` Claude Code agent to check upstream and bump if needed
5. Prune oldest ebuilds beyond the 5 most recent (to prevent unbounded accumulation)
6. Commit via GitHub API (tree + commit objects) using the `divoxx-bot` GitHub App — produces GitHub-signed "Verified" commits without GPG keys in CI
7. Open a draft PR targeting `main`

#### `verify.yml` — QA + Build Verification

**Triggers:** PR open/sync/reopen · push to `main`
**Purpose:** Runs pkgcheck QA and a full build test for every changed ebuild.
**Flow:**
1. Superseding run detection: skip if a newer run for the same branch is already queued/running (avoids redundant work on rapid pushes)
2. Detect changed ebuilds by diffing against `origin/main` (PRs) or `$BEFORE` (main push)
3. Matrix: one job per changed `category/package`, running in `gentoo-ci` container
4. Run `scripts/verify-ebuild.sh` for each package
5. **Promote step** (auto-update branches only): if all verify jobs pass, promote the draft PR to "ready for review"

#### `debug-ci-failure.yml` — Automated CI Debugging

**Triggers:** Any of the three other workflows completes with `failure` status · manual dispatch
**Purpose:** Analyzes failures and either fixes them automatically or opens a tracking issue.
**Flow:**
1. Idempotency check: for verify failures on auto-update branches, skip if the last commit is already a bot fix (prevents infinite retry loops); for build-image/auto-update failures, skip if a fix PR for today already exists
2. Fetch last 50 000 chars of failed job logs
3. Run `ci-debugger` Claude Code agent with the logs and context
4. Agent classifies the failure and takes one of three actions:
   - **Verify failure on auto-update branch:** fix in place on the branch, push, let verify re-run
   - **Build-image or auto-update failure:** create a `ci-fix/...` branch, open a PR
   - **Transient/infrastructure failure:** open a GitHub issue for human review

### Claude Code Agents (`.claude/agents/`)

| Agent | Invoked by | Responsibility |
|-------|-----------|----------------|
| `ebuild-updater` | `auto-update.yml` | Check upstream releases; bump ebuild version if needed; update Manifest |
| `ebuild-writer` | Developer manually | Create a new ebuild from scratch for a given upstream URL |
| `ebuild-verifier` | Developer manually | Run pkgcheck QA + build test; report results |
| `ci-debugger` | `debug-ci-failure.yml` | Classify CI failure; fix, PR, or open issue accordingly |

### CI Helper Scripts (`scripts/ci/`)

Thin shell wrappers around `gh` CLI calls, used by the `ci-debugger` agent to keep GitHub API interactions out of agent prompts:

| Script | Purpose |
|--------|---------|
| `open-fix-pr.sh` | Create a fix PR with title/body/branch from env vars |
| `create-tracking-issue.sh` | Create a GitHub issue; skips label if it doesn't exist |
| `comment-triggering-pr.sh` | Post a comment on the open PR for a branch (best-effort) |

### Authentication: `divoxx-bot` GitHub App

The bot GitHub App is used wherever a token with write access is needed:

- **Auto-update:** create branches and commits via GitHub API; open draft PRs
- **Verify promote:** promote draft PRs to ready
- **Debug fix:** push fix commits; open fix PRs

The GitHub App token is generated fresh per workflow run via `tibdex/github-app-token`. The bot identity (`divoxx-bot[bot]`) is used as the git author so bot commits are visually distinct from human commits.

## Data Flow

```
[Schedule / PR push]
        │
        ▼
  build-image.yml ──► ghcr.io/divoxx/gentoo-ci:latest
        │
        ▼
  auto-update.yml
    ├─ ebuild-updater agent (Claude Code)
    ├─ GitHub API commit (Verified signature)
    └─ Draft PR ──► verify.yml
                      ├─ verify-ebuild.sh (in gentoo-ci container)
                      └─ [pass] promote PR to ready
                      └─ [fail] ──► debug-ci-failure.yml
                                      └─ ci-debugger agent (Claude Code)
                                          ├─ [fixable] push fix → verify re-runs
                                          ├─ [needs PR] open ci-fix/ PR
                                          └─ [transient] open GitHub issue
```

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Commit signing | GitHub API tree+commit creation | Produces "Verified" badge without GPG keys in CI; simpler than key management |
| Bot identity | GitHub App (`divoxx-bot`) | Scoped write permissions; fresh token per run; commits attributed to bot, not maintainer |
| PR lifecycle | Draft on creation, promote on verify pass | Prevents auto-update PRs from landing without CI passing; merge is always a human action |
| Version pruning | Keep 5 most recent ebuilds | Prevents unbounded accumulation; old ebuilds are rarely needed once superseded |
| Portage sync in CI | Synced at image build time, re-synced at update time | Image build is weekly; update jobs re-sync to catch releases between image builds |
| CI failure handling | Auto-debug via Claude Code agent | Reduces maintainer toil; most verify failures from version bumps have predictable fixes |
| Idempotency guard | Last-commit-is-bot-fix check | Prevents infinite debug→fix→fail→debug loops on auto-update branches |
| Superseding run detection | Skip if newer run queued for same branch | Avoids redundant verify runs on rapid pushes; saves CI minutes |

## External Dependencies

| Dependency | Purpose |
|------------|---------|
| `ghcr.io` (GitHub Container Registry) | Hosts the `gentoo-ci` CI container image |
| `tibdex/github-app-token` GitHub Action | Generates short-lived GitHub App tokens per run |
| Anthropic API (`ANTHROPIC_API_KEY`) | Powers the `ebuild-updater` and `ci-debugger` Claude Code agents |
| `gentoo/stage3:amd64-systemd` | Base image for cold CI container builds |
| Portage / Gentoo infrastructure | Package metadata, upstream sync via `emerge --sync` |
