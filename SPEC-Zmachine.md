> **SUPERSEDED — safe to delete once the two marks below are cleared.**
>
> This was the working draft. It is built, and every section that
> describes behaviour now lives with the code it describes:
> `src/zmachine/README.md` for what spans files, and each file's own
> header for the rest. Nothing here is authoritative any more, and
> where this document and the code disagree, the code is right.
>
> Two sections have nowhere to go yet:
>
> * **§8.3, the companion build repository.** Obsolete rather than
>   unhomed: Microsoft's Zork repositories ship the compiled `.z3`
>   files alongside the MIT source, so there is nothing left to
>   build and no ZILF dependency to justify. Delete it.
> * **§11, future work.** Procedural generation, agent-as-user and
>   a Glulx sibling are still live ideas and are not documentation
>   of anything that exists. `IDEAS.md` is their home — moving them
>   is yours to do, since that file is yours.
>
> Everything else is migrated. Deleting this file loses nothing.

# Z-machine Provider Specification

**Status:** Draft for implementation
**Target:** `m8` agent harness, inbuilt provider
**Language:** Zig
**Licence:** MIT (clean-room implementation; no GPL code linked or vendored)

---

## 1. Concept

A Z-machine interpreter implemented as a **model provider**, not as a game
program. It exposes the same interface as any other inbuilt model (cf. the
existing ELIZA provider). It has no weights and no ML component: it is a
deterministic virtual machine wearing a model's interface.

The consequence that shapes everything else: **model APIs are stateless**. The
caller sends the full message list on every call. Therefore the interpreter
persists nothing between calls and reconstructs the entire game state by
replaying the ledger from a seed. This is not an optimisation or a design
preference — it falls out of implementing the interface correctly.

There is no VM state serialisation. No Quetzal. No save files. The ledger is
the only durable artifact.

Two usage modes, both out of scope for this document but shaping the design:

- A human user chats with the provider directly and plays the game.
- An agent under test talks to the provider through a message-passing tool,
  i.e. agent-to-agent. The harness may prime the first turn or may let the
  tested agent send it.

---

## 2. Scope

### 2.1 Z-machine versions

Support **V1, V2, V3, V4, V5, V8**.

Explicitly out of scope:

- **V6** — graphics and windowing VM. Four Infocom titles only (Zork Zero,
  Shogun, Journey, Arthur), all of which depend on visuals for puzzle
  information and are poor agent environments. Largest single effort saving.
- **V7** — defined but effectively unused in the wild.

Suggested build order: V3 first (complete Infocom classic catalogue, free
scoring signal, ~90 opcodes), then V5+V8 together (modern Inform-compiled
`.z5`/`.z8`, adds the `EXT` opcode table), then V4 (mostly a subset of V5 work
by that point), then V1/V2 (minor alphabet-table quirks).

### 2.2 Not in scope

- Glulx (a possible future sibling provider; entirely separate VM)
- Twine and other non-VM formats
- Quetzal save format
- Context window limits — the harness enforces those if wanted
- Error surface conventions — already solved at the harness layer
- Story file bundling (see §9)

---

## 3. Headless text profile

The interpreter runs headless and emits UTF-8 text. Header fields are written
by the interpreter before execution begins, and **re-applied on `restart`** —
hang header initialisation off the same code path as the restart interception
so a post-restart game does not see stale capabilities.

### 3.1 Flags 1 (byte 0x01), V1–V3

Mostly game-set; few interpreter knobs.

| Bit | Meaning | Value |
|-----|---------|-------|
| 1 | Status line type | **read only** — indicates score-game vs time-game |
| 2 | Two-disc story | read only, ignore |
| 3 | Tandy / censorship | **0** |
| 4 | Status line NOT available | **0** (available; `show_status` is a no-op) |
| 5 | Screen-splitting available | **0** (deny; kills upper-window use) |
| 6 | Variable-pitch is default | **0** (we are monospace) |

### 3.2 Flags 1 (byte 0x01), V4+

| Bit | Meaning | Value |
|-----|---------|-------|
| 0 | Colours available | **0** |
| 1 | Pictures available | **0** |
| 2 | Boldface available | **0** |
| 3 | Italic available | **0** |
| 4 | Fixed-space font available | **1** (we are monospace; ASCII art renders correctly) |
| 5 | Sound effects available | **0** |
| 7 | Timed input available | **0** — removes the entire timeout event class |

### 3.3 Flags 2 (word 0x10; bits 0–7 at 0x10, bit 8 at 0x11)

