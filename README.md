
# mEight - The Composable Agentic Shell Harness

The command-line-first agentic harness - fully embracing the shell.

```
fuglaro@localhost> m8 @pagey -- 'One word -> do you like Haiku?'
▐ 🤖
│ Yes.

▐ 🧠pagey/+/swlyayqtjk
fuglaro@localhost> m8 @ -- 'Throw me a quick one please.'
▐ 🤖
│ Moonlight on still ponds
│ Crickets stitch the dark with song
│ Dawn waits behind hills

▐ 🧠pagey/+/psbarddrym
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

The mission:

* The conversation is the artifact.
  * Files you own, in one grammar.
  * Agent, transcript, wire and tool protocol are that
    grammar.
* The ledger is the truth.
  * Anything letting it say what did not happen is a
    bug, not a gap.
* Opinionated on form, and nothing else.
  * Capability by composition, never a plugin api.
* Sugar at the surface, and only there.
* Small enough for a distribution to carry for thirty
  years.

The implementation keeps the same discipline. Keep detail where it
happens; stream or write it in place when it has one use. A helper earns
its distance by naming a real boundary, not by making a unit test easy.
When testing simple code needs awkward setup, put that complexity in the
test rather than routing it through the program.

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
  A `+/` folder holds immutable turns naming their
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

m8 makes orchestration easy rather than deciding it. A
tool sets its own limits, and a shell loop is an agent
loop.

### What a distribution gets

* MIT.
* One binary from `zig build`, or any of its commands as
  programs beside it with `-Dsplit` — the same sources
  either way, and below. `build.zig.zon` declares no dependencies.
  Nothing vendored, nothing fetched at build time, no
  libcurl, no OpenSSL, nothing to CVE-track that is not
  the toolchain in the default build.
* The default `m8 url-provider` hands reaching a url to
  the `curl` already on the machine, which a distribution
  keeps patched anyway. A self-contained HTTP transport is
  available with `-Dno-curl-dep=true`; that build uses
  Zig's standard-library HTTP client and carries TLS and
  certificate handling instead.
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

### One launcher, and programs beside it

Composable is a claim about the command line, and it is
cheap to make while every command is one binary calling
itself. So any command can be built as a program of its
own, and the sizes of those are the guardrail rather than
the optimisation.

* `m8 NAME` runs a command the binary holds by calling it.
* One it does not hold is `m8-NAME` beside it.
  * m8 becomes that program rather than waiting on it.
  * It looks beside itself and nowhere else, so an m8
    installed anywhere reaches its own commands and not
    whichever are on a `PATH`.
  * A command the binary holds wins over a program of the
    same name.
* `m8 --help` lists both.
  * A program beside it is asked for its page, and the first
    line of that says what it is: `m8 NAME - SUMMARY`.
  * So a program of your own named `m8-NAME` is a command,
    listed with the rest.
* `-Dsplit` chooses which commands are programs. See below.

A command that reaches into another command's module still
compiles. Built on its own, it is a program suddenly
carrying a stack it has no business carrying.

* `zig build -Dsmall=true -Dsplit=all` builds every command
  apart, and the sizes in `zig-out/bin` are a reading of the
  architecture.
* Most sit within a few kilobytes of a hello-world against
  this std, and the ones that do not say why: the codecs
  are in the ones that speak to a model.
* In the default build the command that posts to a url is
  not among them, because the posting is curl's.
  `-Dno-curl-dep=true` deliberately puts the
  standard-library HTTP client in that command instead.

Nothing about the command line changes with what is built
where. Symlink `m8-tail` to a binary that holds `tail` and
it *is* `m8-tail`, the way busybox is: same output, same
status.

The url transport is another build-time choice:

```bash
# Small, stripped default: curl is required at runtime.
zig build -Dsmall=true

# Self-contained url provider: no curl executable is required.
zig build -Dsmall=true -Dno-curl-dep=true

# The choices apply to commands built apart too.
zig build -Dsmall=true -Dno-curl-dep=true -Dsplit=url-provider
```

Every artifact is compiled single-threaded. m8 composes concurrent work as
processes and uses none of Zig's in-process concurrency operations, so the
standard I/O implementation keeps its file, terminal, process, random and
network operations without carrying a worker-thread runtime. `small` selects
`ReleaseSmall` and explicitly omits debug symbols; on Darwin it also removes
the local symbols Mach-O retains after linking. Neither choice changes the
command line or stored data. `small` does narrow the wire formats and
builds the toy provider apart, as below.

`no-curl-dep` is comptime-selected in `url-provider`. The
unused transport is not linked, so the default does not carry
`std.http` and the self-contained build does not carry the curl
launcher. The latter is larger because TLS and certificate
validation have to live somewhere, but only the url command
pays for them when it is built apart.

The wire formats are a build-time choice too:

```bash
# Only the formats named, for `encode` and `parse` alike.
zig build -Dformats=anthropic-messages
zig build -Dformats=openai-completions,openai-responses
```

* With no `formats`, all of them are built in.
* `small` with no `formats` builds `openai-responses` alone.
  `-Dsmall=true -Dformats=...` says otherwise.
* `m8` is the language itself, so it is always there.
* A format left out is not compiled, and naming it at
  `m8 encode` or `m8 parse` says there is no such format.
* `m8 encode --help` lists what a build has.

Which commands the binary holds is one as well:

```bash
# `m8-toy-provider` beside `m8`, and out of it.
zig build -Dsplit=toy-provider
zig build -Dsplit=toy-provider,riff
zig build -Dsplit=all
```

* With no `split`, the binary holds every command.
* A command named is built as `m8-NAME` beside `m8`, and
  is not compiled into it.
  * Nothing is lost: `m8 NAME` reaches it there.
  * Leaving one out altogether is not installing its
    program.
* `small` with no `split` builds `toy-provider` apart.
  `-Dsmall=true -Dsplit=` says otherwise.
* The names are the files in `src/command`: one file is one
  command, and what it keeps to itself is in a folder
  beneath.

Two more name a small build with less in the binary:

```bash
zig build -Dminimal=true    # small, with munge and the shields apart
zig build -Dcore=true       # minimal, with riff apart
```

* Each only chooses what `small`, `formats` and `split`
  default to, so any of those can still be said.
* With `riff` nowhere, an address alone at a terminal says
  its one message the plain way.
* `zig build test` is of the sources: it is handed every
  command whatever is built apart.

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
  `+.md` and `+/` do it in a directory, where `ls` and `cat`
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
m8 [@ADDRESS[:|-|--] [-p] [-v] [-- PROMPT]]
m8 COMMAND [ARGS]
```

