# Agent Delegation Plan for Devyn

This is an alternative to `PLAN_AGENTS_LUNA.md`, not a replacement for it.
Luna's plan remains useful as a record of one possible shape.

## Independent review of Luna's plan

Luna's plan contains some sound mechanics, but its overall shape feels like a
conventional multi-agent framework imposed on m8 rather than something emerging
from m8's primitives.

### What Luna got right

- A mob such as `@team/` is idiomatic.
- Named job chats like `@team/reviewer/parser` fit the filesystem model.
- `--new` for a fresh job and continuing the same address for another pass are
  correct.
- `m8 query` does not move the main chat.
- Avoiding concurrent writers to the same files is sensible.
- Scout/reviewer agents with narrower capabilities could genuinely save the
  lead agent context.

### What does not fit

#### 1. The handoff files create a second source of truth

The largest mismatch is:

> “The m8 job transcript for complete history”
> plus
> “Compact handoff files for durable working context”

That introduces mutable summaries beside the actual conversation. They can
become stale, omit evidence, or claim something the ledger does not show. The
README is especially firm about this:

- the conversation is the artifact;
- the ledger is the truth;
- nothing should stand between the user and it.

An `archivist` maintaining `scratch/handoffs/current.md` is essentially a small
session-state subsystem—the thing m8 is trying not to have.

A child agent's concise final response can already be:

1. stored in that child's immutable job history; and
2. recorded as the result of the parent's delegation tool call.

If a standalone artifact is genuinely needed, it should be an intentional
project document or an m8 document/reference, not routinely maintained shadow
state.

#### 2. The five-role team is too prescriptive

`scout`, `implementer`, `reviewer`, `tester`, and `archivist`, together with a
mandatory six-field response contract, amount to a built-in methodology.

That conflicts with m8 being opinionated about form but neutral about agent
structure. Mobs make such a team *possible*; they should not imply that this is
the canonical decomposition.

In particular:

- **Implementer** mostly duplicates the primary coding agent.
- **Tester** is usually a tool activity, not necessarily a separate enduring
  persona.
- **Archivist** exists to maintain the duplicate state described above.
- A fixed `STATUS/EVIDENCE/CHANGED/...` protocol adds another little format
  outside m8's grammar.

Initially, one or two collaborators are enough.

#### 3. It treats delegation as more settled than the project says it is

`IDEAS.md` explicitly calls subagent design the “biggest undecided design” and
considers whether the framework should know about subagents at all.

The important README position is simpler:

> An agent needs no way to spawn another. Calling one is already a command, so
> a 🧰 whose command is that is a subagent.

Luna's plan should therefore be framed as a small composition experiment, not
a proposed permanent team architecture.

#### 4. Manual invocation loses an important property

The recommended first step says to invoke agents manually with `m8 query`.

That proves the child chats work, but it does not make the lead agent the
orchestrator. If the user runs those commands outside the lead agent's turn,
the lead ledger does not contain the delegation call and receipt. The child
ledger remains truthful, but the parent conversation does not show that it
delegated work.

For integrated delegation, the call should eventually happen through an
ordinary lead-agent tool. Then the parent records:

- 📲 the delegation;
- 🧾 the child's answer;
- 🟢 or 🚫 how it ended.

No special subagent subsystem is needed.

#### 5. The shield advice misses the process boundary

“Make scout/reviewer/tester read-only” sounds straightforward but has important
complications.

If a `no-writes` shield wraps the outer `m8 query` command, it can also prevent
that command from writing its child turns and moving its chat under `.m8-st8`.
Persistent job history and a no-write outer wrapper are therefore in tension.

The cleaner distinction is:

- let the child `m8 query` maintain its ledger;
- constrain the tools defined by the child agent;
- put `no-writes` or `no-edit-m8-st8` on the child agent's tool executions, not
  indiscriminately around the outer delegation process.

Also, a tester usually cannot be truly read-only: Zig tests may write
`.zig-cache`, `zig-out`, temporary files, or fixtures. “Cannot edit source” and
“cannot write anything” are different policies.

#### 6. The existing general shell is not a good delegation path

The current `bash` tool runs under `workbench`, which includes:

- `airgap`
- `no-loop`

A nested `m8 query` launched through that tool inherits those restrictions as a
descendant. A remote subagent provider would therefore be unable to reach its
model.

