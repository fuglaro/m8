# CONFIRM_LATER


## pagey

`.m8-st8/pagey.md`, the pages-flavoured alternative to `cody2`. It encodes
clean — four tools for 2243B of schema against cody2's two for 3768B — but its
tools name `m8 call munge read|write|scan`, which does not exist yet, so it can
talk and not act.

* Same `:brain:` as cody2 on purpose, so a comparison between them is only
  about the tools.
* `BYTE_CAP 16000` sits on the definition header rather than on the bare offer
  line where IDEAS sketched it. `agent.project` reads a blockless 🧰 for its
  name alone, so an env var on an offer is silently dropped.
* Tool wording is IDEAS' wording, near verbatim — it is the thing under test.
  Only the 🧭 is mine, and it spends its three bullets on the one habit pages
  are meant to buy: answer an ambiguous match with `pages`, not with more
  `old_string`.
* `list` and `read` are one command by design, as IDEAS has them.

Not built: `munge` itself. Order: `read`/`list` first, since pages have to
exist before `scan` can answer in them, then `write`, then `scan` with the
bundled engine. Sizing the engine from the spec — parser 250, compile 150, VM
150, class bitsets 80, literal prefilter 80, glob 120, scan driver 200 — lands
near 1100 lines with no dependencies. No captures is what buys that: an 8 byte
thread and no allocation in the match loop.

What opencode does, measured rather than recalled, since the ladder came from
there:

* The rung is `EscapeNormalizedReplacer`, sixth of nine, running an unescape
  of `\n \t \r \' \" \` \\ \$` over the search text. It exists to repair
  arguments a model over-escaped through JSON, which is a real problem sitting
  in the wrong layer — a matcher cannot tell transport escaping from an escape
  the source code means.
* It corrupts code that means it: `Some(b'\\n')` in Rust became `Some(b'` and a
  physical newline, and the repair attempt after it answered "No changes to
  apply".
* `BlockAnchorReplacer` anchors on first and last line with Levenshtein 0.65
  across the middle, and is reported accepting wrong search strings and writing
  duplicate closing branches. Their `replace()` never says which rung fired, so
  a syntax error later is the only signal the ladder guessed. 75% and a receipt
  is the gap.

So the rung stays, with a discriminator instead of a deletion: over-escaping is
a property of a whole argument, while a source escape is local. Apply it only
when `old_string` holds no real newline and does hold `\n` sequences. Mixed
means code, and the rung declines.

## munge read

`src/command/munge.zig` and `src/command/munge/read.zig`, registered in the
registry and in `commands.txt`, so `m8 call munge read` runs and the split set
builds `m8-call-munge-read`. Tests are in the file; the suite is green.
`write` and `scan` are not started.

Judgement calls:

* The trailer is a bracketed line written after the content, not a 🙋. IDEAS
  says a user message is appended, which means the tool speaks m8 and answers
  in records — a wiring decision, and it changes the 🧰 value to `read,m8`. Say
  the word and it moves.
* A leading word is a label, not an open start. "A leading non-digit character
  makes it start at 1" turns `pages="pages 3 to 4"` into 1-4, and the argument
  is called `pages`, so a model writes that. Leading punctuation still opens
  the start, and the trailing side is unchanged — `21+`, `21-` and `21 onwards`
  all mean the remainder, because a trailing word never means anything else.
* A value naming no page at all gives the whole file rather than a refusal.
  `all of it` is somebody saying "the file", and zero-failure should cover it.
* A listing joins each name onto the path it was asked about, so every line is
  something to hand straight back to `read`.
* Binary or over BYTE_CAP*100 gives a size and no page count, since counting
  pages means reading the file.
* `(2KB, 57 lines, 1-1 pages)` reads oddly for a single page, and is kept: it
  is the spelling in IDEAS and it matches what `pages` takes.

## munge write and scan

Both landed. `src/command/munge/write.zig`, `scan.zig` and `regex.zig`, all
registered, split set building, 256 tests green. `pagey` now runs: every tool
it names exists.

`write` — the ladder is exact substring, then indentation, then all
whitespace, then the unescaped spelling of the argument, then a line number
pasted on the front, then a quarter of a block once its ends hold. Whatever was
forgiven is in the receipt. Calls made along the way:

* Exact is a substring rather than a line window, so a fragment inside a line
  never has to be spelled as a whole one. Every rung below it is line-based,
  because that is what indentation and whitespace mean.
* A block rung that finds a cheaper explanation says the cheaper one. A block
  with `a+b` against `a + b` reports whitespace, not a differing line, because
  the whitespace rung matched first — which is the ladder working.
* The anchor test is eight non-whitespace characters, and the lines outside the
  anchors are held to the rungs above with no tolerance at all.

`scan` — the engine is `regex.zig`, 480 lines and no dependencies. Parse to an
AST, compile to bytecode, run a Pike VM; a whole-literal pattern skips the
machine entirely and a leading literal skips it to candidates. `(a+)+b` over
forty a's answers immediately, which is the point of not backtracking.

