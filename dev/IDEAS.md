# IDEAS

## TODO (Upcoming and WIP)

* unsloth/inkling2mini

* Review everything again on the mission statement in the README.md.
  - and on our implied style guide. One agent reflected after direction:
    That principle helps beyond this instance too: in this codebase, a one-use helper
    is suspect unless it removes a real conceptual boundary—not merely several nearby lines.
    Tests should not push complexity into the code - but they may hold the complexity.


## Framework

### Tools

* MAYBE: MCP - generic runner tool; output schemas.
  * How would it apply without? 🧰 rendered from a server, per the README?
  * Generic MCP wrapper launcher/runner tool (one for local one for remote).
  * Test with Blender. Test with web service.
  * See MCP_RESEARCH.md

## Commands and UX

* Threads - like `git log --graph --decorate --oneline --all`.
  * dangling turns, forks, dates
  * structure first, summaries later
* List agents.
  * Listing agents and mobs - or just `ls`?
  * Separate out where skills are stored to distinguishable when listing.
* Errors that say where.
  * path, record, line, value, include lineage
  * `m8: BadEnvironmentName` alone costs a hunt.

### Media Extras

* Media workflows -> gen image -> see image -> show image (colored ascii rendering).
  Maybe with a text-image format we find/make??? Custom markdown? ```palettemap...
  Leveraging unicode colors as a LUT??? Needs to be reasonably
  cross-common-font compatible so constraining to some common standardised ones
  is crucial - if even possible. 2 char wide grid? unsloth/inkling2mini supports 40x40 images - allow ascii-to-px-to-ascii?
* Mini renderer for depth and id pass drawn in ascii. Also edge line pass?

### Tool loop de-opinion

* Find a way to elegantly express triggering each tool call rather than loop.
* The loop is hard-wired in converse; make it the default, not the only shape.
* It should be composable either way.
* The pieces already exist:
 * a turn can end on an owed 📲 - the ledger carries unanswered calls
 * m8 already picks an owed call up and answers it
* The loop is just those two steps, repeated.
 * the main command line keeps it as the sensible default
 * anything else composes the steps its own way
* Where are the ReAct loops? Do we need a react command? That does the tool call loop? Or does send run it all inside? `m8 next`? Error when waiting on user? Does this allow putting a user message onto intercept a tool loop??? Be nice in riff. Riff chaser commands?
* Separate react from send? Tool call as a component. So another harness can use m8 itself as a provider! It can be a provider for itself. Harness and provider - like the chat tab in omlx.

### Hooks and Orchistration

* MAYBE: Hooks: Auto-action on response - if max_tokens on robot reply, auto compress/etc.
  - Wrapper command on responses? similar to shields?
* Enough hooks to support a Herdr setup: https://github.com/herdrdev/herdr
  * Env vars will do it.

## Distribution

### Docs

```
* Readme
  - combine What It Is and The Mission
  - section on allowing the user to define the trust model.
    - you may run m8 in a container like other harnesses, but m8 gives you an easy way to secure an agent's tools instead, and gatekeep their creation. An agent is only as dangerous as the tools it can run, and how open to permissions they are.
```


```
▐ 🤖
│ I’ve warmed up on the README’s core context.
│
│ m8 is a composable, shell-first agent harness built around a durable Markdown ledger:
│
│ - Conversations, agent definitions, tool calls, wire formats, and policies share one record grammar.
│ - The ledger is authoritative; projections and provider codecs must not silently lose or reorder records.
│ - Turns are immutable files, while chats are movable references—similar to Git objects and refs.
│ - Tools and providers are ordinary programs in pipelines: m8 reads and writes m8.
│ - Agents, models, mobs, skills, shields, and tools are composed through files rather than a plugin API.
│ - The CLI supports shorthand such as `m8 @agent -- "prompt"` and explicit pipelines such as `ref | encode | providers | parse`.
│ - The project emphasizes text ownership, offline/build simplicity, composability, and long-term durability.
│
│ I’ll keep that architecture and terminology in mind going forward.

