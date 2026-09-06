
# mEight - The Composable Shell Harness

Bringing the `m8` command to the terminal.

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
  `=` holds immutable turns naming their parent,
  `+` holds movable references into them.
  It is git's objects and refs, for conversations,
  on the filesystem.
* Tools are filters. A tool reads m8 and writes m8,
  and talks to the user on `/dev/tty`, so it stays
  in the pipeline even while it is interactive.

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

### Four formats were always one

An agent definition, a transcript, a wire request and a
tool exchange are one sequence of records seen at four
moments. A definition is a ledger nobody has answered
yet. A transcript is one that has been. A request is
that ledger projected onto what a model can be told. A
call and its answer are records in it like any other.

Keeping them apart costs four parsers. A template
language turns config into a prompt. A serialiser turns
history into a request. An adapter turns the response
back into history. A schema dialect describes tools and
matches none of the other three. Four things to learn,
four to version, four places to lose something.

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
@/inbuilt/Z-Machine/zork1` holds a conversation with a
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
* One binary from `zig build`. `build.zig.zon` declares
  no dependencies. Nothing vendored, nothing fetched at
  build time, no libcurl, no OpenSSL, nothing to
  CVE-track that is not the toolchain.
* No daemon, no database, no account, no telemetry, no
  bundled weights, and no network needed to build or
  test. `inbuilt` answers locally, so the loop, tool
  calling and recovery are all testable offline.
* Config under XDG. stdin in, stdout out, errors to
  stderr, `--help` answered in one place.
* Everything it stores is text you could have typed.

That is the shape of a package a distribution carries
for thirty years, because it is the shape of `grep` and
`jq`. Single-binary agent runtimes exist. Single-binary
agent runtimes whose entire state is files you can read
do not.

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
  proved a tool is just a script. That is 🧰 and 🔓.
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
[`SKILL.md`](https://anomity.ai/blog/agent-skills-open-standard-adoption-governance/)
went open standard in December 2025 and had 16+ adopters
by March 2026. A skill is a folder with frontmatter, and
a mob is already a folder. The
[2026-07-28 MCP spec](https://blog.modelcontextprotocol.io/posts/2026-07-28/)
took tool schemas to full JSON Schema 2020-12, and MCP
went to the Linux Foundation, so 🧰 is generated from an
MCP server rather than authored against one. That is
worth doing for its own sake as well: one study measured
MCP integration inflating input tokens
[236x while dropping accuracy 9.5%](https://arxiv.org/html/2508.12566v1),
so rendering those tools into something terse is a
contribution. And forking shipped in a mass-market
product in June 2026, which makes branching table stakes
rather than a differentiator. It is still a menu command
over state you cannot open.

## Commands

```bash
m8 [-l LOCKS] [[@AGENT|+CHAT] MSG_CMD|RUN_CMD] [ARGS]
```

```bash
m8 @mathy -- "Tell me about the Riemann Sphere\nin detail."
m8 +mathy -- "Tell me more."
m8 -- "Summarize in one sentence."
```

```bash
echo "Tell me about the Riemann Sphere\nin detail." | m8 @mathy
```
```
▄ 🤖
│ The Riemann Sphere is a ...

▄ 🧠=/tduyxbutjb
```

The reply went to a tty, so it is rendered. The turn
it saved is a file, so it is markdown:

```bash
cat ".m8-st8/=/tduyxbutjb.md"
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
m8 @=/tduyxbutjb -- "Tell me more."
```
```
▄ 🤖
│ Additionally,
│ ...

