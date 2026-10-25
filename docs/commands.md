# Commands

```bash
m8 [:MOB/AGENT[:|-|--] [-p] [-v] [-- PROMPT]]
m8 COMMAND [ARGS]
```

```bash
m8 :demo/mathy -- "Tell me about the Riemann Sphere\nin detail."
m8 :demo/pagey -- "Tell me more."
m8 :demo/mathy//aside -- "And what about the Möbius strip?"
```

```bash
echo "Tell me about the Riemann Sphere\nin detail." | m8 :demo/mathy
```
```
▐ 🤖:
│ The Riemann Sphere is a ...

▐ 🧠:demo/mathy/+/tduyxbutjb
```

The reply went to a tty, so it is rendered. The turn
it saved is a file, so it is markdown:

```bash
cat ".m8-st8/mobs/demo/.chats/mathy/+/tduyxbutjb.md"
```
```
* :brain::demo/mathy

* :raising_hand::
  > Tell me about the Riemann Sphere
  > in detail.

* :robot::
  > The Riemann Sphere is a ...
```

```bash
m8 :demo/mathy/+/tduyxbutjb -- "Tell me more."
```
```
▐ 🤖:
│ Additionally,
│ ...

▐ 🧠:demo/mathy/+/ypfpkuimzg
```

* `:MOB/AGENT` sits where a command would and is shorthand for `at`.
  A prompt supplied as arguments follows `--`; its words are joined with a
  space. `m8 :demo/mathy -p -- tell me` is
  `m8 at -p :demo/mathy "tell me"`.
* A bare `m8` shows help. There is no global/default chat and no `@` address.
* An address explicitly names an agent's chat, a subchat, or an immutable turn:
  ```
  :demo/mathy                         that agent's own chat
  :demo/utils/mathy                   a nested authored agent's own chat
  :demo/mathy//aside                  a subchat
  :demo/mathy/+/tduyxbutjb             a turn in the agent's own chat
  :demo/mathy//aside/+/tduyxbutjb      a turn in the subchat
  ```
* `:brain:` and 🧠 also mark an address, so a printed reference can be pasted back.
* A trailing `:` asks without advancing the chat. `-` resets it to its parent;
  `--` resets it to its authored agent, regardless of its parent's head.
  The separate `--` after an address remains the prompt separator.
* `m8 :demo/mathy -- hi` is the one-process form of
  `m8 ref :demo/mathy hi | m8 send | m8 tag :demo/mathy`, with replies
  streamed and progress kept incrementally. No other chat is implicitly moved.
* Every agent belongs to one mob: `mobs/demo/mathy.md`. Agent definitions may
  nest, for example `mobs/demo/utils/mathy.md`, and path components cannot start
  with a period. `//` separates an authored agent path from a subchat path;
  `/+/TURN` names an immutable turn within either the main chat or a subchat.
  References inside a document stay in that mob at its selected storage layer.
