# Why m8

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

## Ownership

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
Anyone can write a parser for it from [the language](language.md), in
any language, in an afternoon. That is offered, not
conceded — a format worth adopting is one you could
implement yourself and choose not to.

## It is markdown

A stored m8 document is markdown. A list item per
record, holding its block quote, with each sigil written as its gemoji
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

The emoji column is what a terminal gets. One glyph per
record kind, told apart at a glance, with no pager.
Both spellings are accepted everywhere a sigil is
accepted and they mean the same thing, so a record
copied off a terminal reads back as the record it shows.

What a terminal adds on top is for reading: markdown
highlighted, and a long line broken to fit. `m8 render
--parsable` keeps a display to what still parses.

Every other harness keeps the record in a format meant
for machines and renders a view of it for people. Here
the record is the readable thing: a file, in markdown.

## The formats were always one

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

## Neutrality is the feature

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
`core/providers/NAME.json` is the whole of the configuration,
and reaching a url is one such command rather than the
privileged path.

Form is the part that has to outlast everything else,
and form is the only part m8 insists on.

## Capability is composition

Features do not arrive here through a plugin api. A tool
is a program that reads m8 and writes m8. A provider is
a program that reads a request and writes a response. So
what m8 can do is what your machine can run, and that
was true on the first day.

The proof is already in the tree. `m8 :games/zork` holds a conversation with a
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

## What a distribution gets

* MIT.
* One binary from `zig build`, or any of its commands as
  programs beside it with `-Dsplit` — the same sources
  either way; see [Building](building.md). `build.zig.zon` declares no dependencies.
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

## The field

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
