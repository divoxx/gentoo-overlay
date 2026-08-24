# Best Practices

Accumulated session learnings for this project. See also [CONTRIBUTING.md](CONTRIBUTING.md) for authoritative standards.

## Workflow

- **[2026-08-24]** _Pitfall_: Upgrading `sys-apps/portage` in the same `emerge` invocation as any other package can break every merge queued behind it — the running process keeps old portage modules in memory while new ones land on disk (e.g. `TypeError: movefile() got an unexpected keyword argument 'encoding'` after 3.0.82 dropped the Python 2 unicode layer). `--onlydeps` does **not** keep portage out of the graph: `--deep` enables complete-graph mode, which re-adds deep dependencies of the args, `@system` and `@world` sets, and portage is in `@system`. Only `--nodeps` guarantees a single-package merge list. Upgrade portage first with `emerge -u1vN --nodeps sys-apps/portage`, then run every other emerge afterwards so none of them straddles the version boundary.

- **[2026-04-11]** _Pitfall_: GitHub Actions `cancel-in-progress: true` on `push`/`pull_request` workflows marks canceled runs as **failed** on the commit (not skipped), poisoning commit status checks. Fix: set `cancel-in-progress: false` and add a first step that queries `gh run list --json databaseId,status --jq` for newer queued/in-progress runs on the same branch; if any exist, output `should_skip=true` and gate all downstream steps and jobs with `if:` conditions. Requires `actions: read` permission. Note: only affects `push`/`pull_request` triggers — `schedule` and `workflow_run` don't attach per-commit status.