▄ 🧠=/ypfpkuimzg
```

* There are two kinds of command. A **message command**
  may be preceded by an `@AGENT` or `+CHAT`, and is
  handed the ledger that assembles. A **run command**
  takes no name, because there is no ledger for one to
  go into.
* `--` is a message command, not punctuation. It is the
  one whose arguments are prose, so everything after it
  is what you want to say and nothing has to arbitrate
  between m8's arguments and yours.
* A bare `m8`, and a name with nothing after it, run
  `--`. So consulting an agent and running a filter are
  one path.
* The name is appended as the 🧠 it is, not as what it
  expands to, so a saved turn names its parent instead
  of copying it. Expanding happens in whichever command
  needs it.
* Omitting the name continues the last chat of any agent.
* 🧠 names an agent, and naming one is how you use it.
  Agents are identified by their file, so nothing
  declares its own name. `@` is how the command line
  names one; it is not part of the language.
* Names are paths and the folder part is the mob.
  Turns save into `=`, chats into `+`. See Mobs.
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
* A first word that is none of those names a command.

Every command has a page, and anything under a command
has one too:

```bash
m8 help                    every command, and what m8 reads
m8 help send               one of them
m8 send --help             the same page
m8 help providers url      what is under one
m8 providers url --help    the same page again
```

`--help` is m8's rather than any command's, so no command
has to parse it and no two answer it differently. The one
exception is `--`, whose arguments are prose: there it is
something you said, and `m8 help --` is how that page is
asked for.

A page you asked for is written to stdout, where it can
be paged and piped. A page handed back instead of what
you asked for goes to stderr, where it cannot become part
of a document.

### Assembling

A message command is handed a ledger built from three
things: the name, whatever was piped in, and the prompt,
in that order.

```
nothing piped   NAME (or the last chat) → prompt
m8 piped        NAME → the document → prompt
anything else   NAME (or the last chat) → prompt, then the text
```

One rule is behind all three: what arrived is the
context, and nothing is added to it that was not asked
for. A document that arrived is a ledger already, so no
last chat is grafted onto it. Anything else piped in is
prose rather than context — it is what somebody would
have typed after `--` — so it joins the prompt, and the
fallback still applies.

```bash
m8 -- "Tell me about the Riemann Sphere."
cat notes.txt | m8 -- "Summarize:"        # one 🙋, prompt first
cat ledger.md | m8 send local             # the ledger is what arrived
echo "risky question" | m8 +mathy encode openai-completions
```

That last one is how a prompt reaches a command that is
not `--`: raw stdin is the prompt channel, so a request
can be built and read before anything is sent.

Piping is not required, and neither is a prompt when
something was piped. With neither, there is nothing to
say, and m8 says what it is instead.

A document is told from prose by its first line alone,
so one that opens like a document and then goes wrong is
an error rather than a prompt.

### Encoding

```bash
m8 [@AGENT|+CHAT] encode FORMAT    a ledger, as some api sees it
m8 decode FORMAT                   that api's request, as a ledger
m8 parse FORMAT                    that api's response, as a turn
m8 send [PROVIDER]                 run a ledger and save the turn
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
m8 +mathy encode m8
m8 +mathy encode m8 >full-ledger-copy.md
m8 decode m8 <full-ledger-copy.md      # the null operation
```

```bash
m8 +mathy encode openai-completions
m8 encode openai-completions <full-ledger-copy.md >openai.json
m8 decode openai-completions <openai.json
```

```bash
m8 decode openai-completions <openai.json | m8 send local
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
rather than the ledger. A tool comes back without its 🔌 or
its 🔒 — a model call has no business carrying either, so
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
all `send` needs is the provider. That is why parameters
live on the 🧠 rather than in a config keyed by a name the
wire never carries.

`decode` and `parse` are run commands: they are the way in
rather than filters, so they take stdin exactly as it
arrives. There is no ledger to assemble yet, and naming an
agent at one is refused rather than dropped.

`parse` is the third direction. `encode` and `decode` are
about requests, which are ledger-shaped; a response is
turn-shaped, so it is not decoded into a ledger but read
into the records it adds to one. With it, the whole loop is
something you can watch happen:

