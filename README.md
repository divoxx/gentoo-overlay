# divoxx-overlay

A personal Gentoo package overlay by [Rodrigo Kochenburger](https://github.com/divoxx) containing packages not available in the [official Gentoo tree](https://packages.gentoo.org/) or the [GURU overlay](https://gpo.zugaina.org/overlays/guru).

- **EAPI:** 8
- **Keywords:** `~amd64` (testing only)

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

## Usage

### eselect-repository (recommended)

```bash
eselect repository add divoxx-overlay git https://github.com/divoxx/gentoo-overlay.git
emaint sync -r divoxx-overlay
```

### repos.conf

Create `/etc/portage/repos.conf/divoxx-overlay.conf`:

```ini
[divoxx-overlay]
location = /var/db/repos/divoxx-overlay
sync-type = git
sync-uri = https://github.com/divoxx/gentoo-overlay.git
auto-sync = yes
```

Then run `emaint sync -r divoxx-overlay`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development workflow, engineering standards, and the PR process.

## License

[GPL-2.0-only](LICENSE) — covers the ebuilds and overlay metadata. Each package's upstream license is declared independently via the `LICENSE=` variable in its ebuild.
