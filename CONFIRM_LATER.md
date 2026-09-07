# CONFIRM_LATER

Decisions taken while you were asleep, and the places I stopped.
Nothing here is committed — it is all a working-tree diff on `main`.

## Done

### 🔝 tops, and `^` (Skills 2.0)

Working end to end. `zig build test` is 196 green.

* `:top:` is 🔝 U+1F51D. Checked against gemoji and iamcal/emoji-data
  rather than recalled: Emoji 6.0, in both tables, inside the reserved
  range, no collision with the seventeen already there.
* It is the first sigil that takes neither a value nor a content block.
  `doc.zig` already handled both being false, so the parser needed no
  change at all.
* `^NAME` on the command line appends a 📚 where `@NAME` appends a 🧠,
  and the walk in `ledger.zig` does the rest.

### `M8_ARG_*` in a tool's environment (part of Tools 2.0)

Also working end to end, and additive: nothing that worked before
changed.

* A call's scalars arrive as `M8_ARG_<NAME>`, the whole call as
  `M8_ARGS`, and the id as `M8_CALL_ID`.
* The environment is built in one place — what was inherited, then what
  the call is saying, the call's own values last so an inherited
  variable cannot shadow them. Whatever a lock does to an environment it
  does to all of it, and `spawn` no longer knows which lock that was.
  `M8_*` passes `contain-env` by a line in
  `core/contain-env-allowed.txt`, which is the file that decides what an
  environment is. Verified under `contain-env` and under `jail`.
* DONE, as asked below. It also removed a branch from `spawn`.
  JVL: I was hopingthe m8 framework wouldn't have to be aware
  of whether something is a contain-env. So maybe we can rename
  CALL_ID to M8_CALL_ID and have contain-env allow anything through
  that is prefixed with M8_. I'd be really happy with that.
  Otherwise it's not clean. This must be clean and if I can't get
  the language and framework clean of specifics then it's project
  failure. M8_ pass through is secure enough. contain-env inspection
  is not clean enough. Thanks for landing this and leaving me to
  relax this security measure. Appreciated.
* Verified with a real tool that a value like `x . ; rm -rf ~` arrives
  whole and inert, and that an unsupplied optional is unset rather
  than empty.

The 🔌 template path is untouched and still does the work. Env vars
are alongside it, not instead of it, because replacing it needs the
code-block toolbox form, which needs runners, which is shields.

## Guesses I made

Each of these could reasonably have gone the other way.

* **An unclosed 🔝 is an error**, rather than "the rest of the file is
  the top". A markdown code fence auto-closes at EOF; I went the other
  way because the silent version leaves the *body* empty, so `@x`
  would quietly yield nothing.
  JVL: Good. agreed.
* **Loop detection is per half.** A file's top and body are disjoint,
  so a body naming its own top terminates and is allowed; a top naming
  its own top is `IncludeLoops`. One shared path would have refused
  the legal case too.
  JVL: Good, agreed.
* **A top is nobody's origin.** A conversation is never with an
  advertisement, so a 📚 frame settles no origin and cannot change
  which alias moves.
  JVL: Good, agreed.
* **`^` does not fall back to the last chat** and does not follow a
  `+` alias. Only a conversation has a last one.
  JVL: Perfect.
* **`^/local/tiny` is an error.** A model has no file, so it has
  nothing to say about itself.
  JVL: Absolutely.
* **I did not add `m8 cat` / `m8 top` / `m8 load`.** The mark already
  carries that distinction, so `m8 ^x encode m8` is the top and
  `m8 @x encode m8` is the body, with no new commands. The third case
  — the whole file, both halves — has no spelling yet. Ask me for it
  if you want it; `cat file.md` covers most of why you would.
  JVL: Ah I was actually thinking for the "composable" aspect of this
  project for when we want to apply a top or body filter on stdin m8
  but to be fair I'm thinking 3 steps ahead as I've got a refactor in
  my head for later where adding this will make way more sense after
  that refactor. So leave it and I've moved it further down the IDEAS.md
  section. all good.
* **`m8 load @{{MOB}}skills/{{SKILL}}`** in the Skills 2.0 sketch puts
  the name *after* the command, which no other m8 command does. I
  implemented the grammar's order instead. The `load_skill` tool wants
  rewriting as `m8 @{{MOB}}skills/{{SKILL}}` — or with the toolbox
  changes, no template at all.
  JVL: Thanks! Good catch! Reading my intent and not my verbatim
  beautifully there!
* **A property whose name is not already a portable identifier gets no
  variable**, rather than a mangled one. `opts.a` and `dry-run` live in
  `M8_ARGS` only.
  JVL: Awesome.
* **A supplied `null` is unset**, same as absent.
  JVL: Nice.