* A 🧠 with a leading `/` names a model rather than an agent, for example
  `/local/Bonsai-8B,max_output_tokens:8192`. Put it in an agent definition
  to give it an address and a chat. See [Models](configs.md#models).
* State is written to the selected mob's storage, not the nearest arbitrary
  config folder. See [Configs](configs.md).
* At a terminal, an address alone opens the configured UI. `-p` renders and
  streams a single submission even through a pipe. Ordinary filters always
  write markdown; `m8 render` gives any document its rendered spelling.
  * Rendered 📜, 🤖, 💭 and 📲 text is highlighted as markdown, without
    leaving anything out. Non-markdown text indented four spaces is shown as is.
    Wide lines wrap with their quote and indent carried along.
* `-v` reports progress on stderr; `-vv` reports more detail.
  * `💭` shows the opening of a thought once; `📲` shows a tool call as
    `name(argument=value,…)`. Each is one line, cut where it gets long,
    and stays the last thing said until the next. Snipped thoughts are omitted.

Every command has a page:

```bash
m8 --help                  every command, and what m8 reads
m8 send --help             one command
m8 munge --help            one tool and all its operations
```

A leading `--help` is m8's rather than any command's, so no
command has to parse it and no two answer it differently.
It is the only help option; `-h` remains an ordinary argument.
The words after an address are prose after the required `--`, so a
`--help` among them is said rather than read.

A page you asked for is written to stdout, where it can
be paged and piped. A page handed back instead of what
you asked for goes to stderr, where it cannot become part
of a document.

## Assembling

`m8 :MOB/AGENT` builds a ledger from three things: what
the address reads as, whatever was piped in, and the
prompt, in that order.

```
nothing piped   ADDRESS → prompt
m8 piped        ADDRESS → the document → prompt
anything else   ADDRESS → prompt, then the text
```

One rule is behind all three: what arrived is added to,
and nothing else is. A document piped in is records
already, so it follows the address as it is — which is
how a model piped in after a chat takes it over, since
the last model named is the one that answers. Anything
else piped in is prose rather than context — it is what
somebody would have typed after the address — so it
joins the prompt.

```bash
cat notes.txt | m8 :demo/pagey -- "Summarize:"               # one 🙋, prompt first
echo "* :brain::/local/tiny" | m8 :demo/mathy -- "Quickly?"
m8 top :demo/tight-docs | m8 :demo/mathy -- "Tidy the README."
```

Piping is not required, and neither is a prompt when
something was piped. With neither, at a terminal, the
address alone opens a conversation with it: `m8 :demo/mathy`
is `m8 riff m8 at -p -v :demo/mathy`. See [Riffing](#riffing).

What opens is the `tui` in `core/config.json`:

```json
{ "tui": ["m8", "riff", "m8", "at", "-p", "-v"] }
```

* The address is appended to it.
* An `m8` first is this m8.
* That value is also the default, for when nothing names one.
* A build without riff says the message the plain way.

`-p` after the address is one message the plain way: a
terminal collects lines until Ctrl-D, then shows the
submitted 🙋 before waiting for the reply; Ctrl-D before
anything was entered quietly cancels. An empty
non-terminal input still has nothing to say, and m8 says
so.

A document is told from prose by its first line alone,
so one that opens like a document and then goes wrong is
an error rather than a prompt.

## Composing

Every command reads stdin and writes stdout, and the
ones that take an address resolve it themselves. So
what `m8 :MOB/AGENT` does is a pipeline too, and each step can be
had on its own:

```bash
m8 ref :demo/mathy hi | m8 send | m8 tag :demo/mathy      what m8 :demo/mathy -- hi does
m8 ref :demo/mathy | m8 tag :demo/mathy//aside             fork, with nothing said
m8 ref :demo/mathy hi | m8 send | m8 tag :demo/mathy//other     keep a run somewhere else
m8 ref :demo/mathy | m8 encode >.m8-st8/mobs/demo/notes.md        a chat, flattened into an agent
m8 ref :demo/mathy | m8 encode | m8 render           a chat, as a person reads it
m8 query :demo/critic//job "Review that."             the reply alone, as text
m8 watch :crew/cody//delegated                   a chat, as it moves
```

* `ref :MOB/AGENT` writes the 🧠 that X reads as now.
  * It names the turn rather than the chat, so it is a
    snapshot that stays put when the chat moves on.
  * It is a reference and not a copy, which is what lets
    `tag` point at it without keeping it again.
  * What it names is looked for: a turn or an agent that
    is not there is an error, not a 🧠 for nothing.
  * One argument after the address is a message, and follows
    as a 🙋 — or as the ❗ a chat waiting on a question is owed.
  * `--piped` reads stdin as prose and says that too.
    Without it stdin is left alone, so a `ref` run by a
    tool never waits on a pipe that is not its own.
* `send` runs a ledger and writes the turn: the ledger
  as it arrived and whatever the run added. It keeps
  nothing, so one run can be kept wherever it is
  tagged, or nowhere.
* `tag :MOB/AGENT` keeps a turn and points X at it.
  * A document that is one 🧠 already names a turn and is
    pointed at without writing anything.
  * Anything else is kept as a new turn.
  * Its output is the 🧠 now pointed at, and nothing
    else — a ref was written, and that is its receipt.
  * `--no-advance` keeps the turn and moves nothing.
* `reset :MOB/AGENT` takes a chat's pointer away, so it reads as
  its parent again.
  * `--new` starts it from the agent it is under, whatever
    the chats above it have got to.
  * `--to :MOB/AGENT//CHAT` has it follow Y as named, unsettled:
    `m8 reset --to :demo/mathy :demo/mathy//aside` has aside follow mathy.
  * Something that would lead back to itself is refused.
* `tail` writes the last record of a document, or with
  `--sigil` the last of some kind.
  * `--value` is the rest of its header line, and
    `--block` is its block as the text it holds.
  * A record with neither is an error, not an empty line.
  * Nothing is resolved; `m8 encode` expands a 🧠 first.
* `exclude --sigil S` writes a document back with every
  record of the kinds named gone. See [Shields](shields.md).
* `render` writes a document in the rendered spelling, and
  `render -r` writes markdown back, which is how to check
  that a document parses.
  * `--parsable` breaks no line and pads no table, so a copy
    off the terminal parses again.
  * `--no-highlight` writes no colour.
  * It writes as it reads, so it can sit at the end of
    anything still talking.
* `query :MOB/AGENT MESSAGE` is the pipeline written once more,
  for whatever has parameters rather than a command line.
  * It says the message, runs, keeps the run, and writes
    the reply or the question as text.
  * `-v` says on stderr what the run is doing, and `-vv`
    writes the whole turn there.
  * `--no-advance`, `--new` and `--parent` say where it
    starts and whether anything moves.
  * `--no-store` keeps nothing, so nothing moves either.
  * `--piped` reads stdin as prose, as it does for `ref`.
* `watch :MOB/AGENT` writes a chat out as it moves, which is how to
  look on at one something else is running.
  * Each piece opens with the 🧠 it continues.
  * A chat that is reset starts over under its agent's 🧠.
  * It arrives a turn at a time: a reply once it is whole,
    and a call once it is answered.
  * Only the chat's own pointer is read, so a chat with none
    is waited on rather than shown as the chat above it.
  * A snip stays the 🧠 that names it.
  * New `::stats::` lines from the chat's advisory `+.log`
    go to stderr; ledger output remains stdout. Existing
    stats are not replayed. Watch still polls the pointer.
* `top :MOB/AGENT` is `ref`'s twin for 📚: it names a file for
  what it says about itself, and nothing else. See [Tops](language.md#tops).

A document follows an address by being written after it,
which is all a document needs:

```bash
{ m8 ref :demo/mathy hi; echo "* :brain::/local/tiny"; } | m8 send
{ m8 top :demo/tight-docs; m8 ref :demo/mathy "Tidy the README."; } | m8 send
```

What `m8 :MOB/AGENT` writes ends on the 🧠 of the turn it kept,
and `tail` is how that becomes what the next command is
handed:

```bash
m8 ref ":$(m8 :demo/mathy -- hi | m8 tail --value)" "Review that." | m8 send
```

A turn `send` wrote was never kept and ends on no 🧠, so
`tail --value` has nothing to hand on until it is tagged.

Only the explicitly addressed chat moves. To resume it, name it again.

## Riffing

```bash
m8 riff CMD [ARGS]         an editor pinned under CMD's output
m8 :demo/mathy                  at a terminal: m8 riff m8 at -p -v :demo/mathy
m8 riff -c python3 -i -u -q    one Python, a message at a time
m8 riff -c -s 2 python3 -i -u -q    with its last error above its prompt
```

`riff` is a conversation at a terminal, made of the command
line rather than beside it. The `m8 :MOB/AGENT` shorthand checks the
address before opening the UI, so an unknown agent or missing
turn is reported before you write a message.

* Every message sent is a run of CMD.
  * The message is its stdin.
  * A message sent mid-run waits its turn.
  * If CMD fails without writing any stdout, its stdin is put
    back in the editor before anything typed while it ran.
    Stderr does not prevent recovery. In continuous mode,
    recovered messages are separated by newlines.
* CMD's stdout is ordinary terminal scrollback.
  * Only CMD writes there, so it scrolls, selects and copies
    as any output does.
  * riff never repaints it and keeps no copy.
* The last line CMD wrote to stderr is the status line.
  * `-s N` is N status lines, from 1 to 8: the last N it wrote,
    newest at the bottom.
  * What riff says itself takes the bottom one.
  * A nonzero exit remains `Stopped(N) and waiting ...` until
    the next message is dispatched. A signal uses its number.
* A stderr line that leads with `::stats::` carries a panel.
  * The panel is what follows, up to a `::` or the line's end.
  * It sits at the right end of the top status line, hard
    against the text, and stays until the next one.
  * Anything after the `::` is a status line as usual.
  * A provider's optional `stats` command says one under `-v`:
    `::stats::✥19▇16K::` is what came out, the share the
    prompt cache held as a block, and what went in.
    See [Stats commands](providers.md#stats-commands).
* The editor is the rows under that.
  * It starts as one row and grows with the message, to at most
    half the terminal.
  * It does not shrink while a message is being written.
  * Sending makes it one row again, before CMD says anything.
  * Enter sends.
  * Ctrl-j is a new line, and so is Alt-Enter.
  * A paste keeps its lines: nothing in one sends.
  * Ctrl-d sends too, and leaves when there is nothing to send.
  * PgUp and PgDn move by the editor's height.
  * Ctrl-c interrupts a run, and leaves when nothing is running.
* `-c` is continuous: one run of CMD for every message.
  * The first message starts it, and each is a line on its
    stdin.
  * Ctrl-d with nothing to send closes its stdin.
  * CMD has to work a line at a time on a pipe, and say so as
    it goes. Python needs `-i` for the first and `-u` for the
    second; its `>>>` is on stderr, so it is the status line.
  * `-t` is `-c` with a NUL byte ending each message rather
    than a new line, for a CMD that takes messages of more
    than one line.
* CMD has no terminal.
  * It runs in a session of its own, so `/dev/tty` is not
    there to open and riff keeps the one it has.
  * Its environment is riff's as it arrived, apart from
    `COLUMNS` tracking the terminal width.
  * A tool that asks the person does it through the ledger, so
    the question is the last thing a run says and the next
    message sent is the answer. See [Asking the Person](tools.md#asking-the-person).
  * `m8 riff --detached CMD` is that half alone.

riff knows nothing about m8. `m8 riff sh -c 'cat; date'` is as
much a riff as a chat is.

## Casting

`cast` replays a ledger as riff would have shown it, as an
animated SVG: a session a README can carry.

```bash
m8 ref :games/zork | m8 encode | m8 cast >zork.svg
m8 ref :games/zork | m8 encode | m8 cast --size 100x30 --speed 40l,🤖60w >zork.svg
```

* A small build has it beside `m8` as `m8-cast`, since no
  session needs it. See [Building](building.md).
* Each 🙋 is typed into the editor and sent, and what follows
  arrives above it, as riff shows it.
  * Records before the first 🙋 are left out, as riff shows
    nothing until something is sent.
* `--speed` is a default, then sigils, each a number of
  milliseconds and what it is per.
  * `c` a character, `w` a word, `l` a line, `b` a block.
  * A number after that is the pause before it starts, as in
    `🙋50c1000`.
  * Unless named, 🙋 is typed at `50c` after 600 ms, and the
    rest arrive at `30l`.
    * An answer to a 🙋 starts 200 ms after it is sent, and
      anything else straight on.
* `--no-riff ADDRESS` plays it at a plain terminal instead.
  * Each 🙋 is typed at a `>>> ` prompt as the command that
    says it: `m8 ADDRESS -- 'MESSAGE'`.
  * A message with a `'` or a line break in it, or too wide
    for one line, is a heredoc: `m8 ADDRESS <<'^^'`.
  * What follows is what that command writes, so not the 🙋.
* `--size` is the terminal, `80x24` unless said.
  * A line wider than it wraps, as a terminal wraps it.
* It is CSS and nothing else, so it plays wherever an image
  does.
  * It holds the last frame for 3 seconds and plays again.
  * The text is m8's own rendering, so it keeps m8's look.
  * Every run sits on a cell grid, so a viewer's font cannot
    push it out of line.

## Encoding

```bash
m8 encode [--break NAME] [FORMAT]  a ledger, as some api sees it
m8 parse FORMAT                    that api's response, as a turn
m8 send                            run a ledger and write the turn
```

There are four:

* `m8` — the language itself, so encoding is writing it
  out and loses nothing.
* `openai-completions` — OpenAI chat completions, and the
  many servers that answer in its shape.
* `anthropic-messages` — Anthropic's messages api, which
  is where Claude answers.
* `openai-responses` — OpenAI's responses api, which is
  where Codex and a ChatGPT plan answer.

`m8 encode --help` is the same list, and any provider may
name any of them. With no format named, `m8 encode` uses
`m8`, the lossless format.

`m8` is a format like any other here, so `encode m8` is
how a chat becomes one flat document.

```bash
m8 ref :demo/mathy | m8 encode m8
m8 ref :demo/mathy | m8 encode m8 >full-ledger-copy.md
```

```bash
m8 ref :demo/mathy | m8 encode openai-completions
m8 encode openai-completions <full-ledger-copy.md >openai.json
```

`--break NAME` leaves a 🧠 naming NAME as it was written
rather than expanding it, so what comes out is the ledger
from there on.

```bash
m8 ref :demo/mathy | m8 encode --break mathy/+/tduyxbutjb
m8 ref :demo/mathy | m8 encode --break mathy     # the chat, without its agent
```

* NAME is what a 🧠 says: a turn, or an agent.
* It may be said more than once.
* What is written still reads as the whole ledger, because
  the 🧠 left standing names the rest.

A ledger always has an api view. An api request never has
a ledger. That asymmetry is not a gap in any one format —
a request carries what one model needs in order to answer
once, and a ledger carries what happened and what it was
allowed to do.

So encoding is total, and loses whatever the target cannot
say. That is what makes it a projection, and the ledger it
came from still holds all of it.

How much of a ledger survives is the api's own affair rather
than the codec's care, and the three wire formats differ in
a way worth setting out, because it is the argument for the
grammar rather than an accident of it.

A call is answered by what the tool said and then by how it
went — 🧾, then 🟢 or 🚫. No api carries both halves:

```
                     the saying finished   how it went
openai-completions   —                     —
openai-responses     status                —
anthropic-messages   —                     is_error
```

Two records where every wire format has one field, and each
of them keeps a different half. That is why there are three
records and not one.

Thinking divides them the same way. Chat completions has no
field a 💭 could go out in at all. The other two do, and both
want it signed: a thought carries a 🔏 — a signature under
messages, an id and its encrypted content under responses,
written as a code span because it is data and never prose —
and a 💭 with no 🔏 is dropped rather than sent, because the
api refuses an unsigned one and a thought that arrived off
some other wire has no signature to give. So a reply that
thought before it answered can be replayed and believed.

The ledger holds all of it either way, which is the point of
a projection losing things.

`m8` is the one format whose view is the whole ledger. That
is why it is in the table at all.

A request says which model and everything to ask it for,
and never whose model it was. That is why parameters live
on the 🧠 rather than in a config keyed by a name the wire
never carries.

`parse` is the other direction, and the way in rather than a
filter, so it takes stdin exactly as it arrives. `encode` is about requests,
which are ledger-shaped; a response is turn-shaped, so it is
read into the records it adds to a ledger rather than into
one. With it, the whole loop is something you can watch
happen:

```bash
m8 ref :demo/mathy "Say hi." \
  | m8 encode openai-responses \
  | M8_PROVIDER_URL=http://127.0.0.1:8000/v1/responses m8 url-provider \
  | m8 parse openai-responses
```

* `url-provider` on its own knows no provider, so the
  endpoint is said in its environment.
* A header goes the same way, as `M8_PROVIDER_HEADER_*`.
  See [Providers](providers.md).

Reading is incremental whether or not the provider streamed.
A provider that writes everything at once is a stream of one
chunk, which is what lets streaming be something a provider
MAY do rather than MUST. Where an api has both a streamed and
a whole shape — chat completions changes shape, not just
delivery, when `stream` is set — the one that actually
arrived is the one that is read.

## Calling

```bash
m8 call PROG [ARGS]             a program from the environment
m8 call --no-wrap PROG [ARGS]   one that writes its own records
```

`call` runs a program and writes its answer as m8.

* It is how an ordinary program becomes a tool: a 🧰
  names it, or does the same job itself.
* A whole word naming a call variable becomes whole
  arguments. See [Commands That Want Flags](tools.md#commands-that-want-flags).
* Stdin is whatever `call` was given, so a program can
  read a pipe or reach the terminal.
* What a command may not do is not a flag here: a 🛡 is
  the process a command runs inside, so it is arranged
  around `call` rather than asked about within it.

```bash
__secures__="private airgap" m8 secure-shield secure bash -c "ls"
```

Output is m8: what the program writes becomes a 🧾
receipt, written as it arrives rather than gathered
up, and then 🟢 or 🚫 for how it ended. Both name the
call in `M8_CALL_ID`, when there is one.

`--no-wrap` passes what the program wrote through as
records, such as a 🔗 for files it hands over, and adds
the verdict. See [Handing Over Files](language.md#handing-over-files).

`--md` writes a 📜 rather than a 🧾, for a program whose
output is markdown. A model is handed either as text.

Because the receipt streams, a tool may write more
than there is memory to hold and m8 will not hold it.
A failure keeps the *last* 8K of what the program
complained about — the end is where a program says
why — and marks it `...` when there was more.

A 🛡 expands into a command such as `m8 secure-shield`. See [Shields](shields.md).

`munge` provides the file tools as `m8 munge read`,
`write` and `scan`.

```bash
m8 munge read [--pages RANGE] PATH
m8 munge write [--old TEXT] [--new TEXT] [--pages RANGE] PATH
m8 munge scan [--regex PATTERN] [--pages RANGE] [GLOB]
```

It is an ordinary command line: options, a word, and `--`
to end the options. A 🧰 reaches it through `m8 call`,
which is what turns a call's values into those flags.

A page is about 100 lines, every answer
says which pages it gave and how to ask for the next, and
nothing is ever asserted against a page. Precision lives in
the strings read out of one, so a page number that has
drifted still names the right part of the file.

What that buys is forgiveness with a receipt. A block is
matched down a ladder — indentation, then all whitespace,
then an argument whose escaping doubled in transport, then
a line number pasted on the front, then a quarter of a
block once its ends hold — and whatever was forgiven is
named in what comes back, because forgiveness nobody is
told about is how a near miss lands on the wrong code. A
block that matches twice is still refused: `pages` is how
a model says which one it meant, rather than pasting more
of the file around it.

`write` answers with its diff fenced as `diff`, which is
why a 🧰 runs it under `m8 call --md`: a terminal and
GitHub both colour it.

`scan` answers in the same terms, over the files a glob
names, with its own small regex engine — no captures, no
matching across lines, and linear time by construction
rather than by a timeout. `--page-lines` and
`--page-bytes` set the source-file page shape.

Scan has a second, distinct page coordinate: each result page
contains the complete matches from one source-file page. Adjacent
source pages are not merged, and a result group is never cut to fit
`--byte-cap`; an oversized group is returned whole. Use
`--pages` to select result pages, not the source pages
printed inside them. The cap is applied between result
pages, the first selected page is always retained, and the continuation
trailer is not counted.
