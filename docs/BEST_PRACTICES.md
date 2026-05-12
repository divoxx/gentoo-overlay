# Best Practices

<!-- bootstrap-content-version: 2026-05-10-a81e517 -->

Accumulated non-obvious learnings from development sessions.

Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).

Use `/best-practices-extract` at the end of a session to add new entries.

## Pitfall

- **[2026-05-12]** _Pitfall_: `git add .` fails at repo root in Claude Code sandbox sessions because the sandbox creates null-device character files (`.bash_profile`, `.bashrc`, `.gitconfig`, etc.) that aren't real files. Use explicit paths: `git add src/ docs/ CLAUDE.md .claude/` etc.
- **[2026-05-12]** _Pitfall_: Bash `mkdir`/`cp` may fail in Claude Code sandbox sessions due to write restrictions. The Write file tool often bypasses those restrictions — prefer it over Bash for creating files in restricted directories.

## Workflow

- **[2026-05-12]** _Workflow_: Claude Code agents should never start long-running processes (dev servers, test watchers, build watchers) — always ask the user to run these in a separate terminal.
- **[2026-05-12]** _Workflow_: Run `git fetch --all` at the start of every session before creating branches or worktrees to avoid working from stale refs.
- **[2026-05-12]** _Workflow_: Before pushing any change, run the full quality gate locally (fmt check, linter, tests) — not just the step you touched. The pre-push hook enforces this, but run it yourself first so failures are found before the hook fires.
- **[2026-05-12]** _Workflow_: Keep PRs small and focused on a single concern. Large PRs are harder to review, harder to revert, and hide bugs in unrelated diffs.
- **[2026-05-12]** _Workflow_: Commit messages should describe the WHY, not the WHAT. The diff already shows what changed; the message should explain why the change was necessary.
- **[2026-05-12]** _Workflow_: README.md is a user-facing landing page — not a developer guide. It answers: what is this, why should I care, how does it work, how do I get started. Build commands, test steps, and setup instructions belong in CONTRIBUTING.md.

## Claude Code

- **[2026-05-12]** _Claude Code_: Gather actual error output and logs before diagnosing a problem — don't assume a cause from symptoms. State hypotheses explicitly ("I think X might be causing Y") rather than compressing them into stated facts.
- **[2026-05-12]** _Claude Code_: Verify subagent outputs before reporting success. An agent's summary describes what it intended to do, not necessarily what it did — check the actual file changes or command output.
- **[2026-05-12]** _Claude Code_: Prefer specialized agents (rust-engineer, python-pro, frontend-developer, etc.) for language- and domain-specific work. They have narrower prompts and better defaults for their domain.

## Code Design

- **[2026-05-12]** _Code Design_: A module named `utils`, `helpers`, or `misc` is a textbook example of coincidental cohesion — the weakest type on Constantine's scale, where members are grouped by convenience rather than shared purpose. Every function that ends up there belongs in a domain-aligned module; if you cannot name the module after a concept, the abstraction is missing, not the catch-all.
- **[2026-05-12]** _Code Design_: Apply "Parse, Don't Validate" (Alexis King, 2019): convert raw input into a typed value that structurally encodes its validity constraints, so downstream code cannot use unvalidated data. When enrichment requires external context, make it a separate `resolve(context)` step — keeping parsing pure and dependency-free, and making the enrichment dependencies explicit at the call site.

## Code Style

- **[2026-05-12]** _Code Style_: Optimize code for humans first. Group logically related statements with a blank line between distinct phases (setup, execution, output). A blank line costs nothing and saves the next reader from mentally parsing what belongs together.

## Architecture