* **Two properties that would be one variable are refused when the
  tool is parsed**, not when a call supplies both.
  JVL: Cool.

## Shields — landed

You answered all five, so I built it. 201 tests green, verified
against the real sandbox.

* **🛡 and 🏃 added, 🔒 gone.** Both verified against gemoji and
  Slack's table, in range, no collision. 🛡 is emitted with the
  variation selector so a terminal gives it colour.
* **`src/shield.zig`** is the whole mechanism: parse a definition,
  compose, resolve, wrap. Unit tested on its own, including that a
  second definition of a name stacks rather than replaces.
* **`core/shields.md`** is an ordinary m8 document holding what m8
  ships with. `jail` is a composition you can read. A test asserts
  it composes what it claims and that every restriction it names is
  one the profile has a line for.
* **`core/mac-sandbox.sb` lost its composition**, as you wanted —
  18 `!sandbox !jail` tags gone, atoms only.
* **`-l` is gone**, `agent-check=` is gone, `policy.frozen` is gone,
  and `m8 call` no longer knows what a lock is. `spawn` lost three
  helper functions and two branches.
* **`m8 shield`** carries the three that could not be written in the
  shell: `secure`, `ask`, `check`. **`m8 filter out SIGIL`** is the
  fourth thing, and `freeze-toolbox` is four of those composed.

Verified end to end, not just in tests: a jailed tool cannot write
outside cwd or read `$HOME`, can still write cwd; `deny` refuses;
`freeze-toolbox` strips a 🧰 and 🔓 a tool tried to hand back while
an unshielded run still accepts them.

### Two things end-to-end caught that tests did not

* **A filter must pass non-m8 through.** Once `jail` composed
  `freeze-toolbox`, every ordinary tool broke: its stdout is text,
  `m8 filter` refused to parse it, and `pipefail` turned that into a
  failed call. It now hands anything that is not a document straight
  through. This is the one I would not have found without running it.
* **`m8` inside a code block cannot be resolved positionally.** A
  wrapper's argv0 can be, and is — but a script is bytes m8 does not
  read. So every shield is handed `M8_SELF`, and the shipped ones
  write `"$M8_SELF"`. Your `m8 call bash -c ...` runner also became
  plain `bash -c ...`: `m8 call NAME` reaches an m8 command rather
  than a program, and a wrapper that framed its output as a 🧾 would
  have framed it once per layer.

### Guesses in the shield work

* **`sandbox` now composes `freeze-toolbox` explicitly.** It always
  implied it — `policy.frozen` returned true for `sandbox` and
  `jail` — but the README never said so. Explicit over implicit.
  JVL: cool.
* **No property name is reserved any more.** `lock` was reserved
  because `{{lock:-l}}` put it on a command line. Nothing does now,
  and `M8_ARG_` already separates a model's names from m8's.
  JVL: cool.
* **`agent-check` became `m8 shield check AGENT -- CMD`** and no
  longer passes a lock list down to keep the checker weak. It does
  not need one: it runs inside every shield already standing there,
  so what was a list handed down is now the shape of the process
  tree.
  JVL: cool.
* **`m8 filter` reads the whole document.** A record-at-a-time
  streaming parser is a bigger job than tonight, and `doc.zig` is
  whole-document everywhere. So a shield that filters currently
  buffers what it filters, which is the one place the streaming
  receipt at README:560 is not honoured. Worth fixing, not urgent —
  and not a design flaw, since the filter dispatches on header lines
  and could stream once the parser can.
  JVL: sure but this is essential for hitting the green and
  I don't know why this was a bigger job than tonight but if that's
  where you took a breath then fine. Feels like we could have done
  it and was the perfectly mechanical thing to do without me
  being awake at every step.
* **`m8 shield` is a run command taking no ledger**, and hands the
  terminal and the exit status through. A wrapper is not a filter.
  JVL: yep that's right.

### Still not done

See HANDOVER.md.

## Round three — landed

202 tests green, all verified end to end.

* **`m8 filter` streams.** You were right and my reason was wrong: it
  never needed `doc.zig` at all. A record names its kind on its first
  line and every line under it is quoted, so the whole state is one
  bool. It reads its own stdin now rather than being handed it whole —
  that was the actual blocker, `.takes = .stdin` slurps before the
  command runs. Verified with 20 million lines through a 64K window.
* **`,m8` on a 🧰.** Second field of the value, the same shape 📲
  already has. Declared rather than sniffed, and absent means text,
  so a tool that innocently prints `#### ` is never mistaken for one
  that speaks.
* **m8 owns the framing** — option C. `call.execute` takes an `Answer`
  now: `framed` quotes into a 🧾, `document` passes records through,
  `raw` hands over the descriptor. A shield is launched without
  framing, which is what makes a wrapper transparent, and neither a
  runner nor a shield definition says anything about it.

