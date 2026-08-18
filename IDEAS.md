
# M8 (mEight) - The Composable Shell Harness

This framework brings the power of agents to the shell,
and can be composed into coding and agentic harnesses.

It is fearcly opinionated on simplicity, modularity,
composability, and separation so it can be utterly
void of any opinion on model, prompt, tool,
or agent structures. That it handed carfully to
the user in structures that are easily crafted,
generated, shared, and provided as defaults.

Buds compose entire collections of agents, skills,
and starting scripts, as bundled manifests.

## Configs

```bash
```


## Commands

```bash
m8 @mathy "Tell me about the Riemann Sphere in detail."
```

## Language and Schema

Agent definition:

```m8
🧠Agent or Model
📖Include Agent or Model
📖Include Agent or Model
🔧Allow Tool Name
📐Tool Name🔹Tool Description
📦Required Property Name🔹Type🔹Description
🎁Optional Property Name🔹Type🔹Description
💻System Prompt
The separators for this language consist of
a newline immediately followed by a unicode
character from the set exemplified here.
Use a U+2063 (Invisible Separator) between
the newline and any of the special unicode
characters to escape.
A 🔹 is used to separate fields in
structured lines like when defining tools
and it can be safely used elsewhere.
💻Included Agents inject Tools and System
Prompts.
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
❌Call ID🔹Error response
📃Call ID🔹Text response
```

Simple eample query with definition:

```m8
🧠mathy
📖omlx/Ternary-Bonsai-8B-mlx-2bit
💻You are a mathematics expert that will answer questions,
give insight, and advise on any relevant technique.
Describe concepts with analogies and spacial models
that can be imagined by a human and include how it relates
to the components, equations, and relationships in
the mathematical equations.

🔔mathy
🧑Tell me about the Riemann Sphere in detail.
```

System Prompt is stable by design. Volatile data like time
or reading README.md data should be put into the query
with user content text or a user added tool request.
At some point we might add a concept of
📚Scripts which are predefined sections of query
including tool requests to be invoked,
and which are referencable by name.
Local Wikipedia search with vector database...
Native Functions.
MCP output schema.

# Bonzai setup on oMLX

```bash
# Check metal is available so fast kernels install.
brew tap jundot/omlx https://github.com/jundot/omlx
brew install jundot/omlx/omlx --with-custom-kernel --with-grammar
```



Assistant negged a gap> 📐📦🎁 is a JSON-Schema subset — no enums, arrays, nesting, oneOf. Enums are the one worth adding early: common, and
they're what a grammar constrains against most usefully, so they pay for themselves twice.