An explicit delegation tool may indeed be useful—but because it provides the
correct process/shield boundary, not because m8 lacks a subagent feature.

That tool should be an ordinary, narrow 🧰 calling `m8 query`, and should not
inherit the general-purpose airgapped shell wrapper. The child agent then
controls its own tool capabilities.

### A more m8-shaped first experiment

Start with only:

```text
@team/
  scout.md
  reviewer.md
```

Possibly start with just `reviewer.md`, using different named chats for
reconnaissance and review.

Principles:

1. **The child chat is the handoff.**
   Do not create a `scratch/handoffs/` subsystem.

2. **Delegation is a tool call.**
   The parent ledger records what was asked and what came back.

3. **The mob defines the complexity.**
   Give the model a narrow tool such as “ask reviewer”, rather than a broad
   orchestration API.

4. **Capabilities live on child tools.**
   Scout/reviewer receive read, list, grep, and perhaps a dedicated diff
   reader; they do not receive a generic edit tool.

5. **Use named chats only where continuation matters.**
   Fresh throwaway work can use `--no-store`; work requiring another pass gets
   a persistent address.

6. **Responses stay ordinary prose.**
   Ask for findings, evidence, and uncertainty without inventing a mandatory
   protocol.

7. **Add an implementer only when ownership is genuinely delegated.**
   At that point, give it a bounded file area or task—not merely the title
   “implementer.”

8. **Treat parallelism as a later composition.**
   The project already suggests that one tool could distribute several calls.
   There is no need to encode a parallel-agent scheduler into the initial
   design.

The short verdict is: **keep the mob and named-chat mechanics; discard the
permanent org chart, archivist, handoff directory, and rigid response contract;
explicitly design the shield boundary for one narrow delegation tool.**

## Proposed direction

Use m8's existing composition model to let Devyn consult small collaborators,
without introducing a second orchestration system or a second source of truth.

The first version should prove one thing:

> An agent invoked as an ordinary tool can save the lead agent context while
> leaving both the delegation and the work it performed in readable ledgers.

It should not attempt to establish a permanent five-role organisation, a new
handoff format, or framework-level subagent semantics. `IDEAS.md` still calls
subagent design the largest undecided area, so the first implementation should
be deliberately easy to remove or reshape.

## Constraints from m8's design

The design should follow these project commitments:

- The conversation is the artifact.
- The ledger is the truth.
- An agent, transcript, tool exchange, and wire request use one grammar.
- Capability comes from composition, not a plugin API.
- Agent structure belongs to the authored mob, not to the framework.
- A subagent is already expressible as a tool whose command calls an agent.
- Chats are references to immutable turns; they are already the durable work
  history.
- Shields restrict descendants. Their placement is therefore part of the
  delegation design, not an implementation detail.

## What to retain from Luna's plan

Several parts of `PLAN_AGENTS_LUNA.md` fit well:

- Put collaborators in an authored `@team/` mob.
- Give ongoing jobs named chats such as `@team/reviewer/parser`.
- Use `--new` when a job must restart from the agent as authored.
- Continue the same address when a job genuinely needs another pass.
- Do not run two writers against the same files.
- Give each collaborator only the capabilities its work requires.
- Keep the main Devyn chat stationary while a collaborator's own chat moves.

## What not to carry forward

### No shadow handoff store

Do not routinely maintain `scratch/handoffs/current.md`, `parser.md`, or similar
summaries beside the chats.

Those files would become mutable session state that can drift from the ledger.
The child job chat already contains the complete history. Its concise final
answer also appears as the receipt of the delegation in the parent ledger when
the child is called as a tool.

Create an ordinary project document only when the document itself is a desired
project artifact. If a portable conversation snapshot is wanted, use an m8
reference or an encoded m8 document rather than a parallel handoff convention.

### No archivist role initially

An archivist whose purpose is to keep the shadow summaries current solves a
problem introduced by the summaries. Leave it out.

### No fixed five-agent organisation

Do not initially add implementer, tester, and archivist agents merely because
those are familiar software-team roles.

- Devyn is already the implementer and final decision-maker.
- Testing is normally an operation performed by the working agent; Zig tests
  also need to write caches and outputs, so a nominally read-only tester is not
  straightforward.
