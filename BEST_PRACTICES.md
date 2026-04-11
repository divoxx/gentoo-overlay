# Best Practices

Accumulated session learnings for this project. See also [CONTRIBUTING.md](CONTRIBUTING.md) for authoritative standards.

## Workflow

- **[2026-04-11]** _Pitfall_: GitHub Actions `cancel-in-progress: true` on `push`/`pull_request` workflows marks canceled runs as **failed** on the commit (not skipped), poisoning commit status checks. Fix: set `cancel-in-progress: false` and add a first step that queries `gh run list --json databaseId,status --jq` for newer queued/in-progress runs on the same branch; if any exist, output `should_skip=true` and gate all downstream steps and jobs with `if:` conditions. Requires `actions: read` permission. Note: only affects `push`/`pull_request` triggers — `schedule` and `workflow_run` don't attach per-commit status.
