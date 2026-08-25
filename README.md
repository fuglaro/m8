
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
m8 [@AGENT|+CHAT] [-- PROMPT]
m8 COMMAND [ARGS]
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
cat ".m8/=/tduyxbutjb.md"
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

* A prompt follows `--`, so it may say anything at all.
  Omit it and the prompt is read from stdin instead.
* Omitting the name continues the last chat of any agent.
* 🧠 names an agent, and naming one is how you use it.
  Agents are identified by their file, so nothing
  declares its own name. `@` is how the command line
  names one; it is not part of the language.
* Names are paths and the folder part is the mob.
  Turns save into `=`, chats into `+`. See Mobs.
* 🧠 resolves against the config folders first, and only
  then as `provider/model`. That is what tells `=/tduyxbutjb`
  apart from `local/Ternary-Bonsai-8B-mlx-2bit`.
* Saving is to the nearest existing m8 config folder.
* If a tty is connected, interactive mode is activated,
  which streams tokens without buffering and renders
  the reply. Everything else is written as markdown.
* A first word that is none of those names a command.
  A prompt is never one, because a prompt follows `--`.

### Calling

```bash
m8 call [-w R]... NAME [ARGS]     an m8 command
m8 call [-w R]... -- PROG [ARGS]  a program from the environment
```

`call` is what 🔌 expands into, and `-w` is how much
of the world it keeps. Each restriction only ever
subtracts, so they combine in any order and none of
them can widen another.

```
contain-reads    no reading outside cwd, TMP, system and tool dirs
private          as above, and tool dirs go too
contain-writes   writes confined to cwd and TMP
no-writes        nothing is writable, including TMP
airgap           no internet; loopback and unix sockets stay
no-loop          no loopback or unix sockets; internet stays
sandbox          private + contain-writes + no-loop
jail             sandbox, and no internet either
```

```bash
m8 call -w sandbox -- bash -c "ls"
```

With no `-w` there is nothing to enforce, so the
program is run directly rather than through a
sandbox that grants everything. Restrictions need
`sandbox-exec`, so they are macOS only.

`m8 call` on its own prints this list.

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
▄ 🧠local/Ternary-Bonsai-8B-mlx-2bit

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

## Configs

Configs merge nearest first, searching up from the
working directory and searching outwards:

* `./.m8/` and every `.m8/` above it
* `$XDG_CONFIG_HOME/m8/` else `~/.config/m8/`

Agents are found at `<config_dir>/<name>.md`.

```
.m8/
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

### Providers

`providers.json`:

```json
{
  "local": {
    "url": "http://127.0.0.1:11337/v1",
    "key": "sed -n 's/.*\"api_key\" *: *\"\\([^\"]*\\)\".*/\\1/p' ~/.omlx/settings.json",
    "api": "openai",
    "models": {
      "Ternary-Bonsai-1.7B-mlx-2bit": { "context": 32768, "output": 8192 },
      "Ternary-Bonsai-4B-mlx-2bit":  { "context": 32768, "output": 8192 },
      "Ternary-Bonsai-8B-mlx-2bit":  { "context": 32768, "output": 8192 },
      "Ternary-Bonsai-27B-mlx-2bit": { "context": 32768, "output": 8192 },
      "tiny": { "use": "Ternary-Bonsai-1.7B-mlx-2bit", "context": 4096, "output": 2048 }
    }
  }
}
```

The `use` property points directly to the model in the provider,
but can be omitted to default to the configured model name.
Providers may serve models unlisted in the config which
will also be accessible.

# Bonsai setup on oMLX

```bash
# Check metal is available so fast kernels install.
brew tap jundot/omlx https://github.com/jundot/omlx
brew install jundot/omlx/omlx --with-custom-kernel --with-grammar
```

