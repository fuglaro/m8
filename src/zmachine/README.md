# The Z-machine

A story file, played as a model.

`/inbuilt/Z-Machine/zork1` is a model like any other: it is
handed a ledger and it answers with what to add. It has no
weights. It is a virtual machine wearing a model's interface,
and the fit is not a joke — a model api is stateless, and so
is a Z-machine that never saves.

## Why it is shaped this way

A model is sent the whole conversation on every call, so
nothing can be kept between them. The machine is rebuilt each
time and the ledger replayed through it.

Everything else falls out of that:

* The ledger is the save file. `m8 cat @ | m8 encode m8
  >save.md` writes one and `m8 tag @zork <save.md` restores it.
* Forking a chat forks the world, and copies nothing.
* Two runs of the same words cannot differ, which is what
  makes a transcript a test rather than a demonstration.
* Saving, restoring and undo are not implemented, because
  there is nowhere to put a save and no longer any need.
  `restart` is, because it needs no state to exist.

The first message is not played. It is hashed, and the hash is
the seed the world is built from, so `hello` and `hello!` are
two different games.

## The seam

Two halves that cannot reach each other, which is what stops
either of them cheating.

* `src/zmachine/` is the machine and has never heard of m8. It
  loads a story file, runs it, and hands back text. It cannot
  reach a ledger, so it cannot become stateful by accident.
* `src/command/providers/zmachine.zig` is the provider and has
  never heard of an opcode. It finds the file, derives the
  seed, replays the 🙋 records, and writes a 🤖. It cannot
  reach the machine's insides, so replay is its only way to
  state.

`zmachine.zig` is the whole of what crosses: `play` takes a
story file, a seed and the lines somebody typed, and answers
with what the last line produced.

The provider deliberately never reads the 🤖 records it wrote
last time — state comes from replaying the input alone, so a
doctored transcript changes the story not at all. That is what
makes handing an agent a false history a test rather than a
corruption.

## The invariant

**Ledger + story file + declared versions → byte-identical
transcript.**

If it holds, no save format is ever needed. If it stops
holding, every stored ledger silently describes a world that
no longer exists, so it is a test that runs on every commit
rather than a property anybody remembers to check.

Three things could break it, and each is answered rather than
left to a default:

* `random` never reaches the clock. The generator is written
  out in `machine.zig` rather than taken from the standard
  library, so a compiler upgrade cannot quietly change every
  world.
* Input is the ledger's own text, tokenised by the machine and
  not by the harness.
* The persistence opcodes fail, in the way each version
  expects, and `restart` resets deterministically.

A bug fix in the machine legitimately changes output. That is
why the first reply carries an interpreter *semantic* version —
a hash of these sources — so the change is detectable instead
of mysterious. It is a hash rather than a number somebody bumps,
which is also why there is no separate seed-derivation version:
the rule lives in `zmachine.zig` and `zmachine.zig` is in the
hash, so it cannot change quietly.

That provenance goes out as a 💭, not as part of the 🤖 the
player reads — it is the interpreter's note about how the answer
was produced, and keeping it out leaves the 🤖 naming no story
file and no machine. The cost is that `codec.zig` is licensed to
drop a 💭, so provenance survives `encode m8` and not
`encode openai-completions`. Nothing replays from it, so what is
lost is attribution rather than the world.

## What is here

Each file's header carries its own reasoning; this is the map.

* `story.zig` — the file, its header, and the headless profile
  written over it: eighty columns, no colour, no sound, no
  timed input.
* `text.zig` — Z-strings, the three alphabets, ZSCII. The
  grind, and the version differences worth special-casing.
* `object.zig` — attributes, properties, and who is inside
  what, in both table layouts.
* `dict.zig` — the dictionary, and turning a typed line into
  words the game can match.
* `screen.zig` — four streams, two windows, and where a line
  breaks. Also where ZSCII stops and code points begin.
* `machine.zig` — decode, execute, and the input boundary that
  splits one opcode across two calls.
* `keys.zig` — the keys that are not characters, and the
  symbols that stand for them.
* `zmachine.zig` — the seam: provenance, the seed, the status
  line, and `play`. The status line is V1–3's, synthesised;
  V4 and up have none and what sits above the text is whatever
  the game drew.
* `cli.zig` — `zig build zrun`, for working on the machine
  without m8 in the way.
* `integration.zig` — the machine against real story files.
* `testdata/` — story files written here so they can live
  here, and their Inform source.

## Decisions that span files

Detail lives with the code; these are the ones with no single
file to live in.

* **The emit boundary is the input request.** Nothing is
  emitted until the machine wants input, so a turn is a pure
  function of "it ran until it stopped" rather than of how
  many times a window was repainted.
* **A shrinking upper window gives its rows to the
  transcript.** They stay on a real screen and were read
  there. Without it, a game that paints a display and then
  shrinks — the game Curses opens exactly so — loses it
  entirely.
* **The status line is regenerated, never buffered.** V1–3
  synthesise it from the three reserved globals, so
  `show_status` has nothing left to do; V4+ read the upper
  window off at the boundary.
* **Names are exact.** A model is named after the file it is
  found in, so `Z-Machine` is the folder and `zork1` is
  `zork1.z3`. m8 folds nothing; a case-insensitive filesystem
  may still be kinder on its own account.
* **Story files are data, not `core/`.** They decide which
  world is played, not what runs, so they are found by the
  ordinary nearest-first config search under
  `models/Z-Machine/`.

## Story files

m8 ships with none and plays whichever are there.

```
./.m8-st8/models/Z-Machine/          nearest first
~/.config/m8-st8/models/Z-Machine/
```

`.z1` through `.z8`, and Blorb containers, whose story data is
extracted before anything else looks at it. A name may hold a
path and may not climb out of the directory it is looked up
in.

Zork I to III are MIT-licensed source from Microsoft, and the
compiled files ship in those same repositories. Most other
Infocom games are not licensed for redistribution, so what any
particular machine can play is its owner's business.

## Working on it

* `zig build test` runs everything, including the story files
  in `testdata/`.
* `zig build zrun -- --all game.z5 "open mailbox" "north"`
  plays a file turn by turn and prints each one, which is what
  a transcript diff wants.
* **czech** — the Comprehensive Z-machine Emulation CHecker —
  is the conformance suite, and must report `Failed: 0` on
  V3, V4, V5 and V8. It is not committed, because it is not
  ours; `integration.zig` runs it when it is present and skips
  when it is not. Build it with
  `inform -v5 czech.inf scratch/stories/czech_v5.z5`.
* A transcript diff against `dfrotz -w 80` checks wrapping and
  layout. It cannot check a game with random events, because
  our generator is deliberately not frotz's — czech is the
  conformance test, that is the layout test.

## Not here

* **V6** is the graphical machine: four Infocom titles, all of
  which hide puzzle information in pictures. Poor agent
  environments, and the largest single saving.
* **V7** is defined and effectively unused.
* **Quetzal**, and save formats generally. The ledger is one.
* **Scoring** as a harness signal. Built-in score is sparse
  and idiosyncratic; a task reward defined outside the game is
  a better measure of an agent.
* **A ZIL compiler.** The Z-machine is small and exhaustively
  specified; ZIL is a Muddle dialect with fexprs and
  compile-time macros and no formal specification. ZILF exists,
  is GPL, and is a build-time tool whose licence does not reach
  its output — so writing another buys only the removal of a
  .NET dependency from an optional repository.