```bash
m8 @mathy -- "Tell me about the Riemann Sphere\nin detail."
m8 @ -- "Tell me more."
m8 @mathy/aside -- "And what about the Möbius strip?"
```

```bash
echo "Tell me about the Riemann Sphere\nin detail." | m8 @mathy
```
```
▐ 🤖
│ The Riemann Sphere is a ...

▐ 🧠mathy/+/tduyxbutjb
```

The reply went to a tty, so it is rendered. The turn
it saved is a file, so it is markdown:

```bash
cat ".m8-st8/+/mathy/+/tduyxbutjb.md"
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
m8 @mathy/+/tduyxbutjb -- "Tell me more."
```
```
▐ 🤖
│ Additionally,
│ ...

▐ 🧠mathy/+/ypfpkuimzg
```

* `@` sits where a command would, and is not one. A
  prompt supplied as arguments follows `--`, and its
  words are joined with a space, so nothing has to
  arbitrate between m8's arguments and yours.
* A bare `m8` is `m8 @`, the main chat — whichever chat
  was talked to last.
* An address is a chat, a turn or a model:
  ```
  @                   the main chat
  @mathy              mathy's own chat
  @mathy/aside        a chat under it, as deep as chats go
  @mathy/+/tduyxbutjb a turn
  @/local/tiny        a model
  ```
* `:brain:` and 🧠 mark an address as well as `@` does,
  so a 🧠 line pasted back in names what it printed.
* A trailing `:` asks without moving anything, which is
  what a side question is. A trailing `-` resets a chat,
  makes that fresh chat the main chat, and reads as its
  parent again; only a chat has a parent to go back to.
  A trailing `--` is the `reset --new` form: it resets the
  chat to its agent, whatever its parent chat has got to,
  and makes that chat the main chat. The suffix is attached
  to the address, as in `m8 @mathy/aside--`; the separate
  `--` after an address remains the prompt separator.
* It is a pipeline written once. `m8 @mathy -- hi` is
  `m8 ref @mathy hi | m8 send | m8 tag @mathy` and then
  `m8 reset --to @mathy @`, except that the reply is
  shown as it arrives and tagged as it goes. See
  Composing and Turns and chats.
* It is the shorthand, and every part of it has a plain
  form underneath.
  * `:`, `-` and an address-attached `--` are marks a person types;
    a separate `--` is the prompt separator.
  * A command takes a message as one argument, `--no-advance`
    for `:`, and `m8 reset` (with `--new` for address-attached `--`)
    for the reset forms.
  * So a tool calling an agent passes parameters, and
    carries no mark through one.
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
  which names a model: `/local/Bonsai-8B,max_output_tokens:8192`.
  The mark is the whole of the distinction — nothing is looked
  up to decide it — so a name that is missing is a missing
  agent rather than a model nobody configured. On the command
  line that is `m8 @/local/Bonsai-8B`. See Models.
* Saving is to the nearest existing m8 config folder.
* If a tty is connected, interactive mode is activated,
  which streams tokens without buffering and renders
  the reply. Everything else is written as markdown.
* `-p` after the address is pretty: the reply is rendered and
  streamed whatever stdout is, under the 🙋 it answers.
  * It is for whatever stands between m8 and a terminal.
  * `m8 riff` is one. See Riffing.
* Only `m8 @` asks what stdout is.
  * Every command writes markdown to a terminal and a pipe
    alike, so it is one command and not two.
  * `m8 render` is the rendered spelling for any document:
    `m8 ref @mathy | m8 encode | m8 render | less -R`.
* `-v` after the address is verbose: a line on stderr for
  what the run is doing.
  * `💭 ` and the opening of a thought, said once.
  * `📲` and a call, as `name(argument=value,…)`.
  * Each is one line, cut where it gets long, and stays
    the last thing said until the next.
  * A thought kept aside as a snip is not said.
* A first word that is not an address names a command.

Every command has a page:

```bash
m8 --help                  every command, and what m8 reads
m8 send --help             one command
m8 munge --help            one tool and all its operations
```

A leading `--help` is m8's rather than any command's, so no
command has to parse it and no two answer it differently.
It is the only help option; `-h` remains an ordinary argument.
The words after an `@` are prose after the required `--`, so a
`--help` among them is said rather than read.

A page you asked for is written to stdout, where it can
be paged and piped. A page handed back instead of what
you asked for goes to stderr, where it cannot become part
of a document.

### Assembling

