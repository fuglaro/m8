
# M8 (mEight) - The Composable Shell Harness

This framework brings the power of agents to the shell,
and can be composed into coding and agentic harnesses.

It is fearcly opinionated on simplicity, modularity,
composability, and separation so it can be utterly
void of any opinion on model, prompt, tool,
or agent structures. That is handed carfully to
the user in structures that are easily crafted,
generated, shared, and also provided as defaults.

Buds compose entire collections of agents, skills,
and starting scripts, as bundled manifests.

## Commands

```bash
m8 @mathy "Tell me about the Riemann Sphere in detail."
```

```bash
echo "🧑Tell me about the Riemann Sphere in detail." | m8 @mathy
```

```bash
echo "🔔mathy\n🧑Tell me about the Riemann Sphere in detail." | m8
echo "==="
cat ".m8/+/0A9C9680-6CC1-46F0-BFF8-50B02BA1D9B9"
```
```
🤖The Riemann Sphere is a ...
🧠+/0A9C9680-6CC1-46F0-BFF8-50B02BA1D9B9
===
🔔mathy
🧑Tell me about the Riemann Sphere in detail.
🤖The Riemann Sphere is a ...
🧠+/0A9C9680-6CC1-46F0-BFF8-50B02BA1D9B9
```

```bash
m8 @+/0A9C9680-6CC1-46F0-BFF8-50B02BA1D9B9 "Tell me more."
echo "==="
cat ".m8/+/E3C39A39-8ED3-4F4B-A7F1-32DA0DA0AF76"
```
```
🤖Additionally, ...
🧠+/E3C39A39-8ED3-4F4B-A7F1-32DA0DA0AF76
===
🔔+/0A9C9680-6CC1-46F0-BFF8-50B02BA1D9B9
🧑Tell me more.
🤖Additionally, ...
🧠+/E3C39A39-8ED3-4F4B-A7F1-32DA0DA0AF76
```

* 🧠 Saves to the nearest existing m8 config folder.
* If a tty is connected, iteractive mode is activated,
  which steams tokens without buffering.

## Language and Schema

Agent definition:

```m8
🔔Include Skill, Agent Name or Model
🔔Include Skill, Agent Name or Model
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
Use a U+2063 (Invisible Separator) between
the newline and any of the special unicode
characters to escape.
A 🔹 is used to separate fixed numbers of
fields in structured lines, while being
safely usable in the last field.
💻Included Agents inject Tools and System
Prompts.
🧠Saved as Agent Name
```

Query:

```m8
🔔Agent or Model Name
🧑User Content Text
💭Assistant Thoughts
🔏Optional Associated Metadata & Signatures
🤖Assistant Content Text
📞Tool Request Type🔹Call ID
📞Tool Request Type🔹Call ID
🧩Tool Property Name🔹Value encoded as string
🚫Call ID🔹Error response
📃Call ID🔹Text response
```

Simple eample query with definition:

```m8
📖local/Ternary-Bonsai-8B-mlx-2bit
💻You are a mathematics expert that will answer questions,
give insight, and advise on any relevant technique.
Describe concepts with analogies and spacial models
that can be imagined by a human and include how it relates
to the components, equations, and relationships in
the mathematical equations.
🧠mathy

🔔mathy
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
U+1FAFF. An unknown character from that range
at the start of a line is an error, anything
else is content.
A \r immediately before a \n is stripped, exactly
one, so \r\r\n ends content in a literal \r.

### TODO: Consider the following.
Local Wikipedia search with vector database...
Native Functions.
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

### Providers

`providers.json`:

```json
{
  "local": {
    "url": "http://localhost:11337/v1",
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
