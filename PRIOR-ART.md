# Prior Art

Surveyed August 2026. Nobody is building mEight, but every
layer of it has a strong incumbent. This records who, what
they do better, and what we should join rather than rebuild.

## Neighbours

| Project | Overlap | Difference |
|---|---|---|
| [llm-md](https://codeberg.org/anuna/llm-md) | Conversations as flat markdown-like files, agents as external files, tool piping | Maximalist: `>>>`/`>>=`/`=>>`/`!>>` operators, `{{@tool:op $ args}}` interpolation, variables, control flow. A template language, not a record format. Racket, alpha |
| [Pi](https://pi.dev/) | Calls itself "a minimal terminal coding harness". Interactive/print/RPC/SDK modes. Deliberately excludes MCP, subagents, plan mode, permission popups | TypeScript, npm. Sessions are tree-structured internal state, not a user-facing format |
| [gptel](https://gptel.org/) | The file *is* the conversation. Save, reopen, resume, hand-edit past turns | `###` role prefixes, Emacs only, agent definition not unified with transcript |
| [simonw/llm](https://github.com/simonw/llm) | Unix piping, fragments, templates, `-c` to continue, huge plugin ecosystem | SQLite is the store. The deliberate opposite of our bet |
| [aichat](https://github.com/sigoden/aichat) + [llm-functions](https://github.com/sigoden/llm-functions) | Tools as plain bash scripts, schemas derived from comments | Our 🧰/🔓 layer, already built and shipping |
| [Prompty](https://prompty.ai/core-concepts/file-format/), [dotprompt](https://github.com/google/dotprompt), [POML](https://github.com/microsoft/poml) | Prompt as a plaintext file with roles in the body | YAML frontmatter plus a template language, library-loaded, none are transcripts |
| [Letta `.af`](https://github.com/letta-ai/agent-file) | "Agent as a portable file" | A JSON state blob for stateful-memory agents. Not hand-authored, not a transcript |
| [KrillClaw](https://github.com/krillclaw/KrillClaw), NullClaw, [Talu](https://github.com/aprxi/talu) | Zig, single binary, zero deps, sub-10ms boot | Conventional agent runtimes inside. No format thesis |
| [CTK](https://github.com/queelius/ctk), Forky, GitChat | Conversations as trees, fork and graft primitives | In a database or in an app, never as files |

## Where the field is ahead

* **Skills are solved.** [`SKILL.md`](https://anomity.ai/blog/agent-skills-open-standard-adoption-governance/)
  went open standard in December 2025, 16+ adopters by March
  2026, thousands written. Inventing our own would be strictly
  worse. A skill is a folder with frontmatter; a mob is already
  a folder.
* **Tool schemas.** The [2026-07-28 MCP spec](https://blog.modelcontextprotocol.io/posts/2026-07-28/)
  lifted `inputSchema`/`outputSchema` to full JSON Schema
  2020-12, including the `oneOf` we reject. MCP went to the
  Linux Foundation in December 2025. It is the tool layer now.
* **Forking shipped in a mass-market product.** Claude Code got
  `/fork` and `/branch` in June 2026. Branching is table stakes,
  though still as UI commands over opaque state.
* **Provider abstraction** is the most rebuilt, least
  differentiated code in the space. Everyone writes it. Ours is
  cost with no upside.

## What is unclaimed

Searched for and not found. These are the reasons to continue.

1. **One format for four jobs.** Agent definition, transcript,
   wire format and tool protocol share a grammar. gptel unifies
   transcript and editing. Prompty unifies config and prompt.
   Nobody collapses all four.
   The grammar is also valid CommonMark, so the four are
   readable wherever markdown is. llm-md and gptel are
   markdown-*like*; a stored m8 document is markdown.
2. **Turn as a file with a parent pointer, plus a mutable ref
   namespace.** `=` and `+` are git's object/ref split applied
   to conversations, on the filesystem, where `ls` and `cat`
   work. Others do trees in a database or in an app.
3. **Tools as m8 to m8 filters with interaction on `/dev/tty`.**
   The tty trick is old (fzf, lazygit, `pick`) but no agent
   system has made it the tool contract. Pi rejecting MCP for
   "CLI tools with READMEs" is the same instinct, one step
   less far.

## Positions to hold

* **Read Pi's exclusion list before adding anything.** It is
  the closest thing to an independent peer review of our own
  taste. Where we disagree we should be able to say why.
* **Consume `SKILL.md`, do not invent a skill format.**
* **Generate 🧰 from MCP servers rather than authoring it.**
  Keeps the format, inherits the ecosystem, skips writing a
  schema language that loses to JSON Schema. One study measured
  MCP integration inflating input tokens
  [236x and dropping accuracy 9.5%](https://arxiv.org/html/2508.12566v1),
  so rendering MCP tools into something terse is a contribution,
  not a compromise.
* **The moat is the data model and the format collapse, not the
  CLI.** The format should be specified independently of the Zig
  implementation, sooner than feels necessary.

## Known attacks

* **The sigils.** Grep-hostile, typing-hostile, font-dependent.
  Answered by storing none of them. A file is `m8.md`: markdown
  headers and block quotes, with each sigil written as the
  `:word:` shortcode that already means "an emoji, spelled out"
  everywhere from GitHub to Slack. Typeable, greppable, diffable,
  and renderable by anything. The emoji spelling is what a
  terminal is shown, and the two never mix. See Sigils in the
  README.
* **The name.** `m8` is close to unsearchable and `mate` is the
  MATE desktop. Hence mEight.