`m8 @ADDRESS` builds a ledger from three things: what
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
cat notes.txt | m8 @ -- "Summarize:"               # one 🙋, prompt first
echo "#### :brain:/local/tiny" | m8 @mathy -- "Quickly?"
m8 top @tight-docs | m8 @mathy -- "Tidy the README."
```

Piping is not required, and neither is a prompt when
something was piped. With neither, at a terminal, the
address alone opens a conversation with it: `m8 @mathy`
is `m8 riff m8 @mathy -p -v`. See Riffing.

`-p` after the address is one message the plain way: a
terminal collects lines until Ctrl-D, then shows the
submitted 🙋 before waiting for the reply; Ctrl-D before
anything was entered quietly cancels. An empty
non-terminal input still has nothing to say, and m8 says
so.

A document is told from prose by its first line alone,
so one that opens like a document and then goes wrong is
an error rather than a prompt.

### Composing

Every command reads stdin and writes stdout, and the
ones that take an address resolve it themselves. So
what `m8 @` does is a pipeline too, and each step can be
had on its own:

```bash
m8 ref @mathy hi | m8 send | m8 tag @mathy      what m8 @mathy -- hi does
m8 ref @mathy | m8 tag @mathy/aside             fork, with nothing said
m8 ref @ hi | m8 send | m8 tag @mathy/other     keep a run somewhere else
m8 ref @ | m8 encode >.m8-st8/@/notes.md        a chat, flattened into an agent
m8 ref @mathy | m8 encode | m8 render           a chat, as a person reads it
m8 query @critic/job "Review that."             the reply alone, as text
m8 watch @crew/cody/delegated                   a chat, as it moves
```

* `ref @X` writes the 🧠 that X reads as now.
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
* `tag @X` keeps a turn and points X at it.
  * A document that is one 🧠 already names a turn and is
    pointed at without writing anything.
  * Anything else is kept as a new turn.
  * Its output is the 🧠 now pointed at, and nothing
    else — a ref was written, and that is its receipt.
  * `--no-advance` keeps the turn and moves nothing.
* `reset @X` takes a chat's pointer away, so it reads as
  its parent again.
  * `--new` starts it from the agent it is under, whatever
    the chats above it have got to.
  * `--to @Y` has it follow Y as named, unsettled:
    `m8 reset --to @mathy @` puts the main chat on mathy.
  * Something that would lead back to itself is refused.
* `tail` writes the last record of a document, or with
  `--sigil` the last of some kind.
  * `--value` is the rest of its header line, and
    `--block` is its block as the text it holds.
  * A record with neither is an error, not an empty line.
  * Nothing is resolved; `m8 encode` expands a 🧠 first.
* `exclude --sigil S` writes a document back with every
  record of the kinds named gone. See Shields.
* `render` writes a document in the rendered spelling, and
  `render -r` writes markdown back, which is how to check
  that a document parses.
* `query @X MESSAGE` is the pipeline written once more,
  for whatever has parameters rather than a command line.
  * It says the message, runs, keeps the run, and writes
    the reply or the question as text.
  * `-v` says on stderr what the run is doing, and `-vv`
    writes the whole turn there.
  * `--no-advance`, `--new` and `--parent` say where it
    starts and whether anything moves.
  * `--no-store` keeps nothing, so nothing moves either.
  * `--piped` reads stdin as prose, as it does for `ref`.
* `watch @X` writes a chat out as it moves, which is how to
  look on at one something else is running.
  * Each piece opens with the 🧠 it continues.
  * A chat that is reset starts over under its agent's 🧠.
  * It arrives a turn at a time: a reply once it is whole,
    and a call once it is answered.
  * Only the chat's own pointer is read, so a chat with none
    is waited on rather than shown as the chat above it.
  * A snip stays the 🧠 that names it.
* `top @X` is `ref`'s twin for 📚: it names a file for
  what it says about itself, and nothing else. See Tops.

A document follows an address by being written after it,
which is all a document needs:

```bash
{ m8 ref @mathy hi; echo "#### :brain:/local/tiny"; } | m8 send
{ m8 top @tight-docs; m8 ref @mathy "Tidy the README."; } | m8 send
```

What `m8 @X` writes ends on the 🧠 of the turn it kept,
and `tail` is how that becomes what the next command is
handed:

```bash
m8 ref "@$(m8 @mathy -- hi | m8 tail --value)" "Review that." | m8 send
```

A turn `send` wrote was never kept and ends on no 🧠, so
`tail --value` has nothing to hand on until it is tagged.

The main chat follows the `@` prompt and nothing else. A
command moves the chat it names, and moves the main chat
only when `@` is what it names — so an agent run from a
tool keeps its own chats and never takes over the
conversation of whoever is at the terminal.

Forking a chat is naming somewhere else to tag, and
nothing more.

### Riffing

```bash
m8 riff CMD [ARGS]         an editor pinned under CMD's output
m8 @mathy                  at a terminal: m8 riff m8 @mathy -p -v
m8 riff -c python3 -i -u -q    one Python, a message at a time
m8 riff -c -s 2 python3 -i -u -q    with its last error above its prompt
```

`riff` is a conversation at a terminal, made of the command
line rather than beside it.

* Every message sent is a run of CMD.
  * The message is its stdin.
  * A message sent mid-run waits its turn.
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
  * `m8 parse openai-responses` says one under `-v`:
    `::stats::✥19▇16K::` is what came out, the share the
    prompt cache held as a block, and what went in.
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
    message sent is the answer. See Asking the Person.
  * `m8 riff --detached CMD` is that half alone.

riff knows nothing about m8. `m8 riff sh -c 'cat; date'` is as
much a riff as a chat is.

### Encoding

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
m8 ref @mathy | m8 encode m8
m8 ref @mathy | m8 encode m8 >full-ledger-copy.md
```

```bash
m8 ref @mathy | m8 encode openai-completions
m8 encode openai-completions <full-ledger-copy.md >openai.json
```

`--break NAME` leaves a 🧠 naming NAME as it was written
rather than expanding it, so what comes out is the ledger
from there on.

```bash
m8 ref @mathy | m8 encode --break mathy/+/tduyxbutjb
m8 ref @mathy | m8 encode --break mathy     # the chat, without its agent
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
messages, an id and its encrypted content under responses —
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

`parse` is the way in rather than a filter, so it takes
stdin exactly as it arrives.

`parse` is the other direction. `encode` is about requests,
which are ledger-shaped; a response is turn-shaped, so it is
read into the records it adds to a ledger rather than into
one. With it, the whole loop is something you can watch
happen:

```bash
m8 ref @mathy "Say hi." \
  | m8 encode openai-responses \
  | M8_PROVIDER_URL=http://127.0.0.1:8000/v1/responses m8 url-provider \
  | m8 parse openai-responses
```

* `url-provider` on its own knows no provider, so the
  endpoint is said in its environment.
* A header goes the same way, as `M8_PROVIDER_HEADER_*`.
  See Providers.

Reading is incremental whether or not the provider streamed.
A provider that writes everything at once is a stream of one
chunk, which is what lets streaming be something a provider
MAY do rather than MUST. Where an api has both a streamed and
a whole shape — chat completions changes shape, not just
delivery, when `stream` is set — the one that actually
arrived is the one that is read.

### Calling

```bash
m8 call PROG [ARGS]     a program from the environment
```

`call` runs a program and writes its answer as m8.

* It is how an ordinary program becomes a tool: a 🧰
  names it, or does the same job itself.
* A whole word naming a call variable becomes whole
  arguments. See Commands That Want Flags.
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

Because the receipt streams, a tool may write more
than there is memory to hold and m8 will not hold it.
A failure keeps the *last* 8K of what the program
complained about — the end is where a program says
why — and marks it `...` when there was more.

A 🛡 expands into a command such as `m8 secure-shield`. See Shields.

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

## Language and Schema

Agent definition:

```m8
▐ 🧠Address, Agent Name or Model

▐ 🧰Tool Name
│ │ Tool Description
│ 🛡️Shield Name
│ `m8` `call` `cmd` `{{propertyname|--flag}}`
│ * PropertyName string
│   Property Description
│ * Other? integer
│   Optional, so ? on the name

▐ 🏃bash
│ `m8` `call` `bash` `-e` `-c` `{{CODE}}` `bash`