* Six ops, not five: `^ $ \b \B` are in the syntax, so there is an `assert`
  alongside byte, class, split, jmp and match. There is no way to spell an
  assertion in the other five.
* A capturing group parses and is then treated as a plain group. Nothing here
  can report a capture, and refusing `(a|b)c` would be worse than quietly
  meaning what it looks like.
* A line a page edge runs through is shown as the part of it on that page, with
  an ellipsis on the cut side.
* `**` never steps over a dotted segment, so a glob cannot reach into `.git`
  even though the walk would have skipped it anyway.

README has a section on `munge`, documenting its page-based file tools.

`scan` with no regex is the `:toolbox:glob` use case from IDEAS — the same
command, answering the smaller question. Files are named with the line a search
prints above its matches, and nothing under it, so one shape is learned once.

* The glob is optional too, and defaults to `**` — a pattern with nowhere named
  searches everything below here rather than being refused. Nothing about the
  tool is refusable now; `refuse` is gone from it.
* Positional args are unchanged: `regex` then `glob`, so a lone one is the
  pattern. Listing from a shell is `M8_ARG_GLOB='**' m8 call munge scan`.
* An empty `M8_ARG_*` counts as omitted, so a model that sends `"regex": ""`
  for a parameter it meant to leave out gets the glob listing rather than a
  pattern that matches every line.
* A binary file or one over the 16MB hold is named with its size alone — no
  line or page count, since pages are a thing text has. A search still skips
  both silently; only the listing mentions them.
* Empty answer is `[No files.]` rather than `[No matches.]`, since nothing was
  being matched.

## pagey follow-up

The framework contract is that definition-provided tool and shield environment
names normalize to `M8_ARG_*`, and merge with call parameters by space
concatenation. Read/scan now use `M8_ARG_PAGE_LINES`, `M8_ARG_PAGE_BYTES`, and
`M8_ARG_BYTE_CAP`; directory and scan-result pagination remain to be completed.


 🧠=/slxjebjqtg

## COMMAND ARGS HONE

Built as settled in IDEAS. Suite green; `zig build` and `zig build split` both
build, and the two answer alike on `@x hi`, `cat @x`, `top @x`, an unknown
command and `@-`. Driven end to end against `inbuilt/echo` and `you-are`:
agent chat, main attached then detached, fork, one-shot, reset, model turns
landing in `@/=/`, the guard, `save`, `top`, `decode FORMAT PROVIDER`, the
`cat | send | tag` pipeline, and a model piped after a chat taking it over.
The scratch rule was checked on the real sandbox: a mob's and the top
`.tmpdir/` are writable under `no-edit-m8-st8`, and a chat pointer and an agent
file beside them are not.

New: `src/address.zig` (an `@`, the walk and its guard, read/tag/reset),
`src/prompt.zig` (`m8 @`), `tag`, `save`, `top`, and `ref` (the 🧠 a document
ends on, so `m8 @x hi | m8 ref | m8 tag @y` points rather than copies).
`session.zig` is the chat namespace now; `assembly.zig` no longer reads the
disk. Gone: `--`, `+CHAT`, `^SKILL`, the message/run split (`Takes` is
`stdin | nothing`), `send PROVIDER`.

Judgement calls:

* `m8 @x` with nothing typed or piped says "say something after the address,
  or pipe it in" and exits 1. That is the seat riff takes later.
  JVL:
* `top` takes `@SKILL`, matching `cat @X`, where IDEAS wrote `m8 top [skill]`.
  JVL:
* `m8 @:` (one-shot on main) keeps the turn in the attached chat's `=/`, or
  beside its parent when main is detached, and moves nothing.
* A reset deletes the pointer from the nearest config dir only. A chat of the
  same name further out (XDG) then shows through, the way every lookup merges
  nearest first.
  JVL:
* `tag` handed a lone 🧠 naming an agent or a model points at it without
  checking the agent exists; everything else it writes is settled first.
* `save` refuses a turn, a model, a pointer, a suffix, and any name under an
  agent (it would be a chat), and answers with the saved 🧠.
* `cat @x:` / `cat @x-` and `tag @x-` are refused rather than ignored.
* The unknown-command message is just "'x' is not a command. See m8 --help."
  — `m8 -- hi` and `m8 +x hi` land there.

Migrated this repo's `.m8-st8` by plain `mv` (nothing staged): agents into
`@/`, `=/` into `@/=/` (old `=/x` turn names stay valid there, and turns
naming `mathy` find `@/mathy.md`), `+/X.md` into `@/X/+.md`, `+/+.md` into
`@/+.md`, `.tmp-dir` into `@/.tmpdir`. `.gitignore` is `+.md`, `=/`,
`.tmpdir/`, `models/`. `+/split-probe.md` became `@/split-probe/+.md`, a
pointer with no agent — delete at will.

Not touched: `~/.config/m8-st8/+` and `=` (old layout, now inert — move under
`@/` the same way if they matter), `docs/chats/` transcripts, and the IDEAS
entry itself, which is now built.