- **[2026-05-12]** _Architecture_: Use structured tracing from day one (`tracing` in Rust, OpenTelemetry-compatible libraries elsewhere) — adding spans retroactively is far more painful than instrumenting as you write. Initialize binaries with a runtime env-filter, put spans on functions that perform I/O or cross subsystem boundaries, and never use `println!` / `console.log` for diagnostics in production code.
- **[2026-05-12]** _Architecture_: Single Responsibility — a module/struct/class has one reason to change. Two reasons (e.g., "user persistence" and "user authorization") means two collaborators should split the work, not one monolith.
- **[2026-05-12]** _Architecture_: Open/Closed — extend behavior through new types or strategies, not by editing branches in the existing path. Adding a new payment provider should add a file, not add a `case` to a switch in five files.
- **[2026-05-12]** _Architecture_: Liskov Substitution — a subtype must accept everything its supertype accepts and produce nothing its supertype wouldn't. Violating this turns "polymorphism" into "if statement spread across types."
- **[2026-05-12]** _Architecture_: Interface Segregation — clients depend on the methods they actually use, not a kitchen-sink interface. A 20-method interface that callers use 3 of is 17 methods of false coupling.
- **[2026-05-12]** _Architecture_: Dependency Inversion — high-level policy depends on abstractions; low-level mechanism implements them. The abstraction lives with the policy (it captures what the policy needs), not with the mechanism (which would invert the dependency the wrong way).
- **[2026-05-12]** _Architecture_: Favor composition over inheritance even in OO languages. Inheritance ties two types together at compile time; composition lets you swap collaborators in tests, at runtime, or per environment.
- **[2026-05-12]** _Architecture_: Make illegal states unrepresentable. If a value can only be in one of three modes, model that as a sum type (enum / tagged union / sealed class) rather than three booleans, of which seven of the eight combinations are bugs waiting to happen.
- **[2026-05-12]** _Architecture_: Module boundaries follow change axes. Code that changes together belongs together; code that changes for different reasons belongs apart. Folders organized by technical layer (`controllers/`, `services/`, `models/`) often violate this — group by feature first, by layer second.
- **[2026-05-12]** _Architecture_: A module's public API is a contract; its internals are not. Mark internals as such (private modules / unexported names / `internal/` directory) and resist the pressure to widen the API surface for one-off needs.
- **[2026-05-12]** _Architecture_: Direction of dependency flows from outer (concrete: HTTP, DB, queue) to inner (abstract: domain logic). Domain code never imports adapter code; adapters import the ports the domain defines. This is what hexagonal / clean / onion architecture all boil down to.
- **[2026-05-12]** _Architecture_: Cross-cutting concerns (logging, metrics, auth) belong at the edge, not threaded through domain calls. The domain says what happened; middleware/decorators/aspects observe it.
- **[2026-05-12]** _Architecture_: When a third-party library leaks into a domain type, wrap it. Importing `mongodb::ObjectId` into your `User` struct couples your domain to that driver — when you migrate, every call site changes. A thin adapter type insulates you.

## Testing

- **[2026-05-12]** _Testing_: Tests are non-negotiable — a feature without tests is incomplete. The question is not *whether* to test but *at what level*: pure logic gets unit tests, subsystem boundaries get integration tests, full user flows get end-to-end tests.
- **[2026-05-12]** _Testing_: Practice TDD on pure logic — Red (failing test that captures the requirement) → Green (smallest change that passes) → Refactor (improve structure with the test as a safety net). The cycle prevents over-engineering: code exists only to pass a stated test, not to satisfy an imagined future.
- **[2026-05-12]** _Testing_: TDD-produced tests are documentation of intended usage. Because the test is written before the implementation, it must show how a caller invokes the component — its shape, inputs, and outputs — making the test a worked example a reader can study to understand the design.
- **[2026-05-12]** _Testing_: TDD applies cleanly to algorithmic and decision-logic code (parsers, business rules, state machines). For integration plumbing — code whose entire job is to wire HTTP handlers to a service or shuttle bytes between systems — exercise it via a small integration test that uses the real wire format, not unit tests with mocks of every collaborator.
- **[2026-05-12]** _Testing_: Default to the testing pyramid: many fast unit tests of pure logic, fewer integration tests of subsystem boundaries, fewest end-to-end tests of full user flows. Inverting the pyramid (mostly e2e) makes the suite slow, flaky, and expensive to debug.
- **[2026-05-12]** _Testing_: Use property-based testing for code with algebraic invariants — round-tripping serializers, idempotent operations, sort/parse/normalize functions. Hand-written cases miss adversarial inputs that generators surface in seconds.
- **[2026-05-12]** _Testing_: Mock at architectural boundaries (network, filesystem, clock, randomness), not at module boundaries inside your own code. Mocking your own collaborators couples tests to implementation details and makes refactoring expensive.
- **[2026-05-12]** _Testing_: A flaky test is a broken test — quarantine or fix it the same day, never the same week. Flaky tests train the team to ignore CI failures, which lets a real failure slip through unnoticed.