Bidirectional. The game sets what it wants; the interpreter clears what it
cannot provide.

| Bit | Meaning | Value |
|-----|---------|-------|
| 0 | Transcripting | **allow** (accept, discard output — the ledger already is the transcript) |
| 1 | Forced fixed-pitch | **allow** (no-op for us) |
| 2 | Status redraw request | V6-only; not applicable |
| 3 | Pictures | **clear** |
| 4 | UNDO | **clear** (see §3.5) |
| 5 | Mouse | **clear** |
| 6 | Colours | **clear** |
| 7 | Sound | **clear** |
| 8 | Menus | **clear** |

### 3.4 Other pinned header fields

| Offset | Field | Value |
|--------|-------|-------|
| 0x1E | Interpreter number | **6** (IBM PC) — least likely to trigger odd per-interpreter code paths |
| 0x1F | Interpreter version | **'F'** (or `1` in V1–3) |
| 0x20 | Screen height (lines) | **255** = infinite; suppresses MORE prompts |
| 0x21 | Screen width (chars) | **80** |
| 0x22 | Screen width (units, V5) | **80** |
| 0x24 | Screen height (units, V5) | **255** |
| 0x26 | Font width | **1** |
| 0x27 | Font height | **1** |
| 0x2C | Default background colour | **2** |
| 0x2D | Default foreground colour | **9** |
| 0x32 | Standard revision major | **1** |
| 0x33 | Standard revision minor | **0** |
| 0x36 | Header extension table ptr | read-only; do not choke if present (holds Unicode translation table) |

Notes:

- Height in *units* is 255 rather than the more common 0-means-infinite
  convention, because font height is pinned to 1 unit, making units and lines
  the same scale and keeping 0x20 and 0x24 self-consistent. Do not change font
  height without revisiting this.
- Width stays 80, **not** infinite. Infinite width tells games not to wrap,
  producing unstable transcripts and broken ASCII art. Fixed 80 gives
  diffable output.
- Declaring standard 1.0 rather than 1.1 avoids `set_true_colour` and the 1.1
  header-extension additions. It does **not** exempt Unicode handling —
  `print_unicode` / `check_unicode` and the Unicode translation table are 1.0
  features. Verify exact 1.0/1.1 boundaries against the Standards Document
  §11 before finalising.
- A small number of games do arithmetic on the height value; 255 can produce
  odd results (e.g. 200 blank lines). Per-game issue, not architectural.

### 3.5 Save, restore and undo

Flags 2 bit 4 (UNDO) is cleared. All four persistence opcodes fail. The
failure mechanism differs by opcode and by Z-machine version — get these right,
because games branch on the specific value returned.

| Opcode | Versions | Type | Behaviour |
|--------|----------|------|-----------|
| `save` | V1–3 | **branch** | branch-on-false |
| `save` | V4+ | **store** | store **0** |
| `restore` | V1–3 | **branch** | branch-on-false |
| `restore` | V4+ | **store** | store **0** |
| `save_undo` | V5+ | store | store **-1** |
| `restore_undo` | V5+ | store | store **0** |

Notes:

- `save` and `restore` have **no "unsupported" return value** — unlike
  `save_undo`, whose -1 specifically means "this interpreter cannot do undo".
  For save/restore, 0 (or a false branch) simply means the attempt failed,
  which is what we want.
- A *successful* restore conventionally stores **2**, so 0 is unambiguously
  failure and will not be misread as success.
- `save_undo` must return **-1**, not 0. Games branch differently on
  "unsupported" versus "attempt failed"; the former produces a clean "UNDO is
  not available" message, the latter can produce confused retry behaviour.
- **Never prompt for a filename.** A real interpreter asks "Enter a file
  name." — that is a `read` which is not a game command, and it would land in
  the ledger as a turn, confusing both the agent and transcript diffing. Fail
  before the prompt.
