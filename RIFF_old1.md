# RIFF: Minimal Inline Terminal Command Runner

m8 @pagey (resets chat to pagey)

riff m8 -- 

## Status

Exploratory product/engineering spec for a planning + research agent.

This document intentionally captures the **intent, architecture, constraints, and questions** rather than prescribing a fully nailed-down implementation. The next agent should research the relevant terminal behavior and turn this into a concrete implementation plan.

---

## 1. Goal

Build a standalone, dependency-light Zig command-line tool that runs an arbitrary interactive command while providing a **temporary interactive panel at the bottom of the terminal**.

The user should experience something like:

```text
$ riff some-command

output from some-command...
more output...
more output...

┌─────────────────────────────────────────────┐
  type something here
└─────────────────────────────────────────────┘
```

The command owns the normal/top terminal stream.

The bottom panel is controlled by `riff` and is used for user input.

The user can type into the panel while the command continues to run. Pressing **Ctrl+Enter** submits the current panel contents to the command's stdin.

After submission, the submitted text should become ordinary terminal history/output (or otherwise be committed above the live panel), and the panel becomes available for another input.

The important UX goal is:

> **normal terminal scrollback remains real terminal scrollback; only the small live region at the bottom is actively managed.**

This should *not* be a conventional full-screen TUI.

---

## 2. Core mental model

Think of the terminal as two regions:

```text
┌──────────────────────────────────────────────┐
│                                              │
│       committed / normal command output      │
│                                              │
│       real terminal scrollback               │
│                                              │
├──────────────────────────────────────────────┤
│                                              │
│       small live input panel                 │
│                                              │
└──────────────────────────────────────────────┘
```

The bottom region is a **live region**.

The top region is **not owned by a retained TUI renderer**. Once content is committed there, it should become ordinary terminal history.

The library/tool should be able to:

1. reserve a small number of terminal rows for the live region;
2. render/update those rows;
3. insert/commit output above the live region without repainting the entire terminal;
4. resize the live region as needed;
5. eventually remove the live region and return the terminal to normal command output.

The design should be conceptually similar to the useful parts of Ratatui's inline viewport / `insert_before` approach, but **without adopting Ratatui or another TUI framework**.

---

## 3. Why not a normal alternate-screen TUI?

Do **not** use the terminal alternate screen as the fundamental UI model.

The desired behavior is specifically that command output survives as normal scrollback:

```text
$ riff command

command output 1
command output 2
command output 3

[user submission]

command output 4
command output 5
```

When the user scrolls back in their terminal, they should see the actual history.

We are interested in an **inline / primary-screen / live-region** architecture.

The tool should not periodically repaint the entire transcript.

---

## 4. Process model

At minimum there are two logical participants:

```text
                     terminal
                         │
                         ▼
                       riff
                    /         \
                   /           \
               child PTY       input UI
                   │
                   ▼
             target command
```

`riff` is the terminal owner.

The target command should preferably run under a **PTY**, not merely stdin/stdout pipes, because the target may be an interactive terminal program and may inspect terminal properties.

The target command should receive:

- stdin from `riff`;
- stdout/stderr through the PTY back to `riff`;
- appropriate terminal dimensions;
- terminal-like behavior as far as the minimal implementation can reasonably support.

`riff` multiplexes:

- child output → terminal/top stream;
- user input → bottom panel;
- Ctrl+Enter → submitted text → child stdin.

The initial implementation does not need to promise support for every arbitrary full-screen terminal application. This needs to be researched and explicitly scoped.

---

## 5. Basic interaction

Example:

```bash
riff python
```

The user sees Python's normal output / prompt, plus a bottom input panel.

They type:

```text
print("hello")
```

The panel might look like:

```text
┌─────────────────────────────────────────────┐
│ print("hello")                              │
└─────────────────────────────────────────────┘
```

They press Ctrl+Enter.

`riff` writes:

```text
print("hello")\n
```

(or the appropriate configured submission format) to the target process's stdin.