```bash
echo "Say hi." | m8 @mathy encode openai-completions \
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
m8 [-l LOCKS] call NAME [ARGS]     an m8 command
m8 [-l LOCKS] call -- PROG [ARGS]  a program from the environment
```

`call` is what 🔌 expands into. `-l` belongs to `m8`
rather than to `call`, because a lock covers a whole
run and not one command, and it adds to whatever the
agent already carries.

```bash
m8 -l sandbox call -- bash -c "ls"
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

`m8 call` on its own prints every lock. See Locks.

`call` also reaches m8's own filters and its inbuilt
tools, which is what `m8 call ask` is: a tool that puts
a question to the person and appends their answer to the
document, so the next command in the pipe sees it. An
inbuilt tool is never typed as a command of its own.

## Language and Schema

Agent definition:

```m8
▄ 🧠Address, Agent Name or Model

▄ 🧰Tool Name
│ 🔌`["cmd", "{{Property Name:--flag}}", "{{Property Name}}"]`
│ 📦Required Property Name,Type
│ │ Property Description
│ 🎁Optional Property Name,Type
│ │ Property Description
│ Tool Description

▄ 🧰Tool Name
│ 🔌`["m8", "call", "{{Property Name:-w}}", "--", "{{Property Name}}"]`
│ 📦Property Name,Enum Val|...
│ │ Enums have |
│ 📦Property Name,Type[]
│ │ Arrays suffix []
│ 📦Parent Name,object
│ │ Mandatory Parent Def
│ 📦Parent Name.Property Name,Type
│ │ Nested
│ Tool Description

▄ 🔓Allow Tool Name

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
│ 📦Tool Property Name
│ │ Value encoded as string

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

### TODO: Consider the following.
Local Wikipedia search with vector database...
Native Functions.
Tools responding with text response.
MCP output schema.
Wrapper scripts in a config folder, for the commands a template cannot say.
Command that writes the core config defaults for subsequent extension.
Customisable caps on infinite loop situations like cyclic agent-check or model tool loops.
Some good templating setups to support AGENTS.md
Support custom locks no-edit-* like no-edit-git
How should a user call at tool at a chat.

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
  * 📦 package -> `:package:`
* 🧾 result -> `:receipt:`
* 🟢 ok -> `:green_circle:`
* 🚫 failed -> `:no_entry_sign:`
* 📚 skill -> `:books:`
* 🧭 system -> `:compass:`
* 🔓 allow -> `:unlock:`
* 🧰 tool -> `:toolbox:`
  * 🔌 command -> `:electric_plug:`
  * 📦 required -> `:package:`
  * 🎁 optional -> `:gift:`

A sigil takes a value, a content block, or both.

* Value only: 🧠 📚 🔓 🔏 🔌 🟢
* Content only: 🙋 🤖 💭 🧭
* Both: 🧰 📦 🎁 📲 🧾 🚫

## Types

Type rules compose - `Type[]` covers `object[]`.
An array `[]` suffix applies to the whole field.
Enum values cannot contain a `|`.
Nesting is flat dotted paths.
Parents are always declared, never inferred.
Arrayness lives only on the parent type
and children use plain dots.
Optionality (📦 and 🎁) applies at every depth,
so an optional object with required children
is either absent or complete.
There is no oneOf - a discriminator enum with
optional fields constrains better and lets the
tool return a real error instead of a schema
rejection.

## Command Templates

🔌 is how a tool is run: a list of literal strings
and placeholders, expanded against the JSON of the
call. The value is wrapped in backticks, so it
renders as code wherever the document does.

Given `{"with": ["check", "sandbox"], "cmd_str": "echo hi"}`:

```
{{cmd_str}}       --cmd_str "echo hi"
{{cmd_str:-c}}    -c "echo hi"
{{with:-w}}       -w check -w sandbox
{{with:}}         check sandbox
```

A placeholder is a whole element and expands to as
many as it needs, so

```
["m8", "call", "{{with:-w}}", "--", "bash", "{{cmd_str:-c}}"]
```

