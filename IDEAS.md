# IDEAS

## TODO (Upcoming and WIP)

* m8 @crew/cody/chat-- to new rather than parent...

* m8 watch -> watch live chat - useful to see subagents!

* Review everything again on the mission statement in the README.md.

* Reconsider tool calls in serial.

* "{{SHIELD}} x {{SHIELD}}" - WHY IS THIS ALLOWED?
* "{{CODE}}" - can it always be passed at the end?
  or two list with a post args?

* Maybe use jq instead of sed scraping in the example configs?



* DONE (for devyn): Cody needs to be able to have sub-agents so it isn't a token burner.
* DONE: Prompt to riff: m8 @agent alone at a terminal launches riff (src/main.zig:138). Riff to itself: riff re-spawns as m8 riff --detached, or m8-riff in a split build (src/command/riff.zig:405).
* DONE: Clean: Shield to its subcommands: m8 shield dispatches to secure and ask, spawning m8-shield-secure in a split build (src/command/shield.zig:53).
* DONE: turn `m8 shield ask` into `m8 ask-shield`, and `m8 shield secure` into `m8 secure-shield`, and clean out `m8 shield`
* DONE: -Dformats=openai-completions,anthropic-messages,openai-responses (defaults all, always includes m8, applies to encode and parse)
* OMIT(achieble with any FastCGI tool or even ncat for raw m8 over TCP): m8 serve (middleware proxy for serving a m8 interface in front of a provider specific).

## Framework


* Figure out componentised multi-agent management e.g: https://herdr.dev/ - or check it composes well into https://github.com/herdrdev/herdr
* Cache breakpoint managment:
  * 5min ttl in tool loops - upgrade to 1hr on hand to user?
  * Options on model def? or provider directive sigils? Or just do in providers?
* System locked mode - pre-made agents with locked shields and tools. Locks to root owned configs and agents. When a file exists in root owned /etc… then change storage respect structure. (agents must come from root, tools can't open larger).


  * Do they belong in history at all?


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
* Render nested marckdown.

### MAYBE: Attachments

* Why maybe - a new sigil against a closed set; could a reference do it?
* Media:
  * Images and other binaries.
  * Sent by reference.
  * Needs a sigil or reference form.
  * Must respect the sandbox.
  * Media workflows -> gen image -> see image -> show image (colored ascii rendering).
    Maybe with a text-image format we find/make??? Custom markdown? ```palettemap...
    Leveraging unicode colors as a LUT??? Needs to be reasonably
    cross-common-font compatible so constraining to some common standardised ones
    is crucial - if even possible. 2 char wide grid?

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
* riff needs the gap between steps.
 * a 🙋 slipped in before the next call runs

### Hooks and Orchistration

* MAYBE: Hooks: Auto-action on response - if max_tokens on robot reply, auto compress/etc.
  - Wrapper command on responses? similar to shields?
* Enough hooks to support a Herdr setup: https://github.com/herdrdev/herdr
  * Env vars will do it.

### MAYBE: Codec-specific metadata sigil

* Consider shifting 🔏 into a promoted codec-metadata arbitrary sigil.

### Loose ends

* `m8 @teamA/` - who is the lead?
* MAYBE: `{mob}` magic tool parameter - same mob, `/suffix` if not top level.
* Where is progress recorded?
* Match workstreams to agents and mob chats.
* Mob -> swarm? Or swarm for something else.
* The TUI - tmux sessions? dmux wrapped?
  * tmux is shield-dangerous; see riff.






## Mobs, Agents and Subagents

See: PLAN_AGENTS_*.md

* MAYBE: the framework knowing about subagents at all.
  * Pi excludes them.
  * A subagent may just be a 🧰 whose command is `m8 @agent`.
* Biggest undecided design.
* Wants one honing session, like types got.
* No self-spawning needed - an agent is called fresh, or its chat carried on.
  * Said in the README, under Mobs.
* Parallel calls to agents is one tool call! The tool distributes!
-v also streams the tool stderr! So it can show its progress.

### Shapes on the table

* minion - `m8 @{mob}AGENT -- "prompt"`
  * fresh
  * also resets a peer, or yourself via `m8 @{self}`
* mate - `m8 +{mob}AGENT -- "prompt"`
  * a peer, continued
* Long form:
  * `m8 minion -m MOB -a AGENT [--as CHAT] -- PROMPT`
  * `m8 mate -m MOB -c CHAT [--as CHAT] -- PROMPT`
* Named chats makeable from the command line.
* A chat spawner usable as a tool.

### Principle

* Keep arguments simple; complexity lives in the mob definition.
* Anything a mob can say is not also sayable in arguments.

### Access

* MAYBE: Sub `@` and peer `@+` controls.
  * Why maybe - could shields on the spawning 🧰 say it?
* Allowed minions and peers.
* May a sub spawn a peer session?
* May an agent call its parent mob's agent?
  * `{{mob}}` reflection, or hardcoded?
* Subagent inside the sandbox, and not.

### Discovery

* MAYBE: `@.../` loads every skill and subagent in a mob.
* MAYBE: Agents advertise themselves as subagents.
* MAYBE: Skill-finder minion - auto-post 🙋?



## Sandbox and Cross-OS

* Windows - anything that contains falls back to deny.
  * @ - not great ":"?
* Linux - like Windows first, own containment later.
* `core/` unwritable by tools on macOS only.
  * `mac-sandbox.sb:169`
* A real process-exec filter, not `(allow process-exec)`.



## Distribution

### Docs

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
- Core flow: `ref → send → tag`, with `encode`, `parse`, `query`, `render`, `tail`, and `reset` as composable pieces.
- Sigils define records such as 🧠, 🙋, 🤖, 💭, 📲, 🧾, 🟢, 🚫, 🧰, and  .
- Shields restrict tools by process wrapping and compose through intersection.
- Config resolves nearest-first through `.m8-st8/` and XDG config.
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



## Fun

* Give an agent a Zork tool, and watch it.
* Z-machine Procedural generation.
  * generator + seed = endless graded tasks
  * TextWorld's insight - MIT; its backend wraps GPLv2 Jericho
  * the ledger already carries the seed.
* Unicode text games.
* Test against terminal tests.
* Local Wikipedia search over a vector database.
* Jed style classifier auto-tool approval.

