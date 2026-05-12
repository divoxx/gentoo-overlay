<!--
CONTRIBUTING scope: everything a developer needs to work on this project.
  - Prerequisites or tool versions change
  - Setup steps change
  - Dev workflow or branching conventions change
  - Quality gate commands change
  - PR or RFC process changes

Not here: what the project does or its architecture → README.md / docs/ARCHITECTURE.md
-->

# Contributing

## Prerequisites

- [git](https://git-scm.com/)
- A Gentoo system or container with Portage installed
- `pkgcheck` and `pkgdev` for QA and ebuild management

## Development Setup

```bash
git clone https://github.com/divoxx/gentoo-overlay.git
cd gentoo-overlay
```

## Development Workflow

All work happens on feature branches. Use the [git worktree](https://git-scm.com/docs/git-worktree) workflow for parallel tasks:

```bash
git worktree add .worktrees/<branch-name> -b <branch-name>
cd .worktrees/<branch-name>
# work here
```

See `CLAUDE.md` for agent delegation guidance.

## Commit Conventions

Follow [Conventional Commits](https://www.conventionalcommits.org/) with a scope:

```
feat(scope): add new capability
fix(scope): correct wrong behavior
refactor(scope): restructure without changing behavior
docs(scope): update documentation
chore(scope): tooling, deps, config
```

## Quality Gate

All ebuilds must pass pkgcheck QA and a full build test before merging:

```bash
bash scripts/verify-ebuild.sh <category/package>
```

Fix any reported errors before pushing.

## Pull Request Process

1. Open a PR against `main`
2. CI must pass (pkgcheck QA + build verification)
3. One approval required for merge
4. Squash merge to keep history clean

## RFC Process

Significant changes (new packages, architectural changes, breaking changes) go through the RFC process. See [docs/rfc-process.md](docs/rfc-process.md).