▐ 🧰Tool Name
│ │ A fenced block runs through the 🏃 it names.
│ ```bash
│ echo "$__propertyname__"
│ ```
│ * PropertyName celsius|fahrenheit
│   An enum is its values, which may hold a space
│ * PropertyName string[]
│   Arrays suffix []
│ * ParentName object
│   Mandatory Parent Def
│ * ParentName.PropertyName integer
│   Nested

▐ 🧰Tool Name

▐ 🛡️Shield Name

▐ 🧭
│ System Prompt
│ A record is a header and a content block, and
│ content is verbatim, so this line may begin with
│ anything at all.
│ A , separates a fixed number of fields, so the
│ last field may hold one safely.

▐ 🧭
│ Included Agents inject Tools and System
│ Prompts.
```

Query:

```m8
▐ 🧠Agent or Model Name

▐ 🙋
│ User Content Text

▐ 💭
│ Assistant Thoughts
│ 🔏Optional Signature

▐ 🤖
│ Assistant Content Text

▐ 📲Called Tool Name,Call ID

▐ 🚫Call ID
│ Error response

▐ 📲Called Tool Name,Call ID
│ * Argument Name `value`
│ * Argument Name
│ * Argument Name
│   ```
│   a value over
│   more than one line
│   ```

▐ 🧾Call ID
│ Response

▐ 🟢Call ID
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
▐ 🧠/local/Ternary-Bonsai-8B-mlx-2bit,max_output_tokens:8192

▐ 🧭
│ You are a mathematics expert that will answer questions,
│ give insight, and advise on any relevant technique.
│ Describe concepts with analogies and spatial models
│ that can be imagined by a human and include how it relates
│ to the components, equations, and relationships in
│ the mathematical equations.

▐ 🙋
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
content line. A fully blank line closes the block.
Headers may follow one another without a blank line;
writers may use blank lines between records for
readability.

Sigils are a closed set, written as one codepoint
within U+1F300 to U+1FAFF or U+2700 to U+27BF, or as
`:word:`. An unknown sigil in either spelling is an
error.

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

* ▐ header -> `####`
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
* ❓ question -> `:question:`
  * ❗ exclamation -> `:exclamation:`

A sigil takes a value, a content block, or both — or, for the
one that is a fence rather than a record, neither. A 💭 without a
block uses its value as a compact one-line thought. Its `snip` value
is special only when that same 💭 also has a block; otherwise it is
simply the one-line thought `snip`. 🧰 has three separate header
forms: a content-bearing header defines a tool, a blockless header
with a variable and values configures that tool, and a bare blockless
header offers it. A definition header may not combine content and
variable configuration.

* Value only: 🧠 📚 🔏 🟢 💭
* Content only: 🙋 🧭
* Both: 🤖 🧰 📲 🧾 🚫 🛡️ 🏃 ❓ ❗
* Neither: 🔝

### Stopping Short

A reply the model did not finish ends with a 🤖 that has a
value and nothing under it.

```m8
▐ 🤖
│ Moonlight on still ponds
│ Crickets stitch the

▐ 🤖(cut off at max_output_tokens)
```

* The value is `(words term)`.
  * The words are for whoever reads the transcript.
  * The last word is the provider's own term, untouched.
* Finishing, and asking for tools, say nothing - the ledger
  already shows both.
* A provider that returns neither a reply nor a tool call leaves
  `🤖(no response)`. The invocation happened, so the ledger says so.
* m8 carries it and never reads it.
  * No loop decision is made on it - a call made while
    bailing runs as asked.
  * It is between the provider and the reader, or whatever
    matches on the last word.
* No api takes it back, so encoding drops it.
* Each codec says its own terms:
  * `cut off at` - out of output tokens
  * `context full at` - out of context window
  * `filtered by` - a content filter
  * `declined with` - a refusal
  * `declined by CATEGORY` - a refusal naming its policy
  * `paused at` - a paused server-side turn
  * `MESSAGE - failed with` - an error from the api,
    with what it said ahead of the words
  * `stopped at` - a stop sequence, or a term not yet known

### Kept Aside

A 💭 whose value is `snip` and which has a block asks for what it
holds to be kept out of the way. Keeping it writes a snip, and leaves
the 🧠 naming it in its place. Without a block, `💭snip` is simply the
compact one-line thought "snip".

```m8
▐ 💭snip
│ 🔏c2lnbmF0dXJl

▐ 🧠mathy/+/snip-oniwhbxumk
```

A compact thought keeps its text on the header:

```m8
▐ 💭Checking the result
```

Providers should use this compact form for one-line thought summaries when
possible, and must interpret a value-only 💭 as thought text when reading it.

* Which thoughts ask is the codec's decision.
  * A signature is the case today - it exists only to be handed back.
* A snip is a file holding the `💭snip` as it was written.
  * Its name is `snip-` and ten random letters.
  * `snip-` and a turn's ten letters never collide.
* The 🧠 is an inclusion like any other.
  * Nothing reads a snip specially.
  * Reading a ledger gives a codec exactly what it wrote.
  * Keeping what was read keeps it aside again.
* A snip goes beside the turn that names it, in its `+/`.
* `m8 @` keeps one as it arrives.
  * The 🧠 shown is the file written.
* `m8 send` keeps nothing, so what it writes carries the `💭snip` whole.
  * `tag` writes the snip with the turn.

### Tops

A file may open with a 🔝 and close it with a second one.
What is between them is that file's top: what it says
about itself, rather than what it says.

```m8
▐ 🔝

▐ 🧭
│ Load tight-docs when working on documentation.

▐ 🔝

▐ 🧭
│ Keep every doc comment to one line.
```

Two sigils reach into another file and the mark decides
which half comes back. 🧠 wants what the file says; 📚
wants what it says about itself. On the command line
those are `m8 ref @` and `m8 top @`.

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

A tool's command answers in m8, and how is the
definition's business.

* `m8 call` turns an ordinary program's output into a 🧾
  and a verdict.
* A command that writes m8 itself is named directly.
* m8 keeps no note of which is which. It reads what came
  back, and an answer with no verdict for its call is a
  🚫.

```m8
▐ 🏃bash
│ `m8` `call` `bash` `-e` `-c` `{{CODE}}` `bash`

▐ 🧰search
│ │ Look for something.
│ ```bash
│ grep -r "$__pattern__" .
│ ```
│ * pattern string
│   what to look for
```

What a tool is handed:

* `__<NAME>__` per scalar, preserving the argument's
  original capitalization, when it is a portable identifier.
