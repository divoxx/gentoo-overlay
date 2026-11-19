# Architecture

<!--
ARCHITECTURE scope: system design reference — the "how and why it's built this way."
Update this file when:
  - A package is added or removed from the overlay
  - A workflow is added, renamed, or its trigger/behaviour changes
  - A design decision is made or reversed (update the Decisions table)
  - A new external dependency or service is introduced

Not here: setup/quickstart                   → README.md
          dev workflow, commit conventions   → CONTRIBUTING.md
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
**Built from:** `gentoo/stage3:amd64-systemd`, on every build
**Contains:** Portage tree (the latest daily snapshot at build time, installed with `emerge-webrsync`), `pkgdev`, `pkgcheck`, `gh`, `git`, `go`, `rust-bin`, `jq` and the Claude Code CLI (`dev-util/claude-code`)

Every build starts from stage3 rather than from the previously published image, so nothing accumulates between builds. Dependencies from `::gentoo` use stable keywords, and this overlay's packages `~amd64`, because the [official Gentoo binary package host](https://wiki.gentoo.org/wiki/Gentoo_Binary_Host_Quickstart) is built from the stable tree. With `FEATURES="getbinpkg binpkg-request-signature"`, both the image build and verify's dependency installs use a binary package whenever one matches the requested version, USE flags and dependencies, and compile from source when none does. Every binary package needs a valid signature: one that fails the check fails the install instead of falling back to source. The build ends by removing package versions nothing depends on (`emerge --depclean`), downloaded source tarballs and binary packages, and the binary package keyring; `getuto` creates a new keyring in each job that installs binary packages.

### Workflows

#### `build-image.yml` — CI Container Build

**Triggers:** Sunday 03:00 UTC (weekly) · push to `main` on `Containerfile.ci` changes · manual dispatch
**Purpose:** Keeps the CI container image fresh with an updated Portage tree and tool versions.
**Flow:** Build from `gentoo/stage3:amd64-systemd` via buildah → push `latest` + date-tagged image to `ghcr.io/divoxx/gentoo-ci`.

Runs before `auto-update.yml` (03:00 vs 06:20) so the update jobs always get a fresh Portage tree.

#### `auto-update.yml` — Automated Version Bumps

**Triggers:** Sunday 06:20 UTC · Wednesday 06:20 UTC · manual dispatch
**Purpose:** Checks every package for upstream releases and opens draft PRs for any that have new versions.
**Flow:**
1. List all packages in the overlay
2. Matrix: one run of the reusable `update-package.yml` per package, made of two jobs
3. **`agent` job**, in the `gentoo-ci` container:
   1. Sync Portage tree
   2. Run `ebuild-updater` Claude Code agent to check upstream and bump if needed
   3. Prune oldest ebuilds beyond the 5 most recent (to prevent unbounded accumulation)
   4. Upload the package directory, `README.md` and the PR changelog as an artifact, after checking that they hold only regular files and directories with plain, unhidden names, which is all an artifact carries unchanged and all the `publish` job accepts
4. **`publish` job**, only when the package changed:
   1. Download the artifact by the ID the `agent` job reported, check that it holds only regular files and directories with plain, unhidden names, and copy in the package directory and `README.md`
   2. Commit via GitHub API (tree + commit objects) using the `divoxx-bot` GitHub App — produces GitHub-signed "Verified" commits without GPG keys in CI
   3. Open a draft PR targeting `main`

The agent runs Bash on content this repository doesn't control, such as upstream release pages and package registries, so the job it runs in has no write access to the repository. Its token can only read, the checkout keeps that token out of `.git/config`, and `ANTHROPIC_API_KEY` is its only secret. The boundary is the job: each job runs on its own runner, which holds only the secrets that job references. Within a job, the agent's commands can reach everything the runner holds, because a job container has the host's Docker socket mounted. That includes the job's runtime token, which can upload and replace artifacts in the run, so the `publish` job downloads by artifact ID, and which would also save cache entries if the job's `cache-mode` weren't `none`. The `publish` job's runner holds the bot App's key from the start; what keeps it from the agent is that the job runs no code from the `agent` job and treats the artifact as data. The split doesn't cover text the `agent` job writes to its log: when a run fails, `debug-ci-failure.yml` passes the failed jobs' logs to the `ci-debugger` agent, which holds the bot token.

#### `verify.yml` — QA + Build Verification

