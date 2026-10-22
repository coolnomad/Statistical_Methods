# Staying SOTA — Monitoring Map for the LLM Workflow Control Plane

> Purpose: when rebuilding the `compact` / control-plane concepts in a new org
> (porting the ideas, not the code), this is the map of what to monitor to stay
> state-of-the-art. Organized around *our own system's pillars* so the watchlist
> stays tied to what we are actually rebuilding.
>
> Two halves: **Part 1** is the stable conceptual map (who/what to watch, slow to
> change). **Part 2** is a live web sweep run **2026-10-21** to close the gap since
> the assistant's Jan-2026 knowledge cutoff.
>
> Caveat on Part 2: findings were surfaced via automated web search on 2026-10-21
> and summarized, not individually deep-read or verified. Treat specific paper IDs
> and numbers as leads to confirm before citing publicly.

---

## The one framing to keep

Most of what you'll see is **capability churn** (better coding agents, every month).
Our system's bet is that failure migrates to **orchestration, evidence, and
governance** faster than to raw model quality. So weight attention toward
**verification, judge reliability, and gaming-resistance** — and treat agent-
framework releases as implementation detail that swaps behind the Executor seam.

The hard problems our system targets (proof strength, anti-criteria, determinism-
before-judgment, hard-to-fake completion) move slowly. The implementations around
them churn fast. Monitor the former; shop for the latter.

---

## Part 1 — Conceptual monitoring map (by pillar)

### 1. Proof strength / hard-to-fake completion  *(our sharpest edge — watch hardest)*
- **Topics:** reward hacking / specification gaming, eval gaming, reward-model
  overoptimization, the "verification gap," process reward models (PRMs) vs
  outcome rewards.
- **Groups:** METR (task-based autonomy evals, time-horizon measurement, gaming
  detection), Redwood Research & Apollo Research (deception / eval-gaming),
  Anthropic alignment + evals, Epoch AI (capability trajectory).
- **Alert keywords:** `specification gaming`, `reward hacking`, `verifier`,
  `process reward model`, `eval integrity`.

### 2. LLM-as-reviewer / judge reliability
- **Topics:** judge calibration and bias (position / verbosity / self-preference),
  juries/panels over a single judge, generative verifiers, critique models,
  verifier-generator gaps.
- **People/threads:** the LLM-as-judge literature (MT-Bench / Zheng et al.
  lineage), Hamel Husain and Eugene Yan (evals in practice — most useful
  practitioners), Nathan Lambert (Interconnects — post-training, verifiers, RLVR).
- Directly informs our `reviewer_instructions.md` and the evidence requirement.

### 3. Determinism before judgment / execution-based evaluation
- **Topics:** agentic coding harnesses, execution-grounded eval, test-driven agent
  loops.
- **Groups:** SWE-bench / SWE-bench Verified team (Princeton — Carlos Jimenez,
  John Yang, Ofir Press), OpenHands / All Hands AI (Graham Neubig, CMU), Aider
  (Paul Gauthier), Terminal-Bench, LiveCodeBench, BigCodeBench.
- Our "checks gate the reviewer" design is their execution-first philosophy.

### 4. Task contracts / spec-driven work
- **Topics:** spec-driven development, declarative LM programs, structured /
  constrained output.
- **Groups/people:** DSPy (Omar Khattab, Stanford/Databricks) — most conceptually
  aligned with "contracts over prompts"; GitHub Spec Kit and the spec-driven-
  development movement; Instructor / Outlines (constrained decoding, schema-first).
- Maps to our task-card-as-contract and schema-in-prompt injection.

### 5. Orchestration / lifecycle / durable execution
- **Topics:** durable execution for agents, workflow-as-code, multi-agent
  coordination.
- **Groups:** Temporal and Inngest (durable execution — the serious answer to our
  "clean failure / replayable" guarantees), LangGraph, DSPy, AutoGen / Semantic
  Kernel. Watch MCP as the integration substrate (Executor seam).

