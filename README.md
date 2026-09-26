
# mEight - The Composable Agentic Shell Harness

The command-line-first agentic harness - fully embracing the shell.

```
fuglaro@localhost> m8 @pagey 'One word -> do you like Haiku?'
▄ 🤖
│ Yes.

▄ 🧠pagey/=/swlyayqtjk
fuglaro@localhost> m8 @ 'Throw me a quick one please.'
▄ 🤖
│ Moonlight on still ponds
│ Crickets stitch the dark with song
│ Dawn waits behind hills

▄ 🧠pagey/=/psbarddrym
fuglaro@localhost>
```



This framework brings the power of agents to the shell,
rather than being limited to the other way around,
and is composable into full coding and agentic workflows.

It is fiercely opinionated on simplicity, modularity,
controllability, and composability, so it can be utterly
void of opinion on model, prompt, tool,
or agent structures. That is handed elegantly to
the user in structures that are easily crafted,
generated, shared, and provided as defaults.

Four things make it different:

* One format does four jobs. An agent definition, a
  transcript, the wire format, and the tool protocol
  are all the same grammar, so any of them can be
  written, piped, diffed, or edited by hand.
* The ledger is the truth. Records keep the order they
  happened in and nothing is dropped from them. Every
  api is a projection of it, and reordering, combining
  and forgetting are things a projection does — never
  something done to the ledger on the way past.
* Turns are files, and chats simply reference them.
  A `=/` folder holds immutable turns naming their
  parent, and a `+` is a movable reference into them.
  It is git's objects and refs, for conversations,
  on the filesystem.
* Tools are filters. A tool reads m8 and writes m8,
  and talks to the user on `/dev/tty`, so it stays
  in the pipeline even while it is interactive.

Where things are:

* **Why** — what m8 is for, and what has already been
  proved by somebody else.
* **Commands** — the command line, assembling a ledger,
  composing one pipeline from the commands, encoding,
  calling.
* **Language and Schema**, **Sigils**, **Types**,
  **Carrying the Call** — the format, in enough detail
  to write a parser from.
* **Shields** — what a tool runs inside.
* **Configs** — where agents, mobs, models and providers
  live.
* [docs/providers.md](docs/providers.md) — setting up
  oMLX, Anthropic and a ChatGPT plan.
* [src/zmachine/README.md](src/zmachine/README.md) — the
  seam between a virtual machine and a provider.

An mEight install will bring you a m8 in your terminal.

## Why

The conversation is the artifact. The harness, the
provider, the model, and whichever tool protocol won
this quarter are scaffolding around it. All of that is
replaceable. The conversation is not.

*File over app* (Steph Ango, 2023) puts it plainly: "if
you want to create digital artifacts that last, they
must be files you can control, in formats that are easy
to retrieve and read."

Agent harnesses do the opposite. The reasoning is the
valuable part, and they keep it as app state: a session
tree, a database row, a JSON blob, a record in
somebody's cloud. The most valuable thing you produce
is stored in the least durable place available.

m8 keeps a conversation as markdown files in a folder.
Everything else here follows from that.

### Ownership

You own the ledger, and nothing stands between you and
it.

The files are markdown. They open in `cat`, in any
editor, in any markdown viewer, on any machine, today.
They sit in a folder you chose. Git versions them
because they are text. `grep` searches them. `ls` lists
your conversations, because a conversation is a file.

There is nothing to export, no account to close, no
schema to reverse engineer. m8 does not hold your data.
It reads files and writes files.

The grammar is small so that stays true. A record is a
header line and one block quote beneath it. Sigils are
a closed set. Nothing nests and nothing interleaves.
Anyone can write a parser for it from this README, in
any language, in an afternoon. That is offered, not
conceded — a format worth adopting is one you could
implement yourself and choose not to.

### It is markdown, and it renders itself

A stored m8 document is markdown. Headers and block
quotes, with each sigil written as its gemoji
`:word:` shortcode — the table GitHub renders, and the
closest thing to a common convention across the systems
that substitute shortcodes at all. Typeable, greppable,
diffable, and rendered by anything that renders
markdown.

Shortcodes are not standardised; Unicode registers none.
Slack keeps its own older names and lacks two of ours,
`:robot:` and `:green_circle:`. Slack is not a render
target, and an unknown shortcode degrades to the text
that was typed, so nothing is lost that was not typed.

The emoji column is m8's own rendered form, and a
terminal gets it. One glyph per record kind, told apart
at a glance, with no renderer, no colour and no pager.
Nothing has to pretty-print m8, because m8 already
looks like that.

The rendered form is still m8. Pipe it back in and it
parses. Both spellings are accepted everywhere a sigil
is accepted and they mean the same thing, so neither is
a lossy view of the other and either can be asked for.

Every other harness renders a transcript into something
it cannot read back. The readable output is a dead end
and the real record lives elsewhere, in a format meant
for machines. Here the readable output is the record.

### The formats were always one

An agent definition, a transcript, a wire request, a
tool exchange and a permission policy are one sequence
of records seen at five moments. A definition is a
ledger nobody has answered yet. A transcript is one that
has been. A request is that ledger projected onto what a
model can be told. A call and its answer are records in
it like any other. A 🛡 is a record as well, written in
the agent or the 🧰 it restricts.

Keeping them apart costs a parser each. A template
language turns config into a prompt. A serialiser turns
history into a request. An adapter turns the response
back into history. A schema dialect describes tools and
matches none of the other three. A policy file says what
a tool may do, in a dialect of its own, and none of the
other four ever reads it. Five things to learn, five to
version, five places to lose something.

One grammar removes all of that. What is left can be
piped, diffed, hand-edited, committed, mailed and
replayed, because those are things you do to a file.

### Neutrality is the feature

m8 is opinionated about form and holds no opinion at
all about model, prompt, tool or agent structure. That
is the strategy, not a gap in it.

A provider is a command. A tool is a filter. A skill is
`SKILL.md`. A tool schema comes from MCP's. m8 does not
compete with any of those layers, so no layer's decline
is its own. When a tool protocol is replaced, m8 renders
the new one. When an api changes shape, that is a codec.
When a vendor goes away, every ledger written against it
still opens.

Provider abstraction is the most rebuilt code in the
field, so m8 does not have one. A provider is a command
that reads a request and writes a response.
`core/providers.json` is the whole of the configuration,
and reaching a url is one such command rather than the
privileged path.

Form is the part that has to outlast everything else,
and form is the only part m8 insists on.

### Capability is composition

Features do not arrive here through a plugin api. A tool
is a program that reads m8 and writes m8. A provider is
a program that reads a request and writes a response. So
what m8 can do is what your machine can run, and that
was true on the first day.

The proof is already in the tree. `m8
@/toy/Z-Machine/zork1` holds a conversation with a
1979 Infocom story file, through the same ledger, the
same records and the same forking as any model. m8 needs
no concept of a game. The chat is the save file and
forking a chat forks the world, because that is what a
ledger of files already is.

A format that takes a virtual machine from 1979 in a
model's seat will take whatever the api looks like next
year.

### What a distribution gets

* MIT.
* One binary from `zig build`, or a program per command
  from `zig build split` — the same sources either way,
  and below. `build.zig.zon` declares no dependencies.
  Nothing vendored, nothing fetched at build time, no
  libcurl, no OpenSSL, nothing to CVE-track that is not
  the toolchain.
