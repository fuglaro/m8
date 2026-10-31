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

- [ ] Inspect launcher/dispatch input handling and existing command test helpers.
- [ ] Add the missing stdin reader and terminal metadata to `Ctx`; wire real
      process input at the outer boundary without changing CLI behavior.
- [ ] Move `say`'s direct stdin access behind `Ctx`, including terminal reads.
- [ ] Add a small Zig fixture for invoking a command with supplied args/input,
      captured output/errors, and isolated config/storage. Extract shared helper
      code only as it becomes useful.
- [ ] Exercise the real `say` path with a deterministic provider. Resolve any
      subprocess/executable setup needed for that path during implementation.

### 2. Move the regression into Zig

- [ ] Reproduce riff's child-command conditions without running riff: piped
      stdin, `say -r -i`, and captured rendered output.
- [ ] Assert that the submitted user record appears before the reply, exactly
      once. Confirm the test fails when the original display bug is restored.
- [ ] Cover the relevant alternatives: Markdown output, reply-only output, and
      unwrapped output; ensure the boundary change does not alter them.
- [ ] Replace the corresponding shell-smoke assertions once the Zig coverage
      exercises the same behavior. Keep unrelated storage smoke coverage.

### 3. Extend incrementally

- [ ] Find other commands that bypass `Ctx` for process input or terminal
      detection, and migrate them in small batches.
- [ ] Port smoke scenarios where process arrangement is their only reason to
      live in a shell script. Keep assertions about observable command behavior.
- [ ] Keep a small set of actual executable/process integration tests for
      launcher wiring, inheritance, and other behavior an in-process invocation
      cannot establish.

## Checks as we go

Run `zig build test` and the affected CLI checks. Preserve stdin opt-in, EOF
handling, stream separation, and terminal-versus-pipe behavior. Tests should not
read the test runner's stdin or depend on its terminal or user configuration.

Riff's raw mode, resize handling, signals, and terminal protocol are outside this
work. Do not introduce a PTY emulator to test ordinary commands.
