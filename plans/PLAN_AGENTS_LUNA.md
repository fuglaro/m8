# Agent Delegation Plan for Cody

Cody should use agents as small, named collaborators while remaining the orchestrator and final decision-maker.

## Proposed team

```text
@team/
  scout.md       read-only repository reconnaissance
  implementer.md one bounded code change plus tests
  reviewer.md    inspect diffs, invariants, and missed cases
  tester.md      run focused tests and diagnose failures
  archivist.md   turn decisions into compact durable handoffs
```

### Roles

- **Scout:** Find where something is implemented; cite files and relevant lines. Do not edit.
- **Implementer:** Make one scoped change, run relevant tests, and report files changed.
- **Reviewer:** Inspect the current diff and identify concrete defects. Do not edit.
- **Tester:** Run the smallest useful test matrix and report failures verbatim.
- **Archivist:** Summarize decisions, constraints, open questions, and next steps into a handoff.

## Job workflow

Give each task its own persistent chat:

```bash
m8 query --new @team/scout/ledger "Map the ledger parsing path and likely extension points."
m8 query --new @team/implementer/parser "Implement the scoped parser change described here..."
m8 query --new @team/reviewer/parser "Review the current implementation and diff."
```

Continue an existing job when it needs another pass:

```bash
m8 query @team/implementer/parser "Address the review findings, but keep the original scope."
```

`--new` gives a clean context. Continuing the same address gives the agent its prior work. Job transcripts remain under `+/`, while the main Cody conversation does not move.

## Context-saving pattern

Use two layers:

1. The m8 job transcript for complete history and evidence.
2. Compact handoff files for durable working context:

```text
scratch/handoffs/
  current.md
  parser.md
  architecture.md
```

Each handoff should contain:

```text
Current objective
Decisions made
Relevant files
Constraints/invariants
What has been tried
Tests and results
Open questions
Recommended next action
```

This lets Cody reload essential context without replaying every exploratory turn.

## Guardrails

- Scout, reviewer, and tester agents should be read-only or use no-write shields.
- Implementers should have confined writes and no unnecessary network access.
- Archivists should write only handoff files.
- Agents must not edit `.git` or agent definitions.
- Do not run parallel agents that edit the same files.
- Every agent reports changed files, tests actually run, and uncertainty.

Use a fixed response contract:

```text
STATUS:
EVIDENCE:
CHANGED:
TESTS:
RISKS:
NEXT:
```

## Recommended first step

The current `cody.md` has strong basic tools and `freeze-toolbox`, but no explicit delegation tool yet. Preserve that safety posture and initially add only explicit delegation for:

1. `scout`
2. `reviewer`
3. `archivist`

These reduce Cody's context load without granting broad write authority. Agents can initially be invoked manually with `m8 query`; fixed delegation tools can be added once the workflow is proven.
