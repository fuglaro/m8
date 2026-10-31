# Commands

```bash
m8 [:MOB/AGENT[:|-|--] [-r] [-v] [-- PROMPT]]
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

* `:MOB/AGENT` sits where a command would as convenience shorthand for `say`.
  The launcher form puts `--` after the address and joins following words as
  the prompt. Explicit `say` takes one quoted prompt argument without a separator:
  `m8 say :demo/mathy "tell me"`.
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
  In launcher shorthand only, a separate `--` after the address introduces
  prompt words. Explicit `say` takes one quoted prompt argument directly.
* Compose the addressed run from filters when needed:
  `m8 say --no-send :demo/mathy "hi" | m8 send | m8 tag :demo/mathy`.
* Every agent belongs to one mob: `mobs/demo/mathy.md`. Agent definitions may
  nest, for example `mobs/demo/utils/mathy.md`, and path components cannot start
  with a period. `//` separates an authored agent path from a subchat path;
  `/+/TURN` names an immutable turn within either the main chat or a subchat.
  Authored definitions may include other mobs and resolve per file across
  layers. Chats and turns stay mob-local. See
  [Compose across layers](configs.md#compose-across-layers).
* A 🧠 with a leading `/` names a model rather than an agent, for example
  `/local/Bonsai-8B,max_output_tokens:8192`. Put it in an agent definition
  to give it an address and a chat. See [Models](configs.md#models).
* State is written to the selected mob's storage, not the nearest arbitrary
  config folder. See [Configs](configs.md).
* At a terminal, an address alone opens the configured UI. `say -r` renders
  and streams even when stdout is not a terminal. Ordinary filters write
  markdown; `m8 render` gives any document its rendered spelling.
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
In launcher shorthand, words after the address require `--`; in explicit
`say`, the prompt is one quoted argument. A prompt beginning with `--help` is
prose rather than help.

A page you asked for is written to stdout, where it can
be paged and piped. A page handed back instead of what
you asked for goes to stderr, where it cannot become part
of a document.

## Assembling

`say` reads an addressed conversation and an optional prompt. It reads stdin
only with `-i`, appending that prose after the prompt; otherwise stdin is
untouched. It does not infer m8 documents from stdin.

```bash
m8 say :demo/pagey "Summarize this:"
m8 say -i :demo/pagey "Summarize this:" <notes.txt
m8 say --no-send :demo/mathy | m8 encode openai-responses
```

With no prompt and no explicit input, an address at a terminal opens the
configured UI. By default this is riff, which submits each message with
`m8 say -r -v -i :MOB/AGENT`.

```json
{ "tui": ["m8", "riff", "m8", "say", "-r", "-v", "-i"] }
```

`-r` renders and streams even when stdout is not a terminal. A document follows
an address only when explicitly composed, for example with `say --no-send`
and `send`.

## Composing

Commands compose through stdin and stdout. Commands that take an address
resolve it themselves. `say` combines address resolution, optional prompt and
stdin prose, model execution, and chat advancement in one operation.

```bash
m8 say :demo/mathy "Tell me more."
m8 say -r -i :demo/mathy "Summarize this:" <notes.txt
m8 say --no-send :demo/mathy | m8 encode openai-responses
m8 say --answer --unwrap :demo/critic//job "Review that."
m8 watch :crew/cody//delegated
```

* `--no-send` emits the reference and optional submission without running or
  changing a chat.
* `--answer` selects a reply or question from this run; pair it with `--unwrap`
  for plain answer text.
* `-i` explicitly adds stdin as prose. Without it stdin is untouched.
* `--no-advance`, `--new`, and `--parent` control whether a run moves a chat and
  where it starts. Address suffixes provide the same starting choices; use
  `--chat` instead of a `//` suffix, never with an address suffix.

* `send` runs a ledger and writes the turn without keeping it.
* `tag :MOB/AGENT` keeps a turn and points the chat at it.
  * `--no-advance` keeps the turn and moves nothing.
* Promptless `say CHAT-` takes the chat's pointer away, so it reads as its
  parent again; `say --parent CHAT` is the equivalent spelling.
  * `say CHAT--` starts it from the authored agent, whatever its chats have got
    to; `say --new CHAT` is the equivalent spelling.
* `cat` reads a document and writes block markdown by default.
  * `--pack` writes each record on one physical line for shell filters.
  * `--unwrap` writes generic Markdown: record values become `# VALUE`
    headings, and content is unquoted.
* `render` writes a document in the rendered spelling, and
  `render -r` writes markdown back.
* `watch :MOB/AGENT` writes a chat out as it moves.
* `top :MOB/AGENT` writes a file's self-reference. See [Tops](language.md#tops).

A document follows an address by being written after it:

```bash
{ m8 say --no-send :demo/mathy; echo "* :brain::/local/tiny"; } | m8 send
{ m8 top :demo/tight-docs; m8 say --no-send :demo/mathy "Tidy the README."; } | m8 send
```

What `m8 :MOB/AGENT` writes ends on the 🧠 of the turn it kept.

Only the explicitly addressed chat moves. To resume it, name it again.

## Riffing

```bash
m8 riff CMD [ARGS]         an editor pinned under CMD's output
m8 :demo/mathy                  at a terminal: m8 riff m8 say -r -v -i :demo/mathy
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
  * While CMD runs, elapsed time appears at the bottom-right of
    the status area as minutes and seconds (for example, `0:56`),
    when CMD has not written status text yet or more than one status
    line is visible.
  * A nonzero exit remains `Stopped(N) and waiting ...` until
    the next message is dispatched. A signal uses its number.
* A stderr line that leads with `::stats::` carries a panel.
  * The panel is what follows, up to a `::` or the line's end.
  * It sits at the right end of the top status line, hard
    against the text, and stays until the next one. It takes
    priority over elapsed time when only one status line is visible.
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
m8 say --no-send :games/zork | m8 encode | m8 cast >zork.svg
m8 say --no-send :games/zork | m8 encode | m8 cast --size 100x30 --speed 40l,🤖60w >zork.svg
```

* A small build has it beside `m8` as `m8-cast`, since no
  session needs it. See [Building](building.md).
* Each 🙋 is typed into the editor and sent, and what follows
  arrives above it, as riff shows it.
  * Records before the first 🙋 are left out, as riff shows
    nothing until something is sent.
  * The editor grows with the message, keeping its line
    breaks, to half the terminal, then scrolls within, and
    is one row again once sent.
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
* `--skip-snips` leaves out what a turn kept aside: a `💭snip`,
  and the 🧠 naming where one went.
* `--static` draws it all at once instead, as tall as it is,
  with nothing moving.
  * A 🙋 at the end is left typed and unsent, in the editor or
    at the prompt.
* `--size` is the terminal, `80x24` unless said.
  * A line wider than it wraps, as a terminal wraps it.
* It is CSS and nothing else, so it plays wherever an image
  does.
  * It holds the last frame for 3 seconds and plays again.
  * Opened as a page of its own, holding the mouse down on
    it pauses it. As an image it cannot be pressed, so link
    the image to its raw file:
    `[![Zork](zork.svg)](https://raw.githubusercontent.com/OWNER/REPO/main/zork.svg)`.
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
m8 say --no-send :demo/mathy | m8 encode m8
m8 say --no-send :demo/mathy | m8 encode m8 >full-ledger-copy.md
```

```bash
m8 say --no-send :demo/mathy | m8 encode openai-completions
m8 encode openai-completions <full-ledger-copy.md >openai.json
```

`--break NAME` leaves a 🧠 naming NAME as it was written
rather than expanding it, so what comes out is the ledger
from there on.

```bash
m8 say --no-send :demo/mathy | m8 encode --break mathy/+/tduyxbutjb
m8 say --no-send :demo/mathy | m8 encode --break mathy     # the chat, without its agent
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
m8 say --no-send :demo/mathy "Say hi." \
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
m8 secure-shield "private airgap" bash -c "ls"
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