```

```
- m8 is a shell-first agent harness where the **conversation is the artifact** and the **ledger is authoritative**.
- Agent definitions, transcripts, wire requests, tool exchanges, and policies share one markdown-compatible grammar.
- Commands compose as stdin/stdout filters; tools and providers are ordinary commands.
- Chats are movable refs (`+.md`); immutable turns live under `+/`, similar to Git refs and objects.
- Core flow: `ref → send → tag`, with `encode`, `parse`, `query`, `render`, and `tail` as composable pieces; promptless `say CHAT-` / `say CHAT--` handle chat resets.
- Sigils define records such as 🧠, 🙋, 🤖, 💭, 📲, 🧾, 🟢, 🚫, 🧰, and  .
- Shields restrict tools by process wrapping and compose through intersection.
- Config resolves nearest-first through `.m8st8/` and XDG config.
- Providers are configurable command pipelines; models are selected directly in the ledger.
- No database, daemon, plugin API, or required network/build dependencies.
```


```
▐ 🙋
│ 1 haiku about m8 plz

▐ 🤖
│ Files hold the voices
│ Shell pipelines shape the ledger
│ Turns bloom into paths

▐ 🧠crew/cody/+/xgptrhymlk
```

* Completely redo the README succinct and clear and well described.
* Active demo - easiest way to have text-only animation of a play.
  - Hi m8, can you give yourself a tool to connect to this MCP.
  - First use useful.
* Webassembly build of active demo? Running Zork? Elisa?
* Replay ledger demo system.
* Can this be in github or does it need to be hosted?
  How to make prominent in README of github without big binary media?
* Managed background process examples.
* One polished end-to-end demo.
  * a file edit, a tool call, a fork, a provider response
  * ending in a readable transcript
  * Zork is compelling; this reaches most people faster.
  * first-five-minutes path in the README
* Validate and document common workflow can be reasonably composed with components.
* Format specification:
  * The value is the data model and format collapse, not the CLI.
  * A second implementation is the proof. Relevant for 30 years because it's relevant for software 30 years old.
  * grammar.peg
  * Smallest stable public surface
    * Highlight what is supported long term:
      * ledger grammar
      * filesystem layout
      * command names
      * provider stdin/stdout contract
      * tool contract
    * Durability is the appeal, so the promise has to be explicit.
    * Stabalise core layers the most.

### Build and Size

* ReleaseSmall: 569 KB (2026-10-04).
* Tighten or collapse without losing anything meaningful?
* Comptime groups: framework, defaults, fun.
  * Size of framework alone?
  * Defaults without Zork?
* List subcommands to build separately.
* Some commands in the binary, the rest standalone.
  * `standalones=...`
  * zmachine spun off the same way.
* Comptime elimination of OS-specific code.
* `zig build split` leaves stale binaries in `zig-out/bin`.
* Build minimal options:
  * No inbuilt defaults.
  * No toys.
* Named default? build for release small.
* Option for curl / no-curl.

### Setup

* Fully prepared defaults in repo easily pullable with documented command or setup script.
  * Agents:
    * cody
    * setup - help set up with custom agents etc (needs better name).
    * Planner - `PLAN.md` or `dev/plans/PLAN_X.md`, and `TODO.md`.
    * Reviewer.
    * Compressor/packer, and its tool.
    * ...
    * Ones that respect AGENTS.md? What other conventions to exemplify?
  * Skills:
    * Make a skill agents to understand manipulating themselves.
  * Configs:
    * Providers:
      * Setups for Anthropic, OpenAI, Google.
      * ...
    * OS specific sandbox helpers.
* Clean out inbuilt defaults unless they are really really minimal.
  * Clean out
* Option to build with any inbuilt-defaults which write out on first run.
  * Internally store compressed.