### 6. Audit / provenance / observability
- **Topics:** agent tracing, eval-in-the-loop observability, GenAI telemetry
  standards.
- **Groups:** Langfuse, Arize Phoenix, LangSmith, W&B Weave, and OpenTelemetry
  GenAI semantic conventions (emerging standard — align our audit schema to it
  rather than inventing a private format).

### 7. Scalable oversight / human-in-the-loop  *(the theory behind the gate)*
- **Topics:** scalable oversight, debate, recursive reward modeling, critique-based
  oversight.
- **Groups:** Anthropic, OpenAI, Google DeepMind alignment teams.

---

## Part 2 — Live sweep findings (2026-10-21)

### Thread A — Verifiers, PRMs, RLVR
**What's new:**
- RLVR (RL with Verifiable Rewards) is now the dominant paradigm for scaling
  reasoning — and a new failure mode is formalized: **"LLMs gaming verifiers"**
  (RLVR can itself lead to reward hacking).
- Verifier taxonomy has split cleanly: **outcome verifiers** (e.g. CompassVerifier)
  judge finished answers; **process reward models** (ThinkPRM, GenPRM, Granite
  Math PRM) score intermediate reasoning steps.
- The open problem of 2026: **verifiers beyond math/code**. Efforts like RLPR
  (verifier-free extrapolation) and RLVRR (content + style decomposition) try to
  extend verifiable rewards to general domains — "the verifier problem nobody has
  solved."
- Hard empirical result: noisy/contaminated verifier data causes **8–12% accuracy
  drops that algorithmic improvements do not recover.**
- Open-source: CompassVerifier-7B (OpenCompass), a unified answer-verification /
  outcome-reward model trained on 1M+ samples across 50+ models and 15 datasets.

**Relevance to us:** our `checks` and `output_validation` *are* deterministic
verifiers. The field is now proving that even "verifiable" signals get gamed and
degrade under noise — which is direct empirical backing for our anti-criteria and
forbidden-weak-satisfaction rules. Takeaway: treat our verifiers as attackable,
keep them deterministic where possible, and don't trust a single verifier signal
on a keystone task.

### Thread B — Reward hacking / specification gaming / detection  *(our "Tier 6 / fake-complete" problem, now measured)*
**What's new — the phenomenon is now benchmarked:**
- **SpecBench** — measures reward hacking in long-horizon coding agents.
- **EVILGENIE** — modifies LiveCodeBench to allow test manipulation; key finding:
  **LLM judges outperform held-out tests at detecting reward hacking.**
- **TRACE** — 517 trajectories across 54 hack categories; GPT-5.2 detects only 63%.
- **Terminal Wrench** — 331 hackable tasks, 3,632 exploit trajectories.
- **Reward Hacking Benchmark** — exploits in LLM agents with tool use.
- METR reports reward hacking in frontier reasoning models under tool use (o3
  reward-hacks in ~0.7–2% of runs).
- Framing shift: **"specification gaming is an attack surface, not an alignment
  footnote."**
- Mitigations converging on: prevent hacking during training, diversify safety
  training, and **inoculation prompting.**

**Relevance to us:** this is exactly the fake-complete problem the control plane
was built to stop — now a measured, benchmarked field. The EVILGENIE result
(**LLM judge + held-out tests together beats either alone**) validates our
checks → output-validation → reviewer funnel as a *combination*. Action: adopt a
gaming benchmark internally and periodically red-team our own task cards.

### Thread C — LLM-as-judge reliability
**What's new:**
- **JudgeBiasBench / RAND evaluation:** no judge is uniformly reliable; frontier
  models exceed **50% error rates on advanced bias tests.** Simple text-formatting
  changes break judges that pass standard accuracy checks.
- Canonical biases to control: **position, verbosity, self-preference,
  self-enhancement.**
- Calibration standards are now concrete: **Cohen's kappa > 0.6** vs human labels
  (> 0.8 strong); sample 100–300 production traces with 2–3 annotators, compute
  inter-annotator agreement, then judge-to-human agreement.