runs

```
["m8", "call", "-w", "check", "-w", "sandbox", "--", "bash", "-c", "echo hi"]
```

The flag is `--` and the key unless you name one.
Naming replaces that leading `--key` and nothing
else, so anything beneath it still chains. Naming
nothing drops the flag and leaves the values.

On `{"opts": {"a": 1, "b": {"c": 2}}}`:

```
{{opts:-o}}       -o.a 1 -o.b.c 2
{{opts:}}         1 2
```

Objects expand their leaves and join the keys with
a `.`. Arrays expand in full, repeating the prefix
once per element, at whatever depth they occur and
whatever they hold. On `{"opts": [{"a": 1}, {"a": 2}]}`:

```
{{opts:-o}}       -o.a 1 -o.a 2
```

An array carries no index. That is the one place
the shape is lost, and it is what a POSIX command
wants.

📦 and 🎁 expand alike. They differ only when the
key is missing: a required one is refused by m8
before a command is built, an optional one is
simply left out.

* `null` and `false` omit the key entirely.
* `true` emits the flag with no value.
* `{{{...}}}` is a literal `{{...}}`.
* `{{}}` passes the whole JSON as one string. It is
  the last resort for a command this cannot say,
  and expects a script on the other side that would
  rather read JSON than flags.

## Locks

A lock only ever removes. That is the whole rule,
and everything else follows from it: any combination
is safe, the order never matters, and a lock can be
repeated without meaning anything different.

```bash
m8 -l sandbox -l no-edit-git call -- bash -c "ls"
```

One lock per `-l`, repeated — which is what a 🔒
array expands to through `{{lock:-l}}`.

### Where a lock is written

```m8
▄ 🔒jail, no-edit-git      the floor for this agent
▄ 🧰deploy
│ 🔒airgap                 and this tool as well
```

Three places, and they compose one way:

* **Top level**, in an agent. Cumulative over the
  lineage — the union of every 🔒 an agent and its
  includes carry. Inclusion can only tighten.
* **In a 🧰**, for one tool. The last definition of
  a name wins, as anywhere else.
* **`-l` on the command line.** Added to whatever
  the agent already carries.

The effective set for a tool is the union of the
floor and the tool's own. Since a union of things
that subtract is the narrowest of them, nothing
reachable from a locked agent can be looser than
the agent.

`lock` is a reserved property name. A 🧰 cannot
declare one and a call cannot supply one, or a model
could name its own.

### Where a lock is enforced

Kernel locks are lines in the sandbox profile. Every
descendant of a locked process inherits them, so
they hold however deep a tool spawns.

```
contain-reads    no reading outside cwd, TMP, system and tool dirs
private          as above, and tool dirs go too
contain-writes   writes confined to cwd and TMP
no-writes        nothing is writable, including TMP
airgap           no internet; loopback and unix sockets stay
no-loop          no loopback or unix sockets; internet stays
no-edit-git      no writing to a .git anywhere
no-edit-m8-st8   no writing to a config directory anywhere
sandbox          private + contain-writes + no-loop
                 + no-edit-git + no-edit-m8-st8 + contain-env
jail             sandbox, and no internet either
```

m8 locks are applied by m8, at the point it acts.

```
contain-env      the environment is rebuilt, not inherited
deny             no tool use at all
ask              every tool is put to you first
freeze-toolbox   a tool may not hand back 🧰 🔓 🧠 or 📚
agent-check=A    A is asked whether it looks safe
```

Applying at the point of action sounds weaker than
the kernel, and for these four it is not:

* `deny` is self-enforcing. No tools means no child
  process, so there is nothing to inherit it.
* `ask` gates the decision where the decision is
  made. Whatever happens downstream happens because
  you already said yes to something that could do
  it. With no terminal there is nobody to ask, and
  the answer is no.
