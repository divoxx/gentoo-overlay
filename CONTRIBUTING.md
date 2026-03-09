# Contributing

This is a personal Gentoo overlay. Contributions are welcome for packages that are:

- Not already available in the [official Gentoo tree](https://packages.gentoo.org/) or the [GURU overlay](https://gpo.zugaina.org/overlays/guru)
- Maintained by an active upstream with versioned releases
- Buildable under EAPI 8

## Prerequisites

Install the required Gentoo tooling:

```bash
emerge -av dev-util/pkgdev dev-util/pkgcheck
```

## Development Tooling

| Tool | Package | Purpose |
|------|---------|---------|
| `pkgdev manifest` | `dev-util/pkgdev` | Regenerate Manifest checksums after any ebuild change |
| `pkgdev commit` | `dev-util/pkgdev` | Commit with auto-generated message + Manifest regeneration |
| `pkgcheck scan <cat/pkg>` | `dev-util/pkgcheck` | QA scanning — run before every commit |
| `ebuild <path> <phases>` | `sys-apps/portage` | Build/test individual ebuild phases |

**Standard workflow after writing or editing an ebuild:**

1. `pkgdev manifest` — regenerate Manifest
2. `pkgcheck scan <category/name>` — QA check, fix all errors
3. `ebuild <path>.ebuild clean fetch unpack prepare configure compile` — build test (no install)

## Adding a New Package

1. **Check for prior art** — Search [packages.gentoo.org](https://packages.gentoo.org/) and the [GURU overlay](https://gpo.zugaina.org/overlays/guru) first.
2. **Choose the category** — Consult [packages.gentoo.org/categories](https://packages.gentoo.org/categories) if unsure.
3. **Write the ebuild** (`EAPI=8`) and `metadata.xml`. See the [Gentoo Development Guide](https://devmanual.gentoo.org/) for reference.
4. **Generate the Manifest** — `pkgdev manifest` in the package directory.
5. **QA check** — `pkgcheck scan <category/name>`. Fix all errors.
6. **Build test** — `ebuild <path>.ebuild clean fetch unpack prepare configure compile`.
7. **Submit a PR** — the verify CI runs automatically.

If you use Claude Code, the `/ebuild-create <url>` skill automates steps 2–6.

## Updating an Existing Package

1. Copy the latest ebuild to the new version filename (`<name>-<newver>.ebuild`).
2. Review for any version-specific changes (hardcoded versions, `CRATES=` lists, `EGO_SUM` arrays for Go packages).
3. Run `pkgdev manifest`, `pkgcheck scan`, and a build test.
4. Do not remove the old version — CI prunes beyond 5 automatically.
5. Submit a PR.

If you use Claude Code, the `/ebuild-update <category/name>` skill automates steps 1–3.

## Language-Specific Notes

### Go Packages

Use `go-module.eclass` with the `EGO_SUM` array — no vendor tarball hosting required. Portage fetches each module individually from the Go module proxy.

**Pattern:**
```bash
inherit go-module

EGO_SUM=(
    "github.com/foo/bar v1.2.3"
    "github.com/foo/bar v1.2.3/go.mod"
    # ... one entry per line of go.sum
)

go-module_set_globals

SRC_URI="https://github.com/org/repo/archive/v${PV}.tar.gz -> ${P}.tar.gz
    ${EGO_SUM_SRC_URI}"
```

**Generating `EGO_SUM`:** The array mirrors the upstream `go.sum` file directly — one entry per `<module> <version>` line, including `/go.mod` entries. Use `sed` on the upstream `go.sum` or the `gosum` tool from `dev-go/gosum`.

**When bumping:** regenerate `EGO_SUM` from the new version's `go.sum` — dependency lists change between releases.

**Trade-off:** The `EGO_SUM` array can be hundreds of lines for projects with many dependencies, but requires zero external hosting and matches the pattern used in the official Gentoo tree.

> Note: `go-module_set_globals` and `EGO_SUM` trigger `DeprecatedEclassVariable`/`DeprecatedEclassFunction` warnings from `pkgcheck`. These are expected and acceptable — the eclass has no replacement for this pattern in personal overlays.

## Engineering Standards

1. **EAPI 8 only** — All ebuilds use `EAPI=8`.
2. **Testing keywords only** — Use `~amd64`. Never stable keywords in a personal overlay.
3. **Tab indentation** — Ebuild bodies use tabs, not spaces.
4. **Copyright header** — Every ebuild: `# Copyright <year> Gentoo Authors` + GPL-2 line.
5. **Variable ordering** — `EAPI`, `inherit`, `DESCRIPTION`, `HOMEPAGE`, `SRC_URI`, `S` (if needed), `LICENSE`, `SLOT`, `KEYWORDS`, `IUSE`, `RESTRICT`, then `DEPEND`/`RDEPEND`/`BDEPEND`/`IDEPEND`/`PDEPEND`.
6. **Quoting** — All variables in phase functions must be quoted (`"${S}"`, `"${D}"`, etc.).
7. **`default` in `src_prepare`** — Always call `default` (which calls `eapply_user`).
8. **`RESTRICT="!test? ( test )"`** — Required whenever `test` is in `IUSE`.
9. **No trailing whitespace** in ebuild files.
10. **Thin manifests** — Never manually edit the Manifest; always use `pkgdev manifest`.

## Quality Gates

A PR must pass the following before merging:

- [ ] `pkgcheck scan` reports no errors (warnings acceptable if unfixable upstream)
- [ ] Ebuild builds through the `compile` phase without errors
- [ ] Copyright header present on all ebuilds
- [ ] `metadata.xml` includes maintainer and upstream `<remote-id>`
- [ ] Manifest is current (regenerated with `pkgdev manifest`)

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) with a package scope:

```
feat(dev-python/foo): add foo-1.2.3
feat(dev-python/foo): bump to 1.3.0
fix(dev-util/bar): fix build with gcc-14
chore(dev-python/foo): remove obsolete 1.1.0
ci: ...
```

## PR Process

1. Create a branch: `feat/<category>-<name>` or `fix/<description>`.
2. Push and open a PR. The verify workflow runs automatically.
3. Fix any CI failures before requesting review.

Auto-update PRs (opened by the daily CI bot) are promoted from draft to ready automatically when all checks pass.

### Merge Strategy

PRs are always merged with a **merge commit** — squash and rebase merging are disabled.

**Why merge commits?** A merge commit preserves the exact point where two histories joined. If a conflict was resolved incorrectly, it's immediately visible and bisectable. Squashing or rebasing buries that resolution inside unrelated commits, making mistakes much harder to spot.

#### Cleaning up your commit history

Before opening a PR, use an interactive rebase to tidy up your own commits — squash fixups, reword messages, reorder steps:

```bash
git rebase -i origin/main
```

This presents only the commits on your branch that aren't yet in `main`. Any sync merge commits (from a previous `git pull`) are automatically dropped — your commits are simply replayed on top of the current `main`, linearising the branch history.

#### Syncing your branch with main

If `git rebase -i origin/main` hits conflicts and you'd rather not resolve them commit-by-commit, abort and fall back to a plain merge:

```bash
git rebase --abort
git pull origin/main   # conflict resolution stays in one explicit merge commit
```

## CI/CD Overview

### `verify.yml` — Runs on every push to non-main branches

Detects changed ebuilds, then for each: regenerates Manifest, runs `pkgcheck scan`, builds through `compile`. Blocks merge on failure. Promotes auto-update draft PRs to ready when all checks pass.

### `auto-update.yml` — Runs daily at 06:00 UTC

Checks all packages for upstream updates. Creates version-bump ebuilds, pushes `auto-update/<category>-<name>` branches, opens draft PRs, and prunes packages to at most 5 versions.
