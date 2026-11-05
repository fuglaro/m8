# Pretty parameter declarations

Owner: `crew/devyn`. Delegate: `cody`.

Status: implemented and verified. Atomic cutover; no legacy parser was added.

## Completion notes

- The production change is confined to parameter parsing/rendering in
  `src/toolbox.zig`; the property model and provider schema writers are unchanged.
- Migrated fixtures, docs/examples, all six shared live toolbox files, and the
  live Zork player. No compatibility branch remains.
- `zig fmt --check`, `zig build test`, `zig build`, and `git diff --check` pass.
- The new binary successfully encodes every migrated live toolbox file and the
  Zork player as OpenAI Responses requests. Expanded `crew/devyn` and `crew/cody`
  also encode successfully without contacting a provider.
- Live definition changes are tracked in Git alongside the source migration.
- Cody implemented the toolbox changes and reviewed the result; Devyn integrated
  the migration, corrected an escape test fixture, and added JSON/schema
  round-trip coverage in both record spellings.

## Goal and agreed syntax

Make tool parameter declarations readable Markdown, with explicit boundaries
between the name and the schema specification:

```markdown
* `Count?` **integer,minimum:0**
  Optional number of results.
* `Unit` **degrees celsius|degrees fahrenheit**
* `Parent` **object**
* `Parent.Child` **string[]**
```

The final language accepts only the new spelling. Backward compatibility may
exist temporarily while migrating, but must be removed before completion.

### Names

- Enclose the name in a single pair of backticks.
- Names must be nonempty and contain no whitespace or backticks.
- A trailing `?` inside the backticks marks an optional parameter; strip it
  before storing the name. Reject an empty name after stripping it.
- Reserve a trailing `?` for optionality, not literal name content. Do not add
  name escaping or change the existing dotted-path/environment-name rules.

### Schema span

- Enclose the entire type and comma-separated schema extras in `**...**`.
  Extras belong inside the span: `**integer,minimum:0**`.
- Keep the existing type, enum, array, and extras semantics. Enum values may
  contain spaces; name whitespace remains forbidden.