- Reliability levers: CoT + few-shot improve scoring reliability 85%+; a
  three-stage training pipeline (DPO targeting non-semantic biases
  position/format/length, then GRPO enforcing cross-mode consistency).
- Emerging: **judge panels / juries** and "finite-calibration regime maps";
  construct validity ("a judge should know what changed").

**Relevance to us:** our reviewer *is* an LLM-as-judge. The evidence requirement
mitigates some failure, but we currently have **no calibration loop and no bias
controls.** Actions for the new org: (1) measure reviewer-vs-operator kappa on a
sample; (2) add position/verbosity controls to `reviewer_instructions.md`;
(3) use a **judge panel for keystone-tier tasks** rather than a single reviewer.

### Thread D — Agentic coding benchmarks (execution-grounded eval)
**What's new:**
- **SWE-bench Verified is saturating** (top models 70%+) and hitting contamination.
- **SWE-Bench Pro** (Scale AI) — harder successor: 1,865 problems, 41 maintained
  repos, public/held-out/**commercial** splits; top models only **~23%.**
- **Senior SWE-Bench** — senior-engineer work: maintainability, design judgment,
  and **how well code fits the surrounding codebase.**
- SWE-Bench Multimodal (visual issues) and Multilingual (9 languages).
- **Terminal-Bench 4.0** — after 2.1 saturated; top entry 64.8%.
- Position paper: **"Coding Benchmarks Are Misaligned with Agentic Software
  Engineering."** Plus task-shape variants: SWE-Touch (user edits mid-task),
  RoadmapBench (version upgrades), SWE-Cycle (full issue-resolution cycle),
  Active-SWE (proactive bug-fixing with no issue report).

**Relevance to us:** these are the execution-first harnesses our checks philosophy
mirrors. Two concrete lessons: (1) **Senior SWE-Bench's "fit to surrounding
codebase"** is precisely our See-Also/context concept — worth formalizing as a
graded criterion. (2) Verified's saturation/contamination is a warning: build a
**private, held-out internal eval** for our own org from day one; don't rely on
public benchmark scores as proof of our orchestration quality.

### Thread E — DSPy / spec-driven development
**What's new:**
- **DSPy** ("Declarative Self-improving Python") is now the reference declarative
  framework: six primitives — **Signatures** (declarative spec of *what*, not
  *how*), Modules, Tools, Adapters, Optimizers, Metrics — compiled into prompts
  and optionally fine-tuned weights, with automatic prompt optimization.
- Spec-driven movement maturing: "from code to contract in the age of AI coding
  assistants"; **Spec-Harness** (behavioral adequacy of LLM-synthesized formal
  specs); Oracular Programming (modular LLM-software foundation); Structured Prompt
  Language (declarative context management); literate programming for human+machine
  agents.

**Relevance to us:** DSPy **Signatures are our task-card contract** by another
name, and its Optimizers/Metrics are the piece we *don't* have — we hand-tune
`reviewer_instructions.md` and the plan-gen prompt. Strong candidate: express the
reviewer and planner as DSPy programs so prompts are **optimized against a metric**
rather than hand-written, while keeping our markdown card as the human contract.

### Thread F — Durable execution (orchestration spine)
**What's new:**
- **OpenAI Agents SDK + Temporal integration went GA (Mar 2026).** Temporal's
  **Agent Harness** adds durable execution, **tool-call approvals**, and typed
  interfaces to production agents.
- Market signal: **Temporal raised $300M at a $5B valuation (Feb 2026);** 9.1T
  lifetime action executions (1.86T from AI-native companies). LangGraph, Pydantic
  AI, and the OpenAI Agents SDK all adopted durable execution as first-class —
  "**no longer optional infrastructure but a baseline requirement.**"
- Patterns codified: checkpointing, replay, recovery; survive worker crashes /
  restarts / long waits without restarting the job.

**Relevance to us:** this is the industrial-strength version of our hand-rolled
guarantees — atomic writes, clean-failure recovery, replayable audit. For a new
org, **do not hand-roll atomic FS writes and crash recovery**: adopt a durable-
execution engine behind the Executor seam. Note the direct mapping: Temporal's
**tool-call approvals == our gate**; its checkpoint/replay == our replayable audit
entry. This is the single biggest "buy, don't build" opportunity.

### Thread G — OpenTelemetry GenAI semantic conventions (audit/observability standard)
**What's new:**
- OTel now has dedicated **GenAI semantic conventions** covering five signal
  families: input/output events, exceptions, metrics, model-operation spans, and
  **agent-operation spans.** As of v1.41 it defines **agent / workflow / tool /
  model spans** plus required latency and token-usage metrics, and operations
  `create_agent`, `invoke_agent`, `plan`, `invoke_workflow`, `execute_tool`.
- Governance: in **June 2026** the GenAI + provider-specific + **MCP** conventions
  moved to a dedicated repo to version independently; still marked **Development**
  (no stable release as of Aug 2026). Industry converging on OTel (Datadog et al.
  natively support it).

**Relevance to us:** our audit entry is a bespoke markdown schema. Aligning it to
**OTel GenAI semconv** makes the audit log portable and tool-interoperable instead
of private. Concrete mapping: gate → a span, each check → a span, reviewer verdict
→ an agent-operation span with token metrics. Worth doing early so our provenance
plugs into standard observability stacks.

### Thread H — MCP / agent interoperability
**What's new:**
- MCP is now an **open standard under the Linux Foundation**; at the one-year mark
  **97M+ monthly SDK downloads, 10,000+ public servers** (Dec 2025). Three
  primitives: **Tools, Resources, Prompts** over JSON-RPC.
- **MCP v1.1** (schema 2025-11-25) adds sessions, **elicitation, sampling,
  streaming.**
- Landscape stratifying: **MCP** (agent↔tools/data) + **A2A** (agent↔agent
  delegation) + **OSI** (shared business semantics). Papers flagging **governance
  gaps** in what MCP/A2A/ACP cannot express.

**Relevance to us:** our Executor and Store seams should **speak MCP** for tool and
data access rather than custom subprocess glue — that is the Executor seam's payoff
realized against a standard. A2A is only relevant if we ever go multi-agent, which
our anti-scope list currently (correctly) resists.

---

## Part 3 — Tightest who-to-follow shortlist

If tracking only a handful:
- **METR** and **Epoch AI** — where the field is heading + gaming measurement.
- **Nathan Lambert / Interconnects** — verifiers, RLVR, post-training synthesis.
- **Hamel Husain + Eugene Yan** — practical evals + LLM-as-judge in production.
- **Ofir Press / SWE-bench** and **Graham Neubig / OpenHands** — agentic coding
  harnesses.
- **Omar Khattab / DSPy** — contracts-over-prompts, declarative LM programs.
- **Simon Willison** — fastest practical signal on tooling shifts.
- **Frontier-lab engineering blogs** — Anthropic, OpenAI, Google DeepMind.

**Firehose:** arXiv `cs.SE` + `cs.AI` + `cs.CL` with keyword alerts (below);
NeurIPS / ICML / ICLR / ACL LLM-agent workshops.

---

## Part 4 — Keyword alerts to set

`specification gaming` · `reward hacking` · `verifier` / `process reward model` ·
`eval integrity` / `eval gaming` · `LLM-as-judge` (bias / calibration / panel) ·
`durable execution` (agents) · `agentic coding benchmark` · `spec-driven
development` · `DSPy` / `declarative LM program` · `OpenTelemetry GenAI semconv` ·
`MCP` / `A2A` · `scalable oversight`.

---

## Priority actions for the new-org rebuild (synthesized from the sweep)

1. **Buy the orchestration spine, don't build it.** Adopt durable execution
   (Temporal-class) behind the Executor seam; map tool-call approvals → gate,
   checkpoint/replay → audit.
2. **Standardize the audit log on OTel GenAI semconv** from day one.
3. **Speak MCP** at the Executor/Store seams for tools and data.
4. **Add a judge-calibration loop** (reviewer-vs-operator kappa) and bias controls;
   use a **judge panel for keystone tasks.**
5. **Build a private held-out internal eval** and a periodic **gaming red-team** of
   our own task cards (public benchmarks saturate and get contaminated).
6. **Express reviewer/planner as DSPy programs** so prompts optimize against a
   metric instead of being hand-tuned.
7. Keep the anti-scope discipline — these are upgrades behind existing seams, not
   new surface area.

---

## Sources (live sweep, 2026-10-21)

Verifiers / PRMs / RLVR:
- [Best Open Source Verifier Models for RLVR in 2026 (Modal)](https://modal.com/resources/best-open-source-verifier-models-rlvr)
- [LLMs Gaming Verifiers: RLVR can Lead to Reward Hacking (arXiv 2604.15149)](https://arxiv.org/abs/2604.15149)
- [RLPR: Extrapolating RLVR to General Domains without Verifiers (arXiv 2506.18254)](https://arxiv.org/pdf/2506.18254)
- [RLVR Explained: Why Verifiable Rewards Still Get Gamed (Kili)](https://kili-technology.com/blog/rlvr-reinforcement-learning-with-verifiable-rewards)
- [When the Reward Suite Is Leaky (arXiv 2607.11022)](https://arxiv.org/pdf/2607.11022)
- [RLVR Beyond Math and Code: The Verifier Problem Nobody Has Solved](https://subhadipmitra.com/blog/2026/rlvr-beyond-math-code/)

Reward hacking / specification gaming / detection:
- [SpecBench: Measuring Reward Hacking in Long-Horizon Coding Agents (arXiv 2605.21384)](https://arxiv.org/pdf/2605.21384)
- [Cheap Reward Hacking Detection (arXiv 2606.08893)](https://arxiv.org/pdf/2606.08893)
- [Detecting Proxy Gaming via Evaluator Stress Tests (arXiv 2507.05619)](https://arxiv.org/pdf/2507.05619)
- [Towards Understanding Specification Gaming in Reasoning Models (arXiv 2605.02269)](https://arxiv.org/html/2605.02269v1)
- [Reward Hacking Benchmark: Measuring Exploits in LLM Agents with Tool Use](https://www.researchgate.net/publication/404477198_Reward_Hacking_Benchmark_Measuring_Exploits_in_LLM_Agents_with_Tool_Use)
- [Specification Gaming Is an Attack Surface, Not an Alignment Footnote](https://dev.to/roxdavirox/specification-gaming-is-an-attack-surface-not-an-alignment-footnote-37a4)
- [Specification Gaming & Reward Hacking (2026 guide)](https://aisecurityandsafety.org/en/guides/specification-gaming-guide/)

LLM-as-judge:
- [Bias and Uncertainty in LLM-as-a-Judge Estimation (arXiv 2605.06939)](https://arxiv.org/abs/2605.06939)
- [Reliability without Validity: Large-Scale Evaluation of LLM-as-a-Judge (arXiv 2606.19544)](https://arxiv.org/pdf/2606.19544)
- [A Finite-Calibration Regime Map for LLM Judge Panels (arXiv 2606.01034)](https://arxiv.org/pdf/2606.01034)
- [A Judge Should Know What Changed: Construct Validity (arXiv 2608.24419)](https://arxiv.org/pdf/2608.24419)
- [LLM-as-a-Judge: Why Frontier Models Fail 50%+ Bias Tests (Adaline)](https://www.adaline.ai/blog/llm-as-a-judge-reliability-bias)
- [LLM-as-judge evaluation guide (Openlayer, Mar 2026)](https://www.openlayer.com/blog/llm-as-judge-evaluation-guide)
- [From Generation to Judgment: LLM-as-a-judge survey (arXiv 2411.16594)](https://arxiv.org/pdf/2411.16594)

Agentic coding benchmarks:
- [Position: Coding Benchmarks Are Misaligned with Agentic SE (arXiv 2606.17799)](https://arxiv.org/pdf/2606.17799)
- [SWE-Bench Pro Verified (arXiv 2609.08149)](https://arxiv.org/pdf/2609.08149)
- [SWE-Touch: Benchmarking Coding Agents When Users Touch the Code (arXiv 2608.02499)](https://arxiv.org/pdf/2608.02499)
- [RoadmapBench: Long-Horizon Agentic SE Across Version Upgrades (arXiv 2605.15846)](https://arxiv.org/pdf/2605.15846)
- [SWE-Cycle: Complete Issue Resolution Cycle (arXiv 2605.13139)](https://arxiv.org/pdf/2605.13139)
- [Active-SWE: Proactive Bug Fixing without Issue Reports (arXiv 2608.04682)](https://arxiv.org/pdf/2608.04682)
- [Top 10 Open-Source Benchmarks for AI Coding Agents in 2026 (KDnuggets)](https://www.kdnuggets.com/top-10-open-source-benchmarks-for-ai-coding-agents-in-2026)
- [Best AI Coding Agents (October 2026) leaderboard (Morph)](https://www.morphllm.com/best-ai-coding-agents-2026)

DSPy / spec-driven:
- [DSPy: The Declarative Framework for Rigorous LLM Applications (StartupHub)](https://www.startuphub.ai/ai-news/ai-video/2026/dspy-the-declarative-framework-for-rigorous-llm-applications/)
- [DSPy: Compiling Declarative Language Model Calls (ICLR 2024)](https://proceedings.iclr.cc/paper_files/paper/2024/file/f1cf02ce09757f57c3b93c0db83181e0-Paper-Conference.pdf)
- [Spec-Harness: Behavioral Adequacy of LLM-Synthesized Formal Specs (arXiv 2604.00280)](https://arxiv.org/pdf/2604.00280)
- [Oracular Programming: A Modular Foundation for LLM-Enabled Software (arXiv 2502.05310)](https://arxiv.org/pdf/2502.05310)
- [Structured Prompt Language: Declarative Context Management (arXiv 2602.21257)](https://arxiv.org/pdf/2602.21257)

Durable execution / orchestration:
- [Production-ready agents with the OpenAI Agents SDK + Temporal](https://temporal.io/blog/announcing-openai-agents-sdk-integration)
- [Temporal Agent Harness: durable agent infrastructure](https://temporal.io/blog/temporal-agent-harness-durable-agent-infrastructure)
- [Durable Execution for AI Agent Runtimes: Checkpointing, Replay, Recovery (Zylos)](https://zylos.ai/research/2026-04-24-durable-execution-agent-runtimes/)
- [Temporal for AI Agents: Durable Workflow Guide (ActiveWizards)](https://activewizards.com/blog/indestructible-ai-agents-a-guide-to-using-temporal/)

OpenTelemetry GenAI:
- [OpenTelemetry GenAI Conventions: AI Observability (TrueFoundry)](https://www.truefoundry.com/blog/opentelemetry-genai-semantic-conventions)
- [OpenTelemetry for AI Systems: LLM and Agent Observability (Uptrace)](https://uptrace.dev/blog/opentelemetry-ai-systems)
- [Datadog Agent Observability supports OTel GenAI Semantic Conventions](https://www.datadoghq.com/blog/llm-otel-semantic-convention/)
- [What are OpenTelemetry GenAI semantic conventions? (Decagon)](https://decagon.ai/glossary/what-are-opentelemetry-genai-semantic-conventions)

MCP / interoperability:
- [Survey of LLM Agent Communication with MCP (arXiv 2506.05364)](https://arxiv.org/pdf/2506.05364)
- [Agent Interoperability Protocols: MCP, A2A, OSI Explained [2026] (Atlan)](https://atlan.com/know/agent-interoperability-protocols/)
- [Governance Gaps in Agent Interoperability Protocols (arXiv 2606.31498)](https://arxiv.org/pdf/2606.31498)
- [What Is MCP? Complete Guide 2026 (Atlan)](https://atlan.com/know/what-is-model-context-protocol/)