- The failure is self-recording: the game prints its own message ("Save
  failed.", "UNDO is not available.") into the response, so the attempt is
  already visible in the transcript. Nothing further is needed.

#### Why this is safe

Failure is a normal, spec-defined condition (disk full, write-protected
media, bad filename), so every game has a handling path. The standard response
is a brief message such as "Save failed." followed by a return to the prompt.
Play continues.

- No Infocom game gates progress on saving. There is no puzzle requiring a
  save/restore cycle, and the same holds across essentially the whole
  mainstream IF corpus — save is player convenience, not mechanic.
- The death prompt still functions. V3 games offer "RESTART, RESTORE or
  QUIT?"; V5-era games sometimes add UNDO. With restore and undo failing,
  RESTART remains available and is implemented. The agent always has a
  recovery path, and it is the expensive one.
- Rare exception class: a small number of avant-garde works treat
  save/restore/undo diegetically. Not Infocom, not common in IFComp. Such a
  game is a per-game exclusion, not an architectural problem.

#### Rationale for disabling undo specifically

Beyond the statelessness constraint: undo makes death free, collapsing the
planning-under-irreversibility property that makes IF interesting as an agent
environment. Retry semantics belong at the harness layer, where they are
explicit, rather than in-band where the agent can invoke them unobserved.

### 3.6 Output streams

- **Stream 1** (screen) — the transcript.
- **Stream 2** (transcript file) — accept `output_stream 2` / `-2`, track the
  flag state so games can read it back, write nothing.
- **Stream 3** (memory table) — **must be implemented**. Games use it for real
  computation (measuring string widths, building buffers). Ignoring it
  corrupts game logic. Standard 1.1 refines its nesting and width semantics;
  worth reading even while declaring 1.0.
- **Stream 4** (command record) — stub.

### 3.7 Text styles

Accept `set_text_style` for bold / italic / reverse / fixed-pitch; discard the
styling, keep the characters. Most games will not ask, since Flags 1 denies
bold and italic availability.

---

## 4. Output rendering

### 4.1 Emit boundary

The game's output is not a stream in V4+: the game writes into an upper-window
grid with cursor positioning and may repaint the same cells several times
while processing one turn. A defined quiescent point is required.

**Emit when the VM reaches `read` (or `read_char`) and is about to block.**
Also emit on `quit` and on game-over, or the final turn's text is lost.

This makes intermediate repaints irrelevant: the emitted chunk is a pure
function of "VM ran until it wanted input", not of timing or repaint count.

No state is stored at this boundary. It is purely "when do I stop accumulating
and emit".

### 4.2 Status line

Every machine response includes the status line followed by the response text,
as one opaque rendered chunk. The ledger does not distinguish or hide how it
was produced.

**V3 and earlier:** synthesise from globals. The first three globals are
reserved — `G00` current room object, `G01` score (or hours), `G02` turns (or
minutes). Flags 1 bit 1 selects score-game vs time-game formatting. Globals
base address is at header word 0x0C. `show_status` becomes a no-op since the
line is regenerated from the same globals anyway. No buffering needed.

**V4+:** `show_status` does not exist; games draw their own line via
`split_window` / `set_window` / `set_cursor` / `print`. Maintain a small
character grid for the upper window and read it off at the emit boundary.
Implement `set_cursor`, `erase_window`, `erase_line`. No scrolling, no styles,
no colour.

**A shrinking window gives its rows back.** `split_window` to a smaller height,
and `erase_window -1`, hand the departing rows to the scroll rather than
dropping them: on a real screen those rows stay where they are and were read
there, and the transcript is the scroll. They go ahead of whatever the lower
window already holds for that turn, since that is where the eye finds them.
Leading and trailing blank rows are dropped and interior ones kept; an all-blank
block is silent, so a status line shrinking to nothing says nothing.

Without this the plain reading of §4.1 loses real content. Curses opens by
painting its epigraph into a twelve-row window and then shrinking to one, and
the emit boundary arrives afterwards — so the grid at that moment holds nothing
of it.

Two formatting decisions to make once and never revisit, since they affect
every transcript diff:

- **Trim trailing spaces** on upper-window rows (recommended: yes — padded
  rows make diffs noisy).
- **Empty upper window** emits nothing rather than a blank line (recommended).
  Games do shrink the window to zero height mid-play.

### 4.3 Scoring

Scoring is out of scope but if we later consider it, we can consider the following:

1. Define an external task reward at the harness layer (arguably better for
   agent evaluation anyway — built-in score is sparse and idiosyncratic).
2. Parse the status line text the game prints.
3. Parse the ledger.

### 4.4 What the emitted chunk is, as m8

The chunk goes out as the content of one 🤖 record, and m8's record grammar
takes it verbatim: content is a block of quoted lines, exactly one space after
the quote is stripped, and what is under the quote is bytes.

Three consequences, all of them in the interpreter's favour:

- **No escaping, ever.** A line of game text beginning with `>` or `#` — a
  prompt echo, a box-drawn heading — is written under the quote like any other
  and reads back identically. There is no character the VM must avoid and no
  transformation to undo. Do not invent one.
- **Blank lines survive.** A fully blank line closes a content block, so an
  empty line of game output is written as a bare quote with no trailing space
  (`doc.ContentWriter` in `src/m8/doc.zig` already does this). Paragraph breaks
  in game text are therefore exact, and no trailing whitespace is left for an
  editor to strip.
- **ASCII art survives**, which is what pins width to 80 in §3.4 rather than
  leaving it to a renderer.

The interpreter emits UTF-8 text and nothing else. It never writes m8 records
of its own, never emits 📲, and never emits 🧰, 🔓, 🧠 or 📚 — a story file is
not something that should be able to change the agent that is playing it.

---

## 5. Determinism and the ledger

### 5.1 Non-determinism surface

With the headless profile applied, exactly three things can make two runs
diverge:

1. `random`
2. Line and character input
3. `save` / `restore` / `save_undo` / `restore_undo` / `restart`

That is six opcodes — `random`, `save`, `restore`, `save_undo`,
`restore_undo`, `restart` — plus `read` / `read_char`.

Three more are stateful or determinism-adjacent and must not be left to a
default implementation:

- `input_stream` — switching input to a command file is a second input channel
  and a second source of state at once. Accept the opcode, keep the flag
  readable, never leave stream 1.
- `verify` — compute the real checksum over the story file and branch
  honestly. Games do check, and a game that thinks it is corrupt behaves
  strangely rather than loudly.
- `piracy` — branch "genuine", always.

Everything else is pure.

### 5.2 Seed derivation

The seed comes from the **user's first message**, not from the harness. A
prompt like "Hi I want to play" is hashed to produce the starting seed.

- `seed_0 = first 8 bytes of BLAKE3(seed_string)`
- Hash the **user string only**, never the interpreter's own boot output.
  Otherwise revising the boot text silently changes every future run's world.
- Record hash algorithm and a **derivation version** integer in provenance.
  Breaking changes that invalidate old ledgers are acceptable; silent drift is
  not.

**The seed message is consumed, not played.** It derives the seed and is not
tokenised into the VM as a command. Turn 1 is: hash → seed → boot → run to
first `read` → emit. The first actual game command is turn 2.

**One user message, one input request.** The VM stops at every `read` and
`read_char` (§4.1), so a call consumes exactly one message and produces exactly
one emission. With the seed message consumed, user message *n* answers input
request *n−1* — and that pairing is what lets replay align without the ledger
recording any position. It is an invariant rather than an observation: anything
that consumed two messages in one turn, or none, would desynchronise every
later turn silently. A ledger carrying input the game never asked for is §5.7.

Do not echo the seed string back in the boot output. For story-file play it
carries no advantage, but for future procedurally-generated content the seed
determines the map. An agent that deduces the mechanism unaided is
demonstrating exactly the capability worth measuring.

### 5.3 `random` reseeding

The `random` opcode takes an argument: positive `n` returns 1..n; **`random 0`
tells the interpreter to reseed itself**, traditionally from the clock;
negative `-n` reseeds deterministically to `n`. Games do call `random 0`.

Never let this reach the system clock. Derive deterministically:

```
seed_n = BLAKE3(seed_0 ‖ le64(reseed_counter))
```

The reseed counter is monotonic and **must** be included — the ledger prefix
alone is insufficient, because two `random 0` calls within a single turn would
otherwise collide.

### 5.4 Persistence opcodes and restart

The provider is stateless by construction: it receives the full message list
on every call and reconstructs game state by replaying from the seed. It has
no durable store and no ability to seek within or truncate its own input.
Persistence opcodes are therefore not implementable at this layer.

**Disabled — fail:** `save`, `restore`, `save_undo`, `restore_undo`. See §3.5
for the exact per-version failure mechanism. The returned value matters,
because games branch on success versus failure.

**Enabled — `restart`.** This one is genuinely implementable, because it
requires no external state: reset dynamic memory from the story file,
**re-apply the header profile** (§3), and resume execution. It is fully
deterministic under replay and does not threaten the invariant. Re-run header
initialisation on the same code path used at boot.

The provider records nothing. It has no durable store, and anything written
would be discarded before the next call. Where a record is wanted, it already
exists: the game's own output — a failure message, a restart banner — lands in
the response and therefore in the messages array.

#### Replay cost

The provider replays its entire input ledger on every call. This is inherent
to being stateless, not a consequence of any particular feature. A full Zork
playthrough is a few hundred turns and a V3 VM replays that in milliseconds,
so the cost is not a concern at expected scale. Running hot from exotic
scenarios is intended.

#### Harness-layer note (not provider behaviour)

Save, restore, undo and branching are all available to the **caller**, because
a ledger is a list and the chat API permits editing history and resending.
Truncating by one entry is undo; replaying to an index is restore; copying a
prefix forks a run. This also provides a testing lever — hand an agent a
doctored history and see whether it notices the transcript contradicts itself.

None of this is visible to the provider, which only ever sees the message list
it is given. It is recorded here so the capability is not mistakenly
implemented twice.

---

### 5.5 What the ledger must capture

Almost nothing, and that is the point.

The provider adds 🤖 text and 📲 calls to a ledger and has no other channel;
anything else it wanted to write down would have nowhere to go. It does not
need one. **Determinism is the requirement, not a record of how determinism
was reached.** A value replay re-derives is already recorded by the inputs that
derive it, and writing it down a second time creates a second source of truth
that can disagree with the first.

So the ledger captures this, in the boot block (§7) and nowhere else:

- Story file SHA-256 — of extracted story data, not the container, so
  Blorb-wrapped and bare copies of one game do not spuriously mismatch
- Header release number / serial / checksum
- Z-machine version emulated
- Interpreter **semantic** version: a hash over the VM's own sources, so a bug
  fix that legitimately changes replay output is detectable rather than silent
- Seed derivation version

The user's messages carry the rest by being what they are. Line input is the
raw bytes as received, **pre-tokenisation** — the VM tokenises, not the harness,
and it truncates dictionary words to 6 characters in V1–3 and 9 in V4+. A
terminating keypress is the symbol itself under §6.2, not a field beside the
string; §6.2 is the whole mechanism and there is no structured alternative.

Deliberately **not** recorded, because replay derives every one from the seed
and the messages:

- **`random 0` reseeds.** `seed_n` is a pure function of `seed_0` and a counter
  that advances identically on every replay. It is implied by what is already
  there. Recording it would be verbosity buying nothing.
- **Flags 2 mid-run writes**, and every other observable-environment value.
  They are pinned by §3, and §3 is where they are recorded. Changing one
  changes the interpreter's semantic version, which *is* in the boot block —
  so the invalidation is loud without a per-run inventory.
- **Anything else the VM did on the way.** The transcript is the record.

### 5.6 The invariant

**Ledger + story file + declared versions → byte-identical transcript.**

Make this a test that runs on every commit. If it holds, Quetzal is never
needed. If it silently stops holding, that must surface immediately rather
than after months of accumulated ledgers.

### 5.7 Input the game did not ask for

The pairing in §5.2 holds while the VM is running. Two things break it, both
from outside the VM, and both need a defined answer rather than a crash.

**After `quit`.** The VM is dead but the chat is not: the next call still
arrives with one more 🙋. Every call from then on replays to the same dead end
and answers with the same terminal notice, naming the turn the game ended on.
It is deterministic, it is honest, and it does not invent a hidden meta-channel
for restarting — a game that offers RESTART at its death prompt is still
running and is reached the ordinary way.

**Surplus input generally.** A doctored history (§5.4's testing lever), a
truncated one, or a ledger from a different story file all present as input the
game never asked for or output that cannot be reproduced. The provider does not
police the ledger it is handed — it replays what it can and answers with what
the VM says. Where replay cannot proceed at all, that is an error on stderr in
the harness's own terms, not a fabricated turn.

The provider never silently drops a message. Consuming input the VM did not ask
for is the one failure that would corrupt every later turn invisibly, which is
exactly what §5.6 exists to catch.

---

## 6. Input encoding

Everything is UTF-8 on the wire. Most input is ordinary text. The exception is
ZSCII codes that have no character meaning — input-only key signals occupying
the same numeric space as characters.

### 6.1 Symbol mapping

| ZSCII | Key | Symbol |
|-------|-----|--------|
| 129 | Cursor up | ↑ (U+2191) |
| 130 | Cursor down | ↓ (U+2193) |
| 131 | Cursor left | ← (U+2190) |
| 132 | Cursor right | → (U+2192) |
| 133–144 | F1–F12 | ①–⑫ (U+2460–U+246B) |
| 145–154 | Keypad 0–9 | ０–９ (U+FF10–U+FF19) |
| 27 | Escape | ⎋ (U+238B) |
| 13 | Return | ⏎ (U+23CE) |
| 8 | Delete | ⌫ (U+232B) |
| 252–254 | Mouse | not supported (mouse denied) |

Keypad digits must be distinct from both function keys and ordinary ASCII
digits — a game can distinguish "pressed 5" from "pressed keypad 5". Fullwidth
digits give that separation.

### 6.2 Disambiguation

Context decides, with no escaping mechanism:

- During `read_char`: a message consisting of **exactly** one mapped symbol is
  that keypress.
- During `read` (line input): the symbol is just a character in the line.
- Where V5's terminating-characters table makes a single keypress valid during
  line input: **exactly** the symbol alone is treated as the terminating
  keypress; anything else is treated as a line.

This rule is **not documented to the agent**. It is evident from the prompt
text in the same way it would be to a human player. Working it out is part of
the task.

### 6.3 Extended characters

ZSCII 155–251 are the extended set (accented Latin and similar), mapped via
the spec's default table or a game-supplied Unicode translation table (pointed
at from the header extension table at 0x36). Decode to Unicode and emit UTF-8.

For input, map or reject characters outside ZSCII. `check_unicode` may be
answered honestly and conservatively.

The extended character table may be included in the boot output (see §7).

---

## 7. Boot sequence

The provider answers the first call with **one message in three sections**.

One, not three, because m8 flattens a provider's response: `src/codec/m8.zig`
joins the content of every 🤖 record it reads with a newline, and
`src/converse.zig` appends the result to the ledger as a single 🤖. Three
records in, one record out. A structural boundary between harness output and VM
output is therefore not available at this layer, and inventing one would mean
changing how every provider is read to serve the one that wants it.

So the boundary is a delimiter after all: a line containing exactly `---`,
twice. **VM emission begins after the second one.** A diff tool splits on the
first two and ignores the rest, which is stable even though a game may later
print `---` itself.

**Section 1 — Provenance.** Story title, release / serial / SHA-256,
Z-machine version, interpreter semantic version, seed derivation version.
Human-legible:

```
ZORK I: The Great Underground Empire
Release 88 / Serial 840726 / sha256:4f2a…
Z-machine v3 · m8 Z-Machine <semantic> · seed derivation 1
```

There is no hidden channel; everything is agent-visible by construction. The
hash costs a few tokens. An agent that derails on a hex string in a header line
has failed something worth catching.

**Section 2 — Instructions.** Brief warmup: how input works, the keypress
symbols, what the status line is, the extended character table if included.
Deliberately brief. It does **not** explain §6.2's disambiguation rule; that is
evident from play in the way it would be to a human.

**Section 3 — VM output.** The game's own banner and first room description,
straight from the interpreter. The canonical start of Z-machine output.

Every later call answers with section 3 alone. The first two are in the ledger
already, written once, and a provider that re-sent them would be repeating
itself into its own context.

## 8. Story file resolution

### 8.1 Where story files are found

Story files are **data, not commands**, so they are not `core/` business.
`core/` holds what a lock means and what a provider is — the things a cloned
project must not be able to define — and it is read from the user's own config
alone. A story file decides which world is played, not what runs, and the
fallback below already reaches files a project brought with it. Putting it in
`core/` would buy no safety and would cost the ordinary config search.

So discovery uses m8's ordinary nearest-first search, `config.discover`:

```
./.m8-st8/models/Z-Machine/           and every .m8-st8 above it
$XDG_CONFIG_HOME/m8-st8/models/Z-Machine/   else ~/.config/m8-st8/models/Z-Machine/
```

A file placed there as `zork1.z3` is addressable as:

```
m8 @/inbuilt/Z-Machine/zork1
```

Nearest first means a project can carry the story its agents are tested
against, and a personal collection lives in the config directory and is reached
from anywhere. `models/` is the subpath rather than `stories/` because it is
the model's file: what the 🧠 names is what is found there.

The name is the file's stem, spelled the way the file is spelled, and the
extension is one of the recognised set (`.z1` … `.z8`, and Blorb containers
`.zblorb` / `.blb` / `.blorb` where supported — extract the story data before
hashing). No case folding and no searching: a model in m8 is named after the
file it is found in, and a file's name has a case. Folding it here would make
this the one place in m8 that did, and would let a name work on one machine and
fail on another. (A case-insensitive filesystem may be kinder on its own
account. That is the filesystem's business and not a promise.)

A name may hold a path, and it is taken relative to each `models/Z-Machine/` in
turn:

```
m8 @/inbuilt/Z-Machine/infocom/trinity
```

The name is confined to those directories. A story file elsewhere is named by
putting it there, or by a symlink, which is the ordinary way a file comes to be
somewhere in every other part of m8.

**Dispatch.** `inbuilt` serves its models from a table of exact names
(`src/command/providers.zig`), and a story file has no name m8 knows. Rather
than a second dispatch mechanism, one table entry advertises a family: a model
whose name ends in `...` matches on what precedes it, so `Z-Machine/...` is one
row on the page and serves every story file found. `m8 help providers inbuilt`
lists the row and the directories searched, and — since it can — what is
actually in them.

Compare with the existing ELIZA provider (`m8 @/inbuilt/eliza`) for the
invocation convention.

### 8.2 No bundled story files

The harness ships **no** story files. Rationale:

- Keeps the package clean for distro inclusion (Arch, Debian). Distro
  packagers dislike build-time network fetches and vendored game binaries.
  Precedent: `frotz` has been packaged for years without bundling games.
- Keeps the MIT licensing story simple — no third-party notices needed in the
  main repo.
- The value proposition is that the provider works with **any** story file the
  user supplies. Zork is a demo, not the product.

Document the acquisition path rather than automating it.

### 8.3 Companion build repository (separate, optional)

A parallel repository provides reproducible, provenance-documented builds of
the MIT-licensed Zork I–III story files. Microsoft released Zork I–III as open
source in 2025; the ZIL source is MIT, so compiled story files derive from
MIT-licensed source.

Structure:

- Zig build script fetches the ZIL source at a **pinned commit hash** — by
  reference, never vendored.
- Fetches and builds ZILF (**GPLv3**, C#/.NET) at build time. **Do not vendor
  ZILF** into an MIT tree. A GPL build-time tool does not affect the licensing
  of its output — same principle as GCC — but mixing the source trees creates
  an avoidable licensing mess.
- Compiles ZIL → `.z3`, emits a hash report, publishes binaries via GitHub
  releases (preferred over committing to history, since committed binaries are
  permanent).
- README records: ZIL source URL + commit, ZILF version, full build command,
  per-file SHA-256, Z-machine version, header release/serial, any flags needed
  to pin the serial, and the upstream MIT notice verbatim.

**Phrase the licensing claim precisely.** You are not granting an MIT licence
(you do not hold the copyright); you are stating that these artifacts derive
from MIT-licensed source and providing the reproduction recipe. MIT requires
carrying the upstream copyright notice with the distribution.

**Verify early: is ZILF's output byte-reproducible?** Compilers commonly stamp
build dates, and the Z-machine header's serial field is conventionally a build
date. If ZILF stamps the current date, hashes drift on every build and the
reproducibility claim needs the serial explicitly pinned. This determines
whether hashes can be baked in as constants at all. If it is not reproducible,
document the nondeterministic fields explicitly rather than dropping the
claim.

**Licence notices are not embedded in the story file binary.** Standard
practice is that the notice travels with the distribution, not inside the
artifact — nobody embeds GCC's licence in `a.out`. A `LICENSE`/`NOTICE` file
adjacent to the files satisfies MIT. Embedding a notice would also change the
hash relative to a clean build, defeating the reproducibility claim. The story
files additionally self-identify: Infocom games print their own copyright
banner at startup, and `VERSION` reports release/serial.

**Trademarks are not licensed**, but this is not a blocker. `@/inbuilt/Z-machine/zork1`
is nominative use — using a mark to accurately identify the thing it names,
which is permitted and is what emulator front-ends and package managers do
routinely. Do not name the project after a mark, use Infocom or Activision
logos, or imply endorsement.

Make it in a `scratch/zorks` if you make this. It's already git ignored and
we can pull it out after it we want.

---

## 9. Implementation notes

### 9.1 Version dispatch is pervasive

Opcode *semantics* shift by version, not merely availability. Build a
`version: u8` into the decode path from day one rather than retrofitting.
Known divergences:

- `save` / `restore` are **branch** instructions in V1–3, **store**
  instructions in V4+
- `not` becomes `call_1n` in V5
- Object entries: 9 bytes with 32 attributes in V1–3; 14 bytes with 48
  attributes in V4+
- Packed address multipliers: ×2 in V1–3, ×4 in V4–7, ×8 in V8. V6/V7 also use
  routine/string offset header fields that V8 does not — one more reason
  dropping them simplifies the code.
- Dictionary truncation: 6 characters in V1–3, 9 in V4+
- V5 adds the extended opcode set behind the `EXT` prefix (opcode 0xBE)

### 9.2 Text encoding is the grind

Pay careful attention to the text: three
Z-characters packed per word, three alphabet tables, abbreviation expansion
(V2+), ZSCII escape sequences for arbitrary characters. V1 and V2 have quirky
alphabet differences worth special-casing rather than generalising.

### 9.3 Testing

Build a transcript-diffing harness early. Published walkthroughs for Zork I
can be fed in as ledgers and diffed against a reference interpreter's output.
This turns "is my VM correct" into a regression test and exercises the replay
path as a side effect — the property the whole design rests on.

Test-case selection is left to the implementing session. Note that Zork I, II
and III are all V3 and share one code path. Beyond Zork is the natural V5 test
case and additionally exercises the arrow-key symbol mapping, since it uses
on-screen menus.

Zork test harness can't persist due to not pre-bundling zork but you
can add your own harnesses and test cases and validate with zork or anything you like.

### 9.4 Where the code lives

Two things, because they answer to different masters.

`src/zmachine/` is the VM, and knows nothing about m8. It loads a story file,
runs it, and hands back text — story, text, objects, dictionary, screen, cpu.
It is the part with a specification to be right against, and it is testable
without a ledger anywhere near it. Its sources are what the semantic version in
§5.5 hashes, which is only meaningful because the boundary is real.

`src/command/providers/zmachine.zig` is the provider, and knows nothing about
opcodes. It finds the story file (§8.1), derives the seed (§5.2), replays the
🙋 records through the VM (§5.2), and writes the answer as a 🤖 record (§4.4).
It sits beside `eliza.zig` and is the same shape: given a ledger, say the next
thing.

The seam is the whole design in miniature. The VM cannot reach the ledger, so
it cannot accidentally become stateful; the provider cannot reach the VM's
internals, so replay is the only way it can get state.

### 9.5 Hash choices

- **BLAKE3** for seed derivation (fast, no legacy baggage)
- **SHA-256** for story file identity (universally comparable to what other
  tools report)

Both are changeable later; invalidating old ledgers is acceptable, provided
the version field makes the invalidation loud rather than silent.

---

## 10. Deliberately not clean-rooming ZILF

A Zig ZIL compiler was considered and rejected for v1. The Z-machine is a
small, exhaustively-specified target verifiable by transcript diffing. ZIL is
the opposite: a Muddle/MDL dialect — a Lisp with fexprs and a macro system
that runs arbitrary code at compile time — with no formal specification.
Infocom's own compiler was itself written in MDL. "Compile ZIL" means
"implement enough of a 1970s Lisp to run the macros, then do codegen". ZILF
has had fifteen years of work and still special-cases Infocom-era constructs.

The compiler is a build-time dependency and GPL build tools do not affect
output licensing, so the effort buys only the removal of a .NET dependency
from an optional companion repo.

Higher-value adjacent projects, if the appetite exists:

- **A Z-code disassembler / story file inspector.** Small, immediately useful
  for debugging the VM, and exactly the tool needed when V4+ score annotation
  becomes a problem.
- **A ZIL-like compiler for a deliberately restricted dialect**, targeting
  *new* procedurally generated games rather than historical ones. Sidesteps
  the MDL macro problem entirely and is the natural path to TextWorld-style
  generated content running through the same VM, the same ledger, and the same
  code path as Zork.

---

## 11. Future work (out of scope, noted for design fit)

- **Procedural generation.** A generator plus a seed yields infinite graded
  tasks — the real insight behind TextWorld (MIT licensed; its generation
  approach is legally reusable, though note its Z-machine backend wraps
  Jericho, which is GPLv2 via Frotz). Since the ledger already registers a
  seed derived from the first message, a ledger becomes a fully
  self-describing, portable game session.
- **Agent-as-user.** Recasting an agent as the user side and having two agents
  converse, with sandboxing. This wanted message roles to be first-class in the
  ledger rather than implied by position — which m8 already does: 🙋 and 🤖 are
  sigils, and the provider reads roles rather than counting positions. Nothing
  to build.

  The composition needs no new machinery either. An agent under test is given a
  🧰 whose 🔌 is `["m8", "+zork", "--", "{{command}}"]`; `+` carries the chat
  from turn to turn, and the tested agent never learns it is talking to a VM
  rather than to a model.
- **Glulx provider.** Separate VM, larger address space, Glk I/O including
  hyperlink events. Roughly doubles reach into modern IFComp entries.
