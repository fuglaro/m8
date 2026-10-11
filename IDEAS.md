# IDEAS

## TODO (Upcoming and WIP)

* Figure out componentised multi-agent management e.g: https://herdr.dev/ - or check it composes well into https://github.com/herdrdev/herdr
* Cody needs to be able to have sub-agents so it isn't a token burner.
* Jed style classifier auto-tool approval?
* System locked mode - pre-made agents with locked shields and tools. Locks to root owned configs and agents. When a file exists in root owned /etc… then change storage respect structure. (agents must come from root, tools can't open larger).
* m8 serve (middleware proxy for serving a m8 interface in front of a provider specific).
* Token amounts as ignored metadata lines?
  * Do they belong in history at all?

----

## Mission

Review everything again on the mission statement in the README.md

## Layers

* Framework - form; holds no opinion.
* Distribution - shipped defaults; the operator's to replace.
* Fun - proof the form holds.



## Framework

* Validate and document common workflow can be reasonably composed with components.
* Cache breakpoint managment. 5min ttl in tool loops - upgrade to 1hr on hand to user? Options on model def? or provider directive sigils? Or just do in providers?

### Format spec apart from the Zig

* The moat is the data model and format collapse, not the CLI.
* A second implementation is the proof.
* Pieces:
  * fixtures - every sigil, shortcodes, malformed headers, codec vectors
  * invariants - `parse(render(parse(x)))`, `decode(encode(l))`
  * invariants - streamed == complete, single == split
  * a tiny reader in Python or shell
* Make a skill agents to understand manipulating themselves
  dropped into core defaults.

### Smallest stable public surface

* Decide what is supported long term:
  * ledger grammar
  * filesystem layout
  * command names
  * provider stdin/stdout contract
  * tool contract
* Everything else marked experimental.
* Durability is the appeal, so the promise has to be explicit.


### MAYBE: Attachments

* Why maybe - a new sigil against a closed set; could a reference do it?

* Images and other binaries.
* Sent by reference.
* Needs a sigil or reference form.
* Must respect the sandbox.
* Media workflows -> gen image -> see image -> show image (colored ascii rendering).
  Maybe with a text-image format we find/make??? Custom markdown? ```palettemap...
  Leveraging unicode colors as a LUT??? Needs to be reasonably
  cross-common-font compatible so constraining to some common standardised ones
  is crucial - if even possible. 2 char wide grid?








## Mobs, Agents and Subagents

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

### Hooks

* MAYBE: Hooks: Auto-action on response - if max_tokens on robot reply, auto compress/etc.
  - Wrapper command on responses? similar to shields?

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










## Build and Size

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

## Sandbox and Cross-OS

* Windows - anything that contains falls back to deny.
  * @ - not great ":"?
* Linux - like Windows first, own containment later.
* `core/` unwritable by tools on macOS only.
  * `mac-sandbox.sb:169`
* A real process-exec filter, not `(allow process-exec)`.
* Some git commands, by unlocking `.git` only when constrained.
  * How does it mix with glob-limited commands?

## Distribution

### Docs

* Completely redo the README succinct and clear and well described.
* Active demo - easiest way to have text-only animation of a play.
  - Hi m8, can you give yourself a tool to connect to this MCP.
  - First use useful.
* Webassembly build of active demo? Running Zork? Elisa?
* Replay ledger demo system.
* Can this be in github or does it need to be hosted?
  How to make prominent in README of github without big binary media?

### Core defaults

* Target: install and run.
* A good default set of agents and providers.
* Installed on first run, when no m8 state exists in any config area.
* Defaults as agents: `@/core/defaults/`, named as `#### :brain:/core/defaults/`.
* Example provider setups give instructional errors when a secret is missing.
  * e.g. telling the person to run the openai cli to set up.
* MAYBE: AGENTS.md in templating setups.

### Providers

* Setups for Anthropic, OpenAI, Google.
  * In the default, or a folder of examples?
  * Default carries Mac keychain commands - examples may be honest.
* `providers.json` in a native m8 form?
* MAYBE: A command writing out core defaults and examples.
  * Why maybe - `cp` from a shipped folder may be the whole command.

### Tools

* Add a webfetch tool? Optional build for size?
* MAYBE: MCP - generic runner tool; output schemas.
  * How would it apply without? 🧰 rendered from a server, per the README?
  * Generic MCP wrapper launcher/runner tool (one for local one for remote).
  * Test with Blender. Test with web service.
* Tool-extension skills - flexibility by what the model is told.
* Webfetch (cody's) - make it support pages and grep directly hiding file referencing
  via bash and munge.

### Codecs

* MAYBE: Anthropic cache breakpoint.
  * Why maybe - where to cache is a policy the ledger cannot override.
  * On the last record before the first 🙋.
  * Derivable from the ledger; no new sigil.
  * A codec knowing its api's quirks is what a codec is.
* MAYBE: Parallel tool calls.
  * Why maybe - in turn is simpler, and ledger order stays what happened.
  * Several already run, in turn (`converse.zig:163`).
  * Concurrently is open.

### Agents

* Planner - `PLAN.md` or `dev/plans/PLAN_X.md`, and `TODO.md`.
* MAYBE: Compressor/packer, and its tool.
  * Must be a projection - never forgetting done to the ledger.

## Commands and UX

* riff - see RIFF.md.
  * `m8 riff m8 @agent/new-sub-chat`
  * bare `m8` with a ref runs `riff m8 @`
  * `m8 @agent` likewise, ensuring a chat when it can
* Threads - like `git log --graph --decorate --oneline --all`.
  * dangling turns, forks, dates
  * structure first, summaries later
* List agents.
  * Listing agents and mobs - or just `ls`?
  * Separate out where skills are stored to distinguishable when listing.
* MAYBE: Unwrap the last 🤖 onto stdout.
  * Why maybe - `m8 filter` chains get close; picking the last and unquoting are missing.
* `m8 load` - bottom only, beside `cat` and `top`.
* MAYBE: Cleanup helpers for `.tmpdir` and chats.
  * Why maybe - they are files; `find` and `rm` compose.
* MAYBE: Background processes.
  * Why maybe - README promises no daemon.
  * mob-scoped, through process handles
  * not tmux
  * `m8 watch`
* One polished end-to-end demo.
  * a file edit, a tool call, a fork, a provider response
  * ending in a readable transcript
  * Zork is compelling; this reaches most people faster.
* Errors that say where.
  * path, record, line, value, include lineage
  * `m8: BadEnvironmentName` alone costs a hunt.
* MAYBE: From review:
  * `m8 doctor`
  * `m8 check` for a ledger
  * shell completion
  * first-five-minutes path in the README

## Fun

* Give an agent a Zork tool, and watch it.
* Procedural generation.
  * generator + seed = endless graded tasks
  * TextWorld's insight - MIT; its backend wraps GPLv2 Jericho
  * the ledger already carries the seed
* Glulx.
  * separate VM, bigger address space, Glk I/O
  * roughly doubles reach into modern IFComp
* Test against terminal tests.
* Local Wikipedia search over a vector database.



