# Build Orchestrator — Design Document

> A successor design for the kanban meta-repo orchestrator. Distilled from a
> simulation walkthrough of building a study app end-to-end. Captures both
> what to build and why each choice was made, because the *why* is what
> protects the system from drift.

---

## Table of Contents

1. [Purpose and Scope](#purpose-and-scope)
2. [Core Principles](#core-principles)
3. [The Two-Phase Boundary](#the-two-phase-boundary)
4. [What "Sharp" Means](#what-sharp-means)
5. [System Architecture](#system-architecture)
6. [Schema Layer](#schema-layer)
7. [The Task Card](#the-task-card)
8. [The Project Registry](#the-project-registry)
9. [The Audit Entry](#the-audit-entry)
10. [The Artifact Registry](#the-artifact-registry)
11. [Prompt Assembly](#prompt-assembly)
12. [The Gate](#the-gate)
13. [Checks](#checks)
14. [Output Validation](#output-validation)
15. [The Reviewer](#the-reviewer)
16. [Retry Semantics](#retry-semantics)
17. [The Draft Session](#the-draft-session)
18. [Status Lifecycle and Milestones](#status-lifecycle-and-milestones)
19. [Architectural Seams](#architectural-seams)
20. [Build Sequence](#build-sequence)
21. [Out of Scope (Explicitly)](#out-of-scope-explicitly)
22. [Glossary](#glossary)

---

## Purpose and Scope

This system is a **build orchestrator** — a tool that takes well-formed task
cards as input and produces audited, tested, reproducible artifacts (code,
files, documents) as output. It is domain-agnostic: it does not know or care
whether a task is part of a research project, a web app, a CLI tool, or a
study guide. It accepts task cards. That is the entire contract.

The orchestrator is the **build-engineering** half of a larger
research/build system. The other half — the epistemic phase, where research
questions are sharpened and methodology is developed — produces task cards
as its output. The orchestrator consumes them. Anything in the orchestrator
that "knows" it is running a research project is a leak that should be
plugged. Conversely, anything in the orchestrator that requires a task card
to come from the epistemic phase (rather than being written by hand or by a
draft session) is over-coupling.

The orchestrator is built first, as a solo developer, used daily on real
projects. It is built with seams that allow it to be embedded later as the
execution engine of a multi-user platform — but the platform is not the
target. A sharp single-user system that the operator trusts and uses
regularly is the target. Everything else follows from that.

## Core Principles

These are the principles that win arguments. When a proposed feature
conflicts with one of these, the principle wins.

**1. Domain-agnostic core.** The orchestrator does not know what a "research
project" or "study app" is. It knows tasks, dependencies, checks, reviewers,
artifacts. Domain knowledge lives in task cards, never in orchestrator code.

**2. Markdown is the human interface; typed objects are the machine
interface.** Task cards, registry entries, and audit entries are markdown
files (humans read them, models edit them, git diffs them). Internally, the
orchestrator parses them into Pydantic models and reasons about typed
objects. The markdown is the source of truth; the typed objects are the
runtime representation.

**3. Determinism before judgment.** Mechanical checks (lint, tests, schema
validation) run before LLM reviewers. A task that fails a check never
reaches the reviewer. The reviewer is the *last* line of defense, not the
*only* line.

**4. Atomicity at every write.** Every state change — task card status,
audit entry, registry update — is written via temp file + atomic rename.
The system can crash at any point and be left in a recoverable state.

**5. Plan as a whole, execute one at a time.** Task plans are approved as
complete sets, not card-by-card. Once a plan is approved, every card exists
on disk in a well-formed, schema-validated state. Execution is then
sequential (in assisted mode) or dependency-graph-driven (in managed mode).

**6. The audit log is the system's memory.** Every execution attempt writes
an immutable audit entry. The audit log is the canonical record of what
happened — not the task card status, not the dashboard, not the operator's
memory. State derived from the audit log is reproducible; state held
elsewhere is not.

**7. Human-in-the-loop at the gate.** The operator approves every model
invocation before it happens. The gate is non-negotiable. Even in managed
mode, even with --plan-first, the gate fires before any model call that
will affect the working state. Speed is not a justification for removing
the gate; if speed matters, run multiple tasks in sequence after a single
gate, but the gate itself stands.

**8. Suggest, don't auto-act.** Status transitions, milestone advancements,
plan generations, retries — all of these are *suggested* by the system and
*confirmed* by the operator. Auto-actions are reserved for things that are
mechanically reversible (status updates after a successful run) or part of
an already-confirmed flow (writing audit entries after a logged session).

**9. Be ruthless about scope.** When in doubt, do not add the feature. The
schema that's right for the first 7 tasks of the first project is probably
right for the first 700 tasks across many projects, with maybe 3–4
considered additions. Resist the urge to add fields, commands, or special
cases. Most additions are escapes from a constraint that is doing useful
work.

## The Two-Phase Boundary

The larger system has two phases, and the orchestrator lives entirely in
phase 2.

**Phase 1 (Epistemic):** No code is written. This is where the question is
sharpened, the data schema is designed, the methodology is developed, the
assumptions are made explicit. The output is a set of well-formed task
cards plus a project registry entry. Phase 1 is research-specific and is
not what this document specifies.

**Phase 2 (Build Orchestration):** Task cards become real code, real files,
real artifacts. This is what the orchestrator is. It is broadly applicable
— a study app, a UI, a research pipeline, a content tool, a small SaaS
prototype all flow through the same orchestrator.

The contract between the phases is the **task card schema** and the
**registry schema**. Anything well-formed under those schemas is a valid
input to the orchestrator. The orchestrator never asks "where did this
card come from."

This boundary is what makes the orchestrator reusable. It is also why phase
2 is built first: phase 1 has more uncertainty, more iteration, more
domain-specific shape; phase 2 is more universal. Sharpening phase 2 first
means phase 1's eventual outputs have a clear target to write toward.

## What "Sharp" Means

"Sharp" does not mean feature-rich. It means a small set of guarantees that
hold every time, on every project, with no special handling.

When the operator runs `kanban run <project> <task>`, they can trust that:

1. The task card was schema-validated before any work started. No
   regex-based "best effort" parsing.
2. The execution environment is captured: git SHAs, Python version,
   lockfile hash. The audit entry is replayable in principle.
3. The generated work passes deterministic checks (lint, types, tests,
   schema validation) **before** any LLM reviewer is invoked.
4. Artifacts produced are tracked with content hashes and provenance.
   "What produced this file" and "what consumes this file" are queryable.
5. A failed run leaves the system in a clean state. No half-updated cards,
   no orphan files, no ghost states. The failure mode is fully captured in
   the audit log.
6. Re-running a task with unchanged inputs is detectably idempotent.

These six guarantees define the system's value proposition. Every feature
either supports one of them or is at risk of being scope creep.

## System Architecture

The orchestrator is a Python package with a CLI entry point. It runs
locally, writes to the local filesystem, and invokes external CLIs (Claude,
Codex) as subprocesses. There is no server, no database service, no async
worker pool. Persistence is plain files plus a single SQLite database for
the artifact registry.

```
┌─────────────────────────────────────────────────────────────┐
│                          CLI                                │
│              (kanban run, log, prep, review, …)             │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────────┐
│                       Orchestrator                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐  │
│  │  Plan    │  │ Context  │  │   Gate   │  │  Executor   │  │
│  │ (draft)  │  │ Assembly │  │          │  │             │  │
│  └──────────┘  └──────────┘  └──────────┘  └─────────────┘  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐  │
│  │  Checks  │  │  Output  │  │ Reviewer │  │  Logging    │  │
│  │  Runner  │  │Validation│  │          │  │             │  │
│  └──────────┘  └──────────┘  └──────────┘  └─────────────┘  │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────────┐
│                      Store (interface)                      │
│  ┌─────────────────┐  ┌────────────────┐  ┌───────────────┐ │
│  │   Filesystem    │  │  SQLite        │  │  (Future:     │ │
│  │   (markdown)    │  │  (artifacts)   │  │   Postgres)   │ │
│  └─────────────────┘  └────────────────┘  └───────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

The Store interface is the seam that allows future migration to a
multi-user backend without touching the upper layers. For v1, it is
filesystem + SQLite; the abstraction exists but the only implementation is
local. Do not build a second implementation until there is a real second
deployment target.

## Schema Layer

The schema layer is the foundation. Everything else depends on it. This is
the highest-leverage piece of the system and the first thing to build
right.

**Three schema types, all backed by Pydantic models that mirror the
markdown:**

- `TaskCard` — one per unit of work, lives in `<project_repo>/tasks/`
- `RegistryEntry` — one per project, lives in
  `<meta_repo>/projects/<project_id>/registry.md`
- `AuditEntry` — one per execution attempt, lives in
  `<meta_repo>/audit/`

For each schema:

1. Write the markdown spec in `schemas/<name>.schema.md`. This is the
   human-facing canonical reference.
2. Write the Pydantic model in `orchestrator/models/<name>.py`. This is
   the machine-facing canonical reference.
3. Write a parser `parse_<name>(path) -> <Model>` that reads markdown and
   returns the typed object.
4. Write a serializer `serialize_<name>(model) -> str` that writes a
   markdown representation. Round-trip identity is a test invariant: a
   parsed-then-serialized markdown file equals the original (modulo
   whitespace normalization).
5. Write a validator `validate_<name>(path) -> list[ValidationError]`
   that returns structured errors. Used by `kanban validate <project>` to
   pre-check all cards.

The markdown spec and the Pydantic model are kept in sync by a test that
imports the model and asserts it covers every field documented in the
spec. The spec is the contract; the model is the enforcement.

**Why both markdown and Pydantic:**

The markdown form is what humans edit, what models read in prompts, what
git diffs, what the LLM produces when generating new cards. It is the
substrate. The Pydantic form is what the orchestrator reasons about
internally — typed, validated, queryable. Without the typed form, every
orchestrator function reaches into markdown with regex, which is the
single biggest source of bugs in the current system. Without the markdown
form, humans cannot read or edit the system without tooling.

## The Task Card

A task card represents one unit of work. It is the central object of the
system. Every other piece of the orchestrator exists to serve task cards.

**Required fields:**

- `id`: zero-padded three-digit string, matches filename prefix
- `title`: short imperative phrase
- `status`: TODO | IN_PROGRESS | REVIEW | DONE | BLOCKED
- `objective`: plain-language statement, self-contained
- `acceptance_criteria`: GFM checklist items

**Optional but commonly used:**

- `reviewer`: alias (`sonnet`, `opus`, `sonnet-mini`, `none`) or pinned model ID
- `inputs`: read-only files this task depends on
- `modifies`: files this task will read and edit (existing state included
  in prompt context)
- `see_also`: files for read-only context (included in prompt but not
  declared as dependencies)
- `outputs`: files this task is expected to produce
- `requirements`: discrete, testable constraints
- `checks`: shell commands to run after execution, before reviewer
- `output_validation`: shell commands that validate produced artifacts
  against contracts
- `blocked_by`: task IDs that must reach DONE first
- `notes`: free-form operator commentary, including swap-point flags

**The Inputs / Modifies / See Also distinction:**

This is more important than it looks. Three categories, three different
prompt-assembly behaviors:

- **Inputs**: read-only files this task depends on. Included in prompt as
  context. The model is instructed not to modify them. Missing inputs
  trigger a gate warning.
- **Modifies**: files this task will edit. Current state is included in
  prompt. The model is instructed that it may produce a new version.
  After execution, file existence is verified and content is hashed.
- **See Also**: files for read-only context, supplementary, not part of
  the declared interface. Included in prompt at the operator's discretion
  to give the model architectural visibility without making the task
  dependent on those files. Missing See Also files do not warn.

The semantic difference: Inputs and Modifies are the *contract* of the
task; See Also is *context*. The contract is what makes the task
reproducible. The context is what makes the task generate code that fits
the existing architecture.

**The reviewer field:**

Use aliases (`sonnet`, `opus`, `sonnet-mini`) not pinned model strings, so
cards do not go stale when models are updated. Aliases resolve via
`orchestrator/models.yaml`. Selection guidance:

- `opus` — statistical modeling, architecture decisions, judgment-heavy
  UX requirements, anything where false-PASS verdicts are costly
- `sonnet` — mechanical tasks, schema work, persistence layers, UI
  scaffolding where most criteria are mechanically verified
- `sonnet-mini` — trivial validation passes
- `none` — the task's pass/fail is entirely mechanical, or the final
  judgment is the operator's eyeball check

**Project default checks:**

Most tasks share the same set of mechanical checks (lint, format, types,
tests). These are declared once in the registry under `## Default Checks`
and inherited by every task. Task-level `checks` are *additional* unless
the card explicitly opts out via `## Skip Default Checks: [<check name>]`.

## The Project Registry

The registry has one entry per registered project, in
`projects/<project_id>/registry.md`. It is the orchestrator's discovery
mechanism — the dashboard reads it, the gate reads it, the runner reads
it.

**Required fields:** `project_id`, `name`, `status`, `default_mode`,
`created_date`, `updated_date`.

**Recommended fields:** `description`, `repo_path`, `tech_stack`,
`dependencies`, `downstream_dependents`, `cli`, `timeout_minutes`,
`success_criteria`, `default_checks`.

**Status values:** `PLANNED`, `ACTIVE`, `MILESTONE_<TAG>`, `PAUSED`,
`COMPLETE`, `ARCHIVED`. The `MILESTONE_<TAG>` form (e.g. `MILESTONE_V1`)
is used to mark significant points; the orchestrator suggests these
transitions but does not auto-apply them.

**Default Checks:**

A new section, `## Default Checks`, lists the project-wide checks that
every task inherits. Example for a Python project:

```markdown
## Default Checks
- `uv sync --frozen`
- `uv run ruff check .`
- `uv run ruff format --check .`
- `uv run mypy src/`
- `uv run pytest`
```

For an R project:

```markdown
## Default Checks
- `Rscript -e 'lintr::lint_dir()'`
- `Rscript -e 'devtools::test()'`
```

For polyglot, list both. The orchestrator does not interpret the
commands; it runs them and checks exit codes.

## The Audit Entry

One audit entry per execution attempt. Filename:
`YYYYMMDD_HHMMSS_<project_id>_<task_id>.md`. Reviewer entries get a `_rev`
suffix.

**Required fields:** `entry_id`, `timestamp`, `project`, `task_id`,
`task_title`, `mode`, `model`, `reviewer_model`, `status_before`,
`status_after`.

**New required fields (additions to current system):**

- `git_sha_project`: SHA of the project repo HEAD at task start
- `git_sha_orchestrator`: SHA of the orchestrator HEAD at task start
- `python_version`: full version string
- `lockfile_hash`: SHA256 of the project's lockfile (uv.lock,
  requirements.lock, renv.lock — whichever applies)
- `env_vars_present`: list of env var names present (not values), for
  reproducibility documentation

**Optional fields:** `duration_seconds`, `verdict`, `prompt_file`,
`output_file`, `notes`, `check_results`, `validation_results`,
`api_cost_estimate`.

**The check_results and validation_results sections:**

Each check and validation gets a structured result block:

```markdown
## Check Results

- [OK]   uv sync --frozen (0.4s)
- [OK]   uv run ruff check . (0.7s)
- [FAIL] uv run mypy src/ (3.2s, exit code 1)

  Output (verbatim):
  ```
  src/study_app/pdf_extraction.py:34: error: ...
  ```
```

The audit log captures the *full* check output verbatim. Truncation is
for the terminal display; the audit log keeps everything because you
cannot predict what will be needed later.

## The Artifact Registry

A SQLite database at `audit/artifacts.db` tracking every file produced by
every task. Schema:

```sql
CREATE TABLE artifacts (
    id INTEGER PRIMARY KEY,
    path TEXT NOT NULL,
    sha256 TEXT NOT NULL,
    size_bytes INTEGER NOT NULL,
    produced_by_entry_id TEXT NOT NULL,
    created_at TEXT NOT NULL,  -- ISO 8601 UTC
    UNIQUE (path, sha256)
);

CREATE TABLE artifact_consumers (
    consumer_entry_id TEXT NOT NULL,
    artifact_id INTEGER NOT NULL REFERENCES artifacts(id),
    role TEXT NOT NULL,  -- 'input' | 'modifies' | 'see_also'
    PRIMARY KEY (consumer_entry_id, artifact_id, role)
);

CREATE INDEX idx_artifacts_path ON artifacts(path);
CREATE INDEX idx_artifacts_entry ON artifacts(produced_by_entry_id);
CREATE INDEX idx_consumers_entry ON artifact_consumers(consumer_entry_id);
```

After a successful task run, the orchestrator hashes every declared output
and inserts a row. Consumer relationships are inserted from the task
card's Inputs and Modifies fields.

**Initial queries to support (via `kanban artifact ...` subcommands):**

- `kanban artifact origin <path>` — what produced this file
- `kanban artifact dependents <path>` — what tasks consumed this file
- `kanban artifact diff <path>` — list all versions, by hash, with
  producing entry IDs

Defer more advanced queries (cross-artifact graph queries, schema
conformance queries) until they are needed. The data accumulates whether
or not the queries exist.

**Why SQLite, not a graph database:** SQLite handles this. The "graph"
queries are two-table joins. Adding Neo4j or RDF would be a significant
operational and conceptual cost for queries that don't yet exist. Resist.

## Prompt Assembly

The orchestrator assembles a prompt from the task card and its
declared context. Section order:

1. **Meta-repo project context** — `project_context.md` from the meta-repo
2. **Project context** — `project_context.md` from the project repo (if
   different from meta-repo)
3. **Project registry entry** — full content
4. **Upstream project audit summaries** — recent audit entries from
   projects this project depends on
5. **Inputs (read-only)** — full content of every file in the task's
   Inputs field
6. **Modifies (current state)** — full content of every file in Modifies,
   labeled as current state to be edited
7. **See Also (context)** — full content of every file in See Also,
   labeled as supplementary
8. **Schemas in scope** — Pydantic models referenced by Inputs/Modifies/
   Outputs, exported as JSON Schema
9. **The task card itself** — full markdown

**Schema injection (item 8):**

When a Pydantic model in the project's `schemas.py` (or equivalent) is
referenced by the task — either because it appears in an Input, a
Modifies, or because the task's Outputs include validators that reference
it — the orchestrator includes the schema in the prompt as JSON Schema
exported via `Model.model_json_schema()`.

This is the cleanest argument for schema-as-code: the same Pydantic model
drives the generation prompt and the validation step. The model gets the
contract at generation time, not just at validation time, which
substantially reduces the rate of schema-noncompliant outputs.

**Token budget management:**

This is the part that needs real engineering work. A naive "include
everything declared" strategy works for a 7-task project; it does not
scale to a 50-task project where Inputs include large data files or
where See Also accumulates the entire codebase.

V1 strategy: include everything declared, no truncation, no summarization.
Trust the operator to declare narrowly. Add a token-count display in the
gate output so the operator sees when a task is approaching context
limits. Defer smarter strategies (per-section truncation, lazy loading,
summarization) until a real task hits a real limit.

## The Gate

The human-in-the-loop gate fires before every model invocation that will
affect working state. It is non-negotiable.

**Gate display:**

```
------------------------------------------------------------
  KANBAN GATE
------------------------------------------------------------
  Project    : <name> (<project_id>)
  Task       : <id> — <title>
  Reviewer   : <alias> → <resolved model>
  Mode       : <assisted | managed>
  Inputs     : <n> found, <m> missing
    [OK]      <path>
    [MISSING] <path>
  Modifies   : <n> found, <m> missing
  See Also   : <n> found
  Outputs    : <n> declared (none exist yet — expected)
  Checks     : <n> inherited + <m> task-level
  Output Validation: <n> declared
  Schemas in prompt context: <list>
  Environment:
    Python <version>
    Project repo SHA: <sha> (clean | dirty)
    Orchestrator SHA: <sha> (clean | dirty)
    Lockfile SHA: <sha>
    API keys present: <list of env var names>
  Estimated prompt tokens: <n>
------------------------------------------------------------

[NOTE] <any contextual notes — opus rationale, missing PDF warning,
        live-API test about to run, etc.>

[y/n/e] Proceed? _
```

**Operator choices:** `y` (proceed), `n` (abort), `e` (open prompt in
$EDITOR before proceeding).

**Notes section:** explicit, bracketed, used for contextual reminders the
operator should see. Examples: "Reviewer is opus because UX requirements
are judgment-heavy"; "Declared input X was not found"; "This task makes a
real API call (~$0.02)"; "Prompt is approaching token limit (87% of
budget)".

The notes section is the place to put friction. If a task is doing
something unusual or expensive, the gate is where the operator gets one
more chance to notice.

## Checks

Checks are deterministic boolean functions of the project's working state,
expressed as shell commands. They run after declared outputs are verified
to exist and before the reviewer is invoked. Any non-zero exit code halts
the sequence and blocks the task.

**Check specification:**

In a task card, checks are a list of strings (shell commands) or objects
(for advanced cases):

```markdown
## Checks
- "uv run pytest tests/integration/"
- name: "load test"
  run: "uv run pytest tests/load/"
  timeout: 300
  on_fail: warn
```

The string form desugars to `{run: <string>, on_fail: block}`. The object
form supports:

- `name`: human-friendly display name
- `run`: the command (required)
- `timeout`: per-check timeout in seconds
- `on_fail`: `block` (default), `warn`, or `retry` (with `max_retries`)

**v1 implementation:** support only the string form. Object form is a v2
addition. The string form covers 95% of use cases and is enough to ship.

**Check resolution:**

The full check set for a task is: project default checks + task-level
checks - skipped defaults. The gate displays the resolved list. The
operator should never have to wonder which checks will run.

**Failure handling:**

- Halt on first failure (v1). Argument for run-all-collect-failures is
  real; defer until a real workflow demands it.
- Capture full stdout + stderr verbatim into the audit entry under
  `## Check Results`. Truncate for terminal display only.
- Block the task: status goes from TODO/IN_PROGRESS to BLOCKED.
- Write the audit entry **before** updating status. Both writes are
  atomic. If the orchestrator crashes between them, the system is
  recoverable from the audit log.

**The boundary with the reviewer:**

The reviewer never sees a task whose checks failed. When a task is
retried after a check failure and checks then pass, the reviewer sees
the *latest* audit entry — the green one — not the failed history. The
failed entries remain on disk for forensic purposes but are not part of
the reviewer's input.

This is what makes the reviewer focused. The reviewer's job is "given
that this code passes mechanical checks, does it satisfy the intent of
the acceptance criteria?" Not "did the linter pass?" — that's already
known.

## Output Validation

Output validation is a separate field from checks, even though
mechanically they are similar. The distinction is semantic:

- **Checks** answer: "did the tools accept the code I wrote?" (about the
  producer's work)
- **Output Validation** answers: "does the artifact this task produced
  conform to the contract that downstream tasks will consume?" (about the
  contract the artifact must satisfy)

**v1 implementation:** output validations are declared in
`## Output Validation` as the same shape as checks (shell commands).
Convention: validator scripts are named `validate_<artifact>.py` so they
are greppable. They take a path argument and exit 0 (pass) or non-zero
(fail) with errors on stderr.

**Layered validation:**

A well-written validator checks at four layers:

1. **Existence** — file is at declared path
2. **Format** — file parses as the type it claims to be (JSON, YAML,
   PNG, etc.)
3. **Schema** — parsed content matches a Pydantic model
4. **Semantic** — content is plausible given context (cross-field
   constraints, references to other artifacts)

Layers 1 and 2 are universal. Layer 3 is universal-when-applicable
(structured outputs only). Layer 4 is project-specific.

**Schema-as-code:**

Output schemas are Pydantic models in `<project>/schemas.py`. They are
used in three places:

- Generation: injected into the prompt as JSON Schema
- Validation: imported by the validator script for `model_validate`
- Documentation: optionally exported to markdown for human reference

This is a different choice from task-card / registry / audit schemas,
which are markdown-first with Pydantic mirrors. Output schemas are
code-first because they are consumed by code at validation time and have
no human-edit pathway during normal use.

**The validator-in-the-loop pattern:**

For LLM-generated artifacts (e.g., MCQs), output validation may be
combined with retry: if validation fails, the model is re-invoked with
the validation errors appended to the prompt, up to N retries. This is
implemented as a separate command, `kanban regenerate <project>
<task_id> [--max-retries N]`, not as automatic behavior in `kanban log`.

This is opt-in because LLM cost matters and because some validation
failures genuinely require human intervention.

## The Reviewer

The reviewer is invoked after all checks and output validations pass. It
evaluates each acceptance criterion and returns a structured PASS/FAIL
verdict. On PASS, the task advances to DONE. On FAIL, the task goes to
BLOCKED.

**Reviewer prompt structure:**

1. Reviewer instructions (canonical, version-controlled in
   `orchestrator/reviewer_instructions.md`)
2. Task card (full content)
3. Latest audit entry (showing all checks and validations passed)
4. The files produced or modified by the task (full content)

**Verdict format:**

```
VERDICT: PASS | FAIL
CRITERIA:
- [criterion text]: PASS | FAIL — [evidence or one-line note]
SUMMARY: [2-3 sentences]
```

**Evidence requirement (key change):**

For any *judgment-class* criterion — one not already mechanically
verified by checks or validation — the reviewer must cite specific
evidence: a quoted line, a structural property, a verified absence.

Acceptable: "PASS — `routes.py` lines 34–48 (`POST /sessions`) call
`extract_pdf()` and `generate_mcqs()` then `dal.create_session()`; no
scoring or filtering logic in this handler."

Not acceptable: "PASS — code looks clean."

This rule is what defends against false-PASS verdicts on judgment-heavy
tasks (especially UX-style criteria). Encoded in the reviewer
instructions; enforced by the verdict format.

**Mechanical criteria** (those already verified by checks or output
validation) can pass with "verified by check N" without restating
evidence.

**Verdict parsing:**

Regex-extract the `VERDICT:` line. If parsing fails, retry once with the
same prompt. If parsing fails twice, treat as FAIL with a note that
parsing failed; the operator must intervene manually.

**Reviewer audit entry:**

A reviewer invocation produces its own audit entry, with `mode: review`
and a `_rev` suffix on the entry ID. The reviewer's full output is saved.
The verdict block is also appended to a `## Reviewer Notes` section in
the task card.

## Retry Semantics

Three distinct retry mechanisms exist. They must be kept conceptually
separate because confusing them is a source of bugs.

**1. `kanban retry <project> <task_id>`** — re-run all checks and
validations against the *current* state of the working directory. Does
NOT re-invoke the LLM. Used after the operator has manually fixed an
issue (typo, lint error, etc.) and wants to verify before proceeding.

Behavior: re-runs all checks from scratch (not just the failed one),
re-runs all validations, writes a new audit entry, advances status if
all pass.

**2. `kanban rerun <project> <task_id> [--include-failure]`** — re-invoke
the LLM with the previous prompt. With `--include-failure`, the previous
audit entry (containing failure output) is appended to the prompt with an
instruction to fix the issues and produce a complete corrected version.

Behavior: builds a new prompt, fires the gate, runs the executor, captures
output, advances to the same post-execution flow as a fresh run.

**3. `kanban regenerate <project> <task_id> [--max-retries N]`** —
specifically for output-validation-failure-driven retry of LLM-generated
artifacts. The model is re-invoked with the validation errors appended,
up to N times. Each attempt produces an audit entry. The task advances
only on a clean validation pass.

Behavior: like rerun, but with a feedback loop driven by validation
failure rather than check failure, and bounded by max-retries.

These three commands have different semantics, different audit shapes, and
different cost profiles. Document them clearly. Resist the temptation to
unify them into a single "retry" command.

## The Draft Session

`kanban draft` is the orchestrator's own intake mechanism for projects that
do not come from the epistemic phase. It produces task cards from a
short conversational session.

**Session structure:**

1. **Project framing questions (3–5):** target user, deployment context,
   data flow, technology constraints, definition of done. The system
   accepts "skip" as a first-class answer and makes a defensible default.

2. **Plan generation:** a flat list of proposed tasks with titles, scope
   one-liners, dependency edges, reviewer model assignments, and notes
   on open questions or assumptions. NOT generated as task cards yet.

3. **Plan approval gate:** displayed as a complete proposal, approved as
   a whole. Options: y (write all cards), n (abort), e (edit the plan
   in $EDITOR; the orchestrator re-parses on save).

4. **Card generation:** on approval, every card is written to disk in
   schema-validated form. The project status moves from PLANNED to
   ACTIVE.

**Draft session principles:**

- Short by default. 3–5 questions, not 20. The session generates
  defensible defaults and flags them; the operator iterates by editing
  cards, not by extending the questionnaire.
- Inconsistency-tolerant. The operator may give answers that conflict.
  The session resolves by asking a clarifying question only when the
  conflict is significant; otherwise it picks one and notes the choice.
- Plan-as-a-whole. Cards are not generated until the entire plan is
  approved. This keeps architectural coherence — the model sees the full
  task graph before writing any individual card.

**For research projects:**

The draft session is *not* used for research projects. Those flow from
the epistemic phase (Counsel/Committee/Board), which produces task cards
directly. The orchestrator does not care which path produced the cards —
both are well-formed inputs.

## Status Lifecycle and Milestones

**Task statuses:** TODO → IN_PROGRESS → REVIEW → DONE, or any of these to
BLOCKED. A task that fails checks goes to BLOCKED. A task whose reviewer
returns FAIL goes to BLOCKED. The operator can manually set BLOCKED for
external reasons.

**Project statuses:** PLANNED → ACTIVE → MILESTONE_<TAG> → COMPLETE.
PAUSED and ARCHIVED are off-axis states.

**Milestone advancement:**

When all tasks marked as part of a milestone reach DONE, the orchestrator
*suggests* a milestone advancement:

```
[runner] Project milestone detected: all 7 v1 tasks DONE.
[runner] Suggesting registry update: study-app status PLANNED → MILESTONE_V1.
         Run 'kanban milestone study-app v1' to confirm, or skip to leave
         registry status unchanged.
```

The advancement is not automatic. v1 being "done" is a judgment call that
includes things outside the orchestrator's view (have you actually used
the app?). The orchestrator detects the *condition*; the operator makes
the *call*.

**How tasks are marked as part of a milestone:**

Two options, decide before implementing:

(a) A `milestone:` field on each task card (e.g., `milestone: v1`).
    Pro: explicit per task. Con: must be set on every card.

(b) Milestone groups declared in the registry, listing task IDs.
    Pro: centralized. Con: another file to keep in sync.

**Recommendation:** start with (a). Simpler. Migrate to (b) only if the
v1 list of milestones grows beyond what feels manageable as per-card
fields.

## Architectural Seams

These are the seams that allow the system to grow without rewrites. Build
them from day one even if the second implementation is years away.

**1. The Store interface.** All filesystem and database access goes
through a `Store` abstraction with methods like `get_task`,
`update_status`, `list_audit_entries`, `register_artifact`,
`query_artifacts`. The default implementation is filesystem + SQLite. A
future Postgres implementation can replace it without touching upper
layers.

**2. Schema-as-code for output schemas.** Pydantic models in the project
repo, imported by validators, exported as JSON Schema for prompts. One
source of truth, three consumers.

**3. The Executor interface.** Task execution is `Executor.run(task,
prompt) -> ExecutionResult`. The default executor is local subprocess
(claude CLI, codex CLI). A future remote executor (worker pool, queue)
can replace it. Same `run` signature.

**4. The LLM Client abstraction (in projects, not the orchestrator).**
For projects that themselves call LLMs at runtime, an `LLMClient`
abstraction in the project's code separates "which provider" from "what
the project does with completions." This is project-internal architecture,
but the orchestrator can encourage it by making it cheap to declare in
task cards (e.g., a task whose deliverable is the LLMClient itself, used
by downstream tasks).

**5. The plan/execute boundary.** Drafting and executing are separate
commands. A plan is data; executing a plan is a separate action.
Combining them would foreclose batch operations, plan-only previews, and
non-interactive plan generation.

**Do NOT build these seams yet:** plugin systems, DSLs for task
definition, web APIs, multi-tenant isolation, message queues. These are
all "build for the future" features that solve problems that do not yet
exist. The seams above are different — they are minimal abstractions
that prevent leakage, not infrastructure for capabilities that may never
be needed.

## Build Sequence

Roughly two months of solo work, paced for steady progress. Each step
produces something usable and is testable before moving on.

**Phase A: Schema layer (1 week)**

A1. Pydantic models for `TaskCard`, `RegistryEntry`, `AuditEntry`.
A2. Markdown parsers for each (replace existing regex parsers).
A3. Markdown serializers for each.
A4. Round-trip tests (parse-then-serialize equals original).
A5. `kanban validate <project>` command — schema-validates all cards.
A6. Migration: convert existing tasks/, registry, audit to validated form.

Outcome: malformed cards are rejected at gate time, not silently parsed.
This is the foundation.

**Phase B: Checks (3 days)**

B1. Implement project-level default checks in registry.
B2. Implement task-level checks (additive).
B3. Implement skip-default-checks (subtractive).
B4. Run checks after declared outputs verified, before reviewer.
B5. Capture verbatim output to audit entry.
B6. Block task on first failure.

Outcome: deterministic verification before LLM judgment. The biggest
single quality-of-life improvement.

**Phase C: Audit entry enhancements (2 days)**

C1. Capture git SHA of project repo at task start.
C2. Capture git SHA of orchestrator at task start.
C3. Capture Python version, lockfile hash, env vars present.
C4. Add structured `## Check Results` section.
C5. Add structured `## Validation Results` section.

Outcome: every audit entry is replayable in principle.

**Phase D: Artifact registry (3 days)**

D1. SQLite schema with `artifacts` and `artifact_consumers` tables.
D2. After successful task run, hash declared outputs and insert.
D3. Insert consumer relationships from Inputs/Modifies/See Also.
D4. CLI commands: `kanban artifact origin`, `dependents`, `diff`.

Outcome: queryable provenance. "What produced this file" is one command.

**Phase E: Reviewer prompt rewrite (1 day)**

E1. Update `reviewer_instructions.md` to require evidence for judgment
    criteria.
E2. Update verdict format spec.
E3. Test against several existing audit entries to confirm verdict
    quality improves.

Outcome: fewer false PASSes on UX-heavy tasks.

**Phase F: Output Validation (3 days)**

F1. Add `## Output Validation` section to task card schema.
F2. Run validators after checks pass, before reviewer.
F3. Distinguish in audit log between check failures and validation
    failures.

Outcome: artifact-against-contract validation as a first-class category.

**Phase G: Schema-in-prompt injection (2 days)**

G1. Detect Pydantic models referenced by task (in Inputs, Modifies,
    Outputs).
G2. Export referenced models as JSON Schema.
G3. Include in assembled prompt under "Schemas in scope" section.
G4. Display in gate output.

Outcome: LLMs generate schema-conformant outputs more often on first try.

**Phase H: Modifies / See Also distinction (2 days)**

H1. Add `## Modifies` and `## See Also` sections to task card schema.
H2. Update prompt assembly: Inputs as read-only, Modifies as
    current-state-to-edit, See Also as supplementary context.
H3. Update gate display.
H4. Update artifact-consumer registration to record role.

Outcome: cleaner contracts between tasks; less prompt noise.

**Phase I: Retry semantics (3 days)**

I1. `kanban retry` — re-run checks/validations only.
I2. `kanban rerun [--include-failure]` — re-invoke LLM with optional
    failure context.
I3. `kanban regenerate [--max-retries N]` — validation-failure-driven
    retry loop.
I4. Audit entry shape for each.

Outcome: retry mechanics are clean, named, distinct.

**Phase J: Draft session (1 week)**

J1. Conversational intake script (CLI prompts).
J2. Plan generation (LLM call producing a structured plan).
J3. Plan approval gate.
J4. Card generation from approved plan.
J5. Initial registry entry creation.

Outcome: starting a new project is one command.

**Phase K: Store interface (3 days, low priority)**

K1. Define `Store` Protocol with methods used across the codebase.
K2. Refactor existing filesystem access through the Store.
K3. Default `LocalStore` implementation backed by filesystem + SQLite.

Outcome: future platform conversion is moderate work, not a rewrite. Low
priority because it has no user-visible payoff in the single-user case,
but high value when (if) the platform path is taken.

**Phase L: Quality of life (ongoing)**

- Token-count display in gate
- Cost estimation in audit entries
- Milestone advancement suggestions
- Better dashboard rendering
- Light cross-project queries (which projects use which schemas, which
  models are most often used, etc.)

These are nice-to-have. Build them as the need is felt.

## Out of Scope (Explicitly)

These are things the orchestrator will NOT do, ever, unless the basic
premise of the system changes. Listing them explicitly so future-you
remembers why they were rejected.

**Web UI for the orchestrator.** The dashboard is generated markdown
rendered on GitHub. The CLI is the primary interface. A web UI would mean
auth, sessions, server hosting — none of which is the orchestrator's job.

**Plugin system.** Adding plugin loading, plugin discovery, plugin
versioning, plugin sandboxing is months of work to solve a problem that
exists only when there is a community of plugin authors. There is one
operator. Resist.

**A Python DSL for tasks (decorators, etc.).** Markdown task cards are
the interface. Adding a code interface creates two ways to do everything
and a sync problem.

**Workflow DAG engine (Prefect/Dagster style).** Task dependencies via
`blocked_by` are sufficient for the project sizes this orchestrator
targets. A real workflow engine is the right tool for 100+ task DAGs with
dynamic structure. Defer until that exists.

**Knowledge graph / RDF / Neo4j.** SQLite handles the queries the
artifact registry needs. Graph databases are an attractive trap. Resist.

**Multi-user, multi-tenancy, auth, billing.** Single-operator system.
The Store interface allows this to be added later by someone else, but
the orchestrator itself does not concern itself with it.

**Domain-specific extensions (research, ML, web dev).** The orchestrator
is domain-agnostic. Domain knowledge lives in task cards. Resist any
proposal to add a "research project type" or "ML pipeline mode."

**Integration with task-tracking systems (Jira, Linear, etc.).** Task
cards are markdown files. They are git-versioned. They are the system of
record. Bidirectional sync with external trackers is months of work for
ambiguous benefit.

**LLM-powered enhancements outside the existing roles (executor and
reviewer).** Resist proposals to add a "summarizer agent" or "planner
agent" or "explainer agent." Each one is a new context to manage, a new
prompt to maintain, a new audit shape, a new failure mode. The current
roles (executor LLM, reviewer LLM, optional plan-first LLM) cover the
useful surface. Add a fourth role only when a clear gap is observed in
practice, not in anticipation.

## Glossary

- **Artifact** — any file produced or consumed by a task. Tracked in the
  artifact registry by content hash.
- **Audit entry** — markdown file recording one execution attempt. The
  canonical record of what happened.
- **Check** — a deterministic shell command run after execution; used to
  verify mechanical properties (lint, types, tests pass).
- **Draft session** — conversational intake for projects not coming from
  the epistemic phase.
- **Executor LLM** — the model invoked by the orchestrator to do task
  work. Distinct from runtime LLMs called by the project's own code.
- **Gate** — the human-in-the-loop checkpoint before model invocation.
- **Milestone** — a named status marker indicating significant project
  progress (e.g., MILESTONE_V1).
- **Output validation** — a deterministic check that produced artifacts
  conform to their declared contract.
- **Plan-first** — optional summarization call before execution, in
  managed mode, to surface what the task is about to do.
- **Reviewer LLM** — the model invoked after checks pass, to evaluate
  acceptance criteria. Distinct from the executor LLM.
- **Runtime LLM** — an LLM called by the project's own code at runtime
  (e.g., MCQ generation in the study app). Not part of the orchestrator's
  invocation chain.
- **Seam** — an architectural boundary between concerns, designed to
  allow swapping one implementation for another without touching the
  other side.
- **Store** — the persistence abstraction. Currently filesystem +
  SQLite; could be Postgres or remote in future.
- **Swap point** — a documented architectural seam where v1 will be
  replaced by v2. Flagged in task card Notes for future-self.
- **Task card** — markdown file representing one unit of work; the
  central object of the system.

---

## Appendix: Lessons from the Simulation

These are the specific observations from walking through tasks 001–007 of
the study app simulation. Captured here as the empirical basis for the
design decisions above.

**On task structure:**

- Tasks 001 (ADR) and 007 (integration test) are structurally different
  from the rest. Most tasks produce code. ADR-class tasks produce
  documents. Integration-test-class tasks produce evidence. Both are
  legitimate; both fit the schema.
- The "no library types leak" acceptance criterion is a recurring
  pattern. PDF extraction owns pypdf. MCQ generation owns the API client.
  DAL owns sqlite3. Web layer owns FastAPI. Each task creates a clean
  module boundary; downstream tasks consume only typed domain objects.
  This is the seam pattern at the project level.

**On checks:**

- Most check failures are real bugs, not flaky tests. The mypy failure in
  003 was a missing null check. The pytest failure in 004 was a missing
  substring validation. The pytest failure in 006 was a wrong redirect
  pattern. In each case, the check caught a real defect that would have
  shipped if the reviewer had been the only line of defense.
- Project default checks must be sub-five-second total. Slow checks belong
  in CI or as task-specific additions. If the inner loop is slow, the
  operator will start adding `skip_default_checks` to avoid friction, and
  the system degrades.

**On the reviewer:**

- Sonnet is enough for most tasks. Opus is needed for tasks where
  judgment-class criteria dominate (UX, architecture, statistical
  reasoning). The cost difference (~5x) is real and visible; the gate
  should display the rationale.
- The biggest false-PASS risk is on UX criteria like "no business logic
  in routes" or "every interaction has a no-JS fallback." Mitigation:
  require evidence in the verdict (a quoted line, a structural property),
  not just a one-line claim.

**On retries:**

- Path A (operator fixes manually, retries) is right for mechanical
  failures (typo, lint).
- Path B (rerun with failure context) is right for failures that suggest
  the model misunderstood something architectural.
- Validation-failure retry (regenerate) is specifically for
  LLM-generated artifacts where re-sampling with feedback has a real
  chance of success.

**On planning:**

- The draft session is best when short. Five questions plus skips. Real
  defaults made aggressively. The operator iterates by editing cards,
  not by extending the questionnaire.
- Plan-as-a-whole is critical. Once the seven-task graph is visible, the
  individual cards are coherent. If cards were generated one at a time,
  each would optimize locally and the architecture would drift.

**On scope:**

- The pattern works well for projects in the 5–50 task range. Below 5,
  the orchestrator overhead exceeds the benefit. Above 50, a higher
  layer (epics, phases) is needed.
- The pattern works for code-producing tasks. Tasks like "interview five
  users" or "write the marketing copy" don't fit and shouldn't be
  forced.

**On platform conversion:**

- The Store / Executor / Schema seams make conversion to a multi-user
  platform tractable. They do not make it cheap. The real cost of the
  platform conversion is the surface area that hasn't been built (auth,
  multi-tenancy, file uploads, async workers, web UI). Don't conflate
  architectural readiness with feature readiness.

**On the audit log:**

- Six months from now, the most valuable thing in the repo is the
  accumulated audit history. Every task run, check failure, reviewer
  verdict, API cost. Structured and queryable. The first time you sit
  down to mine it for patterns, you'll wish you'd started earlier. The
  data accumulates whether or not the queries exist; the queries are
  cheap to add later. The structure is what matters.