The submitted input is then committed into the terminal's normal history, e.g.:

```text
>>> print("hello")
hello
```

or whatever the target itself produces.

The bottom panel becomes empty and ready for the next input.

---

## 6. The panel is a real editor, but a tiny one

The panel needs enough editing behavior to be useful, but this is **not intended to become a general-purpose text editor or TUI toolkit**.

Minimum likely requirements:

- printable character input;
- Backspace;
- Delete if practical;
- left/right cursor movement;
- Home/End;
- Up/Down for multi-line input if multi-line mode is supported;
- Ctrl+Enter = submit;
- Ctrl+C / Ctrl+D / Escape semantics need explicit research/design;
- terminal resize;
- Unicode text handling to a reasonable terminal-cell level.

Potentially:

- Ctrl+A / Ctrl+E;
- Ctrl+W;
- word movement;
- history;
- paste;
- bracketed paste handling.

These should be treated as scope decisions, not assumptions.

---

## 7. Single-line vs multi-line input

The intended UX may eventually support a panel taller than one line.

For example:

```text
┌─────────────────────────────────────────────┐
│ for i in range(10):                         │
│     print(i)                                │
│                                             │
│                                             │
└─────────────────────────────────────────────┘
```

Ctrl+Enter submits the complete buffer.

The initial implementation may choose a single-line panel to prove the terminal mechanics first.

The architecture should not make multi-line input impossible.

The panel's height should be dynamic:

```text
one line → 3 lines → 10 lines → one line
```

The live region should grow/shrink without destroying terminal scrollback.

---

## 8. Critical terminal behavior

This is the most important technical research area.

We want to establish whether the implementation can use terminal scrolling regions / related ANSI control sequences to achieve:

```text
existing output
existing output
existing output
────────────────────
live region
live region
```

then commit new output:

```text
existing output
NEW OUTPUT
NEW OUTPUT
existing output
────────────────────
live region
live region
```

without repainting the entire live panel.

Ratatui's inline viewport and `insert_before` implementation are a useful reference point.

Research should identify:

- exact ANSI escape sequences involved;
- DECSTBM / scrolling-region behavior;
- cursor save/restore requirements;
- interaction with terminal scrolling;
- what happens when inserting lines above a live region;
- whether the terminal moves the live region naturally;
- how to preserve scrollback;
- how to resize the region;
- behavior when the live region grows/shrinks;
- behavior during terminal resize;
- behavior in common terminal emulators;
- behavior under tmux/Zellij if relevant.

The implementation should avoid becoming a terminal emulator.

---

## 9. Output handling

The child command's output is fundamentally ordinary terminal output.

Prefer:

```text
child stdout/stderr
        │
        ▼
   terminal output
```

rather than buffering the entire command output in application memory.

The target command may output:

- arbitrary bytes;
- ANSI color;
- cursor movement;
- carriage returns;
- progress indicators;
- wrapped lines;
- Unicode;
- stderr independently from stdout.

Research is needed to determine what can safely be passed through directly while `riff` owns a bottom live region.

A key design question:

> Can arbitrary terminal output be passed through while maintaining a bottom scrolling/live region, or must `riff` interpret some terminal control sequences?

Do not assume the answer.

---

## 10. Input routing

While `riff` is running:

```text
terminal stdin
      │
      ▼
    riff
   /    \
  /      \
editor   control
  │
  └──── Ctrl+Enter ────> child stdin
```

Normal printable input belongs to the panel.

Ctrl+Enter is intercepted and means "submit."

Other control keys need deliberate semantics.

The target command should still be able to receive appropriate signals/control characters where possible.

For example:

- Ctrl+C may need to interrupt the child rather than become panel text;
- Ctrl+D may need to behave as EOF;
- Ctrl+Z may require special handling or may be unsupported initially.

Research terminal raw mode and signal semantics carefully.

---

## 11. Child PTY / terminal ownership

A likely architecture:

