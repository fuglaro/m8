# IDEAS

## Mission

Review everything again on the mission statement in the README.md

## Layers

* Framework - form; holds no opinion.
* Distribution - shipped defaults; the operator's to replace.
* Fun - proof the form holds.

## Ledger Truth

### DONE: Cut-off replies read as finished

* `finish_reason` / `stop_reason` are dropped.
* A `max_tokens` stop looks like a complete 🤖.
* Continuing feeds the model its own severed sentence.
* Design question: 🤖 is content-only and the sigil set is closed.
* OMIT: Same question:
  * Resolved model - what answered, versus what the 🧠 asked.
* Not ledger:
  * Usage, id, fingerprint, service tier.

### DONE: Writes are not crash-safe

* `session.zig` writes turns and `+` refs with plain `writeFile`.
* Interrupt - partial turn.
* Two runs - race on a ref.
* Fix: temp file, fsync, rename; compare-and-swap for refs.

### DONE: Bad 🛡 env name vanishes

* `shield.zig:180` turns it into "no variable".
* `toolbox.parse` returns `BadEnvironmentName` for the same mistake.
* Should fail when the definition is read.

### OMIT: Concurrent edits in munge

* Omitted because this isn't munge's brand - that's a patch editing system.

* `read` hands back a hash.
* `write` takes it, refuses if the file moved.
* Exact match catches most; this closes the race.

### OMIT: Things that never end

This should be built into tool design itself,
and used in conjunction with a an agent loop.
Agent loops are easily done in the layer orchistrating m8,
and could be done with m8 with a looper toy model ->
calls subagent, again and again. Or just a cron!

* A tool that hangs or floods output hangs the harness.
  * `launch.spawn` writes all input, then waits.
* A model calling tools forever.
* Agents calling each other in a cycle.
* Caps are operational:
  * timeout
  * output size
  * descendant count
  * cancel on parent exit
* Customisable - so a 🛡 or definition variable?

## Framework

### Format spec apart from the Zig

* Sooner than feels necessary.
* The moat is the data model and format collapse, not the CLI.
* A second implementation is the proof.
* Pieces:
  * fixtures - every sigil, shortcodes, malformed headers, codec vectors
  * invariants - `parse(render(parse(x)))`, `decode(encode(l))`
  * invariants - streamed == complete, single == split
  * a tiny reader in Python or shell

### Smallest stable public surface

* Decide what is supported long term:
  * ledger grammar
  * filesystem layout
  * command names
  * provider stdin/stdout contract
  * tool contract
* Everything else marked experimental.
* Durability is the appeal, so the promise has to be explicit.

### Placeholders

* Squash remaining `{{CODE}}` and `{{M8}}` at framework level.
  * `shield.code_mark` and friends.

### MAYBE: Attachments

* Why maybe - a new sigil against a closed set; could a reference do it?

* Images and other binaries.
* Sent by reference.
* Needs a sigil or reference form.
* Must respect the sandbox.

### Open questions

* Token amounts as ignored metadata lines?
  * Do they belong in history at all?
* MAYBE: In-chat subagent forking with `> >`.
* Native sigils projected to tool calls?
* A tool only the person can call?
  * How does a person call a tool at a chat at all?
* Git-friendly `.m8-st8`?
  * `+` refs always change.
  * Does changing an agent change histories naming it?
* Can a tool parameter value take a template?

## Mobs, Agents and Subagents

* MAYBE: the framework knowing about subagents at all.
  * Pi excludes them.
  * A subagent may just be a 🧰 whose command is `m8 @agent`.
* Biggest undecided design.
* Wants one honing session, like types got.
* No self-spawning needed - an agent is called fresh, or its chat carried on.
  * Said in the README, under Mobs.

### Shapes on the table

* minion - `m8 @{mob}AGENT -- "prompt"`
  * fresh
  * also resets a peer, or yourself via `m8 @{self}`
* mate - `m8 +{mob}AGENT -- "prompt"`
  * a peer, continued
* Long form:
  * `m8 call minion -m MOB -a AGENT [--as CHAT] -- PROMPT`
  * `m8 call mate -m MOB -c CHAT [--as CHAT] -- PROMPT`
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