## Documentation

- **[2026-05-12]** _Documentation_: Documentation is a first-class deliverable, not a chore. A feature that ships without docs is incomplete in the same way as one without tests — the code may run, but no one outside its author can use, review, or evolve it confidently.
- **[2026-05-12]** _Documentation_: Three audiences, three files: `README.md` (users — what is this and how do I run it), `docs/CONTRIBUTING.md` (developers — how do I work on it), `docs/ARCHITECTURE.md` (system designers — how is it built and why). Mixing audiences forces every reader through irrelevant content.
- **[2026-05-12]** _Documentation_: Write docs for the *next* developer (often you in six months), not for the current one. Explain *why* a decision was made, not just what was decided — the diff already shows the what.
- **[2026-05-12]** _Documentation_: Keep docs adjacent to the code they describe. Library-level docs in module headers; function-level docs on the function. Out-of-band docs drift; in-tree docs travel with the code.
- **[2026-05-12]** _Documentation_: Examples are the highest-density docs. A working example beats a paragraph of prose — copy-paste-ability is what real users need.
- **[2026-05-12]** _Documentation_: Code comments explain *why* and *what for*, not *what*. The code already shows what it does; a comment that paraphrases the code adds noise. A comment that captures the constraint, the trade-off, or the reason for an apparent contradiction is gold.
- **[2026-05-12]** _Documentation_: Architecture decision records (ADRs / RFCs) are how you preserve the *why* across years. When you reverse a past decision, link the new RFC to the old one — the historical context is part of the explanation.

## Security

- **[2026-05-12]** _Security_: Never expose tokens, credentials, or secrets in committed code, in client-side bundles, or in logs. Pull secrets from a secret manager at runtime; redact known-secret keys from log output unconditionally.
- **[2026-05-12]** _Security_: Validate input at the boundary, then trust it inside. A request enters validation once and emerges as a typed domain value — no defensive re-validation throughout the stack.
- **[2026-05-12]** _Security_: Run with the lowest privilege required. Service accounts get the narrowest IAM role; container processes run as non-root; database users get only the schemas they need.
- **[2026-05-12]** _Security_: Pin and audit dependencies. Lockfiles commit the exact versions you tested; an automated audit step catches CVEs in CI rather than in the wild.
- **[2026-05-12]** _Security_: Treat AuthN and AuthZ as separate concerns. Authentication answers "who is this"; authorization answers "may they do this". Conflating them is how systems end up with `if user.is_admin` checks scattered through business logic.

## Error Handling

- **[2026-05-12]** _Error Handling_: Distinguish recoverable errors (return them) from programmer errors (panic / abort). A failed network call is recoverable; a violated invariant inside your own code is not — recovering from it produces zombie state.
- **[2026-05-12]** _Error Handling_: Errors carry context. The error returned three layers up should tell the operator what the system was trying to do, what failed, and what input was involved — not just the leaf cause.
- **[2026-05-12]** _Error Handling_: Errors should be observable before they are user-visible. Structured logs and metrics catch the error trend before the user reports the symptom.
- **[2026-05-12]** _Error Handling_: Retries belong at the edge of an idempotent operation. Wrapping a non-idempotent call in retry logic doubles the transactions and corrupts state.

## Project-Specific

Entries below describe rules and gotchas specific to this codebase. They are not promoted to the global pool by `/best-practices-sync` and they are not transferable to other projects. Do not move entries into or out of this section without re-triaging — see [`skills/best-practices-extract/TRIAGE-AND-LIFT.md`](../skills/best-practices-extract/TRIAGE-AND-LIFT.md).

(none yet — entries are added by `/best-practices-extract` when a learning fails the portability triage)