* `____`, always, carrying the whole call as JSON.
  Anything nested, dotted or arrayed has no scalar env
  spelling and lives here instead.
* `M8_CALL_ID`, which call this is.
* `M8_EXCLAMATION_1` and up, what the person answered the
  call. See Asking the Person.

An inherited `__<NAME>__` environment variable is available
as a fallback when the call does not supply that argument.

An argument that was not supplied is unset rather than
empty, which is the whole of what optional means to
whatever reads it. A required one that is missing is
refused before a command is built at all.

### Commands That Want Flags

A shell reads its environment. `curl` and `git` do not,
and turning variables back into flags for them is a
command's own business rather than the framework's.
`m8 call` is the one m8 ships for it.

```m8
▐ 🧰bash
│ │ Run a bash command.
│ `m8` `call` `bash` `-euo` `pipefail` `{{command|-c}}`
│ * command string
│   The bash command to run.
```

Given `__command__=echo hi`:

```
{{command}}       --command "echo hi"
{{command|-c}}    -c "echo hi"
{{command|}}      "echo hi"
{{deep?--deep}}   --deep, when the value is exactly true
{{}}              -- followed by the whole call as JSON
{{|}}             the whole call as JSON, without a flag
```

The flag a bare placeholder carries is the argument's
own name, preserving its spelling. An empty name is the
whole call: `{{}}` gives it the `--` flag, while `{{|}}`
injects it directly.

A placeholder is a whole argument and is never spliced
into a larger one, so a value cannot become syntax in
what runs. Only an explicit `m8 call` expands one; the
harness passes every other command as written, and a shield
reads what it was told from its environment.

### Definition variables

A tool definition can supply fixed environment values without
putting them on the definition header. Each value gets its own
blockless header, and a final bare header offers the tool:

```m8
▐ 🧰read
│ │ Read a file or directory.
│ `m8` `call` `m8` `munge` `read` `{{page_lines|--page-lines}}` `--` `{{path|}}`
│ * path string

▐ 🧰read page_lines 100
▐ 🧰read
```

Definition variables and call parameters share the `__name__`
environment convention. Definitions are written with logical names,
for example `read PAGE_LINES 100` or `sandbox byte_cap 20000`.
If both provide the same name, their values are joined with a space,
with definition values first and call values last. Shields use the
same convention, so their definition values participate in that merge.

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
* Only a whole argv word shaped as `{{name}}` is looked at,
  so values are never spliced into larger words. Other brace
  expressions survive — `m8 call awk '{{print $1}}' f` runs
  the awk program it was handed.

None of this is privileged. An argv is passed on as it
was written, so a toolbox naming some other expander
works the same way, and deleting `call` leaves the
framework whole.

### Asking the Person

A tool that needs something from the person asks through
the ledger, so the question and its answer are part of the
conversation.

```m8
▐ 📲deploy,c1
│ * target `prod`

▐ ❓tool,c1
│ deploy to prod?

▐ ❗tool,c1
│ yes

▐ 🧾c1
│ deployed
▐ 🟢c1
```

* A tool asks by ending in a particular way.
  * Exit status 75.
  * Nothing on stdout.
  * A stderr that opens `QUESTION:tool:`, with the question
    after it.
* A shield asks the same way, under its own name.
  * `QUESTION:shield_ask:` is `🛡️ask` asking.
  * Every shield is handed its own name, `ask`, before
    the command it wraps.
* The ❓ says who asked and of which call: `❓tool,c1`.
* The run stops on the ❓.
  * Calls the model made alongside it are written down
    first, unanswered.
  * No model is told anything: the call is still owed.
* Whatever is said next is the ❗, to whoever asked.
  * It takes the place of a 🙋 whenever a ledger ends in a ❓.
  * Whoever says it is who answered. A person, a script
    and another agent are all the same to m8.
* The call is then run again, from the start.
  * A tool is safe to repeat up to the point it asks.
  * The owed calls follow it, and then the model.
* A tool asks as many times as it needs.
  * Each run is handed every answer so far.
  * A tool and the shields it stands inside each ask their
    own, and each finds only what was said to it.
  * Questions are asked in the same order every run, which
    is what makes the second answer the second question's.
* Exit status 75 without a question, once answered, is the
  tool saying no.
  * Its result is written as any failure is.
  * Calls made alongside it lean on each other, so the ones
    still owed are not run. Each is closed with a 🚫 saying
    another was refused.
  * The conversation goes to the person, not the model, so
    a refusal is followed by what to do instead.

What the person answered is in the call's environment:

```
M8_EXCLAMATION_1          the tool's first answer
M8_EXCLAMATION_2          its second
M8_EXCLAMATION_1_ask      a shield's first
```

* The tool and every shield around it are handed the same
  ones.
  * None set is nothing answered yet.
  * They are made from the ledger every run, so the ledger
    is the only place an answer lives.
* An answer has to fit in an environment.
  * One too long for it is a call that fails to start.
* A run of `m8` starts with none.
  * It drops any it was handed, so an agent run by a tool
    never takes that tool's answers as its own.

```bash
[ -n "${M8_EXCLAMATION_1+x}" ] || { echo "QUESTION:tool: deploy to prod?" >&2; exit 75; }
```

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
the wrappers stack and a repeat means nothing. A name
runs one command, so a second definition of it is an
error once it is activated: a mob you have not read
cannot replace what it was given, and nothing runs.

```bash
__secures__="private airgap" m8 secure-shield secure bash -c "ls"
```

### Defining and activating

With a block it defines; with a value alone it
activates.

```m8
▐ 🛡️deny
│ `false`

▐ 🛡️deny                   now it is on
```

A definition body holds a command spelled out in
backticks, a fenced block in some language, or another
🛡 to stand inside. Shields to stand inside may repeat,
and all of them stack around the one command.

```m8
▐ 🏃bash
│ `m8` `call` `bash` `-e` `-c` `{{CODE}}` `bash`

▐ 🏃bash raw
│ `bash` `-e` `-c` `{{CODE}}`

▐ 🛡️passthrough
│ ```bash raw
│ exec "$@"
│ ```
```

A 🏃 is what makes a block runnable: an argv with
`{{CODE}}` in it.

* It must be defined before a block names it, so a
  document reads in one pass.