- A second implementer is useful only after there is a real, bounded ownership
  boundary that permits independent work.

Mobs permit specialised teams, but m8 should not imply that one decomposition
is canonical.

### No mandatory response mini-language

Do not require every collaborator to emit a rigid
`STATUS/EVIDENCE/CHANGED/TESTS/RISKS/NEXT` template.

Ask for a concise answer containing findings, evidence, actions taken, and
uncertainty when those are relevant. The m8 ledger is the protocol; another
fixed textual protocol should be introduced only if a real consumer needs to
parse it.

## Initial team

Start with at most two collaborators:

```text
@team/
  scout.md       repository reconnaissance; no source writes
  reviewer.md    inspect a proposed or completed change; no source writes
```

Even this split is optional. One `peer.md` with separate named job chats may be
a better first experiment if the prompts and capabilities are otherwise the
same.

### Scout

Purpose:

- Locate implementations and tests.
- Trace relevant control and data flow.
- Identify invariants and likely extension points.
- Return file paths, symbols, and short quoted anchors rather than relying only
  on line numbers that will drift.

Capabilities:

- `list`, `read`, and `grep`.
- Possibly a narrow read-only command for repository metadata.
- No general edit tool.
- No general shell unless reconnaissance proves it necessary.

### Reviewer

Purpose:

- Inspect the current change and nearby invariants.
- Find concrete correctness defects, regressions, or missing tests.
- Distinguish blocking defects from optional improvements.
- Never edit the change it is reviewing.

Capabilities:

- The same read tools as Scout.
- A narrow way to read the current diff and test output.
- No edit tool.

A review should cite evidence and say when it found no defect. It should not
manufacture findings to satisfy a response template.

## Delegation must be an ordinary tool call

The integrated path should be:

```text
Devyn ledger
  -> 📲 delegation tool
     -> m8 query @team/ROLE/JOB MESSAGE
        -> child job ledger
     <- concise child answer
  <- 🧾 answer and verdict
```

This has two useful records:

1. The child chat contains its complete work history and can be continued.
2. The parent ledger records that delegation occurred and exactly what answer
   Devyn received from it.

Running `m8 query` manually from the user's shell is useful as a smoke test, but
it should not be the normal orchestration path. A manually launched child is
not a tool call in Devyn's ledger.

No new framework command is required. The delegation facility should be an
ordinary authored toolbox definition, possibly backed by a small dispatcher
owned by the mob.

## Tool interface

Prefer one narrow tool per collaborator over a general "run any agent" tool:

```text
scout(job, request, fresh?)
review(job, request, fresh?)
```

The tool, not the model, supplies the fixed agent prefix. `job` selects the
chat below that agent. The implementation must validate it as one safe path
component rather than interpolating arbitrary shell or address syntax.

Semantics:

- A missing `fresh`, or `fresh=false`, continues the named job if it exists.
- `fresh=true` maps to `m8 query --new` and deliberately resets that job's
  starting point.
- The request is one argument and never becomes shell syntax.
- The command's textual answer is wrapped as a normal m8 tool receipt.
- Failure remains a tool failure; it is not rewritten as a successful summary.

A throwaway mode may later map to `m8 query --no-store`, but it is not needed to
prove persistent jobs.

## The shield boundary

This is the most important correction to the earlier plan.

### Do not wrap the outer child query in `no-writes`

A shield around the delegation tool wraps the `m8 query` process and all of its
descendants. `no-writes` there can prevent m8 from storing the child turns and
moving its chat. It can also interfere with providers or commands that need
ordinary temporary state.

Read-only source access should instead be expressed by the child agent's tool
surface and by shields applied to those child tools. The m8 process hosting the
child must remain able to maintain its ledger.

### Do not delegate through Devyn's current `bash` tool

The current `bash` tool uses `workbench`, which includes both `airgap` and
`no-loop`. A nested remote-model provider is a descendant and inherits those
restrictions, so it cannot serve as the normal delegation path.

The dedicated delegation tool needs its own deliberately chosen shield set. It
should inherit Devyn's top-level protections such as `no-edit-git`, but should
not acquire the generic shell tool's network restrictions merely by reuse.
The child agent then constrains its own tools.

### Keep state protection on child tools