* `freeze-toolbox` applies to each m8 as it reads
  its own tool responses, which is exactly where it
  belongs, at every depth independently.
* `contain-env` is applied once, when the child is
  built, and a child cannot put back what it never
  received.

### Two agents

One that cannot widen, whatever it includes or is
asked to do:

```m8
▄ 🧠/local/Ternary-Bonsai-8B-mlx-2bit,max_tokens:8192

▄ 🔒jail, freeze-toolbox

▄ 🧠team/helpers
```

`team/helpers` may define whatever tools it likes.
They all run jailed, because the floor is a union
and inclusion cannot subtract from it. Nothing this
agent is told can add a tool, because a reply is
never read for definitions and `freeze-toolbox`
closes the tool response channel too.

One that builds its own:

```m8
▄ 🧠/local/Ternary-Bonsai-27B-mlx-2bit

▄ 🧰toolmaker
│ 🔌`["m8", "call", "--", "make-tool", "{{spec}}"]`
│ 📦spec,string
│ │ What the tool should do
│ Write a new tool and return its definition.

▄ 🔓toolmaker
```

No 🔒 at all, so `toolmaker` may hand back 🧰 and 🔓
records and they are honoured. The two live happily
in one config, and neither can become the other.

### The checker

`agent-check=A` puts the candidate to agent `A`,
which answers `allow` or explains itself. Anything
else becomes `Failed agentic check: <response>`.

The locks in force are passed through to `A`, so a
checker is never more capable than what invoked it.
That is what stops a jailed agent reaching the
network by talking its own checker into it — and it
means the jailed-validator pattern, where a checker
runs the candidate somewhere tighter and reports
what happened, needs the caller loose enough to
allow it.

A checker reads text an attacker may have shaped.
It belongs beside `ask`, not instead of it.

### Thinking it through

* Decide the floor first. A 🔒 at the top of an
  agent is the only thing that cannot be argued
  with later.
* Prefer a level to a list. `sandbox` and `jail`
  say what they mean and pick up new locks as they
  are added; a hand-written list does not.
* Kernel locks survive anything the tool spawns.
  If a restriction has to hold three processes
  deep, it needs to be one of those.
* A mob you include can define tools. That is the
  point of a mob. Your floor is what makes it safe
  to include one you have not read.
* `no-edit-m8-st8` is what stops a tool rewriting
  the agent that constrains it. Without it, every
  other lock is advisory as of the next run.
* `core/` is denied to every locked process, always
  and untagged, which is what makes the profile
  safe to override from your own config.
* Read a config directory before working in it. It
  arrives with a `git clone` like anything else,
  and it defines what runs — though never what
  running is allowed to reach, which is `core/`,
  and yours alone.

## Configs

Configs merge nearest first, searching up from the
working directory and searching outwards:

* `./.m8-st8/` and every `.m8-st8/` above it
* `$XDG_CONFIG_HOME/m8-st8/` else `~/.config/m8-st8/`

`core/` is the exception. It holds the files that decide
what a lock *means* and what a provider *is*, and it is
read from your own config only — a project folder arrives
with a `git clone`, and a provider is a command that runs
on your machine. Each is a whole-file override of the copy
m8 ships with, not a merge.

Agents are found at `<config_dir>/<name>.md`.

```
.m8-st8/
  core/
    mac-sandbox.sb
    contain-env-allowed.txt
    providers.json
  mathy.md              @mathy
  team/reviewer.md      @team/reviewer
  +/+.md                ++
  +/mathy.md            +mathy
  +/team/reviewer.md    +team/reviewer
  =/tduyxbutjb.md       @=/tduyxbutjb
```

### Mobs

Mobs compose entire collections of agents, skills,
and starting scripts, as bundled packages.

A name is a path, so the folder part is the mob
it belongs to. Mobs bundle the agents, skills and
starting scripts that travel together.

Two mobs are generated rather than authored.