- An unescaped `**` closes the span. A single `*` is ordinary content.
- Within the span, `\*` decodes to `*`, and `\\` decodes to `\`.
  Other backslashes remain unchanged. These are language-level quoting rules,
  not a request to run a general Markdown unescaper.
- Scan for the closing delimiter while respecting escapes, then unescape the
  complete payload, then pass it to the existing type/extras parser.
- Keep JSON escaping separate: extras are parsed only after this outer quoting
  layer is removed. Rendering must apply the reverse layers in reverse order.
- Require a nonempty type and reject non-whitespace trailing text after the
  closing span. Descriptions stay on following indented lines.
- Malformed declarations must produce a useful error rather than becoming
  literal backtick-bearing property names or unknown bold-wrapped types.

Example of an escaped literal asterisk pair in a JSON extra:

```markdown
* `Pattern` **string,default:"\*\*/*.zig"**
```

The decoded default is `**/*.zig`.

## Scope and implementation map

- `src/toolbox.zig`: `property()` parses bullets; `render()` serializes them.
  Keep stored names/types/extras free of presentation delimiters and escapes.
  `writeParameters()` and the provider schema writers must retain their current
  semantics; this is an m8 declaration syntax change, not a JSON schema change.
- `src/agent.zig`: loads tool declarations through the toolbox parser.
- `src/ledger.zig`: mode conversion uses toolbox parse/render; verify conversion
  preserves meaning in both native and Markdown record spellings.
- `src/m8/highlight.zig` and Markdown helpers: inspect existing rendering and
  highlighting behavior; change only what the new syntax actually requires.
- Tests and embedded declarations throughout `src/`, plus docs, examples and
  other authored agent definitions: audit all declaration producers/consumers.
- `.m8st8/mobs/`: migrate live tool definitions, particularly
  `.m8st8/mobs/shared/toolbox/*.md`, and inspect every other mob subtree too.
  These hidden runtime files need an explicit search; ordinary recursive globs
  may skip them. Do not assume a tracked-file diff covers this migration.

Tool-call argument syntax is out of scope. Do not mechanically rewrite every
bullet, backtick span, command, enum value, or description in the repository.

## Work plan

### 1. Inventory and choose migration sequencing

- [x] Record the current worktree changes; preserve the user's existing changes
      to `docs/language.md`.
- [x] Locate all old declaration fixtures, expected render strings, tool
      definitions, docs, and live mob declarations.
- [x] Choose either temporary dual parsing or an atomic cutover. If choosing the
      latter, avoid `zig build` until parser, renderer, fixtures and live toolbox
      definitions have all been migrated. Do not run an old binary against
      newly migrated live definitions during the transition.
- [x] If temporary compatibility is used, make it explicit and track its removal;
      renderer output should use only the new canonical syntax.

### 2. Parser and renderer

- [x] Parse and validate the backtick-delimited name and optional marker.
- [x] Scan the schema span with escape awareness, validate boundaries, decode
      only the two agreed escapes, then use the existing type/extras machinery.
- [x] Add focused errors for malformed names, missing delimiters, empty schema
      types, and unexpected trailing text.
- [x] Render the name/optionality in backticks and the full schema payload in
      bold. Serialize extras first, then escape the full payload, including
      backslashes introduced by JSON serialization.
- [x] Prefer a deterministic canonical encoder: escape all literal backslashes
      and asterisks in the payload. Parsing need not require every single `*`
      to be escaped.
- [x] Keep descriptions, commands, shields, dotted paths, optionality, and
      environment-variable behavior unchanged.

### 3. Migrate declarations and documentation

- [x] Update embedded declarations and exact rendering expectations in tests.
- [x] Update `docs/language.md` in both record spellings, documenting extras
      inside bold, whitespace-free names, and the escape rules.
- [x] Migrate other docs/examples and authored definitions found in the inventory.
- [x] Migrate tool parameter declarations throughout `.m8st8/mobs/`, including
      shared toolbox tools used by `crew/devyn` and `cody`.
- [x] Review each changed live file; preserve descriptions, command bodies,
      schema extras, and required/optional semantics.

### 4. Test and finish the cutover

- [x] Remove temporary legacy parsing and prove old declarations are rejected.
- [x] Run focused tests and the repository's normal build/test checks after the
      migration is complete; inspect `build.zig` for the supported commands.
- [x] Smoke-test loading the migrated live toolbox definitions with the new
      binary. Compilation alone does not validate runtime mob files.
- [x] Audit for remaining old declarations, distinguishing declarations from
      call-argument bullets and illustrative legacy-rejection tests.
- [x] Review the final diff and report any untracked/ignored live-file changes
      separately so they are not silently lost.

## Required test coverage

- Required/optional names, dotted names, arrays, objects, enum values containing
  spaces, descriptions, and multiple extras (including comma-containing JSON).
- Reject whitespace/backticks in names, empty names, missing delimiters, empty
  types, trailing garbage, and the legacy plain declaration spelling.
- Escaped stars, literal single stars, literal `**`, escaped backslashes,
  unknown backslash sequences, and odd/even backslash runs before delimiters.
- JSON extras containing quotes, backslashes, asterisks, and delimiter-like text;
  ensure m8 escaping neither consumes nor adds JSON escapes after round-trip.
- Parse -> render -> parse semantic equality and stable canonical rendering.
- Native/Markdown conversion and provider JSON schema equivalence.
- All migrated live toolbox definitions load successfully.

## Delegation

`crew/devyn` owns sequencing, integration, live configuration migration, and the
final result. Delegate bounded, independent work to `cody`, for example a
read-only declaration inventory or a test/edge-case review. Avoid concurrent
edits to the same files, and verify delegated findings before closing items.

## Definition of done

Only the pretty syntax is accepted and emitted; docs, fixtures, and live mob
toolboxes agree; escapes round-trip without altering schema values; normal
checks and live-definition loading pass; no compatibility branch remains.