* Defining one twice is an error rather than a question.
* Its name is the whole of a fence's info string, so
  ` ```bash raw ` names `bash raw` while a renderer still
  highlights bash.
* m8 ships none. What `bash` means is the agent's own:
  above, a tool's block answers through `m8 call`, and a
  shield's stays a transparent wrapper.

Every wrapper is handed the name it stands as and then
the command it wraps, as arguments. A wrapper whose first word is `m8` *is* an m8
command, and that word becomes this m8's path. `🛡️ask` is
`` `m8` `ask-shield` `` and nothing else.
A tool's own command is read the same way, as is the program
named by `m8 call`, so `` `m8` `call` `m8` `munge` … ``
reaches this build at both executable positions.

When launching providers and calls, m8 adds its absolute
launcher path as `M8`. Opaque program text stays opaque: a
shell script
that needs the current build runs `"$M8"`, and m8 does not
rewrite its source.

What a call said arrives in the environment, never in these
words, so no value a model wrote is read for a command.

The name is the shield's own, made safe for a folder.

* It is the shield whose command runs: `sandbox` stands
  as the shields it is made of.
* It is who a wrapper asks the person as, and what its
  answers are named for. See [Asking the Person](#asking-the-person).
* A name runs one command, so two of a kind are two
  names, such as `ask1` and `ask2`. A second command under
  one name is an error rather than a second wrapper.

A shield takes nothing else as words. What it was
activated with arrives in its environment, as a tool's
call does, so nothing in a shield's command is expanded.

`bash -c` binds `$0` to the first argument after the
script, which is the name, so a shell shield runs its
command as `"$@"`. A shield author is trusted, exactly
as a tool author is.

### Activation order

Activation order is wrapping order, and the first is
furthest out. It decides nothing about what is
permitted — intersection does not care — and everything
about what a person is shown, which is why `ask` is
worth activating last: innermost, it asks about the
bare command rather than about a stack of prefixes.

A shield stands once, however many times it is activated.

* It stands where it was first activated.
* Each later activation adds its values to what the shield
  is told, and nothing else.
* So `jail` is one `secure`, told every restriction, and a
  tool's own `airgap` joins that one's list.

### Where a shield is written

```m8
▐ 🛡️jail                   the floor for this agent

▐ 🧰deploy
│ 🛡️airgap                 and this tool as well
```

* **Top level**, in an agent. Cumulative over the
  lineage, and inclusion can only tighten.
* **In a 🧰**, for one tool, on top of the floor.

There is no third place and no flag. A shield is written
down where it applies, so what a run may not do is a
fact about the agent rather than about how it was
invoked.

### A shields file

m8 defines no shield. A name means what an agent, or
something it includes, says it means.

* `@/utils/shields.md` is an ordinary document holding
  definitions and activating none of them.
* An agent that wants them includes it with `🧠utils/shields`.
* A name nothing defines is refused, so a tool under one
  does not run.

What `jail` means there is a composition you can read:

```m8
▐ 🛡️sandbox
│ 🛡️freeze-toolbox
│ 🛡️private
│ 🛡️contain-writes
│ 🛡️no-loop
│ 🛡️no-edit-git
│ 🛡️no-edit-m8-st8
│ 🛡️contain-env
│ 🛡️contain-home

▐ 🛡️jail
│ 🛡️sandbox
│ 🛡️airgap
```

Each of those atoms is `secure` with one more value
appended to its variable, and `m8 secure-shield` turns
that variable into lines removed from the sandbox
profile:

```
contain-reads        no reading outside cwd, TMP, system and tool dirs
contain-reads-home   as above, with HOME readable too
private              as contain-reads, and tool dirs go too
contain-writes       writes confined to cwd and TMP
contain-writes-home  writes confined to cwd, TMP and HOME
no-writes            nothing is writable, including TMP
airgap               no internet; loopback and unix sockets stay
no-loop               no loopback or unix sockets; internet stays
no-edit-git           no writing to a .git anywhere
no-edit-m8-st8        no writing to a config directory anywhere
```

Those are atoms and the profile knows nothing else. Each
one only takes permissions away, so combinations silently
take the most restrictive form: `contain-writes` together
with `contain-writes-home` is `contain-writes`. A level is
a composition in the language, where it can be read,
overridden or taken apart — and a value `secure` does not
recognise is refused rather than ignored, so not
understanding what was asked for is never a reason to
apply less than was asked for.

`contain-home` and `contain-env` are not atoms. Each is a
wrapper that changes the environment before the tool starts:

```m8
▐ 🛡️contain-home
│ `bash` `-c` `HOME=$TMPDIR exec "$@"`

▐ 🛡️contain-env
│ `bash` `-c` `for v in $(compgen -e); do case $v in __*|M8|M8_*|TMPDIR|PATH|HOME|LANG|LC_*) ;; *) unset "$v";; esac; done; exec "$@"`
```

* `contain-home` points `HOME` at the mob's scratch.
* `contain-env` drops every variable its body does not name.
  * The names are written in the body rather than passed as
    values, because values add up across activations and a
    list that could grow would be a way to widen.
  * A second definition is a second filter, so stacking
    still only tightens.
  * `__*` and `M8_*` are what a call said and what the person
    answered, so a definition keeps them.

`freeze-toolbox` is written in the language too, and
shows what the mechanism buys. A tool may hand back 🧰
records — that is how a toolmaker works — and closing
that channel is a pipe rather than a rule:

```m8
▐ 🛡️freeze-toolbox
│ `bash` `-euo` `pipefail` `-c` `"$@" | "$M8" exclude --sigil toolbox --sigil brain --sigil books`
```

`m8 exclude` takes out every record of the kinds it is
told. Both forms of 🧰 go with the one name, which is the
point of their sharing a sigil: there is no spelling of
"define but do not offer" for a reply to reach for.
Including an agent or a skill *is* a way to acquire a
toolbox, so 🧠 and 📚 are named alongside 🧰 rather
than being resolved to see what they happen to carry. What
is not m8 at all is handed through untouched: most of
what a tool says is text, and text has no records in it
to take out.

### The two that could not be written in the shell

Most shields are programs you already have, which is
why `deny` is `/usr/bin/false` and a filter is a pipe.
Two need m8 itself:

```bash
m8 secure-shield NAME CMD   the profile, from __secures__
m8 ask-shield NAME CMD      the person
```

`ask-shield` puts the command to the person as a ❓, the way any
tool asks. See Asking the Person.

* `y` or `yes` runs it.
* Anything else does not, and the person is asked what to
  do instead.
* It needs no terminal, so it asks the same under a pipe,
  a riff or anything else that can answer the conversation.

Putting a command to another agent is a shield written in
the language: a block that pipes `m8 ref` into `m8 send`
and runs the command when the reply is `allow`.

* It runs inside every shield already standing, so it is
  never more capable than what invoked it.
* A checker reads text an attacker may have shaped, so it
  belongs beside `ask` rather than instead of it.

### Two agents

One that cannot widen, whatever it includes or is asked
to do:

```m8
▐ 🧠utils/shields

