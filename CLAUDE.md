# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Gentoo Overlay — Claude Code Instructions

## Project Identity

- **Overlay name:** `divoxx-overlay`
- **Type:** Gentoo package overlay
- **EAPI:** 8 (all packages)
- **Architecture:** `~amd64` (testing keywords only — never stable)
- **Masters:** `gentoo` (inherits from the official Gentoo tree)

## Repository Structure

```
<overlay>/
├── <category>/              # Gentoo category (e.g. dev-python, dev-util)
│   └── <package>/
│       ├── <pkg>-<ver>.ebuild  # One file per version
│       ├── metadata.xml         # Maintainer, upstream info, USE flags
│       └── Manifest             # Distfile checksums (thin-manifests, auto-generated)
├── metadata/
│   ├── layout.conf              # Overlay config: masters, thin-manifests, hash algorithms
│   └── md5-cache/               # Portage metadata cache (auto-generated, do not edit)
├── profiles/
│   ├── eapi                     # Supported EAPI (8)
│   └── repo_name                # Overlay name
├── docs/plans/                  # Point-in-time design documents (historical, not authoritative)
├── .github/workflows/
│   ├── auto-update.yml          # Daily upstream version check and bump
│   ├── build-image.yml          # Weekly CI container image build
│   ├── debug-ci-failure.yml     # Auto-debug and fix CI failures via Claude agent
│   └── verify.yml               # pkgcheck QA + build verification on every PR branch
└── .claude/
    ├── agents/                  # Specialized AI agents for ebuild work
    └── skills/                  # Skill shortcuts
```

## Standards and Workflow

Follow all engineering standards, tooling conventions, and the PR process documented in [CONTRIBUTING.md](CONTRIBUTING.md). It is the authoritative source for:

- Development tooling and the standard ebuild workflow
- Adding and updating packages
- Engineering standards (EAPI, keywords, formatting, variable ordering, etc.)
- Quality gates, commit messages, and CI/CD overview

## Agent Delegation

Always delegate to the appropriate agent for ebuild work. Do not write or modify ebuilds inline.

| Task | Agent | Skill |
|------|-------|-------|
| Create a new ebuild from scratch | `ebuild-writer` | `/ebuild-create <url>` |
| Bump an existing ebuild to a new version | `ebuild-updater` | `/ebuild-update <category/name>` |
| Verify an ebuild (QA + build test) | `scripts/verify-ebuild.sh` | `/ebuild-verify <category/name>` |
| Debug a CI workflow failure | `ci-debugger` | (invoked automatically by `debug-ci-failure.yml`) |
