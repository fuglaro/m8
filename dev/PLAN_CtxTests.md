# Command integration tests through Ctx

## Goal

Run real command implementations in Zig tests, with process inputs supplied
through `api.Ctx`. Prefer these tests over shell smoke scripts when the shell
only arranges arguments, stdin, terminal properties, and captured output.

Keep real command parsing, assembly, rendering, and persistence in the test.
Use temporary config/storage and deterministic providers where practical.
This is not a project to mock the filesystem or build a fake OS.

## Boundary

`Ctx` is the command's process boundary; do not add a parallel `Platform` API.
The launcher discovers real process state and supplies it to commands.

- Args, environment, stdout/stderr writers, and the interaction channel are
  already represented in `Ctx`.
- Supply stdin through `Ctx`, including whether it is a terminal, rather than
  opening global stdin inside commands.
- Keep stdin, stdout presentation/pipe properties, and the controlling terminal
  distinct. Piped input can legitimately produce rendered output.
- Reconcile the existing pre-read `Ctx.in` document with the stdin reader as we
  wire the first command. Avoid ambiguous ownership or reading stdin twice.
- Use Zig's existing reader/writer and `std.Io` facilities; add abstractions
  only where a real test needs them.

## Work through

### 1. Establish the boundary with say

- [x] Inspect launcher/dispatch input handling and existing command test helpers.
- [x] Add the missing stdin reader and terminal metadata to `Ctx`; wire real
      process input at the outer boundary without changing CLI behavior.
- [x] Move `say`'s direct stdin access behind `Ctx`, including terminal reads.
- [x] Add a small Zig fixture for invoking a command with supplied args/input,
      captured output/errors, and isolated config/storage. Extract shared helper
      code only as it becomes useful.
- [x] Exercise the real `say` path with a deterministic provider. Resolve any
      subprocess/executable setup needed for that path during implementation.

### 2. Move the regression into Zig

- [x] Reproduce riff's child-command conditions without running riff: piped
      stdin, `say -r -i`, and captured rendered output.
- [x] Assert that the submitted user record appears before the reply, exactly
      once. Confirm the test fails when the original display bug is restored.
- [x] Cover the relevant alternatives: Markdown output, reply-only output, and
      unwrapped output; ensure the boundary change does not alter them.
- [x] Replace the corresponding shell-smoke assertions once the Zig coverage
      exercises the same behavior. Keep unrelated storage smoke coverage.

### 3. Extend incrementally

- [x] Audit remaining process-input and terminal-detection bypasses; migrate
      `cat`, `render`, and `parse` with supplied-input command tests.
- [x] Migrate `toy-provider`, including terminal refusal and supplied-request tests.
- [x] Migrate `url-provider` stdin and curl response streams; test input-boundary
      rejection and the transport pump separately from HTTP integration.
- [x] Migrate the remaining ordinary command, `cast`.
- [x] Audit the retained storage smoke scenarios: they exercise storage,
      launcher dispatch/discovery, or actual child environment inheritance,
      rather than only arranging process input/output.
- [x] Port any further smoke scenarios where process arrangement is their only
      reason to live in a shell script. Keep observable-behavior assertions.
      No further Ctx-only candidates remained; the storage script was subsequently
      ported to Zig executable/process tests without dropping its assertions.
- [x] Keep a small set of actual executable/process integration tests for
      launcher wiring, inheritance, and other behavior an in-process invocation
      cannot establish.

## Continuation guide

Stages 1–3 are complete, including `cast` and the final shell-scenario audit.
The former storage smoke script is now `src/storage_process_test.zig`, run by
`zig build test` against the test-built launcher.
Inspect the working tree before further edits and preserve the completed coverage.

### Boundary and implementation locations

- `src/api.zig` defines `Ctx.stdin: ?*std.Io.Reader`, a borrowed raw-input
  reader, and `Ctx.stdin_terminal: bool`.
  - Null stdin means no raw input is supplied; never fall back to global stdin.
  - Terminal metadata is independent of stdout presentation and `Ctx.tty`.
  - `api.readDocument(reader, terminal, arena)` reads a nonterminal document;
    terminal input yields an empty document without waiting for EOF.
- `src/harness.zig` supplies real process stdin for launcher and leaf commands.
- `src/launch.zig` handles in-process dispatch.
  - Commands taking a document receive pre-read `Ctx.in`, with `stdin` cleared
    to prevent reading the same input twice.
  - Raw-input commands (`.takes = .nothing`) receive the reader instead.
  - Check each command's `.takes` setting and input ownership before migrating
    it; do not mechanically replace stdin access.

### Existing test pattern

- `Invocation` and the integration tests in `src/command/say.zig` invoke the
  real command with supplied readers, captured stdout/stderr, and isolated
  temporary config, storage, and environment.
- `build.zig` supplies `@import("test_options").launcher`, an unsplit executable
  built as a test dependency for the real toy-provider subprocess.
  - Do not depend on an installed `zig-out/bin/m8` from an in-process test.
- `src/command_input_test.zig` now supplies a small shared fixture for the raw
  filters `cat`, `render`, and `parse`: arena, isolated environment/config
  discovery, and captured stdout/stderr. It needs no filesystem storage.
  Say's subprocess/storage fixture remains local; do not generalize it until
  another command needs those facilities.
- The say regression checks that a piped submission appears exactly once before
  the reply. Restricting its display guard to terminal stdin makes the test
  fail with zero user records; the correct guard passes.
  - Preserve Markdown, reply-only, unwrapped, stdin opt-in, and terminal EOF
    coverage as well.