1. `riff` opens the user's terminal.
2. `riff` puts its terminal input into raw/noncanonical mode as necessary.
3. `riff` creates a PTY pair.
4. `riff` forks/execs the target command attached to the PTY slave.
5. `riff` becomes the PTY master + terminal multiplexer.
6. `riff` propagates terminal resize information to the child PTY.
7. `riff` multiplexes terminal input and child PTY output.

On Unix-like systems, investigate:

- `forkpty` / `openpty`;
- `setsid`;
- controlling terminals;
- `ioctl(TIOCSWINSZ)`;
- `SIGWINCH`;
- process groups;
- signal forwarding;
- terminal foreground process groups;
- raw/canonical terminal modes.

Zig's standard library should be preferred where it gives sufficient primitives.

If a libc dependency is required for the Unix PTY layer, assess whether that is acceptable.

Do not optimize for Windows in the first design unless research shows it is nearly free.

---

## 12. Command-line shape

The exact CLI is intentionally open.

A likely first form:

```bash
riff COMMAND [ARGS...]
```

Examples:

```bash
riff python
riff bash
riff ssh host
riff some-custom-program --foo
```

The semantics are:

> run COMMAND interactively, while providing an inline bottom input panel.

Potential future options:

```text
--lines N
--height N
--no-panel
--debug
--raw-panel
```

Do not over-design the CLI yet.

---

## 13. What "minimal dependencies" means

Prefer:

- Zig standard library;
- direct ANSI/VT escape sequences;
- direct POSIX APIs where necessary;
- no full TUI framework;
- no Ratatui port;
- no large terminal abstraction;
- no third-party widget library;
- no general-purpose line-editing dependency unless research strongly justifies one.

A small amount of terminal-specific code is desirable.

The project should feel like:

```text
riff
 ├── main.zig
 ├── pty.zig
 ├── terminal.zig
 ├── inline_region.zig
 ├── editor.zig
 └── process.zig
```

rather than a framework.

This is illustrative only.

---

## 14. What the inline-region library should know

Ideally, the core inline-region layer knows only about:

### Terminal

- dimensions;
- cursor;
- scrolling region;
- raw output;
- cleanup.

### Live region

- current height;
- position at bottom;
- redraw;
- resize.

### Committed output

- insert bytes/lines before the live region.

It should **not** know about:

- widgets;
- menus;
- application state;
- command syntax;
- process management;
- business logic.

That separation is important.

---

## 15. Rendering strategy

Do not build a retained-mode TUI.

A useful model is:

```zig
region.beginFrame();
region.writeLine(...);
region.writeLine(...);
region.endFrame();
```

or even simpler:

```zig
region.render(bytes);
```

The region may maintain a tiny in-memory representation of only its own cells/lines.

If efficient differential rendering is easy, use it.

If not, repainting the **small live region only** is acceptable.

The explicit goal is to avoid repainting all historical output.

---

## 16. Commit semantics

The key operation is something like:

```zig
region.commit(bytes);
```

Meaning:

> These bytes are now permanent terminal output above the live region.

A useful conceptual state machine:

```text
             render/update
        ┌────────────────────┐
        │                    │
        ▼                    │
     LIVE PANEL              │
        │                    │
        │ commit             │
        ▼                    │
  TERMINAL HISTORY           │
        │                    │
        └────────────────────┘
```

After commit, the old live panel should no longer be managed by the live-region renderer.

This is the central "B" behavior discussed during exploration.

---

## 17. Submission behavior

When Ctrl+Enter is pressed:

1. capture the current editor buffer;
2. optionally commit/display the submitted text above the panel;
3. send the text plus newline to the child process;
4. clear the editor;
5. resize the live region to the new editor height;
6. continue forwarding child output.

Ordering needs research/testing.

The terminal should not visibly glitch between:

```text
typed text in live panel
```

and:

```text
typed text committed into scrollback
```

The exact ANSI sequence ordering matters.

---

## 18. Exit behavior

When the child exits:

