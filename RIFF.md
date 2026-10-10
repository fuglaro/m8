`m8 riff cmd arg…` runs a command with stdout flowing into real terminal scrollback, the last stderr line as a status line, and a small bottom editor that writes to the command's stdin.

**Invariant: only the child writes to the flow area.** riff never prints into it — no echo, no stderr, no messages. riff writes only to the live region and to terminal modes.

## 1. Layout

```
rows 1 .. H-L        flow area: child stdout, ordinary scrollback, never repainted
row  H-L+1           status line: last stderr line, reverse video, full width
rows H-L+2 .. H      editor: staging buffer for the next send (E rows)
```

- H × W terminal, 1-based. Live region = status line + editor = L rows, pinned to the bottom.
- E defaults to `min(5, floor(H/4))`; L = E + 1.
- If H < L + 2: hide the editor, keep the status line; if H < 3: hide both.
- Only the status line fills to the right edge. Editor rows end with `CSI K`, never trailing spaces.
- Start: if the cursor is mid-line emit CR LF, then claim L rows with LF, set region `1..H-L`. MUST NOT clear the screen.
# Riff: minimal command runner with continuous stdin writer

m8 outputs compressed status lines to stderr when it is not connected to a tty.
  - 💭 thinking about the things…
  - 📲edit(path=hhgf,old_st…
The editing area does not fill to the right - to allow clean copy. No area fills to the right except the status line.

[bottom region buffer]
(send)
  |
stdin
  |
  V
[cmd]--stdout->[top region scrollback]
     `-stderr->[riff status line]

```
top region is direct stdout from cmd
and is the real normal terminal scrollback
so not part of any conventional full-screen TUI.
▀▀ status line: last cmd stderr line truncat... ▀▀
▌bottom region is the only live region
▌which is actively managed.
▌it comprises of a staging buffer for
▌editing the next stdin run.
▌
```
* Status line is bg on fg colour. 


## 2. Child stdout passthrough

Bytes are forwarded unmodified inside region `1..H-L`, except:

| Child emits | riff does | Why |
|---|---|---|
| Text, UTF-8, SGR colour, OSC (titles, hyperlinks) | forward | no cursor effect beyond printing |
| CR, BS, TAB, LF, wrapped lines, `\r` progress | forward | LF/autowrap at the region bottom scroll rows into scrollback |
| CUU/CUD/CUF/CUB, EL, CHA | forward | CUU stops at row 1, CUD at the region bottom |
| CUP / VPA / HVP, `CSI J`, `CSI 2J` | forward, then repaint live region | can overwrite or erase it |
| `CSI ? … h/l` (any private mode), `CSI > … u` / `CSI < u` / `CSI = … u` | **drop** | would change riff's cursor, mouse, paste, keyboard or screen modes |
| DECSTBM `CSI … r`, `ESC c`, `CSI ! p`, `CSI 3J` | **drop** | destroy riff's region or the user's scrollback |
| `ESC 7`/`ESC 8`, `CSI s`/`CSI u` | forward | shares riff's save slot; rare on a pipe — see §9 |

stdout is a pipe (§6), so programs see "not a tty" and seldom emit anything in the last four rows.

## 3. Escape sequence budget (riff's own output)

Allowed: CR, LF, `CSI r;c H`, `CSI K`, `CSI J` (only from the live region's top or the child cursor), SGR ending in `CSI 0 m`, `CSI t;b r` / `CSI r` (homes the cursor), `ESC 7`/`ESC 8`, `CSI ?25 l/h`, `CSI ?2026 h/l` around every update, `CSI 6n`, `CSI ?2004 h/l`, mouse modes (§8), keyboard protocol (§7).

Forbidden:
- `CSI n S` (SU) to scroll up: xterm.js and Windows Terminal delete the lines instead of saving them.
- `CSI n M` / `CSI n L` in the flow area: tmux loses lines.
- Scrolling up any region whose top is not row 1: tmux writes it into history out of order.
- `CSI 2J`, `CSI 3J`; moving the cursor to rows already in scrollback.

## 4. Operations

**4.1 Flow** — child stdout is written straight to the terminal (after §2) with region `1..H-L` set. Never buffered beyond one read chunk.

**4.2 Live region render** — keep previous rows; rewrite only changed rows with `CUP row;1` + content + `CSI K`, inside `CSI ?2026 h … l`, cursor hidden while drawing, wrapped in `ESC 7`/`ESC 8`. Only at a scanner boundary (§5).

**4.3 Status line** — read the stderr pipe; keep only the current last line (text after the last LF; `\r` resets it). Strip control sequences, truncate to W−1 display cells with `…`, draw `CSI 7 m` + text + spaces to W cells + `CSI 0 m`. Emoji (💭 📲) are 2 cells. Redraw on change, ≤ 30 Hz.

**4.4 Child cursor query** (used by 4.5 and 4.7) — stop reading stdout, wait for a scanner boundary, send `CSI 6n`, read `CSI row;col R` from stdin, resume. Timeout 100 ms → assume the region's bottom row. The child has no terminal, so every CPR reply is riff's.

**4.5 Grow by k** (drag or Ctrl-↑) — query the child cursor row r (4.4). Inside `?2026`:
1. If r ≤ H−L−k: erase the k rows above the status line, set region `1..H-L-k`.
2. Else: CUP to row H−L, emit k LF (top k rows go to scrollback), set region `1..H-L-k`, r −= k.
3. Redraw the live region, CUP back to (r, col).

**4.6 Shrink by k** (drag or Ctrl-↓) — erase the top k live rows, set region `1..H-L+k`, redraw. The freed rows stay blank until output fills them.

**4.7 Terminal resize** (MUST — without it the live region smears into scrollback; reproduced in tmux):
1. SIGWINCH → self-pipe → event loop. Re-read `TIOCGWINSZ`; coalesce ~50 ms.
2. Query the child cursor (4.4).
3. Inside `?2026`: CUP to the child cursor, `CSI J` (removes the stale live region wherever reflow put it).
4. If r > H−L: CUP H;1, emit the excess as LF with no region set, adjust r.
5. Clamp E (§1), set region `1..H-L`, full redraw, CUP back to the child cursor.

**4.8 Teardown** — `CSI r`, erase the live region, `CSI 0 m`, `CSI ?25 h`, `CSI ?2004 l`, pop keyboard protocol, mouse off, restore termios, cursor on a fresh line under the last output. MUST run on exit, SIGINT/SIGTERM/SIGHUP and panic.

## 5. Scanner

~150 lines, not an emulator. Tracks escape state (ground / ESC / CSI / OSC / DCS-type strings) and UTF-8 continuation across reads. riff MUST inject its own bytes only at ground state with no partial UTF-8. Applies §2.

## 6. Process model

| fd | Child gets | Why |
|---|---|---|
| stdin | pipe | riff writes sent buffers; close = EOF |
| stdout | pipe | no PTY code at all |
| stderr | pipe | status line; m8 detects non-tty and emits compressed status |

- Spawn: `pipe2(O_CLOEXEC)` ×3 → `fork` → child: `setsid`, `dup2`, `execve`. Parent: close child ends, poll {stdin, stdout pipe, stderr pipe, signal pipe}, read until EOF, `wait4`.
- `setsid` MUST be used: a child opening `/dev/tty` gets ENXIO instead of fighting riff for the terminal (sudo, ssh, git prompts).
- Env: MUST set `COLUMNS=W` at spawn. SHOULD set `PYTHONUNBUFFERED=1`. MAY set `CLICOLOR_FORCE=1` / `FORCE_COLOR=1` behind a flag.
- Keystrokes never reach the child; only sent buffers do.

**Long-lived or per send** — one code path:
- `riff cmd …` — long-lived; each send writes buffer + LF. Ctrl-D on an empty editor closes stdin.
- `riff -e cmd …` — per send: spawn, write buffer, close stdin, stream, wait. Sends during a run are queued.
- `riff python` needs `python -i -u` long-lived (plain `python` on a pipe waits for EOF); `-e` runs each buffer as a script.

**Pausing**
- Ctrl-C → `kill(-pgid, SIGINT)`. In `-e` mode it ends the run.

**Platform**
- Linux: no libc. All of the above via `std.os.linux` syscalls; termios via `TCGETS`/`TCSETS`. Read `$SHELL`, not `getpwnam`; ship width tables, not `wcwidth`.
- macOS: libSystem (Zig links it anyway): `pipe`, `fork`, `setsid`, `execve`, `tcgetattr`/`tcsetattr`, `waitpid`, `sigaction`. MUST use `select`, not `poll`/kqueue, for the tty fd.

Do we really have to use libSystem? Is there no zig stdlib for this?

## 7. Editor

- Multi-line staging buffer; Enter inserts a newline. Scrolls vertically when taller than E rows.
- Send: **Alt+Enter** (`ESC CR`, works everywhere); **Shift+Enter, Ctrl+Enter** where the terminal reports them:
  - Push kitty keyboard flags `CSI > 1 u`; fallback xterm `modifyOtherKeys` `CSI > 4;2 m`. Pop at exit (`CSI < u`, `CSI > 4 m`).
  - Once pushed, Esc, Ctrl and Alt combinations also arrive as `CSI … u` / `CSI 27;…~`: the decoder MUST handle both encodings for every key, not just Enter.
  - Without either protocol, Shift/Ctrl+Enter look like Enter; Alt+Enter still works.
- After send: buffer cleared.
- Keys: printable UTF-8, Backspace, Delete, arrows, Home/End, Ctrl-A/E/U/K/W, history ↑/↓ at buffer edges, Ctrl-C, Ctrl-D, PgUp/PgDn, Ctrl-↑/↓ resize, pause key.
- Bracketed paste `CSI ?2004 h`; pasted text inserted literally, newlines kept.
- Hardware cursor shown in the editor, column = display width.
- Out of scope: undo, selection, completion, syntax.

## 8. Mouse — two-state toggle

No terminal reports clicks without also capturing the wheel, and riff cannot hand an event back. riff switches reporting at moments it can observe. Researched in emulator source (kitty, Alacritty, Ghostty, xterm.js, WezTerm, VTE, Windows Terminal, xterm) and tmux 3.4; not yet run with a real wheel.

| State | Mouse modes | Wheel / drag in flow area | Wheel in editor | Drag on status line | Selection |
|---|---|---|---|---|---|
| A: captured | `?1002 h ?1006 h` | reaches riff | scrolls buffer | resizes (4.5/4.6) | Shift/Option-drag |
| B: native | off | terminal scrollback / selection | terminal scrollback | selects text | native |

Transitions (mode bytes written at a scanner boundary):
- Start in B.
- Any keypress → A. Terminals checked jump the view to the bottom on a keypress (kitty, Alacritty, Ghostty, xterm.js, WezTerm, VTE, Windows Terminal), so reporting returns with the live screen in view. xterm jumps on output instead (`scrollTtyOutput`, default on), which the editor redraw provides. iTerm2: unverified.
- Send → B. The type → send → scroll cycle loses nothing.
- In A, wheel or button press in the flow area → B. That one event is swallowed.
- MUST NOT re-enable on a timer: if still scrolled back, Alacritty drops reports over history rows and Ghostty reports on-screen rows.

Inside tmux (`$TMUX` set): stay in A; forward flow-area wheel ticks with `tmux copy-mode -e` + `tmux send-keys -X -N <n> scroll-up` / `scroll-down`. Nothing lost. Commands tested; real wheel not yet.

Cost outside tmux: scrolling history while composing swallows the first tick; selecting then needs a second drag or Shift-drag.

