
# M8 (mEight) - The Composable Shell Harness

This framework brings the power of agents to the shell,
and can be composed into coding and agentic harnesses.

It is fearcly opinionated on simplicity, modularity,
composability, and separation so it can be utterly
void of any opinion on model, prompt, tool,
or agent structures. That is handed carfully to
the user in structures that are easily crafted,
generated, shared, and also provided as defaults.

Mobs compose entire collections of agents, skills,
and starting scripts, as bundled scripts.

## Commands

```bash
m8 [@AGENT|+CHAT] [-- PROMPT]
```

```bash
m8 @mathy -- "Tell me about the Riemann Sphere\nin detail."
m8 +mathy -- "Tell me more."
m8 -- "Summarize in one sentence."
```

```bash
echo "Tell me about the Riemann Sphere\nin detail." | m8 @mathy
echo "==="
cat ".m8/=/tduyxbutjb.m8"
```
```
🤖The Riemann Sphere is a ...
🧠=/tduyxbutjb
===
🧠mathy
🧑Tell me about the Riemann Sphere
  in detail.
🤖The Riemann Sphere is a ...
```

```bash
m8 @=/tduyxbutjb -- "Tell me more."
echo "==="
cat ".m8/=/ypfpkuimzg.m8"
```
```
🤖Additionally,
  ...
🧠=/ypfpkuimzg
===
🧠=/tduyxbutjb
🧑Tell me more.
🤖Additionally,
  ...
```

* A prompt follows `--`, so it may say anything at all.
  Omit it and the prompt is read from stdin instead.
* Omitting the name continues the last chat of any agent.
* 🧠 names an agent, and naming one is how you use it.
  `@` is its typeable spelling. Agents are identified by
  their file, so nothing declares its own name.
* Names are paths and the folder part is the mob.
  Turns save into `=`, chats into `+`. See Mobs.
* 🧠 resolves against the config folders first, and only
  then as `provider/model`. That is what tells `=/tduyxbutjb`
  apart from `local/Ternary-Bonsai-8B-mlx-2bit`.
* Saving is to the nearest existing m8 config folder.
* If a tty is connected, interactive mode is activated,
  which streams tokens without buffering.

## Language and Schema

Agent definition:

```m8
🧠Include Skill, Agent Name or Model
🧠Include Skill, Agent Name or Model
🔧Allow Tool Name
📐Tool Name🔹Tool Description
  📦Required Property Name🔹Type🔹Description
  🎁Optional Property Name🔹Type🔹Description
📐Tool Name🔹Tool Description
  📦Property Name🔹Enum Val|...🔹Enums have |
  📦Property Name🔹Type[]🔹Arrays suffix []
  📦Parent Name🔹object🔹Mandatory Parent Def
  📦Parent Name.Property Name🔹Type🔹Nested
💻System Prompt
  The separators for this language consist of
  a newline immediately followed by a unicode
  character from the set exemplified here.
  Blocks can continue by adding a double
  space after the newline,
  which will be ignored.
  An empty line continues a block too, so a
  paragraph break never depends on trailing
  spaces an editor would strip.
  A 🔹 is used to separate fixed numbers of
  fields in structured lines, while being
  safely usable in the last field.
💻Included Agents inject Tools and System
  Prompts.
```

Query:

```m8
🧠Agent or Model Name
🧑User Content Text
💭Assistant Thoughts
🔏Optional Associated Metadata & Signatures
🤖Assistant Content Text
📞Tool Request Type🔹Call ID
📞Tool Request Type🔹Call ID
  📜Tool Property Name🔹Value encoded as string
📟Call ID🔹Text (error) response
🚫Call ID
📟Call ID🔹Text response
🟢Call ID
```

Simple eample query with definition:

```m8
🧠local/Ternary-Bonsai-8B-mlx-2bit
💻You are a mathematics expert that will answer questions,
  give insight, and advise on any relevant technique.
  Describe concepts with analogies and spacial models
  that can be imagined by a human and include how it relates
  to the components, equations, and relationships in
  the mathematical equations.
🧑Tell me about the Riemann Sphere in detail.
```

System Prompt is stable by design.
Volatile data such as the time or when reading
files, should be put into the query,
with user content text or a user added tool request.
📚Scripts can also be included, which are predefined
sections of query, including tool requests to be invoked,
and which are referencable by name.
Sigils are a closed set within U+1F300 to
U+1FAFF. A record starts where one appears at
column 0, and an unknown character from that
range there is an error. Every other line is
indented or empty and continues the block
above it, so a body may hold a line that looks
like a sigil and no escape is needed.
A \r immediately before a \n is stripped, exactly
one, so \r\r\n ends content in a literal \r.

### TODO: Consider the following.
Local Wikipedia search with vector database...
Native Functions.
Tools responding with text response.
MCP output schema.

## Types

Type rules compose - `Type[]` covers `object[]`.
A array `[]` suffix applies to the whole field.
Enum values cannot contain a `|`.
Nesting is flat dotted paths.
Parents are always declared, never inferred.
Arrayness lives only on the parent type
and children use plain dots.
Optionality (📦 and 🎁) apply at every depth,
so an optional object with required children
is either absent or complete.
There is no oneOf - a discriminator enum with
optional fields constrains better and lets the
tool return a real error instead of a schema
rejection.

## Configs

Configs merge nearest first, searching up from the
working directory and searching outwards:

* `./.m8/` and every `.m8/` above it
* `$XDG_CONFIG_HOME/m8/` else `~/.config/m8/`

Agents are found at `<config_dir>/<name>.m8`.

```
.m8/
  providers.json
  mathy.m8              @mathy
  team/reviewer.m8      @team/reviewer
  +/+.m8                ++
  +/mathy.m8            +mathy
  +/team/reviewer.m8    +team/reviewer
  =/tduyxbutjb.m8       @=/tduyxbutjb
```

### Mobs

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
🧠=/tduyxbutjb
🧑Tell me more.
🤖Additionally, ...
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

# Bonzai setup on oMLX

```bash
# Check metal is available so fast kernels install.
brew tap jundot/omlx https://github.com/jundot/omlx
brew install jundot/omlx/omlx --with-custom-kernel --with-grammar
```