* ReleaseSmall: 1.04 MB (2026-09-27).
* Tighten or collapse without losing anything meaningful?
* Comptime groups: framework, defaults, fun.
  * Size of framework alone?
  * Defaults without Zork?
* Some commands in the binary, the rest standalone.
  * `standalones=...`
  * zmachine spun off the same way.
* Comptime elimination of OS-specific code.
* `zig build split` leaves stale binaries in `zig-out/bin`.

## Sandbox and Cross-OS

* Windows - anything that contains falls back to deny.
* Linux - like Windows first, own containment later.
* `core/` unwritable by tools on macOS only.
  * `mac-sandbox.sb:169`
* A real process-exec filter, not `(allow process-exec)`.
* Some git commands, by unlocking `.git` only when constrained.
  * How does it mix with glob-limited commands?
* MAYBE: Command classes as shields, not a confirmation mode:
  * Why maybe - from review; each tool's shields may already say it.
  * read-only
  * workspace-mutating
  * destructive
  * network

## Distribution

### Core defaults

* Target: install and run.
* A good default set of agents and providers.
* Installed on first run, when no m8 state exists in any config area.
* Defaults as agents: `@/core/defaults/`, named as `#### :brain:/core/defaults/`.
* Example provider setups give instructional errors when a secret is missing.
  * e.g. telling the person to run the openai cli to set up.

### Providers

* Setups for Anthropic, OpenAI, Google.
  * In the default, or a folder of examples?
  * Default carries Mac keychain commands - examples may be honest.
* `providers.json` in a native m8 form?
* MAYBE: A command writing out core defaults and examples.
  * Why maybe - `cp` from a shipped folder may be the whole command.

### Tools

* MAYBE: Pick the editor tool.
  * Why maybe - munge already has one, with its forgiveness ladder.
  * Maybe several, if models are tuned to them.
  * Weigh Anthropic's `str_replace_based_edit_tool`:
    * stateless, explicit path every call
    * `view` `create` `str_replace` `insert` `undo_edit`
    * clear errors on non-unique matches
* MAYBE: Delete, move and mkdir, without an unrestricted shell.
  * Why maybe - from review; `rm` inside a 🛡 may be enough.
  * an explicit path, never a shell expression
  * refuse directories by default
  * require existence
  * show size and path
  * dry-run
  * optionally move to a trash folder instead of deleting
* MAYBE: Report the files a command changed.
  * From the model feedback - for shell commands especially.
* Common toolboxes, especially coding.
* MAYBE: Standard section markers for any file with comments.
  * `.* ___...--->>>> # SECTION HEADING NAME <<<<---...___ .*`
  * Built into tools.
  * Why maybe - a convention imposed on every file.
* MAYBE: MCP - generic runner tool; output schemas.
  * Pi excludes MCP.
  * How would it apply without? 🧰 rendered from a server, per the README?
* MAYBE: Wrapper scripts in a config folder.
  * For commands a template cannot say.
* Every inbuilt tool runnable under `m8 call args`.
* MAYBE: Plugins - look in `m8-st8` folders first? Tool freezing?
  * README - "Features do not arrive here through a plugin api."
* MAYBE: Native functions.
  * Why maybe - a tool is a program; native ones are a second kind.
* MAYBE: Local Wikipedia search over a vector database.
* MAYBE: AGENTS.md in templating setups.
* Tool-extension skills - flexibility by what the model is told.
* Nudges in definitions:
  * several calls in one reply
  * string-match anchors for several changes in one file

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
  * `m8 call watch`
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

## Settled

Off the list - check any you disagree with.

* Remove edline - gone.
* PositiveInt, Pascal-case types - pass-through with `,key:value` extras.
* Validate types early - decided against; the provider finds mistakes.
* Deterministic rendering - `std.json.ObjectMap` keeps insertion order.
* Enforce required params - `converse.zig:250`.
* Two toolbox modes, `BYTE_CAP` on pagey - definition variables.
* Back-to-back toolbox variable lines - pagey carries them.
* Binary search results - `scan` names binaries.
* `m8 cat`, `m8 top` - exist.
* Zork agent-as-user - nothing to build.
* Tools responding with text - `speaks` defaults to text (🧾).
  * Unless you meant something else.
* Review's `m8 new` / `show` / `fork` - not real commands.

## TODO

* Validate and document everything can be reasonably composed.