▐ 🛡️jail

▐ 🧠team/helpers

▐ 🧠/local/Ternary-Bonsai-8B-mlx-2bit,max_output_tokens:8192
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
▐ 🧠/local/Ternary-Bonsai-27B-mlx-2bit

▐ 🧰toolmaker
│ │ Write a new tool and return its definition.
│ `make-tool`
│ * spec string
│   What the tool should do

▐ 🧰toolmaker
```

No 🛡 at all, so `toolmaker` may hand back 🧰 records
— a definition, and the blockless one that offers it —
and they are honoured. `make-tool` writes m8 itself,
verdict included, reading `__spec__`. The two live happily in one
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
  and untagged, so a tool cannot rewrite what a
  restriction means.
* Running m8 in a directory trusts the config found from
  it.
  * It arrives with a `git clone` like anything else.
  * It defines what runs, what a shield means, and which
    command a provider is.
  * Read it first.

## Configs

Configs merge nearest first, searching up from the
working directory and searching outwards:

* `./.m8-st8/` and every `.m8-st8/` above it
* `$XDG_CONFIG_HOME/m8-st8/` else `~/.config/m8-st8/`

`core/` holds what a restriction *means* and what a provider
*is*, and is searched the same way.

* `providers.json` composes through the stack: every file
  adds its entries, and the nearest entry of a name stands.
* `mac-sandbox.sb` is taken whole from the nearest directory
  that has one, else from the copy m8 carries.
* m8 carries no providers.

Authored names live under `@/`, so `@mathy` on the command
line is `@/mathy.md` on disk. Generated state lives in the
sibling `+/`, mirroring the same logical paths. The rest of a
config directory is nothing a name can reach.

```
.m8-st8/
  core/
    mac-sandbox.sb
    providers.json
  models/
  @/
    mathy.md                  mathy, the agent
    team/reviewer.md          @team/reviewer
  +/
    +.md                      @, the main chat
    mathy/+.md                @mathy, its own chat
    mathy/+/tduyxbutjb.md     @mathy/+/tduyxbutjb
    mathy/aside/+.md          @mathy/aside
    team/.tmpdir/             the team mob's scratch
    +/psbarddrym.md           a turn a model answered
```

In folder chat state can be omited with `echo "+/" >> .m8-st8/.gitignore`

### Mobs

Mobs compose entire collections of agents, skills,
and starting scripts, as bundled packages.

A name is a path, so the folder part is the mob
it belongs to. Mobs bundle the agents, skills and
starting scripts that travel together, and each
mob's agents share its mirrored `+/<mob>/.tmpdir/`
for scratch.

Walking down a name, the first agent file met is
the agent and every word after it is a chat. So
`x.md` beside `x/` is an agent and its chats, and
`x/` alone is a mob. A chat named like an agent in
that same folder would hide the agent without
anyone saying so, so that is an error naming both.

An agent needs no way to spawn another. Calling one is
already a command, so a 🧰 whose command is that *is* a
subagent, standing inside whatever shields that 🧰 does.

* `m8 query --new @team/reviewer/job MESSAGE` starts one
  fresh, from the agent as it is written.
* The same without `--new` carries that chat on, which
  is also how a question it asked is answered.
* `--no-advance` asks and keeps no chat to carry on.
* What comes back is the reply as text, so the caller is
  handed an answer and not a ledger.
* The main chat is not moved, so the conversation at the
  terminal stays where it was.

### Turns and chats

Turns and chats are generated rather than authored,
and they are git's objects and refs.

* A turn is a file in a `+/` folder, named with ten
  lowercase letters and never rewritten. It holds
  only what it continues and the exchange.
* A chat is a `+.md`: a single 🧠 naming the turn
  it has got to, rewritten every time it moves.
* The main chat is `+/+.md` on disk. Attached, it names a
  chat, and talking to it moves that chat. Detached,
  it names a turn — after `m8 @/local/tiny` or
  `m8 @mathy/+/tduyxbutjb` — and moves itself.

```m8
▐ 🧠mathy/+/tduyxbutjb

▐ 🙋
│ Tell me more.

▐ 🤖
│ Additionally, ...
```

`m8 @` tags a run as it goes rather than once it is
over, so a run is a chain of turns and the chat moves
with each.

* A model call is a turn: what it said, under the turn
  it continues.
* A tool call is a turn: the 📲 and its answer.
* A run that dies keeps everything up to where it died,
  and the chat reads as that.
* A 📲 is kept with its answer and never ahead of it, so
  nothing half run is owed to whoever carries on.

A turn goes in the `+/` of the chat it advances. One
that advances no chat — a side question, or a turn
talked to directly — goes beside the turn it
continues, and a model's go in the top `+/`.

A chat with no `+.md` of its own reads as its
parent's head. That is the whole of forking and
resetting: a new chat starts wherever its parent
is, and a reset one goes back to following it. The
parent of an agent's own chat is the agent.

A chat's `+.md` usually names a turn, and may name two
other things.

* The agent itself, which is what `m8 reset --new` writes
  when a chat above has moved on: the chat reads as the
  agent all the same. Where taking the `+.md` away already
  reads as the agent, that is all `--new` does.
* Another chat, which is what `m8 reset --to` writes: it
  is followed, and reads as wherever that chat gets to
  until it is itself moved on.
* The main chat on a chat is the second of those.
* A chat following something that leads back to it is
  the one loop a pointer could make, and is refused when
  it is asked for.

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
name through `+` is lineage, the turn this one
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
▐ 🧠/local/Ternary-Bonsai-8B-mlx-2bit,max_output_tokens:8192,temperature:0.7
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
▐ 🧠/local/Ternary-Bonsai-1.7B-mlx-2bit,max_output_tokens:2048
```

An agent file is the only kind of alias there is, so it also
composes: put a model after an agent you include and the
model wins, since the last model named is the one that
answers — the same rule as a tool's last definition.

```m8
▐ 🧠mathy
▐ 🧠/local/Ternary-Bonsai-27B-mlx-2bit,max_output_tokens:16384
```

A chat is the same: a model piped in after one runs it, and
every turn after that is still on it, because the model is
later in the ledger than the agent it took over from.