`=` holds turns. Every run writes one, named with
ten lowercase letters, and prints it back. A turn
holds only what it continues and the exchange —
its name is the file it is in, and it is never
rewritten.

```m8
▄ 🧠=/tduyxbutjb

▄ 🙋
│ Tell me more.

▄ 🤖
│ Additionally, ...
```

The 🧠 printed after a reply is not part of the
turn. It is the line you would write to continue
from it, which is also what you paste after `m8`.

`+` holds the chats, each a single 🧠 into `=`
and each rewritten every run. `+/mathy` is your last
chat with mathy, and `+mathy` on the command line
is short for `@+/mathy`. The chat for any agent at
all is named `+` too, so `++` reaches it and a bare
`m8` addresses it.

A chat is named after the first authored name in
the lineage, so continuing a chat keeps pointing at
the agent it began with.

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
composes: put a model in front of an agent you include and
the model wins, since the first 🧠 is the one that counts.

```m8
▄ 🧠/local/Ternary-Bonsai-27B-mlx-2bit,max_tokens:16384
▄ 🧠mathy
```

### Providers

A provider is a command. It reads an api-formatted request on
stdin and writes that api's response on stdout — the same
shape a tool has, a filter that stays in a pipeline. Reaching
a url is one such command rather than the privileged path, so
anything you can write a program for is a provider.

`core/providers.json`:

```json
{
  "inbuilt": {
    "cmd": ["m8", "providers", "inbuilt"],
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
rather than a projection of it — 🧰 with its 🔌 and its 🔒
included — and answers in the same language. It is trusted
with that because a provider command lives in `core/`, which
a cloned project cannot reach.

Worth knowing in both directions: it is more capable, and it
means a shim that forwards what it receives will forward your
local command lines. A provider speaking m8 is responsible for
projecting before anything leaves the machine.

#### Locks

Locks are not applied to a provider command. That is safe
rather than generous, and the reason matters:

A lock is a sandbox the child is launched inside, and
`sandbox-exec` is one way — a provider inherits whatever m8 is
already inside and can never shed it. So the rule only ever
means m8 adds nothing. A jailed agent's tool that reaches a
provider is still jailed, because it is a descendant of a
jailed process; what the rule buys is that a jailed *agent*
can still reach its own model, since an agent's locks are
applied to its tools rather than to m8.

Trust is held where the command is written down. `core/` is
read from your own config only, so a project cannot define
what runs. **Mobs travel with agents; providers are yours.**

#### The ones m8 ships with

```bash
m8 providers url       post the request to $M8_PROVIDER_URL
m8 providers inbuilt   answer it here
```

```bash
m8 providers                   these two, and what is configured
m8 providers url --help        what it reads, and from where
m8 providers inbuilt --help    which models it serves
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
provider offers. `inbuilt` is the exception, because its
models are m8's own.

`inbuilt` speaks m8 and answers without a network, which is
what makes the loop, tool calling, and picking up a call that
was never answered testable rather than only demonstrable:

```bash
m8 @/inbuilt/echo -- hello        # says the last thing said
m8 @/inbuilt/you-are -- anything  # "I know you are but what am I?"
m8 @/inbuilt/runner -- 'RUN;;;say;;;text=hi'
m8 @/inbuilt/eliza -- "I am not sleeping well."
m8 @/inbuilt/Z-Machine/zork1 -- "I would like to play"
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
be: `m8 ++ encode m8 >save.md` already is one, and
`cat save.md | m8 -- "look"` is the restore.

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
inbuilt` lists what it can find.

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
TMPDIR            where a locked tool's own directory is made;
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

# Bonsai setup on oMLX

```bash
# Check metal is available so fast kernels install.
brew tap jundot/omlx https://github.com/jundot/omlx
brew install jundot/omlx/omlx --with-custom-kernel --with-grammar
```


# Claude setup on the Anthropic api