1. stop accepting normal panel input;
2. remove/shrink the live region;
3. restore the terminal's previous scrolling/cursor state;
4. restore terminal input settings;
5. forward/return the child's exit status where appropriate;
6. ensure the shell gets a clean prompt.

If the user kills `riff` unexpectedly, cleanup should still happen as robustly as possible.

Consider signal handling and `defer`/cleanup paths.

---

## 19. Failure modes to research

The planning agent should explicitly investigate:

### Terminal resize

What happens when the terminal changes from:

```text
80x24 → 120x40
```

while the panel is active?

### Scrollback

Does inserting above the live region preserve real scrollback?

Can the user scroll back without destroying the live region?

### Alternate-screen child

What happens if the child itself enters the alternate screen?

Examples:

```bash
riff vim
riff less
riff top
riff fzf
```

This may be out of scope initially, but the behavior should be documented.

### ANSI output

What if the child sends cursor movement that conflicts with the live region?

### Carriage returns

What if the child does:

```text
Downloading 10%\rDownloading 20%\r...
```

### Large output

Ensure no unbounded buffering.

### Fast output

Ensure the PTY reader and terminal writer cannot deadlock.

### Child process termination

Handle normal exit, signals, and abrupt termination.

### Ctrl+C / Ctrl+D

Define what happens to the panel versus the child.

### Terminal multiplexer

Test:

```text
riff command
```

inside:

- tmux;
- Zellij;
- possibly screen.

### Terminal implementations

At least investigate:

- Ghostty;
- Kitty;
- WezTerm;
- iTerm2;
- xterm;
- GNOME Terminal / VTE;
- macOS Terminal if relevant.

Do not assume behavior is identical.

---

## 20. Security / correctness

The tool should not blindly interpret child output as its own control protocol.

If child output contains ANSI sequences, those are part of the child terminal stream.

Avoid introducing a second "magic escape sequence protocol" unless there is a compelling reason.

If a protocol is eventually needed for panel control, consider a separate FD or IPC channel rather than overloading stdout.

---

## 21. First milestone

Do not start with the full arbitrary-command experience.

A good proof-of-concept sequence is:

### POC 1

Hard-coded process:

```text
child = a tiny program that periodically prints output
```

and a fixed 1-line live panel.

Prove:

```text
output
output
[panel]
```

can coexist.

### POC 2

Make panel height dynamic.

```text
[1 line]
[2 lines]
[5 lines]
[1 line]
```

### POC 3

Implement `commit()`.

Prove:

```text
live panel
   ↓
committed history
   ↓
new live panel
```

works without repainting history.

### POC 4

Replace fake child with a real PTY child.

### POC 5

Add minimal editor and Ctrl+Enter.

### POC 6

Run real interactive commands such as:

```bash
python
bash
```

### POC 7

Stress resize, Unicode, ANSI output, large output, and terminal multiplexers.

---

## 22. Suggested research targets

The next planning/research agent should inspect actual implementations rather than relying on conceptual descriptions.

### Ratatui

Research:

- `Viewport::Inline`;
- `Terminal::insert_before`;
- `scrolling-regions` feature;
- inline viewport resize;
- actual ANSI emitted;
- tests for scrollback and resize.

Relevant project:

https://github.com/ratatui/ratatui

### eye-declare

Research:

- how it models committed output vs live tail;
- why it redraws the whole live frame;
- whether its terminal manipulation layer is reusable independently;
- whether its design reveals additional edge cases.

Relevant project:

https://github.com/atuinsh/eye-declare

### libvaxis

Use primarily as a reference for Zig/terminal mechanics, not as a dependency.

Relevant project:

https://github.com/rockorager/libvaxis

### Terminal standards / behavior

Research:

- DECSTBM / scrolling regions;
- ANSI save/restore cursor;
- insert/delete line operations;
- terminal primary vs alternate screen;
- DECSC/DECRC or modern cursor save/restore equivalents;
- SGR and ordinary output pass-through;
- terminal resize semantics.

### PTYs