### Remaining batches

- `cat`, `render`, and `parse` now consume `Ctx.stdin`; absent stdin is EOF.
  They remain raw streaming commands (`.takes = .nothing`), including when
  supplied input is terminal-marked. Tests cover modes, final unterminated
  input, terminal metadata, null input, and diagnostic/output separation.
  Render consumes buffered bytes before refilling (important for fixed readers).
- `cast` consumes supplied `Ctx.stdin`; absent input is EOF. It remains a raw
  streaming command (`.takes = .nothing`) and reads terminal-marked input too.
  Tests cover static record ordering, hidden prelude and final unsent draft,
  animated output, CRLF/unterminated input, null input, argument rejection
  without consumption, and diagnostics separated from SVG output.
- The final audit found no ordinary direct-stdin users or terminal probes left
  in `src/command/`.
- `riff` also probes stdin; its terminal protocol remains outside this work.
- Audit shell scenarios for cases whose only process requirement is arranging
  arguments, stdin, terminal metadata, and captured output; port those to Zig.
- `src/storage_process_test.zig` replaces `dev/comptime-platforms/storage-smoke.sh`.
  It spawns the test-built launcher with EOF stdin, captured output, isolated
  environment and temporary config/storage. It preserves cross-invocation
  persistence, no-advance pointer/turn checks, mob-space recreation, session
  reset and shorthand, user storage relocation, real delegated-child root
  inheritance, help/error dispatch, and nearest-project registration checks.
  These remain process tests, not in-process Ctx tests; the delegated tool
  still uses `sh` to narrow its child's environment. Default and no-curl test
  suites, build, formatting and diff checks passed after the script was retired.
- Update this plan's checklist and remaining-command inventory as batches land.

### Next-session handoff

- Keep test helpers outside `src/command/`: `src/command.zig` tests that every
  Zig file in that directory is a registered command. The shared fixture lives
  at `src/command_input_test.zig` for this reason.
- `toy-provider` now consumes `Ctx.stdin` (null means EOF) and uses
  `Ctx.stdin_terminal`. Its tests reuse the shared fixture and cover Markdown
  and m8 replies with unterminated input, terminal refusal without consumption,
  missing/unknown models, malformed requests, and `--models` bypassing input.
  Full tests, build, storage smoke, formatting, diff checks, and an executable
  echo-provider pipe check passed for this batch.
- `url-provider` now owns supplied `Ctx.stdin` and terminal metadata; `--get`
  and `--upload` still do not consume stdin. Curl stdout/stderr are captured
  through Ctx even without stats. Its single-threaded build cannot concurrently
  pump request/response pipes, so POST input is spooled to an exclusive 0600
  file under supplied TMPDIR (fallback /tmp), with positional writes leaving
  the child descriptor at offset zero. The file is closed/deleted on exit.
  Curl's `--data-binary @-` already buffers requests before sending them.
- URL tests cover terminal refusal, endpoint/argument validation, large supplied
  input, absent-input EOF, exit codes, stream separation, and the no-input pump.
  The pump uses a deterministic shell transport, not an HTTP server. Successful
  HTTP POST/upload, stats formatting, and the stdlib HTTP transport are not
  established by these input-boundary tests. Stats' formatter still inherits
  process stderr; migrate that separately if adding captured formatter tests.
- Default and no-curl test suites, build, storage smoke, formatting and diff
  checks passed. An executable curl file-URL GET passed. A localhost HTTP check
  could not run because the sandbox prohibits binding a socket.
- The `cast` batch preserved its existing summary/formatting edits. Full tests,
  build, storage smoke, formatting and diff checks passed, as did an executable
  supplied-ledger `cast --static` pipe check. No terminal emulator was needed.
- `parse` command tests now cover both the `m8` codec and deterministic
  `openai-completions` responses: SSE/whole-response equivalence with no final
  newline, fragmented tool arguments rendered as one call without an empty
  assistant record, and non-object arguments preserved after assistant text.
  Usage metadata stays off stdout/stderr at verbosity 0 and 1. No current codec
  produces a nonempty `Reply.aside`, so that branch remains unexercised; do not
  mistake the metadata test for nonempty-aside coverage. These fixed-reader
  tests cover provider event fragments, not transport chunking or flush timing.
- The first batch also passed executable pipe checks for `cat --pack`,
  `render -r` (CRLF and unterminated input), and `parse m8`. Full tests, build,
  storage smoke, changed-Zig formatting checks, and `git diff --check` passed.
- At handoff, earlier boundary/say changes were staged, while this batch and
  the shared fixture were unstaged/untracked. Inspect status before staging;
  do not discard or overwrite either set of changes.

### Validation baseline

The completed stages pass these commands from the repository root:

```sh
zig build test
zig build
```

Formatting checks and `git diff --check` also pass. Repeat the tests and affected
CLI checks for each migration. Storage/process integration is included in
`zig build test`; no separate storage smoke script or installed launcher is needed.

## Checks as we go

Run `zig build test` and the affected CLI checks. Preserve stdin opt-in, EOF
handling, stream separation, and terminal-versus-pipe behavior. Tests should not
read the test runner's stdin or depend on its terminal or user configuration.

Riff's raw mode, resize handling, signals, and terminal protocol are outside this
work. Do not introduce a PTY emulator to test ordinary commands.