* No daemon, no database, no account, no telemetry, no
  bundled weights, and no network needed to build or
  test. `toy` answers locally, so the loop, tool
  calling and recovery are all testable offline.
* Config under XDG. stdin in, stdout out, errors to
  stderr, `--help` answered in one place.
* Everything it stores is text you could have typed.

That is the shape of a package a distribution carries
for thirty years, because it is the shape of `grep` and
`jq`. Single-binary agent runtimes exist. Single-binary
agent runtimes whose entire state is files you can read
do not.

### One registry, two builds

Composable is a claim about the command line, and it is
cheap to make while every command is one binary calling
itself. So m8 builds both ways from one registry, and
the split set is the guardrail rather than the
optimisation.

* `zig build` is the single binary. A launcher reaching
  a command calls it.
* `zig build split` is a program per command — `m8-cat` and
  `m8-call-munge-read` — plus a launcher. Prompt mode, selected by
  `--` or by a bare `m8`, is launcher syntax; commands are spawned.

The difference is one comptime branch. What a launcher
reads is a command's *spec* — its name, what it takes,
and whether its arguments are prose — and a spec holds
no function pointer, so a launcher knows every command
without carrying one. The whole registry costs it two
kilobytes.

A command that reaches into another command's module
still compiles. It shows up in the split set, as a leaf
that is suddenly carrying a stack it has no business
carrying — so the sizes in `zig-out/bin` are a reading
of the architecture. Most commands sit within a few
kilobytes of a hello-world against this std, and the
ones that do not say why: TLS is in the command that
posts to a url, the codecs are in the ones that speak to
a model, and a nested agent turn is in the shield that
asks one.

Nothing about the command line changes between the two,
and a distribution picks by what it is packaging rather
than by what it gets. Symlink `m8-cat` to the single
binary and it *is* `m8-cat`, the way busybox is: same
output, same status, so the uber download and the split
package behave alike.

### The field

Surveyed August 2026. Every piece of this has been
proved by somebody. None of them put the pieces in the
same place.