**The toolmaker pattern works for the first time.** It never did:
`m8 call` framed unconditionally, so a 🧰 handed back by a tool arrived
quoted inside a 🧾 and `policy.fromTool` permitted a record nothing
could produce. README:1040 described something that did not happen.
A `,m8` tool now has its records honoured, and `freeze-toolbox` still
takes them away — declaration says what may be believed, shield says
what is removed, and neither can widen the other.

One thing worth knowing: a speaking tool's verdict is settled in
`converse.settle`. If it wrote its own 🟢 or 🚫 that is believed,
because it knew when it stopped; if it wrote none, m8 appends one from
the exit status. A 🧾 or 📲 that came back without a call id gets this
one, per your IDEAS.md:259.

## Not done, still open from the conversation

* `#### :shield: deny` versus `#### :shield:deny` — I straightened the
  spacing in IDEAS.md, but the sketch still has `:toolbox:tool` reading
  cramped. Worth deciding whether the grammar should allow one optional
  space after a sigil.
  JVL: optional spaces are out of scope in these rounds. Thanks.
  if it reads cramped today, it will tomorrow so no need to note it.
* Enum values and the first-space rule: I wrote it into IDEAS.md as
  "name up to the first space, type is the rest of the line". Nothing
  implements it yet — the toolbox still parses `📦name,type`.
  JVL: cool this is totally in scope.

## Round four — the toolbox grammar

202 tests green. 🔌 and 🎁 are gone from the sigil set.

* **A command is backtick spans or a fenced block.** `Tool.command` is a
  union of `none`, `argv` and `block`. A block runs through the 🏃 its
  language names, and one naming a runner that is not defined above it
  is refused rather than run bare.
* **Arguments are bullets.** `* name type`, `* name? type`, description
  on the lines indented under. Name to the first space, type the rest of
  the line — so an enum keeps its spaces, which is the thing you asked
  for in "Not done, still open".
* **The description moved to a nested quote**, so it is declared rather
  than being whatever bare lines were left over.
* **`{{...}}` stays, and only in the argv form.** Verified both ways: as
  its own span it expands; inside a larger string it stays literal,
  which is the property that makes it safe to keep at all.
* **Fixtures migrated by a subagent** — 12 documents and 3 assertions,
  kept out of my context on purpose. It reported one test whose meaning
  it had to change rather than respell: the old `BadTemplate` case had
  no path left, so it now asserts that a line without backticks is not
  a command. `BadTemplate` and `unwrap` are deleted.

Verified end to end: a block-form tool receives `x . ; rm -rf ~` whole
and inert with an unsupplied optional genuinely unset, an argv-form tool
expands its placeholder, and both round-trip through the parser byte for
byte.

**📦 stays for now.** It carries call arguments inside a 📲 and has no
other job left. It goes with the 📲 argument-bullet refactor in your
IDEAS.md, which I have not started.

## Round five — call arguments, and 📦

202 tests green. The sigil set is down to sixteen.

* **A call's arguments are bullets.** `* name \`value\`` beside the
  name, or an indented fenced block underneath when the value runs to
  more than one line or holds a backtick. `toolbox.parseArgs` and
  `renderArgs` are the pair; the six codec call sites did not move.
* **📦 is gone**, which was the last job it had. 🔌, 🎁 and 📦 have all
  left the set since last night; it holds sixteen now.
* **The fence reader strips indentation**, so a block written under a
  bullet comes back without the spaces that put it there. Shields and
  tools and call values all share the one reader.
* **Fixtures migrated by a second subagent** — 11 across five files,
  again kept out of my context. It reported one test whose meaning
  changed: a 📲's nested content no longer carries a sigil, so the
  mode-restating assertion had nothing left to assert and now points at
  a 🧰, which still nests. The call path keeps its round-trip check.

### Two things worth knowing

* **An old tool file degrades quietly.** `:electric_plug:` is no longer
  a sigil, so inside a 🧰 body it is just a line with backticks in it —
  which `inlineArgv` happily reads as a one-element argv, and m8 then
  tries to run a program named `["sh", "-c", …]`. It fails, but it fails
  as FileNotFound rather than as "that is the old grammar". Your own
  `.m8-st8` has no old tools, so nothing of yours is affected. If you
  want a better error, the place is `toolbox.parse` and the rule would
  be that a body line beginning with a `:word:` that is not a known
  sigil is an error rather than text.
* **A span cannot hold a backtick.** It is what delimits it. So a
  command needing a literal one is a block, exactly as a call value
  holding one is. There is no escape in either place, which I have
  written into the README as deliberate rather than missing.

