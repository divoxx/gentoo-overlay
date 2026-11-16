# Best Practices

Accumulated non-obvious learnings from development sessions.

Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).

Use `/bytewyrd:best-practices-extract` at the end of a session to add new entries.

## Workflow

- **[2026-08-24]** _Pitfall_: Upgrading `sys-apps/portage` in the same `emerge` invocation as other packages can break every merge queued behind it (e.g. `TypeError: movefile() got an unexpected keyword argument 'encoding'` after 3.0.82 dropped the Python 2 unicode layer) — the running process keeps old portage modules in memory while new ones land on disk. The danger is combining the portage atom with `--deep`, not merely omitting `--nodeps`: `--deep` enables complete-graph mode, which re-adds deep dependencies of `@system`/`@world`, and portage is a member of `@system`, so it re-enters the graph alongside unrelated packages even under `--onlydeps`. Fix: gate on `emerge --pretend --update sys-apps/portage | grep -q '^\[ebuild'`, then upgrade with a plain (non-`--deep`) `emerge --oneshot --update sys-apps/portage` before anything else, matching [Gentoo's own recommendation](https://wiki.gentoo.org/wiki/Portage).

- **[2026-04-11]** _Pitfall_: GitHub Actions `cancel-in-progress: true` on `push`/`pull_request` workflows marks canceled runs as **failed** on the commit (not skipped), poisoning commit status checks. Fix: set `cancel-in-progress: false` and add a first step that queries `gh run list --json databaseId,status --jq` for newer queued/in-progress runs on the same branch; if any exist, output `should_skip=true` and gate all downstream steps and jobs with `if:` conditions. Requires `actions: read` permission. Note: only affects `push`/`pull_request` triggers — `schedule` and `workflow_run` don't attach per-commit status.

## Project-Specific

Entries below describe rules and gotchas specific to this codebase. They are not promoted to the global pool by `/best-practices-sync` and they are not transferable to other projects. Do not move entries into or out of this section without re-triaging — see `skills/best-practices-extract/TRIAGE-AND-LIFT.md`.

(none yet — entries are added by `/bytewyrd:best-practices-extract` when a learning fails the portability triage)