Child agents that have any command capable of writing should activate
`no-edit-m8-st8` and `no-edit-git` for their tools. This prevents a child tool
from changing the definitions or restrictions governing a later run while
still allowing the hosting m8 process to write the child's generated chat
state.

For Scout and Reviewer, the stronger design is not to offer broad write tools
at all. A denied edit tool still consumes model attention and invites failed
calls.

## Job workflow

Use one chat for one continuing problem, not one chat for one invocation:

```bash
m8 query --new @team/scout/parser "Trace the parser path and identify the invariant this change must preserve."
m8 query @team/scout/parser "Check the proposed seam against the two callers we found."

m8 query --new @team/reviewer/parser "Review the current parser diff for concrete correctness defects."
m8 query @team/reviewer/parser "Recheck after the two blocking findings were addressed."
```

These commands illustrate the child semantics. In normal use the equivalent
calls should be made by Devyn's delegation tools so their requests and results
remain in the parent ledger.

Start a new job when the objective changes materially. Continue an old one only
when its prior evidence is useful. A persistent chat is not automatically
better; irrelevant history is still context.

## Context policy

The parent should send a bounded request containing:

- the objective;
- the relevant scope or files, when known;
- the specific question to answer;
- constraints the child cannot infer from the repository.

The child should return a compact answer, with enough file and symbol evidence
for Devyn to verify it. Exploration detail remains in the child chat rather
than being copied wholesale into the parent.

Devyn remains responsible for:

- deciding whether delegation is worthwhile;
- checking consequential claims;
- integrating findings;
- making edits unless ownership was explicitly delegated;
- running or confirming the final relevant tests;
- presenting the final answer to the user.

## Rollout

### Phase 1: composition smoke test

- Author one read-only collaborator, preferably Scout.
- Invoke it directly with `m8 query` to verify its prompt, tools, and chat
  continuation.
- Confirm that its tools cannot alter source, `.git`, or agent definitions.
- Confirm that its child ledger remains readable and resumable.

### Phase 2: one integrated delegation tool

- Add the narrow `scout(job, request, fresh?)` tool to Devyn.
- Ensure the call and result appear in Devyn's ledger.
- Ensure the child can reach its provider despite the parent shell's airgap.
- Ensure child state can be stored while child tools remain unable to edit it.
- Exercise fresh, continue, failure, and interruption cases.

### Phase 3: review collaborator

- Add Reviewer only if Scout demonstrably saves useful parent context.
- Give Reviewer a narrow diff-reading path rather than a broad shell where
  practical.
- Test review followed by a continuation after fixes.

### Phase 4: evaluate rather than automatically expand

Measure informally:

- Did delegation reduce Devyn's context or merely duplicate reading?
- Is the returned evidence sufficient to verify?
- Are named child chats being usefully continued?
- Does the parent ledger clearly show what was delegated?
- Are shield failures understandable?
- Is operating the team simpler than doing the work directly?

Only then consider a bounded implementing collaborator, parallel distribution,
or a more general dispatcher.

## Acceptance criteria

The first experiment is successful when:

- No new framework-level subagent concept was required.
- Devyn can delegate through a normal 🧰 record.
- The delegation and returned answer are present in Devyn's ledger.
- The child's detailed work is present in its own immutable chat history.
- No mutable handoff summary is needed to resume the job.
- Scout cannot edit repository files, `.git`, or `.m8-st8` through its tools.
- The child provider remains reachable through the intended delegation path.
- A failed child call is recorded as a failure rather than hidden by a summary.
- Removing the experiment means deleting ordinary agent/tool definitions, not
  migrating stored application state.

## Questions to settle during implementation

- Is one peer with named chats enough, or do Scout and Reviewer need different
  prompts and capabilities?
- Where should the small job-name validator/dispatcher live so it remains an
  ordinary mob-owned composition?
- Should initial child chats be persistent by default, or should throwaway
  `--no-store` consultations be the common case?
- What is the narrowest useful way for Reviewer to inspect a diff without
  inheriting the general shell tool?
- Which protections belong on the delegation tool itself, and which belong on
  tools offered by the child?
- How should interrupted child runs be presented while preserving the partial
  turns m8 already stored?

Do not settle these by adding framework machinery first. Build the smallest
ordinary composition, inspect its ledgers and process boundaries, and let that
evidence determine the next shape.