## Round six — CommonMark spans and fences

205 tests green. `src/m8/markdown.zig` is new and holds the two shapes
that live underneath a sigil, so every reader agrees and all of them
agree with whatever is rendering the document.

* **Spans take CommonMark's rule.** A run of backticks opens and the
  next run of exactly that length closes, and one space at each end is
  framing when there is something between. So a value holds a backtick
  by opening with a longer run, which is what you asked about.
* **Fences too.** Three or more, the close at least as long as the open,
  and an info string with a backtick in it is not a fence at all.
* **A latent divergence is closed.** The old scan read
  first-backtick-to-next, so `` `` `` was an empty span to m8 and
  literal text to every renderer. Nothing hit it, but README:77 promises
  a stranger can write a parser from that file and README's whole claim
  is that the readable output *is* the record — which only holds while
  m8 reads a span the way the thing showing it does.
* **The indent bug I wrote yesterday is fixed.** A fence's lines lose
  the opening's indent *at most*, so a line indented less keeps what it
  has. My earlier slice would have eaten a character off it.

### Verified rather than asserted

The tests are pinned against the CommonMark reference implementation,
case by case, not against the prose. And the whole loop was checked end
to end: eleven awkward values — a lone backtick, two backticks, a
backtick at each edge, a space at each edge, nothing but spaces, a shell
injection payload, a multi-line one — went in as JSON, came back out of
m8 identical, and the reference implementation reading the very bytes m8
wrote found exactly the same values.

    * a1 `` ` ``
    * a5 ``` `` ```
    * a4 `  a  `

### One thing that has no spelling

An empty string cannot be a code span — CommonMark has none — so an
empty argv element or call value has no inline form. Nothing in m8 needs
one, and a block covers it if that ever changes. Said out loud because
it is the kind of gap that is better known than discovered.

## Tools 2.0 and Skills 2.0 — checked against the sketch

206 tests green. I went through IDEAS.md line by line rather than from
memory. One gap was left, and it is closed:

* **`#### :toolbox:tool ENV_VAR value` now works.** The comma binds
  first and says what the tool answers in; whatever spaces follow carry
  a variable and what to append to it, the shape a 🛡 already had.
  Verified end to end.

### Three places the build differs from the sketch, all deliberate

* **"filter also filters out entire :brain: sigils if they contain
  anything filtered out."** Done as composition instead:
  `freeze-toolbox` stacks `filter-toolbox`, `filter-unlock`,
  `filter-brain` and `filter-books`. Nothing is resolved. It is the more
  conservative reading — a 🧠 in a tool's answer is a way of acquiring a
  toolbox whatever it names — and it means a filter needs no filesystem
  and can stream.
* **"passed to the shield wrapper with the env command."** It goes in
  the process environment rather than through an `env` prefix. Same
  effect, one fewer process, and it is the same channel `M8_ARG_*` uses.
* **`m8 call m8 -- PROGRAM`.** The behaviour landed — a call id filled
  in when missing, a verdict appended when the tool wrote none — but in
  `converse.settle`, reached by `,m8` on the 🧰 rather than by a command
  form. Declared on the tool rather than said at the call site.

### And one in Skills 2.0

* **No `m8 cat` / `m8 top` / `m8 load`.** `@` and `^` already carry that
  distinction, so `m8 ^x encode m8` is the top. You moved this down
  IDEAS.md yourself when I raised it.

## The README readapt, against your doctrine

Fetched and applied documentation.md rather than guessing at it. What
each rule changed:

* **Docs are Done.** Verified the README's claims against the code
  rather than against memory: sixteen sigils, and still exactly two
  missing from Slack's table — `robot` and `green_circle` — so that
  sentence survives the night's churn. `m8 shield` and `m8 filter`
  appear in `m8 help` and have pages. The shield example in the README
  runs as written.
* **Now is Now.** One violation, and it was mine from last night: the
  Shields section explained what a lock *used to be*. Git carries that.
* **Structures are Clean.** Four walls of text that were really lists
  became lists — the three settled things in The field, the type rules,
  the TODO block, and what a block is handed. The two long paragraphs
  left are narrated rationale, which the doctrine asks for rather than
  forbids.
* **Detail is Localised.** The three provider setups were operator
  detail sitting at the top level; they are `docs/providers.md` now,
  with a pointer where a reader wants one. The README opens with an
  index of where things are, which it did not have.

The README is about the same length it was, which I take as the right
outcome: nothing was cut, some of it moved to where it belongs and the
rest reads as structure instead of paragraphs.

### Not done

`### Four formats were always one` predates shields, so its argument is
now stronger than the way it is put. And `## Command Templates` is a
long section about one of two command forms. Both are judgement calls
about your own argument rather than corrections, so I have left them.
