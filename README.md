
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

Three things make it different:

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

See PRIOR-ART.md for who else is nearby.

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
# :brain:mathy

# :raising_hand:
> Tell me about the Riemann Sphere
> in detail.

# :robot:
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
m8 send [PROVIDER]                 run a ledger and save the turn
```

`m8` is a format like any other here, so `encode m8` is
how a chat becomes one flat document. It is the only one
that loses nothing.

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

Encoding may lose whatever the target cannot say, and
that is what makes it a projection: chat completions has
no 🔌 in it and cannot tell a 🚫 from a 🧾.

Coming the other way loses one thing only. A request says
which model and everything to ask it for, and never whose
model it was — so `openai-completions → m8 → openai-completions`
is the same request, byte for byte, and all `send` needs is
the provider. That is why parameters live on the 🧠 rather
than in a config keyed by a name the wire never carries.

`decode` is a run command: it is the way in rather than
a filter, so it takes stdin exactly as it arrives. There
is no ledger to assemble yet, and naming an agent at it
is refused rather than dropped.

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
receipt, or 🚫 when it exits non-zero. `--raw` hands
stdout straight through instead.

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

▄ 💻
│ System Prompt
│ A record is a header and a content block, and
│ content is verbatim, so this line may begin with
│ anything at all.
│ A , separates a fixed number of fields, so the
│ last field may hold one safely.

▄ 💻
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
```

Simple example query with definition:

```m8
▄ 🧠/local/Ternary-Bonsai-8B-mlx-2bit,max_tokens:8192

▄ 💻
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

Sigils are a closed set, written as emoji within
U+1F300 to U+1FAFF or as `:word:`. An unknown sigil
in either spelling is an error.

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

* ▄ header -> `#`
* │ content -> `>`
* 🧠 agent -> `:brain:`
* 🙋 user -> `:raising_hand:`
* 🤖 bot -> `:robot:`
* 💭 thinking -> `:thought_balloon:`
  * 🔏 signature -> `:lock_with_ink_pen:`
* 📲 call -> `:calling:`
  * 📦 package -> `:package:`
* 🧾 result -> `:receipt:`
* 🚫 failed -> `:no_entry_sign:`
* 📚 skill -> `:books:`
* 💻 system -> `:computer:`
* 🔓 allow -> `:unlock:`
* 🧰 tool -> `:toolbox:`
  * 🔌 command -> `:electric_plug:`
  * 📦 required -> `:package:`
  * 🎁 optional -> `:gift:`

A sigil takes a value, a content block, or both.

* Value only: 🧠 📚 🔓 🔏 🔌
* Content only: 🙋 🤖 💭 💻
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

`core/` is the exception. It holds the two files that
decide what a lock *means*, and it is read from your
own config only — a project folder arrives with a
`git clone`.

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

`providers.json`:

```json
{
  "local": {
    "url": "http://127.0.0.1:11337/v1",
    "key": "sed -n 's/.*\"api_key\" *: *\"\\([^\"]*\\)\".*/\\1/p' ~/.omlx/settings.json",
    "api": "openai-completions"
  }
}
```

A provider is a url, an api, and a way to get a key. That is
all of it. Which models it serves and what to ask them for is
the ledger's business, written on the 🧠 that names one — so
nothing here has to be kept in step with what a provider
offers, and a model it has never listed works like any other.

`api` names a codec, which is the same name `m8 encode`
takes. There is no second table mapping one to the other, and
the codec is also what says which path under `url` it lives
at.

A provider that speaks two apis is two providers pointing at
one url, rather than a second kind of override:

```json
{
  "local":   { "url": "http://127.0.0.1:11337/v1", "api": "openai-completions" },
  "local-r": { "url": "http://127.0.0.1:11337/v1", "api": "openai-responses" }
}
```

# Bonsai setup on oMLX

```bash
# Check metal is available so fast kernels install.
brew tap jundot/omlx https://github.com/jundot/omlx
brew install jundot/omlx/omlx --with-custom-kernel --with-grammar
```