**Triggers:** PR open/sync/reopen · push to `main`
**Purpose:** Runs pkgcheck QA and a full build test for every changed ebuild.
**Flow:**
1. Superseding run detection: skip if a newer run for the same branch is already queued/running (avoids redundant work on rapid pushes)
2. Detect changed ebuilds by diffing against `origin/main` (PRs) or `$BEFORE` (main push)
3. Matrix: one job per changed `category/package`, running in `gentoo-ci` container, with a 120-minute timeout
4. Run `scripts/verify-ebuild.sh` for each package
5. **Promote step** (auto-update branches only): if all verify jobs pass, promote the draft PR to "ready for review"
6. **Result job** (`verify-result`, every run): fails unless detect-changes succeeded and every verify job passed or was skipped. It is the status check the `main` ruleset requires, since verify's own checks are named per package

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
| `ebuild-updater` | `update-package.yml`, called by `auto-update.yml` | Check upstream releases; bump ebuild version if needed; update Manifest |
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

- **Auto-update:** create branches and commits via GitHub API; open draft PRs. Only `update-package.yml`'s `publish` job mints the token; the `agent` job never has it
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
  auto-update.yml ──► update-package.yml, per package
    ├─ agent job: ebuild-updater agent (Claude Code), read-only token
    ├─ publish job: GitHub API commit (Verified signature)
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
| Portage sync in CI | Daily snapshot (`emerge-webrsync`) at image build time, re-synced at update time | A fresh stage3 has no tree, and one signed snapshot is a single download instead of an rsync of every file; update jobs re-sync to catch releases between image builds |
| CI failure handling | Auto-debug via Claude Code agent | Reduces maintainer toil; most verify failures from version bumps have predictable fixes |
| Idempotency guard | Last-commit-is-bot-fix check | Prevents infinite debug→fix→fail→debug loops on auto-update branches |
| Superseding run detection | Skip if newer run queued for same branch | Avoids redundant verify runs on rapid pushes; saves CI minutes |
| CI image base | Rebuilt from `gentoo/stage3` on every build | Nothing accumulates between builds (old package versions, caches, repeated config lines); binary packages keep a full build short |
| Dependency keywords in CI | Stable for `::gentoo`, `~amd64` for this overlay's packages | Lets most dependencies install from the official binhost, which is built from the stable tree; with `~amd64` everywhere, testing versions such as a second LLVM toolchain always compiled from source |
| Binary packages in CI | Official Gentoo binhost via `getbinpkg`, valid signatures required | Avoids multi-hour source builds (LLVM, nodejs, gcc) that pushed jobs into GitHub's 6-hour limit |
| Verify job timeout | 120 minutes | A build that can't finish fails early instead of at GitHub's 6-hour limit |
| Auto-update agent isolation | The agent runs in its own job, with a read-only token and `ANTHROPIC_API_KEY` as its only secret; a separate `publish` job mints the bot token | A prompt injection in upstream content can use whatever the agent's commands reach, and through the job container's Docker socket that is everything the runner holds, so only a separate job keeps the bot App's key away from the agent |
| Updates to `main` | The `main` ruleset restricts updates, with the Repository admin role as its only bypass actor | A leaked token with write access can't change `main`. Every merge bypasses the ruleset, and a bypass skips all of its rules, so `verify-result` and signatures don't block the admin's merges |
| Subprocess env scrub for the agent | Not used | On Linux, `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` runs every Bash command in Claude Code's sandbox, which needs bubblewrap and socat and doesn't start in the job container, so the agent's commands would be refused. `ANTHROPIC_API_KEY` stays readable by those commands |

## External Dependencies

| Dependency | Purpose |
|------------|---------|
| `ghcr.io` (GitHub Container Registry) | Hosts the `gentoo-ci` CI container image |
| `tibdex/github-app-token` GitHub Action | Generates short-lived GitHub App tokens per run |
| Anthropic API (`ANTHROPIC_API_KEY`) | Powers the `ebuild-updater` and `ci-debugger` Claude Code agents |
| `gentoo/stage3:amd64-systemd` | Base image for every CI container build |
| Gentoo binary package host (configured by stage3's `binrepos.conf`) | Signed binary packages for the CI image build and verify's dependency installs |
| Portage / Gentoo infrastructure | Package metadata, upstream sync via `emerge --sync` |