### Providers

A provider is a command. It reads a request on stdin and
writes a response on stdout — the same shape a tool has, a
filter that stays in a pipeline. Reaching a url is one such
command rather than the privileged path, so anything you can
write a program for is a provider.

`core/providers.json`:

```json
{
  "toy": {
    "cmd": ["m8", "toy-provider"],
    "models": ["m8", "toy-provider", "--models"]
  },
  "local": {
    "cmd": ["m8", "url-provider"],
    "encode": ["m8", "encode", "openai-responses"],
    "parse": ["m8", "parse", "openai-responses"],
    "url": "http://127.0.0.1:8000/v1/responses",
    "models-url": "http://127.0.0.1:8000/v1/models",
    "models": ["sh", "-c", "\"$M8\" url-provider --get \"$M8_PROVIDER_MODELS_URL\" | tr ',' '\\n' | sed -n 's/.*\"id\" *: *\"\\([^\"]*\\)\".*/\\1/p'"],
    "header-authorization": "echo Bearer $(cat ~/.omlx/key)"
  },
  "anthropic": {
    "cmd": ["m8", "url-provider"],
    "encode": ["m8", "encode", "anthropic-messages"],
    "parse": ["m8", "parse", "anthropic-messages"],
    "url": "https://api.anthropic.com/v1/messages",
    "header-anthropic-version": "echo 2023-06-01",
    "header-x-api-key": "security find-generic-password -s anthropic-api-key -w"
  }
}
```

Four entries mean anything to m8, and each is a command:

* `cmd` gets the request answered.
* `encode` makes the ledger a request.
* `parse` makes the answer a turn.
* `models` lists what it serves. See Listing models.

The first three are one pipeline, each one's output the next
one's input:

* m8 writes the ledger in, as m8.
* m8 reads the turn out, as m8.
* With no `encode` or `parse`, `cmd` is handed m8 and
  answers in it, as `toy` does.
* Which apis there are is no list m8 holds.
  The ones it ships are `m8 encode` and `m8 parse`,
  named the way a command of your own would be.

What a stage says on stderr is held until the turn is in:

* A provider that answered has it passed on as it was said.
* One that failed has it given as the reason.
* `-v` reaches every stage as `M8_VERBOSITY`,
  so each says no more than was asked for.

Every string in the entry is handed to all three as
`M8_PROVIDER_*` on top of the inherited environment, and
means whatever a command makes of it. `url` arrives as
`M8_PROVIDER_URL`, `api-version` as
`M8_PROVIDER_API_VERSION`. Only string values with
lowercase-and-hyphen keys go, because only those have a name
to take. The commands stay behind — each already knows what
it is.

`header-` is nothing special to m8. It is `m8
url-provider`'s one convention rather than the language's, and it is
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

#### Listing models

```bash
m8 models                  every provider that can say
m8 models local codex      the ones named
```
```m8
#### :brain:/local/Ternary-Bonsai-8B-mlx-2bit
#### :brain:/codex/gpt-5.5
```

* `models` in an entry is a command that prints one model
  name a line.
  * It is handed the entry as `M8_PROVIDER_*`, as `cmd` is.
  * `$M8` names the m8 that is running.
* `m8 models` runs each and writes a 🧠 per name, spelled
  the way one is asked for.
* m8 knows no api's shape for a list.
  * Reaching the list and picking the names out of it are
    the command's business, beside the url that needs them.
  * A list that cannot be fetched is a `printf` of names.
* `m8 url-provider --get URL` asks a url with the entry's
  headers, so a key is not spelled out twice.
  * `models-url` is no key of m8's: it arrives as
    `M8_PROVIDER_MODELS_URL` like any other string.
* A provider with no `models` is left out.
* m8 says nothing of its own: what a command says on
  stderr is passed on.

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
* A name that names a file in a `core/` is that file, nearest
  first — and if it is not executable, that is an error rather
  than a fall-through to something else of the same name.
* A bare word is searched for on `PATH`.
* Anything else fails.

So a provider you write lives beside the config that names it,
in `core/`, and is reached as `["my-provider"]`.

#### Speaking m8

A provider declaring `api: "m8"` is handed the ledger itself
rather than a projection of it — 🧰 with its command and its 🛡
included — and answers in the same language.

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

Worked entries for oMLX, Anthropic and a ChatGPT plan
are in [docs/providers.md](docs/providers.md).

#### The ones m8 ships with

```bash
m8 url-provider              post the request to $M8_PROVIDER_URL
m8 url-provider --get URL    ask a url, with the same headers
m8 toy-provider              answer it here
m8 toy-provider --models     its models, one name a line
```

* Each is a command like any other, with a page of its own
  under `--help`.
* A provider command reads a request on stdin.
  * A terminal there is nobody piping one, so it says what
    it is instead of waiting for an end of file that is not
    coming.
* Which models a provider serves is in no config.
  * That is the ledger's business, written on the 🧠 that
    names one, so nothing has to be kept in step with what
    a provider offers.
  * `m8 models` asks each provider instead.

`toy` is configured like any other, with the first entry of
the `core/providers.json` above. It speaks m8 and answers
without a network, which is
what makes the loop, tool calling, and picking up a call that
was never answered testable rather than only demonstrable:

```bash
m8 @/toy/echo -- hello     # says the last thing said
m8 @/toy/runner -- 'RUN;;;say;;;text=hi'
m8 @/toy/eliza -- "I am not sleeping well."
m8 @/toy/Z-Machine/zork1 -- "I would like to play"
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
be: `m8 ref @ | m8 encode m8 >save.md` already is one, and
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
repositories carry the compiled files. `m8 toy-provider
--models` lists what it can find.

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

What m8 adds when launching a provider or a call:

```
M8               absolute path of the m8 launcher running it;
                  an inherited value is always overwritten
M8_VERBOSITY      1 under -v, 2 under -vv; a tool is handed
                  it too, and an m8 started with it set says
                  as much without being asked
```

And what a provider's commands are handed as well:

```
M8_PROVIDER_*     every string the entry said
```

The two m8 ships with read `M8_PROVIDER_URL` and
`M8_PROVIDER_HEADER_*` between them, and `m8 url-provider
--help` says what each is for. A provider you write reads
whatever its entry says, under its own name.

Every tool is handed the mob's scratch as `TMPDIR`, and its
`HOME` is left alone.

Moving `HOME` or dropping what was inherited is a shield's
business. See `contain-home` and `contain-env` under Shields.