The entry above reaches `https://api.anthropic.com/v1/messages`
and needs an api key. A Claude subscription does not include
one — the api is a separate product with its own billing — so
take a key from platform.claude.com/settings/keys and put it
where `header-x-api-key` looks:

```bash
security add-generic-password -s anthropic-api-key -a "$USER" -w
```

That header is a command, so anywhere else you already keep
secrets works as well — `pass`, `op read`, `gpg -d`, an
environment variable, a file only you can read.

Then a model is a 🧠 like any other, and a file is how it comes
to have a name:

```m8
▄ 🧠/anthropic/claude-opus-5,max_tokens:16000,thinking:{"type":"adaptive","display":"summarized"}
```

A parameter may be JSON, and a `,` inside it is the JSON's
rather than the form's, so an object goes on a 🧠 whole.

`display` is worth writing down. It is `omitted` by default on
every current model, which streams a thought with no text in
it — so without this a 💭 reaches the ledger carrying nothing
but its 🔏, and a terminal shows a long pause and then an
answer. Thinking happens and is billed the same either way;
the only question is whether the ledger gets to record it.

```bash
m8 @claude -- "Tell me about the Riemann Sphere."
m8 @/anthropic/claude-haiku-4-5,max_tokens:1024 -- "In one line."
```

# Codex setup on a ChatGPT plan

Unlike a Claude subscription, a ChatGPT plan reaches the api:
OpenAI has publicly backed third-party harnesses on a plan,
and GPT-5.5 is subscription-auth only with no api key at all.
It is tolerated rather than contracted, so the token shape is
theirs to change and this is the entry most likely to need a
line moved.

`codex login` writes an OAuth token to `~/.codex/auth.json`,
and requests carrying it reach the responses api billed to the
plan. So the entry is a url and a command that reads the token:

```json
"codex": {
  "cmd": ["m8", "providers", "url"],
  "api": "openai-responses",
  "url": "https://chatgpt.com/backend-api/codex/responses",
  "header-authorization": "echo Bearer $(...access_token from ~/.codex/auth.json...)",
  "header-chatgpt-account-id": "...the account id claim in that token...",
  "header-originator": "echo m8",
  "header-openai-beta": "echo responses=experimental",
  "header-accept": "echo text/event-stream"
}
```

None of that is a published api, so it is worth saying where it
came from: it is what Pi sends, and Pi is a harness reaching the
same endpoint for the same reason. `originator` is the client
naming itself — Pi sends `pi`, so m8 sends `m8`, and copying
somebody else's would be a lie told to a server that asked.

The endpoint speaks websockets first and falls back to server-sent
events, so posting to it is a supported path rather than a trick.
That is the whole reason `m8 providers url` can reach it at all.

Two things the codec sends without being asked, because every
client that speaks this api sends them and a ledger cannot do
without either: `store` off, so the conversation stays yours
rather than being kept and replayed by id at the far end, and
`include` naming `reasoning.encrypted_content`, without which a
💭 comes home with nothing to sign it. A 🧠 that names either
overrules it. One gotcha that is neither: the subscription
endpoint refuses `max_output_tokens`, so do not put one on a
🧠 aimed at it.

An api key instead, which reaches the same codec:

```json
"openai": {
  "cmd": ["m8", "providers", "url"],
  "api": "openai-responses",
  "url": "https://api.openai.com/v1/responses",
  "header-authorization": "echo Bearer $(security find-generic-password -s openai-api-key -w)"
}
```

```bash
m8 @gpt -- "Tell me about the Riemann Sphere."
m8 @/codex/gpt-5.6-luna -- "In one line."
```

GPT-5.6 is three models rather than one: `sol` is the
flagship, `terra` the balanced middle, `luna` the fast and
cheap one — the same three tiers as opus, sonnet and haiku,
and a file each. Which of them a subscription endpoint serves,
and whether it wants a `-codex` variant of the name instead,
is that endpoint's business rather than this file's.