Research:

- `openpty`;
- `forkpty`;
- controlling terminal setup;
- process groups;
- `TIOCSWINSZ`;
- `SIGWINCH`;
- signal forwarding.

---

## 23. Important design philosophy

The project should resist becoming a TUI framework.

The intended abstraction is closer to:

```text
"Give me a little live rectangle at the bottom of the real terminal,
and let me turn things above it into permanent terminal history."
```

than:

```text
"Give me a terminal UI framework."
```

The application should be free to render the panel however it wants.

The first application happens to be:

```text
a tiny line editor
```

but the underlying mechanism should also support:

```text
progress indicator
confirmation menu
command palette
status panel
multi-line prompt
interactive form
small transient widget
```

without the inline-region layer knowing what any of those are.

---

## 24. Desired end state

A successful minimal implementation should make this possible:

```bash
riff python
```

Then:

```text
Python 3.x.x ...

>>>                         ← child output

┌──────────────────────────────────────────────┐
│ print("hello world")                         │
└──────────────────────────────────────────────┘
```

Ctrl+Enter:

```text
Python 3.x.x ...

>>> print("hello world")
hello world

┌──────────────────────────────────────────────┐
│                                             │
└──────────────────────────────────────────────┘
```

Then another submission:

```text
>>> print(2 + 2)
4

┌──────────────────────────────────────────────┐
│ _                                           │
└──────────────────────────────────────────────┘
```

Meanwhile the user can continue typing while Python continues producing output.

The terminal's scrollback should contain the real conversation/history, rather than a giant application-owned framebuffer.

---

## 25. Questions the planning agent should answer

The planning/research agent should come back with concrete answers to these:

1. What is the smallest reliable set of terminal escape sequences needed for the live-region behavior?
2. Can Ratatui's scrolling-region technique be reproduced directly in a small Zig module?
3. What exact sequence does Ratatui use for `insert_before`?
4. How does it preserve scrollback?
5. How should growing/shrinking the live region work?
6. Is there a simpler approach that works well enough without DECSTBM?
7. What terminal emulators support the required behavior?
8. What breaks under tmux/Zellij?
9. Does a child PTY interfere with the primary-screen live region?
10. How should child ANSI cursor movement interact with `riff`'s own cursor?
11. Is it practical to pass arbitrary child terminal output through untouched?
12. What happens when the child enters the alternate screen?
13. What minimal PTY implementation is needed in Zig?
14. Which parts require libc on Linux/macOS?
15. How should Ctrl+C/Ctrl+D/Ctrl+Z behave?
16. What is the minimum viable line editor?
17. Can the live panel be differentially rendered without a TUI framework?
18. What cleanup is necessary on abnormal exit?
19. What tests can deterministically validate the terminal protocol?
20. What should be explicitly out of scope for v1?

---

## 26. Non-goals for v1

Unless research shows they are essentially free:

- full-screen TUI framework;
- general widget system;
- declarative UI;
- arbitrary terminal emulator implementation;
- Windows support;
- mouse interaction;
- sophisticated text editing;
- persistent input history;
- syntax highlighting;
- arbitrary nested live regions;
- multiple simultaneous panels;
- remote terminal protocols.

The primary objective is to prove:

> **one arbitrary child process + one small live input panel + real terminal scrollback + Ctrl+Enter submission.**

---

## 27. Success criterion

The implementation is successful if a user can run:

```bash
riff python
```

or another ordinary interactive CLI and experience the following without the application feeling like it has taken over the terminal:

- command output streams normally;
- terminal scrollback remains real and useful;
- a small bottom panel remains available for input;
- the panel can change height;
- Ctrl+Enter submits input to the child;
- submitted input becomes part of normal terminal history;
- the child continues running normally;
- no full-screen alternate-screen TUI is required;
- no large TUI framework is required;
- terminal repainting is limited to the live region where possible.

The implementation should be small enough that a developer can understand the entire terminal-management layer rather than treating it as framework magic.

