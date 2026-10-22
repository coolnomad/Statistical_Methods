# What is `compact`?

`compact` is a **control plane for LLM-assisted work**. You write a task as a
structured "card" — objective, acceptance criteria, inputs/outputs, checks — and
the system drives it through a fixed lifecycle where a task cannot reach "done"
until the supporting evidence exists.

It contains an execution harness, but the point of the system is the governance
*around* that harness: every step is audited, every state transition is explicit,
and acceptance criteria cannot be satisfied by a stub or a mock.

## The bet

As LLMs get wired into real engineering work, failures increasingly come from
**orchestration, evidence, and governance defects** — fake-complete states,
stubbed implementations that still pass acceptance criteria, documentation that
outruns what actually runs — rather than from model output quality alone.

`compact`'s answer is to make the *unit of work* a machine-checkable contract and
never let it advance without proof:

> explicit task contracts → governed state transitions → deterministic checks +
> output validation → durable audit trail → review gating.

## How it works

### 1. The task card is the contract

A card is not a prompt or a ticket. It is a strictly-validated object
(`extra="forbid"`, frozen) with:

- `objective`, `requirements`, `acceptance_criteria`
- `inputs` / `outputs` / `modifies` / `see_also`
- `checks`, `output_validation`, `blocked_by`
- `reviewer` and a lifecycle `status`
  (`TODO → IN_PROGRESS → REVIEW → DONE`, plus `BLOCKED`)

Malformed contracts are rejected up front.

### 2. The pipeline is a fixed gauntlet

`compact run` walks every task through the same stages, and **each failure stage
has a defined landing state** rather than a vague "error":

```
assemble context → operator gate → execute → deterministic checks → output validation → audit → review
```

- Execution fails → task parks in `IN_PROGRESS` (operator-reviewable)
- Checks or output validation fail → task goes `BLOCKED`
- Everything passes → `REVIEW` (or `DONE` if no reviewer is assigned)

Every stage writes a durable **audit entry** capturing the prompt, an environment
snapshot, check results, and the before/after status.

### 3. A human-in-the-loop gate

Before any execution, the gate prints a summary — which inputs/outputs exist vs.
are missing, which checks will run, the estimated prompt tokens, the reviewer
model — and asks `[y/n/e]` (yes / no / edit the prompt). Nothing runs silently.

### 4. Execution modes

- `managed` — the configured executor (LLM) runs the task
- `assisted` — writes a prompt file for a human operator and skips the executor

The same post-execution flow (checks → validation → audit) applies regardless, so
proof requirements do not depend on *who* did the work.

### 5. Recovery verbs

- `retry` — re-run checks only, no executor
- `rerun` — re-invoke with the prior prompt
- `regenerate` — loop the executor, feeding validation failures back into the
  prompt, until it passes or retries exhaust

Plus `draft` / `greenfield` to author cards and `review` / `milestone` /
`artifact` for the rest of the lifecycle.

## Non-negotiable principles

- No keystone runtime claim without real end-to-end proof.
- No acceptance criterion that can pass while the behavior is still fake.
- No hidden lifecycle mutation — every transition is audited.
- No direct model calls outside a governed adapter layer.
- Judge the system by *control quality, proof quality, review quality, and
  cross-project reuse* — not by number of agents, prompts, or workflow nodes.

## What to call it

It is a **control plane**, not a harness. A harness *wraps and drives* an
executable so you can run it and capture output; it has no opinion about whether
the work was legitimately completed. `compact` contains such a harness, but the
distinguishing layer is **governance and state**: lifecycle, evidence, proof, and
review gating that decide whether work is allowed to advance.

| Compared to…            | …they do                        | `compact` adds                                         |
| ----------------------- | ------------------------------- | ------------------------------------------------------ |
| Agent frameworks        | define & run agents             | whether the work is *valid, proven, allowed to advance* |
| Workflow engines        | manage execution order & state  | LLM-specific contracts, evidence, proof semantics      |
| Evals platforms         | measure quality                 | uses measurement as one input to lifecycle governance  |
| Observability/guardrails| report / constrain              | governs the full propose→execute→review→accept lifecycle |

## The benefit, in one line

AI-generated work becomes **auditable, reproducible, and hard to fake** — instead
of "the model said it's done, hope it's right." It is domain-agnostic and built
for a single operator, so one person can push a lot of governed work through
without losing the proof trail.

## See also

- [`LLM_WORKFLOW_CONTROL_PLANE_MANIFESTO.md`](LLM_WORKFLOW_CONTROL_PLANE_MANIFESTO.md)
  — the category definition and positioning