* [gptel](https://gptel.org/) proved the file *is* the
  conversation: save it, reopen it, resume it, edit a
  past turn by hand. It stops at Emacs, and at defining
  the agent somewhere the transcript is not.
* [llm-md](https://codeberg.org/anuna/llm-md) proved
  conversations pipe. Then it added `>>>`/`>>=`/`=>>`/
  `!>>` operators, `{{@tool:op $ args}}` interpolation,
  variables and control flow, and became a template
  language. m8 stays a record format on purpose.
* [simonw/llm](https://github.com/simonw/llm) proved the
  unix shape: piping, fragments, templates, `-c` to
  continue, and a large plugin ecosystem. All of it
  lands in SQLite. It is the closest neighbour and the
  clearest fork in the road.
* [aichat](https://github.com/sigoden/aichat) and
  [llm-functions](https://github.com/sigoden/llm-functions)
  proved a tool is just a script. That is 🧰.
* [Pi](https://pi.dev/) proved a harness can win by
  exclusion: no MCP, no subagents, no plan mode, no
  permission popups. Its sessions are still internal
  state nobody is meant to read. Its exclusion list is
  the closest thing to an independent review of this
  taste, and worth reading before anything is added.
* [Prompty](https://prompty.ai/core-concepts/file-format/),
  [dotprompt](https://github.com/google/dotprompt) and
  [POML](https://github.com/microsoft/poml) proved a
  prompt belongs in a plaintext file, then wrapped it in
  frontmatter and a template language and loaded it from
  a library. None of them is a transcript.
* [Letta `.af`](https://github.com/letta-ai/agent-file)
  proved people want the agent as a portable file. It
  ships one as a JSON state blob nobody writes by hand.
* [KrillClaw](https://github.com/krillclaw/KrillClaw),
  NullClaw and [Talu](https://github.com/aprxi/talu)
  proved Zig, one binary, no dependencies and sub-10ms
  boot. Conventional runtimes inside. No claim on form.
* [CTK](https://github.com/queelius/ctk), Forky and
  GitChat proved conversations are trees worth forking
  and grafting. Each does it in a database or an app.
  `=` and `+` do it in a directory, where `ls` and `cat`
  already work: git's object and ref split, applied to
  conversations.

Three things are settled, and m8 joins them rather than
relitigating them.

* [`SKILL.md`](https://anomity.ai/blog/agent-skills-open-standard-adoption-governance/)
  went open standard in December 2025 and had 16+
  adopters by March 2026. A skill is a folder with
  frontmatter, and a mob is already a folder.
* The [2026-07-28 MCP spec](https://blog.modelcontextprotocol.io/posts/2026-07-28/)
  took tool schemas to full JSON Schema 2020-12, and MCP
  went to the Linux Foundation, so 🧰 is generated from
  an MCP server rather than authored against one. Worth
  doing for its own sake as well: one study measured MCP
  integration inflating input tokens
  [236x while dropping accuracy 9.5%](https://arxiv.org/html/2508.12566v1),
  so rendering those tools into something terse is a
  contribution.
* Forking shipped in a mass-market product in June 2026,
  which makes branching table stakes rather than a
  differentiator. It is still a menu command over state
  you cannot open.

## Commands

```bash
m8 [@ADDRESS[:|-] [WHATEVER YOU WANT TO SAY]]
m8 COMMAND [ARGS]
```

```bash
m8 @mathy "Tell me about the Riemann Sphere\nin detail."
m8 @ "Tell me more."
m8 @mathy/aside "And what about the Möbius strip?"
```

```bash
echo "Tell me about the Riemann Sphere\nin detail." | m8 @mathy
```
```
▄ 🤖
│ The Riemann Sphere is a ...

▄ 🧠mathy/=/tduyxbutjb
```

The reply went to a tty, so it is rendered. The turn
it saved is a file, so it is markdown:

```bash
cat ".m8-st8/@/mathy/=/tduyxbutjb.md"
```
```
#### :brain:mathy

#### :raising_hand:
> Tell me about the Riemann Sphere
> in detail.

#### :robot:
> The Riemann Sphere is a ...
```

```bash
m8 @mathy/=/tduyxbutjb "Tell me more."
```
```
▄ 🤖
│ Additionally,
│ ...

▄ 🧠mathy/=/ypfpkuimzg
```

* `@` sits where a command would, and is not one. The
  words after it are prose, joined with a space, so
  nothing has to arbitrate between m8's arguments and
  yours.
* A bare `m8` is `m8 @`, the main chat — whichever chat
  was talked to last.
* An address is a chat, a turn or a model:
  ```
  @                   the main chat
  @mathy              mathy's own chat
  @mathy/aside        a chat under it, as deep as chats go
  @mathy/=/tduyxbutjb a turn
  @/local/tiny        a model
  ```
* `:brain:` and 🧠 mark an address as well as `@` does,
  so a 🧠 line pasted back in names what it printed.
* A trailing `:` asks without moving anything, which is
  what a side question is. A trailing `-` resets a chat,
  which then reads as its parent again; only a chat has
  a parent to go back to.
* It is a pipeline written once. `m8 @mathy hi` is
  `echo hi | m8 cat @mathy | m8 send | m8 tag @mathy`,
  except that the reply is shown as it arrives. See
  Composing.
* What an address reads as is appended as the 🧠 it
  settles on — the turn a chat has got to, never the
  chat — so a saved turn names its parent instead of
  copying it, and never names something that moves.
  Expanding happens in whichever command needs it.
* 🧠 names an agent, and naming one is how you use it.
  Agents are identified by their file under `@/`, so
  nothing declares its own name. `@` is how the command
  line names one; it is not part of the language.
* Names are paths and the folder part is the mob. See
  Mobs.
* 🧠 names an agent, unless it is written with a leading `/`,
  which names a model: `/local/Bonsai-8B,max_tokens:8192`.
  The mark is the whole of the distinction — nothing is looked
  up to decide it — so a name that is missing is a missing
  agent rather than a model nobody configured. On the command
  line that is `m8 @/local/Bonsai-8B`. See Models.
* Saving is to the nearest existing m8 config folder.
* If a tty is connected, interactive mode is activated,
  which streams tokens without buffering and renders
  the reply. Everything else is written as markdown.
* A first word that is not an address names a command.

Every command has a page, and anything under a command
has one too:

```bash
m8 help                    every command, and what m8 reads
m8 help send               one of them
m8 send --help             the same page
m8 help providers url      what is under one
m8 providers url --help    the same page again
m8 help @                  what an address is
```

`--help` is m8's rather than any command's, so no command
has to parse it and no two answer it differently. The words
after an `@` are prose, so a `--help` among them is said
rather than read, and `m8 help @` is how that page is asked
for.

A page you asked for is written to stdout, where it can
be paged and piped. A page handed back instead of what
you asked for goes to stderr, where it cannot become part
of a document.

### Assembling

`m8 @ADDRESS` and `m8 cat @ADDRESS` build a ledger from
three things: what the address reads as, whatever was
piped in, and the prompt, in that order.

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
cat notes.txt | m8 @ "Summarize:"               # one 🙋, prompt first
echo "#### :brain:/local/tiny" | m8 @mathy "Quickly?"
m8 top @tight-docs | m8 @mathy "Tidy the README."
```

Piping is not required, and neither is a prompt when
something was piped. With neither, there is nothing to
say, and m8 says so.

A document is told from prose by its first line alone,
so one that opens like a document and then goes wrong is
an error rather than a prompt.

### Composing

Every command reads stdin and writes stdout, and the
ones that take an address resolve it themselves. So
what `m8 @` does is a pipeline too, and each step can be
had on its own:

```bash
m8 cat @mathy | m8 send | m8 tag @mathy      what m8 @mathy does
m8 cat @mathy | m8 tag @mathy/aside          fork, with nothing said
m8 cat @ | m8 send | m8 tag @mathy/other     keep a run somewhere else
m8 cat @ | m8 encode m8 | m8 save @notes     a chat, flattened into an agent
m8 @mathy hi | m8 ref | m8 @critic "Review that."
```

* `cat @X` writes the 🧠 that X reads as now, then
  whatever was piped in. It names the turn rather than
  the chat, so it is a snapshot that stays put when the
  chat moves on.
* `send` runs a ledger and writes the turn: the ledger
  as it arrived and whatever the run added. It keeps
  nothing, so one run can be kept wherever it is
  tagged, or nowhere.
* `tag @X` keeps a turn and points X at it. A document
  that is one 🧠 already names a turn and is pointed at
  without writing anything; anything else is kept as a
  new turn. Its output is the 🧠 now pointed at, and
  nothing else — a ref was written, and that is its
  receipt.
* `save @X` writes a document as an agent, over whatever
  was there. An agent is authored, so changing one from a
  pipe is the same as editing its file.
* `top @X` is `cat`'s twin for 📚: it names a file for
  what it says about itself. See Tops.
* `ref` keeps the 🧠 a document ends on, and nothing
  else. `m8 @X` writes the reply and then that 🧠, which
  is what a person reads; `ref` is how it becomes what
  the next command is handed. A turn `send` wrote was
  never kept and ends on no 🧠, so it has nothing to
  reference until it is tagged.

Forking a chat is naming somewhere else to tag, and
nothing more.

### Encoding

```bash
m8 encode FORMAT                   a ledger, as some api sees it
m8 decode FORMAT [PROVIDER]        that api's request, as a ledger
m8 parse FORMAT                    that api's response, as a turn
m8 send                            run a ledger and write the turn
```

There are four:

* `m8` — the language itself, so encoding is writing it
  out and decoding loses nothing.
* `openai-completions` — OpenAI chat completions, and the
  many servers that answer in its shape.
* `anthropic-messages` — Anthropic's messages api, which
  is where Claude answers.
* `openai-responses` — OpenAI's responses api, which is
  where Codex and a ChatGPT plan answer.

`m8 encode --help` is the same list, and any provider may
name any of them.

`m8` is a format like any other here, so `encode m8` is
how a chat becomes one flat document.

```bash
m8 cat @mathy | m8 encode m8
m8 cat @mathy | m8 encode m8 >full-ledger-copy.md
m8 decode m8 <full-ledger-copy.md      # the null operation
```

```bash
m8 cat @mathy | m8 encode openai-completions
m8 encode openai-completions <full-ledger-copy.md >openai.json
m8 decode openai-completions <openai.json
```

```bash
m8 decode openai-completions local <openai.json | m8 send
```

A ledger always has an api view. An api request never has
a ledger. That asymmetry is not a gap in any one format —
a request carries what one model needs in order to answer
once, and a ledger carries what happened and what it was
allowed to do.

So encoding is total, and loses whatever the target cannot
say. That is what makes it a projection, and the ledger it
came from still holds all of it.

Decoding is partial, and hands back something ledger-shaped
rather than the ledger. A tool comes back without its command or
its 🛡 — a model call has no business carrying either, so
their absence on the way home is that rule holding rather
than a corner missed. A tool read back is an interface, and
calling one answers with 🚫 rather than running something
nobody sent.

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
messages, an id and its encrypted content under responses —
and a 💭 with no 🔏 is dropped rather than sent, because the
api refuses an unsigned one and a thought that arrived off
some other wire has no signature to give. So a reply that
thought before it answered can be replayed and believed.

The ledger holds all of it either way, which is the point of
a projection losing things.

`m8` is the one format whose view is the whole ledger. That
is why it is in the table at all, and why `decode m8`
approximates nothing.

What a request does carry, it carries exactly. A request
says which model and everything to ask it for, and never
whose model it was — so `openai-completions → m8 →
openai-completions` is the same request, byte for byte, and
all it is missing is the provider. `decode` is where that
went missing, so `decode FORMAT PROVIDER` is where it is
said, and what comes out runs as it is. That is why
parameters live on the 🧠 rather than in a config keyed by
a name the wire never carries.

`decode` and `parse` are the way in rather than filters, so
they take stdin exactly as it arrives.

`parse` is the third direction. `encode` and `decode` are
about requests, which are ledger-shaped; a response is
turn-shaped, so it is not decoded into a ledger but read
into the records it adds to one. With it, the whole loop is
something you can watch happen:

```bash
echo "Say hi." | m8 cat @mathy \
  | m8 encode openai-completions \
  | m8 providers url \
  | m8 parse openai-completions
```

Reading is incremental whether or not the provider streamed.
A provider that writes everything at once is a stream of one
chunk, which is what lets streaming be something a provider
MAY do rather than MUST. Where an api has both a streamed and
a whole shape — chat completions changes shape, not just
delivery, when `stream` is set — the one that actually
arrived is the one that is read.

### Calling

```bash
m8 call NAME [ARGS]     a m8 command
m8 call -- PROG [ARGS]  a program from the environment
```

`call` is what a 🧰 expands into. What a command may not
do is not a flag here: a 🛡 is the process a command
runs inside, so it is arranged around `call` rather
than asked about within it.

```bash
m8 shield secure "private airgap" -- bash -c "ls"
```

Output is m8: what the program writes becomes a 🧾
receipt, written as it arrives rather than gathered
up, and then 🟢 or 🚫 for how it ended. `--raw` hands
stdout straight through instead.

Because the receipt streams, a tool may write more
than there is memory to hold and m8 will not hold it.
A failure keeps the *last* 8K of what the program
complained about — the end is where a program says
why — and marks it `...` when there was more.

`m8 shield` is what a 🛡 expands into. See Shields.

`call` also reaches m8's own filters and its inbuilt
tools, which is what `m8 call ask` is: a tool that puts
a question to the person and appends their answer to the
document, so the next command in the pipe sees it. An
inbuilt tool is never typed as a command of its own.

`munge` provides the file tools as `m8 call munge read`,
`write` and `scan`. A page is about 100 lines, every answer
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

`scan` answers in the same terms, over the files a glob
names, with its own small regex engine — no captures, no
matching across lines, and linear time by construction
rather than by a timeout. `M8_ARG_PAGE_LINES` and
`M8_ARG_PAGE_BYTES` set the source-file page shape.

Scan has a second, distinct page coordinate: each result page
contains the complete matches from one source-file page. Adjacent
source pages are not merged, and a result group is never cut to fit
`M8_ARG_BYTE_CAP`; an oversized group is returned whole. Use
`M8_ARG_PAGES` to select result pages, not the source pages
printed inside them. `BYTE_CAP` is applied between result
pages, the first selected page is always retained, and the continuation
trailer is not counted.

## Language and Schema

Agent definition:

```m8
▄ 🧠Address, Agent Name or Model

▄ 🧰Tool Name
│ │ Tool Description
│ 🛡️Shield Name
│ `m8` `call` `args` `cmd` `{{M8_ARG_PROPERTYNAME|--flag}}`
│ * PropertyName string
│   Property Description
│ * Other? integer
│   Optional, so ? on the name

▄ 🧰Tool Name,m8
│ │ Answers in m8 rather than text.
│ ```bash
│ echo "$M8_ARG_PROPERTYNAME"
│ ```
│ * PropertyName celsius|fahrenheit
│   An enum is its values, which may hold a space
│ * PropertyName string[]
│   Arrays suffix []
│ * ParentName object
│   Mandatory Parent Def
│ * ParentName.PropertyName integer
│   Nested

▄ 🧰Tool Name

▄ 🛡️Shield Name

▄ 🧭
│ System Prompt
│ A record is a header and a content block, and
│ content is verbatim, so this line may begin with
│ anything at all.
│ A , separates a fixed number of fields, so the
│ last field may hold one safely.

▄ 🧭
│ Included Agents inject Tools and System
│ Prompts.
```

Query:

```m8
▄ 🧠Agent or Model Name

▄ 🙋
│ User Content Text

▄ 💭
│ Assistant Thoughts
│ 🔏Optional Signature

▄ 🤖
│ Assistant Content Text

▄ 📲Called Tool Name,Call ID

▄ 🚫Call ID
│ Error response

▄ 📲Called Tool Name,Call ID
│ * Argument Name `value`
│ * Argument Name
│ * Argument Name
│   ```
│   a value over
│   more than one line
│   ```

▄ 🧾Call ID
│ Response

▄ 🟢Call ID
```

A call is answered by what the tool said and then by
how it went. 🧾 is the saying, and it is written while
the tool is still speaking; 🟢 and 🚫 are the verdict,
which nothing can know until it stops.

That order is the reason there are three. A record
names its kind on its first line, so a single record
meaning "it worked, and here is what it said" cannot
be started until the program has finished — which is
to say the output would have to be held in full,
however large it is, so that the first line could be
written last. Splitting the verdict off is what lets
the answer be written as it arrives.

A tool that says nothing is answered by its verdict
alone. 🧾 without a verdict under it is a tool that
spoke and was cut off; it still answers the call,
because running it again to find out how it would
have ended would do whatever it does a second time.

What a call supplies is a bullet per argument: the name,
then the value beside it as a code span. Only a value
over more than one line needs a block underneath,
indented under its bullet. The closing fence is what
ends it, so the newline before that fence is framing
rather than something the value said — which is how a
value that really does end in one is written as a blank
line before the close.

The empty string is the name with nothing after it at
all: no span, no block. Models hand an optional argument
an empty string rather than leave it out, often enough
that the block spelling would cost three lines of
document to say nothing. An empty block still reads as
the empty string, so a model that writes one is
understood either way.

Neither form escapes anything, and neither has to.
Backticks are CommonMark's, so a span opens with a run
longer than any run inside it and a fence with one at
least as long as anything it holds:

```
`` ` ``      a value that is one backtick
``a`b``      a run ends at a run of its own length
`  a  `      one space each side is framing, and only one
```

That last rule is what lets a span start or end with a
backtick at all, and it costs a value that begins and
ends with a space an extra one at each end. A value that
is nothing but spaces is left alone, or a single space
would have no spelling.

So a human reads the value and not an escaped copy of
it, and what m8 reads is what the thing rendering the
document shows. That is the whole reason for taking
CommonMark's rule rather than a simpler one: the moment
they differ, a document says one thing to a person and
another to m8.

Simple example query with definition:

```m8
▄ 🧠/local/Ternary-Bonsai-8B-mlx-2bit,max_tokens:8192

▄ 🧭
│ You are a mathematics expert that will answer questions,
│ give insight, and advise on any relevant technique.
│ Describe concepts with analogies and spatial models
│ that can be imagined by a human and include how it relates
│ to the components, equations, and relationships in
│ the mathematical equations.

▄ 🙋
│ Tell me about the Riemann Sphere in detail.
```

System Prompt is stable by design.
Volatile data such as the time or when reading
files, should be put into the query,
with user content text or a user added tool request.
📚Skills can also be included, which are predefined
sections of query, including tool requests to be invoked,
and which are referenceable by name.

A record is a header line and at most one content
block. The header is a sigil and its value; the
content is the block quoted beneath it. That is the
whole of the harness. Content never nests further
and records never interleave.

Exactly one space follows the quote and is stripped,
so content is verbatim and a line that looks like a
record is only a line. Missing that space is an
error. A bare quote with no space is an empty
content line. A fully blank line closes the block,
and one is required between records.

Sigils are a closed set, written as one codepoint
within U+1F300 to U+1FAFF or as `:word:`. An unknown
sigil in either spelling is an error.

An emoji sigil may be followed by presentation
modifiers — a variation selector, a skin tone, or a
joiner binding another codepoint into the glyph — and
they belong to the sigil, not to the value behind it.
A renderer adds them without being asked: Slack shows
🙋 as 🙋‍♀️. Text pasted back from one still reads as
the sigil it looks like.

A `,` separates a fixed number of fields, so the
last field may hold one safely. What a content block
means is decided by the sigil above it.

A \r immediately before a \n is stripped, exactly
one, so \r\r\n ends content in a literal \r.

## Sigils

Every sigil has two spellings, an emoji and a plain
one. Both are accepted anywhere a sigil is accepted
and they mean the same thing. Output is emoji by
default, and either form can be asked for.

The emoji is the default because a tool's output is
the language itself. The raw bytes are what a human
reads, so a column of emoji down the left edge is
the formatting. One glyph per record kind, told
apart at a glance, with no renderer, no colour and
no pager. Nothing needs to pretty-print m8 because
m8 already looks like that.

The plain form exists to ease typing from scratch.
The one real cost is paid at the keyboard,
and so it is answered at the keyboard
rather than by giving up the display.

The two spellings never mix. A document is `m8` or
it is `m8.md`, decided by its first line and held
for the rest of it, and a line in the other spelling
is an error. Files and piped streams are `m8.md`,
which is also valid markdown, so anything that
renders markdown renders them. A tty gets `m8`.

* ▄ header -> `####`
* │ content -> `>`
* 🧠 agent -> `:brain:`
* 🙋 user -> `:raising_hand:`
* 🤖 bot -> `:robot:`
* 💭 thinking -> `:thought_balloon:`
  * 🔏 signature -> `:lock_with_ink_pen:`
* 📲 call -> `:calling:`
* 🧾 result -> `:receipt:`
* 🟢 ok -> `:green_circle:`
* 🚫 failed -> `:no_entry_sign:`
* 📚 skill -> `:books:`
* 🔝 top -> `:top:`
* 🧭 system -> `:compass:`
* 🛡️ shield -> `:shield:`
* 🏃 runner -> `:runner:`
* 🧰 tool -> `:toolbox:`

A sigil takes a value, a content block, or both — or, for the
one that is a fence rather than a record, neither. 🧰 has three
separate header forms: a content-bearing header defines a tool, a
blockless header with a variable and values configures that tool,
and a bare blockless header offers it. A definition header may not
combine content and variable configuration.

* Value only: 🧠 📚 🔏 🟢
* Content only: 🙋 🤖 💭 🧭
* Both: 🧰 📲 🧾 🚫 🛡️ 🏃
* Neither: 🔝

### Tops

A file may open with a 🔝 and close it with a second one.
What is between them is that file's top: what it says
about itself, rather than what it says.

```m8
▄ 🔝

▄ 🧭
│ Load tight-docs when working on documentation.

▄ 🔝

▄ 🧭
│ Keep every doc comment to one line.
```

Two sigils reach into another file and the mark decides
which half comes back. 🧠 wants what the file says; 📚
wants what it says about itself. On the command line
those are `m8 cat @` and `m8 top @`.

A file with no 🔝 is all body and has no top at all, so
📚 naming one yields nothing rather than the whole of
it. There is no advertisement, so nothing is advertised.

The fence is why it is two sigils and not one closing
delimiter: a reader knows which half it is in from the
first record rather than from the end of the file, so a
top is read without holding a body nobody asked for.
One 🔝 that nothing closes is an error, and so is one
anywhere but at the head.

The mark decides at every reference rather than being
inherited, so a top may advertise what it builds on and
a body may pull in a skill's advertisement. Neither
drags in the other, and a 🔝 never reaches a ledger.

## Types

An argument is a bullet: `* NAME TYPE`, and its
description on the lines indented under it. The name
runs to the first space and the type to the first comma,
so the last field may hold one safely and an enum keeps
whatever spaces its values have.

A type is JSON Schema's own and goes to the wire exactly
as it is written, so it is lowercase: `string`, `number`,
`integer`, `boolean`, `object`. There is no keyword for an
enum — a type holding a `|` is one, and its values are what
it lists.

Anything else JSON Schema says goes after the type as
`,key:value` extras — `* limit integer,minimum:0` — split
and read the way a 🧠's parameters are, so a value may be
JSON with commas of its own. m8 has no vocabulary for
them and checks none of it, a type included: a mistake
is found at the provider.

Type rules compose, so `Type[]` covers `object[]`.

* An array `[]` suffix applies to the whole field, and
  arrayness lives only on the parent type — children use
  plain dots.
* Enum values cannot contain a `|` or a `,`.
* Extras go on the outermost node, so an array's are the
  array's own; a key for its items is written as
  `items:{...}`.
* An extra sharing a key m8 writes itself, such as
  `description` over the lines under the bullet, stays in
  the ledger but loses on the wire: m8's own codecs send
  one key, and it is m8's.
* Nesting is flat dotted paths, and parents are always
  declared, never inferred.
* Optionality is a `?` on the name and applies at every
  depth, so an optional object with required children is
  either absent or complete.

There is no oneOf. A discriminator enum with optional
fields constrains better, and lets the tool return a real
error instead of a schema rejection.

## Carrying the Call

What a call said reaches its tool in the environment,
and nowhere else. A tool written as an argv is the words
it was written as, one written as a fenced block is the
script it was written as, and m8 hands either to its
command unchanged.

```m8
▄ 🧰search
│ │ Look for something.
│ ```bash
│ grep -r "$M8_ARG_PATTERN" .
│ ```
│ * pattern string
│   what to look for
```

What a tool is handed:

* `M8_ARG_<NAME>` per scalar, the name uppercased, when
  it is already a portable identifier.
* `M8_ARGS`, always, carrying the whole call as JSON.
  Anything nested, dotted or arrayed has no env spelling
  of its own and lives here rather than in a mangled
  variable that might collide.
* `M8_CALL_ID`, which call this is.

An argument that was not supplied is unset rather than
empty, which is the whole of what optional means to
whatever reads it. A required one that is missing is
refused before a command is built at all.

### Commands That Want Flags

A shell reads its environment. `curl` and `git` do not,
and turning variables back into flags for them is a
command's own business rather than the framework's.
`m8 call args` is the one m8 ships for it.

```m8
▄ 🧰bash
│ │ Run a bash command.
│ `m8` `call` `args` `bash` `-euo` `pipefail` `{{M8_ARG_COMMAND|-c}}`
│ * command string
│   The bash command to run.
```

Given `M8_ARG_COMMAND=echo hi`:

```
{{M8_ARG_COMMAND}}       --command "echo hi"
{{M8_ARG_COMMAND|-c}}    -c "echo hi"
{{M8_ARG_COMMAND|}}      "echo hi"
{{M8_ARG_DEEP?--deep}}   --deep, when the value is exactly true
{{M8_ARGS}}              the whole call as JSON, one argument
```

The flag a bare placeholder carries is the argument's
own name, which is what the variable was made from in
the first place. `M8_ARGS` is the call rather than an
argument, and stands alone.

A placeholder is a whole argument and is never spliced
into a larger one, so a value cannot become syntax in
what runs.

### Definition variables

A tool definition can supply fixed environment values without
putting them on the definition header. Each value gets its own
blockless header, and a final bare header offers the tool:

```m8
▄ 🧰read
│ │ Read a file or directory.
│ `m8` `call` `munge` `read`
│ * path string

▄ 🧰read PAGE_LINES 100
▄ 🧰read PAGE_BYTES 10000
▄ 🧰read BYTE_CAP 20000
▄ 🧰read
```

Definition variables and call parameters share the `M8_ARG_*`
namespace. If both provide the same name, their values are joined
with a space, with definition values first and call values last.
Shields use the same convention, so a shield's definition values
also reach the tool under `M8_ARG_*` and participate in that merge.

The three toolbox header forms are intentionally separate: content
defines, a variable header configures, and a bare header offers.
This keeps a definition readable when it has several defaults.


* An unset variable leaves nothing behind. An empty one
  is a value a command was given, and is passed as an
  empty argument.
* Only `?` reads a value: `true` emits the flag, `false`
  emits nothing, and anything else is an error naming
  what arrived, because a call that looked like it
  succeeded while ignoring what was asked is worse than
  one that failed.
* Only a word opening `{{M8_ARG` is looked at, so the
  braces a templating language meant for itself survive
  — `m8 call args awk '{{print $1}}' f` runs the awk
  program it was handed.

None of this is privileged. An argv is passed on as it
was written, so a toolbox naming some other expander
works the same way, and deleting `args` leaves the
framework whole.

## Shields

A shield is not a program that decides to restrict a
tool. It is the process the tool runs inside, so it
holds exactly the tool's authority and there is no
operation available to it for restoring a capability
its own parent lacked. Widening is not declined here;
it is unsayable. That is the same argument a provider
rests on, one level further down.

Everything follows from it. Restriction is
intersection, so the permitted set is the same however
the wrappers stack and a repeat means nothing. A second
definition of a name adds another wrapper rather than
replacing one, so a mob you have not read can tighten
what it was given and can never un-define it.

```bash
m8 shield secure "private airgap" -- bash -c "ls"
```

### Defining and activating

With a block it defines; with a value alone it
activates.

```m8
▄ 🛡️deny
│ `false`

▄ 🛡️deny                   now it is on
```

A definition body holds a command spelled out in
backticks, a fenced block in some language, or another
🛡 to stand inside. Any of them may repeat, and all of
them stack.

```m8
▄ 🏃bash
│ `bash` `-c` `{{CODE}}` `bash`

▄ 🛡️secure
│ ```bash
│ exec {{M8}} shield secure "${M8_ARG_SECURES}" -- "$@"
│ ```
```

A 🏃 is what makes a block runnable: an argv with
`{{CODE}}` in it. It must be defined before a block
names it, so a document reads in one pass, and defining
one twice is an error rather than a question.

Every wrapper is handed the command it wraps as
arguments, and two spellings say "the m8 that is
running", because a wrapper is m8 two different ways.

* A wrapper whose first word is `m8` *is* an m8 command,
  and that word becomes this m8's path. `🛡️ask` is
  `` `m8` `shield` `ask` `--` `` and nothing else.
* A wrapper that mentions m8 inside a word says `{{M8}}`
  and that becomes the path. A script is bytes m8 does
  not read, so a pipe through `m8 filter` needs somewhere
  to write where m8 is.

Said in the argv either way, so the path reaches the
wrapper that asked for it rather than every process
underneath. The tool's own argv is untouched: it is not
a wrapper.

Nothing inserts an argv0 for you. `bash -c` binds `$0`
to the first argument after the script, which is why
these are written `"$0" "$@"` and why m8 does not try
to know that on your behalf. A shield author is
trusted, exactly as a tool author is.

### Activation order

Activation order is wrapping order, and the first is
furthest out. It decides nothing about what is
permitted — intersection does not care — and everything
about what a person is shown, which is why `ask` is
worth activating last: innermost, it asks about the
bare command rather than about a stack of prefixes.

### Where a shield is written

```m8
▄ 🛡️jail                   the floor for this agent

▄ 🧰deploy
│ 🛡️airgap                 and this tool as well
```

* **Top level**, in an agent. Cumulative over the
  lineage, and inclusion can only tighten.
* **In a 🧰**, for one tool, on top of the floor.

There is no third place and no flag. A shield is written
down where it applies, so what a run may not do is a
fact about the agent rather than about how it was
invoked.

### What m8 ships

`core/shields.md` is an ordinary m8 document, read from
your own config or from the copy m8 carries. What
`jail` means is a composition you can read:

```m8
▄ 🛡️sandbox
│ 🛡️freeze-toolbox
│ 🛡️private
│ 🛡️contain-writes
│ 🛡️no-loop
│ 🛡️no-edit-git
│ 🛡️no-edit-m8-st8
│ 🛡️contain-env

▄ 🛡️jail
│ 🛡️sandbox
│ 🛡️airgap
```

Each of those atoms is `secure` with one more value
appended to its variable, and `m8 shield secure` turns
that variable into lines removed from the sandbox
profile:

```
contain-reads    no reading outside cwd, TMP, system and tool dirs
private          as above, and tool dirs go too
contain-writes   writes confined to cwd and TMP
no-writes        nothing is writable, including TMP
airgap           no internet; loopback and unix sockets stay
no-loop          no loopback or unix sockets; internet stays
no-edit-git      no writing to a .git anywhere
no-edit-m8-st8   no writing to a config directory anywhere
contain-env      the environment is rebuilt, not inherited
```

Those are atoms and the profile knows nothing else. A
level is a composition in the language, where it can be
read, overridden or taken apart — and a value `secure`
does not recognise is refused rather than ignored, so
not understanding what was asked for is never a reason
to apply less than was asked for.

`freeze-toolbox` is a composition too, and shows what
the mechanism buys. A tool may hand back 🧰 records —
that is how a toolmaker works — and closing that
channel is three filters rather than a rule:

```m8
▄ 🛡️freeze-toolbox
│ 🛡️filter-toolbox
│ 🛡️filter-brain
│ 🛡️filter-books
```

Each is a pipe through `m8 filter out SIGIL`. Both
forms of 🧰 go with the one filter, which is the point
of their sharing a sigil: there is no spelling of
"define but do not offer" for a reply to reach for.
Including an agent or a skill *is* a way to acquire a
toolbox, so 🧠 and 📚 are named alongside 🧰 rather
than being resolved to see what they happen to carry. What
is not m8 at all is handed through untouched: most of
what a tool says is text, and text has no records in it
to take out.

### The three that could not be written in the shell

Most shields are programs you already have, which is
why `deny` is `/usr/bin/false` and a filter is a pipe.
Three need m8 itself:

```bash
m8 shield secure "RESTRICTIONS" -- CMD   the profile
m8 shield ask -- CMD                     the person
m8 shield check AGENT -- CMD             another agent
```

`ask` puts the command to whoever is at the terminal.
With no terminal there is nobody to ask, and the answer
is no — a pipe or a cron job must not be a way of
skipping the question.

`check` puts the candidate to an agent, which answers
`allow` or explains itself. Anything else becomes
`Failed agentic check: <response>`. It is never more
capable than what invoked it, and nothing has to be
passed down to make that true: it runs inside every
shield that was already standing there. A checker reads
text an attacker may have shaped, so it belongs beside
`ask` rather than instead of it.

### Two agents

One that cannot widen, whatever it includes or is asked
to do:

```m8
▄ 🛡️jail

▄ 🧠team/helpers

▄ 🧠/local/Ternary-Bonsai-8B-mlx-2bit,max_tokens:8192
```

`team/helpers` may define whatever tools and shields it
likes, and whatever model: the one named last is the one
that answers. They all run jailed, because activating adds and
defining stacks, and neither can subtract. Nothing this
agent is told can add a tool, because a reply is never
read for definitions and `jail` composes
`freeze-toolbox`, which closes the tool response
channel too.

One that builds its own:

```m8
▄ 🧠/local/Ternary-Bonsai-27B-mlx-2bit

▄ 🧰toolmaker
│ │ Write a new tool and return its definition.
│ `m8` `call` `args` `make-tool` `{{M8_ARG_SPEC|}}`
│ * spec string
│   What the tool should do

▄ 🧰toolmaker
```

No 🛡 at all, so `toolmaker` may hand back 🧰 records
— a definition, and the blockless one that offers it —
and they are honoured. The two live happily in one
config, and neither can become the other.

### Thinking it through

* Decide the floor first. A 🛡 at the top of an agent
  is the only thing that cannot be argued with later.
* Prefer a level to a list. `sandbox` and `jail` say
  what they mean and pick up whatever is added to their
  composition; a hand-written list does not.
* Kernel restrictions survive anything a tool spawns.
  If something has to hold three processes deep, it
  needs to be one of those rather than a wrapper the
  tool could simply not call.
* A mob you include can define tools and shields. That
  is the point of a mob. Your floor is what makes it
  safe to include one you have not read.
* `no-edit-m8-st8` is what stops a tool rewriting the
  agent that constrains it. Without it, every other
  restriction is advisory as of the next run.
* `core/` is denied to every secured process, always
  and untagged, which is what makes the profile safe to
  override from your own config.
* Read a config directory before working in it. It
  arrives with a `git clone` like anything else, and it
  defines what runs — though never what running is
  allowed to reach, which is `core/`, and yours alone.

## Configs

Configs merge nearest first, searching up from the
working directory and searching outwards:

* `./.m8-st8/` and every `.m8-st8/` above it
* `$XDG_CONFIG_HOME/m8-st8/` else `~/.config/m8-st8/`

`core/` is the exception. It holds the files that decide
what a restriction *means* and what a provider *is*, and it is
read from your own config only — a project folder arrives
with a `git clone`, and a provider is a command that runs
on your machine. Each is a whole-file override of the copy
m8 ships with, not a merge.

Every name lives under `@/`, so `@mathy` on the command
line is `@/mathy.md` on disk, and the rest of a config
directory is nothing a name can reach.

```
.m8-st8/
  core/
    mac-sandbox.sb
    contain-env-allowed.txt
    providers.json
  models/
  @/
    +.md                      @, the main chat
    mathy.md                  mathy, the agent
    mathy/+.md                @mathy, its own chat
    mathy/=/tduyxbutjb.md     @mathy/=/tduyxbutjb
    mathy/aside/+.md          @mathy/aside
    team/reviewer.md          @team/reviewer
    team/.tmpdir/             the team mob's scratch
    =/psbarddrym.md           a turn a model answered
```

### Mobs

Mobs compose entire collections of agents, skills,
and starting scripts, as bundled packages.

A name is a path, so the folder part is the mob
it belongs to. Mobs bundle the agents, skills and
starting scripts that travel together, and each
mob's agents share its `.tmpdir/` for scratch.

Walking down a name, the first agent file met is
the agent and every word after it is a chat. So
`x.md` beside `x/` is an agent and its chats, and
`x/` alone is a mob. A chat named like an agent in
that same folder would hide the agent without
anyone saying so, so that is an error naming both.

### Turns and chats

Turns and chats are generated rather than authored,
and they are git's objects and refs.

* A turn is a file in a `=/` folder, named with ten
  lowercase letters and never rewritten. It holds
  only what it continues and the exchange.
* A chat is a `+.md`: a single 🧠 naming the turn
  it has got to, rewritten every time it moves.
* The main chat is `@/+.md`. Attached, it names a
  chat, and talking to it moves that chat. Detached,
  it names a turn — after `m8 @/local/tiny` or
  `m8 @mathy/=/tduyxbutjb` — and moves itself.

```m8
▄ 🧠mathy/=/tduyxbutjb

▄ 🙋
│ Tell me more.

▄ 🤖
│ Additionally, ...
```

A turn goes in the `=/` of the chat it advances. One
that advances no chat — a side question, or a turn
talked to directly — goes beside the turn it
continues, and a model's go in the top `=/`.

A chat with no `+.md` of its own reads as its
parent's head. That is the whole of forking and
resetting: a new chat starts wherever its parent
is, and a reset one goes back to following it. The
parent of an agent's own chat is the agent.

The 🧠 printed after a reply is not part of the
turn. It is the line you would write to continue
from it, which is also what you paste after `m8`.

Because chats move, a turn's 🧠 names the turn it
continues and never a chat, or it would become
its own ancestor.

A saved turn is an agent like any other, so
nothing resolves it specially — 🧠 walks back
through parents until it reaches an agent, and
that agent's 🧠 reaches a model. Forking is two
turns naming one parent, and copies nothing.

Two different things are written 🧠. An agent
naming an agent is a mob reaching into a mob; a
name in `=` or `+` is lineage, the turn this one
continues. Both are as deep as they are — nine
mobs is nine mobs, a thousand turns is a thousand
turns, and neither is a fault.

The one fault either can have is a loop, and a
loop is not a depth: it is a name met twice on the
way to itself. So that is what is looked for, and
what m8 says when it finds one.

```
m8: an agent includes one that leads back to it
m8: a turn in that chat names one that leads back to it
```

There is no length or depth either may not reach.
Expanding is a loop over a stack rather than a
call per link, so what it costs is the memory to
hold the ledger it built.

### Models

A 🧠 written with a leading `/` names a model rather than an
agent, and carries whatever the api should be asked for:

```m8
▄ 🧠/local/Ternary-Bonsai-8B-mlx-2bit,max_tokens:8192,temperature:0.7
```

Parameters are the api's own words, passed through as
written. m8 translates none of them and knows none of them
by name, so one it has never heard of works, and one that
came back off a wire goes out again unchanged. `,` separates
them, and a value may be JSON — quote it if it holds a comma.

A model is not a name. Nothing declares its own name in m8,
a file is what it is called, and a model has no file. So it
has no name, keeps no chat, and is written out in full
wherever it is used.

Writing a file is how it comes to have one, like everything
else, and that is also how a model is configured once and
used everywhere:

```
.m8-st8/
  local/Ternary-Bonsai-8B-mlx-2bit.md   @local/Ternary-Bonsai-8B-mlx-2bit
  tiny.md                               @tiny
```

```m8
▄ 🧠/local/Ternary-Bonsai-1.7B-mlx-2bit,max_tokens:2048
```

An agent file is the only kind of alias there is, so it also
composes: put a model after an agent you include and the
model wins, since the last model named is the one that
answers — the same rule as a tool's last definition.

```m8
▄ 🧠mathy
▄ 🧠/local/Ternary-Bonsai-27B-mlx-2bit,max_tokens:16384
```

A chat is the same: a model piped in after one runs it, and
every turn after that is still on it, because the model is
later in the ledger than the agent it took over from.

### Providers

A provider is a command. It reads an api-formatted request on
stdin and writes that api's response on stdout — the same
shape a tool has, a filter that stays in a pipeline. Reaching
a url is one such command rather than the privileged path, so
anything you can write a program for is a provider.

`core/providers.json`:

```json
{
  "toy": {
    "cmd": ["m8", "providers", "toy"],
    "api": "m8"
  },
  "local": {
    "cmd": ["m8", "providers", "url"],
    "api": "openai-completions",
    "url": "http://127.0.0.1:11337/v1/chat/completions",
    "header-authorization": "echo Bearer $(cat ~/.omlx/key)"
  },
  "anthropic": {
    "cmd": ["m8", "providers", "url"],
    "api": "anthropic-messages",
    "url": "https://api.anthropic.com/v1/messages",
    "header-anthropic-version": "echo 2023-06-01",
    "header-x-api-key": "security find-generic-password -s anthropic-api-key -w"
  }
}
```

Two entries mean anything to m8:

* `cmd` says what to run.
* `api` says how to write the request and read the answer.
  It names a codec, which is the same name `m8 encode` takes.

Everything else is handed to the command as `M8_PROVIDER_*`
on top of the inherited environment, and means whatever the
command makes of it. `url` arrives as `M8_PROVIDER_URL`,
`api-version` as `M8_PROVIDER_API_VERSION`. Only string
values with lowercase-and-hyphen keys go, because only those
have a name to take. `cmd` stays behind — the command already
knows what it is — and `api` goes, because what to write may
be the command's business too.

`header-` is nothing special to m8. It is `m8 providers
url`'s one convention rather than the language's, and it is
the entry beside the url that knows it: a key named
`header-x-api-key` arrives as `M8_PROVIDER_HEADER_X_API_KEY`,
what it says is run, and its output is that header's value.

Each is a command rather than a value so a config can commit
safely and still reach a keychain, and a constant is `echo`.
A command that fails or says nothing leaves its header off,
so a machine with no key configured still reaches a provider
that wants none.

A bearer token, an api version, a beta flag and a tenant are
all just headers, and not one of them is a format's business
— which is the same reason there is no path m8 appends. So
none of them is known about here and there is one rule rather
than a field per vendor habit.

A provider you write reads whatever its own entry says,
under its own `M8_PROVIDER_` name, and owes none of this.

There is no path m8 appends to a url. Which api lives where is
a fact about a provider, not about a format, and m8 keeps no
table of those. The whole endpoint goes in `url`.

Which models a provider serves is the ledger's business,
written on the 🧠 that names one, so nothing here has to be
kept in step with what a provider offers.

A provider that speaks two apis is two entries pointing at one
url, rather than a second kind of override.

#### Finding the command

The first word of `cmd` is looked for in order:

* `m8` is the m8 that is running, so a provider reaches this
  build rather than whichever one is on a `PATH`, or none.
* An absolute path is one.
* A name that names a file in `core/` is that file — and if
  it is not executable, that is an error rather than a
  fall-through to something else of the same name.
* A bare word is searched for on `PATH`.
* Anything else fails.

So a provider you write lives beside the config that names it,
in `core/`, and is reached as `["my-provider"]`.

#### Speaking m8

A provider declaring `api: "m8"` is handed the ledger itself
rather than a projection of it — 🧰 with its command and its 🛡
included — and answers in the same language. It is trusted
with that because a provider command lives in `core/`, which
a cloned project cannot reach.

Worth knowing in both directions: it is more capable, and it
means a shim that forwards what it receives will forward your
local command lines. A provider speaking m8 is responsible for
projecting before anything leaves the machine.

#### Shields

Shields are not applied to a provider command. That is safe
rather than generous, and the reason matters:

A shield is a process the child is launched inside, and
`sandbox-exec` is one way — a provider inherits whatever m8 is
already inside and can never shed it. So the rule only ever
means m8 adds nothing. A jailed agent's tool that reaches a
provider is still jailed, because it is a descendant of a
jailed process; what the rule buys is that a jailed *agent*
can still reach its own model, since an agent's shields are
applied to its tools rather than to m8.

Trust is held where the command is written down. `core/` is
read from your own config only, so a project cannot define
what runs. **Mobs travel with agents; providers are yours.**

Worked entries for oMLX, Anthropic and a ChatGPT plan
are in [docs/providers.md](docs/providers.md).

#### The ones m8 ships with

```bash
m8 providers url       post the request to $M8_PROVIDER_URL
m8 providers toy       answer it here
```

```bash
m8 providers                   these two, and what is configured
m8 providers url --help        what it reads, and from where
m8 providers toy --help        which models it serves
```

A provider command reads a request on stdin. A terminal
there is nobody piping one, so it says what it is instead
of waiting for an end of file that is not coming — which
makes `m8 providers url` a third way to that page.

`m8 providers` also lists the providers this machine has,
naming the file they came from. Which models any of them
serves is not in that list and is not missing: that is the
ledger's business, written on the 🧠 that names one, so
nothing in a config has to be kept in step with what a
provider offers. `toy` is the exception, because its
models are m8's own.

`toy` speaks m8 and answers without a network, which is
what makes the loop, tool calling, and picking up a call that
was never answered testable rather than only demonstrable:

```bash
m8 @/toy/echo hello        # says the last thing said
m8 @/toy/you-are anything  # "I know you are but what am I?"
m8 @/toy/runner 'RUN;;;say;;;text=hi'
m8 @/toy/eliza "I am not sleeping well."
m8 @/toy/Z-Machine/zork1 "I would like to play"
```

`eliza` is Weizenbaum's doctor of 1966: a keyword found in
what you said, whatever followed it with its pronouns
turned around, and a sentence to put the two into. Which
of a rule's replies comes back is decided by how many
times you have spoken, which the ledger already says — so
she varies through a conversation while remembering
nothing outside it, and a conversation replays exactly.
It is a chat that is worth having a few turns of while
the loop around it is being worked on.

A name ending in `...` is a family rather than one model, and
what follows the prefix is that model's own business. There is
one: `Z-Machine`, which takes the name of a story file and is a
Z-machine — Zork, and forty years of interactive fiction after
it. It has no weights. It is a virtual machine wearing a model's
interface, and it is here because a model api is stateless and
so is it.

Which is the whole of the design. A model is sent the messages
every time, so the machine is rebuilt every time and the ledger
is replayed through it. Nothing is kept between calls because
there is nowhere to keep it — so the chat is the save file,
forking a chat forks the world, and two runs of the same words
cannot differ. Saving is not implemented and does not need to
be: `m8 cat @ | m8 encode m8 >save.md` already is one, and
`m8 tag @zork <save.md` is the restore.

The first thing you say is not played. It is hashed, and the
hash is the seed the world is built from, so "hello" and
"hello!" are two different games.

```
.m8-st8/models/Z-Machine/       nearest first, like everything
~/.config/m8-st8/models/Z-Machine/
```

m8 ships with no story files: it plays whichever are there,
`.z1` through `.z8`. The name is the file's own and the folder's,
spelled the way they are, like every other name in m8.
Zork I to III are MIT-licensed source from Microsoft and their
repositories carry the compiled files. `m8 help providers
toy` lists what it can find.

`src/zmachine/README.md` is the rest of it: the seam between
the machine and the provider, the invariant every stored
ledger rests on, and what a headless Z-machine has to decide.

`runner` calls a tool for every line of the last thing said
reading `RUN;;;tool;;;property=value;;;...`. Deliberately
witless — `;;;` separates and nothing escapes it — because it
exists to drive m8's own tool path from a test rather than to
be a language.

### Environment

What m8 itself reads:

```
XDG_CONFIG_HOME   your own config, as m8-st8 under it
HOME              that, when XDG_CONFIG_HOME says nothing:
                  ~/.config/m8-st8
PATH              where a provider or tool named as a bare
                  word is looked for, and where m8 finds itself
TMPDIR            where a shielded tool's own directory is made;
                  /tmp when unset
```

And what a provider's command is handed, which m8 writes
and never reads:

```
M8_PROVIDER_API   the codec the entry named
M8_PROVIDER_*     every other string the entry said
```

The two m8 ships with read `M8_PROVIDER_URL` and
`M8_PROVIDER_HEADER_*` between them, and `m8 providers url
--help` says what each is for. A provider you write reads
whatever its entry says, under its own name.

Under `contain-env` the environment is rebuilt from
`core/contain-env-allowed.txt` rather than inherited, and
`HOME` and `TMPDIR` become the sandbox's own directory.
