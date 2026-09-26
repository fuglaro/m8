

# ====

This is creeping up...
zig build -Doptimize=ReleaseSmall
what can we do? We want this tiny.
Can anything tighten or collapse without dropping anything meaningful?

# ====
Consider the following.

* Local Wikipedia search with a vector database.
* Native functions.
* Tools responding with a text response.
* MCP output schema.
* Wrapper scripts in a config folder, for the commands a
  template cannot say.
* A command that writes the core config defaults, for
  extending afterwards.
* Customisable caps on loops that do not end — a cyclic
  agent check, or a model calling tools forever.
* Templating setups that support AGENTS.md.
* How a person calls a tool at a chat.


# ====

parallel tool calling.

# ====

.tmpdir cleanup helpers chat cleanup helpers.

# ====

Minimalistic standalone RIFF terminal tool composable into simple TUI.
See RIFF.md.
m8 riff m8 @agent/new-sub-chat
m8 # If there is a ref there, automatically runs m8 riff m8 @
m8 @agent # If there is an agent there, automatically runs m8 riff m8 @agent
Similarly will ensure a chat if it can, and riff.

# ====

Ochistrating multiple background long running processes.
Not tmux - needs to be mob scoped and  managed through process handles.

m8 call watch

# ====

Compressor / packer agent and associated tool.

# ====

Make all the inbuilt tools runnable under m8 call args by having them accept arguments.

# ====

Command to unwrap last robot message and put it on stdout.

# ====

Build options - put some sub commands in a self-contained binary with
others separate as standalone callables. Build via standalones=... or something.
How big is the framework build? The build with defaults including the opinionated tools
but not the fun stuff like Zork. Classify them in comptime groups. Framework, defaults fun.

# ====

Defaults / example generator in a separate sub command.

# ====

Set up subagents through tools.

In README talk about how subagents don't need self-spawning when you can call them fresh or reply via commdns line. Named chats must be makable from the command line.
Make a named chat spawner command usable as a tool!

What is the TUI for this? tmux sessions? Like dmux wrapped? tmux is shield-dangerous!

# ====

Give one a tool to play Zork and watch it.

# ====

Planner agent which works on PLAN.md or dev/plans/PLAN_X.md
Manages TODO.md also.

# ====

Generic MCP runner inbuilt tool command.

# ====

Ignored metadata lines for token amounts? Although don't want them showing up in historical logs or do

# ====

m8 threads list (or something) - analyses all chats for danglings, forks, and dates and gives a thread branches - perhaps with summary etc) like git log --graph --decorate --oneline --all

# ====

│ The main gaps I noticed:
│
│ 1. **No first-class file deletion**
│
│    I had to use `bash rm` to remove the three obsolete Zig files. Deletion is a normal refactoring operation and deserves a dedicated tool, perhaps:
│
│    ```text
│    delete(path, require_exists=true)
│    ```
│
│    Ideally it would refuse directories, show the file size, and require an explicit path rather than accepting a shell expression.
│
│ 3. **Generated artifacts can become misleading**
│
│    After `zig build split`, the old `m8-call-edline*` binaries remained in `zig-out/bin`, even though they were no longer built. The source was correct, but a later directory listing could false
ly suggest the command still existed.
│
│    A build-aware harness could either:
│    - expose a clean build operation, or
│    - report stale generated artifacts separately from current outputs.
│
│ 4. **Shell commands have broad destructive power**
│
│    `bash` was useful for deletion and testing, but it is also the least constrained tool. For a harness intended for agents, I’d consider:
│    - a confirmation mode for destructive commands,
│    - a distinction between read-only and mutating shell commands,
│    - optional command timeouts,
│    - explicit reporting of files changed by a command.
│

│ On concurrent work, I agree that the harness cannot know which edits belong to whom. The most useful protection is therefore not ownership tracking but optimistic conflict detec
tion:
│
│ - read/search records the content or hash it observed;
│ - edit refuses if the file changed since that observation;
│ - edits report the before/after state;
│ - unrelated files and unrelated regions are left alone.
│
│ Exact old-text replacement already gives you much of that behavior, but a file-level compare-and-swap would close the race between reading and writing. That seems more valuable
than adding Git-specific concepts.
│
│ For binary grep results, omitting their contents by default makes sense, especially for an agent. I’d avoid making them disappear completely, though. A compact notice such as:
│
│ ```text
│ (binary skipped: image.png)
│ ```
│
│ prevents “no results” from being confused with “nothing was searched.” An explicit mode could later allow:
│
│ - `skip` — default;
│ - `report` — identify binary files that would otherwise match;
│ - `search` — search their raw bytes.
│
│ That keeps the default output useful without making the harness decide what a repository considers important. Also, binary detection should remain conservative—typically a NUL-b
yte check or similar heuristic—because many useful files are technically binary but still meaningfully searchable.

# ====

multiple toolbox var-set lines back to back fails on "m8 --: MissingBlankLine" -> look into being forgiving here. I see no need to force the blank line if we can tell it is expected.

# ====

Remove edline. I like munge better.

# ====

Comptime elimination of OS specific code depending on target build.

# ====


Try to squash out remaining {{CODE}} and {{M8}} framework level placeholders.


# ====

User only-callable tool?

# ====


# ====

m8 to enforce required params regardless of whether the command does. So required for some models and not others!

tool extension skills - Scaling flexibility by what we tell the model.

# ====

Make toolbox activation only when providing no value or quoted block so we can template the setting of env vars.
Make sure that value mechanism of setting of env vars also prefixes M8_ARG_

Cleanup in pagey -> `BYTE_CAP 16000` sits on the definition header of toolbox.

Want 2 modes to toolbox.
1: stack on definition.
2: activate.

Adding an env var is 1, not 2.

# ====

Nudge the model to make multiple calls in a single response.
Nudge it to use string match anchors when doing multiple changes in the same file.

# ====
Attach binary files like images?

# ====
Allowed minions and peers?

# ====
How deal with Linux vs osx on sandbox

# ====
m8-st8 core and open areas. core can never be written to by a tool.
defaults inside @/core/defaults/
#### :brain:/core/defaults/
# ====
sandbox-exec with a process-exec filter

# ====
Allow some git commands by only unlocking .git when it's constrained. How does this mix with glob limited commands.

# ====

In chat subagent forking with > > 

# ====
match workstreams with agents and mobs chats.

# ====
Concurrent edit resilient editing
(stamp read state uuid? timestamp? Updated on write? Check opened? writeIf)
====

@.../ -> load all skills and sub-agent (if md) or all sub-agents in mob.
Agents need to be able to advertise themselves as sub-agents though
A way to call a sub agent in the sandox… and not.

# ====
# Tightening

# ====
 the anthropic-messages codec places a breakpoint on the last record before the first 🙋. That's derivable from the ledger alone, needs no new sigil, and matches the "stable prefix first" ordering you already have. A codec is allowed to know its own api's quirks; that's what a codec is.

# ====
Skill finder minion - auto post :raising_hand: minions?


# ====

sigil for loading a file and sending it as an attachment - like an image etc.
use a reference.
ensure it complies with sandboxing...



# ====
Spin zmachine off into an isolated subcommand. Z-machine-m8 and do the same for everything else.
— commands become
m8-call—


# ====

m8 cat … (gives full file)
m8 top … (gives top only)
m8 load … (gives bottom only)

# ====

Consider swarm name. Mob->Swarm? Use for something else?
Swarm intelligence?

# ====

Sub (@) and peer (@+) agents with protections and agent access controls.
Allow agent to spawn a peer agent session from a sub agent?
Native sigils projected to tool calls?

# ====

git friendly storage of .m8-st8 of a project.

e.g: + sessions always changing?
changing an agent changes chat histories?

# ====

COMMON TOOLBOXES

Standard ones out there esp for coding.

Think about standardised file sectioning for anything that supports comments, etc.
(`.* ___...--->>>> # SECTION HEADING NAME <<<<---...___ .*`).
Built into tools.

Plugin support -> look first for tool cmds in m8-st8 folders? Think about tool freezing...

# ====

CROSS OS SUPPORT

* Windows -> anything that locks in a container way falls back to a DENY.
* Linux -> initially like Windows, eventually implementing it's own containerisation system.


# ====

CONSIDER DISCARED MODEL RESPONSE PARAMS

  No — the turn is about a quarter of it. A chat-completions response is four things:

  1. The turn — choices[0].message: content, tool_calls, and depending on provider refusal and reasoning content. This is the only part m8 keeps.
  2. How it stopped — finish_reason: stop, length, tool_calls, content_filter. (Anthropic: stop_reason — end_turn, max_tokens, tool_use, refusal.)
  3. What actually answered — model resolved to a concrete build, since asking for an alias gets you a dated snapshot back; plus id, system_fingerprint, service_tier.
  4. Accounting — usage: prompt/completion/total, and details like cached prompt tokens and reasoning tokens.

  Streaming is the same shape with delta for message, and usage only arrives in a final chunk if you ask via stream_options.include_usage.

  Sorted by the line you just drew

  Same distinction as requests — what happened, versus what belonged to this run:

  - finish_reason is a ledger fact, and m8 drops it. provider.zig reads content and tool_calls and nothing else. So when a reply is cut off at max_tokens, the ledger records a 🤖 that is
    indistinguishable from a complete answer — it says the model finished when it didn't. Worse than cosmetic: continuing that chat silently feeds the model its own severed sentence as
    though it had meant to stop there. That's the one I'd call an actual "ledger is truth" violation.
  - Resolved model is arguably a ledger fact too. The 🧠 says what was asked for; the response says what answered. Recording it is what lets a replay know which build produced the text.
  - usage is real but it's about the run, not about what was said.
  - id, fingerprint, service tier are run metadata with no business in a ledger.

  One thing already anticipated, one constraint in the way

  💭 and 🔏 are already in the sigil table and map exactly onto reasoning content plus its signature — which some providers require you to send back verbatim or they reject the turn. The
  ledger foresaw the one part of a response that's neither text nor a call. Nothing populates them yet, but the slot is there.

  finish_reason has no such slot, and there's a constraint: 🤖 is content-only — takesValue() is false for .bot — so it can't ride on the header without touching the sigil table, and the
  sigil set is deliberately closed. That's a design question rather than a fix, so I'd rather put it to you than pick.

# ==== ZMachine Extras

- **Procedural generation.** A generator plus a seed yields infinite graded
  tasks — the real insight behind TextWorld (MIT licensed; its generation
  approach is legally reusable, though note its Z-machine backend wraps
  Jericho, which is GPLv2 via Frotz). Since the ledger already registers a
  seed derived from the first message, a ledger becomes a fully
  self-describing, portable game session.
- **Agent-as-user.** Recasting an agent as the user side and having two agents
  converse, with sandboxing. This wanted message roles to be first-class in the
  ledger rather than implied by position — which m8 already does: 🙋 and 🤖 are
  sigils, and the provider reads roles rather than counting positions. Nothing
  to build.
  The composition needs no new machinery either. An agent under test is given a
  🧰 whose 🔌 is `["m8", "+zork", "--", "{{command}}"]`; `+` carries the chat
  from turn to turn, and the tested agent never learns it is talking to a VM
  rather than to a model.
- **Glulx provider.** Separate VM, larger address space, Glk I/O including
  hyperlink events. Roughly doubles reach into modern IFComp entries.


# ====

Editor tools

Need to pick one.

Maybe need to make a few if models are tuned for them...

Not sure if the following is the right pick:

Implement a str_replace_based_edit_tool (Anthropic's text-editor tool convention).
Stateless interface: every call is fully self-contained (explicit path every time — no implicit cursor/current-file). Any state (undo history) lives server-side, keyed by file path, not in the conversation.
Commands (dispatched via a command field):
view — path (required), view_range (optional [start, end]). If path is a file, return numbered lines in that range (or whole file if omitted). If path is a directory, list contents up to 2 levels deep, skipping hidden files.
create — path, file_text (required). Fails if path already exists.
str_replace — path, old_str (required — must match exactly once in the file; error if zero or multiple matches, telling the caller to add more context), new_str (optional, empty = delete).
insert — path, insert_line (required — insert after this line number), new_str (required).
undo_edit — path only. Reverts the last edit made to that file.
Implementation requirements:
Maintain a small server-side history/snapshot per file path (e.g. save previous content before each mutating op) so undo_edit has something to revert to. This is the only real state — everything else is derived fresh from the filesystem each call.
Truncate very long view output with a note suggesting the caller grep for line numbers first, rather than dumping the whole file.
Return clear errors, not silent failures, on old_str uniqueness violations, missing files, or invalid line numbers.


# ====

# MOB CHATS

Mob chats

IDEAS CURRENTLY ALL OVER THE PLACE


m8 @quick @teamA/coder
m8 @think @teamA/review
m8 @big @teamA/lead
m8 @teamA/ ??? who is the lead??

Or maybe we keep the argument interface simpler and put the complexity in the mob definition. Certainly anything that can be done there shouldn't be also done in the arguments.

LONG FORM:
m8 call minion -m {mob} -a {AGENT} [--as CHAT] -- {prompt}
m8 call mate -m {mob} -c {CHAT} [--as CHAT] -- {prompt}

TOOL: minion
m8 @{mob}AGENT -- "prompt"

TOOL: mate
m8 +{mob}AGENT -- "prompt"

Use minion to reset a peer.
Use minion to reset yourself.
m8 @{self}

m8_st8/+/MOB/

* Support magic tool parameter {mob} (same mob as agent, adds /suffix if not top level)
* Are tool parameter values comparable with templates?


Where to record progress?

{{mob}} placehold reflection for use in ensuring an agent
can't call a parent mob agent? or just hardcode?



# ====

Specify the format independently of the Zig implementation, sooner than
  feels necessary. The moat is the data model and the format collapse,
  not the CLI, and a second implementation is the proof of it.
  (dude was ona about Z-machine)

# ====

Other common LLM providers / Anthropic / OpenAI / Google?
setup api.

Reformat providers.json into a native m8 form?

~/.config/m8-st8/core/providers.json has a good default for url.
Should we add to the default one some basic setups like for claude / openai etc?
Is that too opinionated?
There are some Mac commands in there for key access.
Maybe we just make a folder of example setups

# ==== REVIEW SUGGESTIONS

Review notes after inspecting the README, architecture, and source, and running:

* `zig build test` — passes
* `zig build` — passes
* `zig build split` — passes

The core idea is unusually coherent: the ledger, file-based state, codecs,
tools-as-filters, and split/single builds all reinforce each other.

## Highest priority

### Make writes crash-safe and concurrency-safe

`src/session.zig` currently writes turns and aliases directly with `writeFile`.
That risks partial files if the process is interrupted, and concurrent runs can
race while updating `+/...` aliases.

Use:

1. write to a uniquely named temporary file in the same directory;
2. flush/fsync it;
3. atomically rename it into place;
4. optionally fsync the directory.

For aliases, consider a lock or compare-and-swap mechanism. This is especially
important because the project's strongest claim is that the ledger is durable
and authoritative.

### Fix silent invalid environment names

In `shield.parseValue`, invalid environment names are currently swallowed:

```zig
const env_var = envName(arena, raw_env_var) catch
    return .{ .name = name };
```

That silently converts an invalid variable name into “no variable”.
`toolbox.parse` is stricter and returns `BadEnvironmentName`, so the behavior is
inconsistent.

Make `parseValue` return:

```zig
(Error || Allocator.Error)!Activation
```

and propagate `BadEnvironmentName`. Configuration mistakes should fail when
the definition is read, not disappear.

### Add resource limits around external processes

The design intentionally avoids arbitrary ledger depth limits, which makes
sense semantically. Operational limits are still needed:

* maximum expanded ledger bytes/records;
* maximum provider response size;
* maximum tool output size;
* process timeout;
* maximum number of spawned descendants;
* cancellation when the parent exits;
* perhaps a per-command memory budget.

`launch.spawn` currently writes the complete input and waits for the child.
That is simple, but a tool that hangs or emits unbounded output can hang the
whole harness.

### Treat `munge` edits as transactions

The ideas already in this file are good. Prioritize:

* `read` returns a content hash or revision token;
* `write` accepts `expected_hash`;
* refuse the write if the file changed;
* support dry-run;
* write atomically;
* report a compact unified diff.

Exact substring matching gives useful safety already, but a file-level
compare-and-swap closes the read/write race.

## Testing and compatibility

### Add single-vs-split parity tests

The two build modes are a major architectural feature. Test them as two
implementations of the same CLI contract.

For a corpus of commands, compare:

* stdout;
* stderr;
* exit status;
* saved ledger output;
* error behavior;
* streaming behavior.

Run this on Linux and macOS, in debug and release modes, and add CI if there
is not already a tracked CI configuration.

### Add fuzz/property tests

The parser and codecs are ideal candidates for fuzzing:

* malformed m8/Markdown records;
* unclosed fences and quotes;
* include cycles;
* very long lines;
* invalid provider JSON;
* streamed versus complete responses;
* regex patterns such as nested repetition;
* schema round-trips.

Useful invariants include:

```text
parse(render(parse(x))) == normalized(parse(x))
decode(encode(ledger)) == equivalent ledger
streamed_response == complete_response
single_binary == split_binary
```

### Define a formal conformance suite

The README is detailed, but a third-party implementation would benefit from:

* canonical input/output fixtures;
* explicit grammar rules;
* malformed-document examples;
* unknown-sigil behavior;
* canonical rendering rules;
* codec test vectors.

This would turn “implementable from the README” into a practical compatibility
promise.

## API and data-model improvements

### Validate toolbox types earlier

Tool property types are currently stored as strings and emitted directly into
JSON Schema. A typo such as an unsupported type can survive until a provider
rejects the request.

Consider parsing the type into a small internal representation:

```text
string
integer
number
boolean
object
array(T)
enum(...)
```

Then reject malformed types, empty enum members, invalid dotted paths, and
contradictory object declarations at definition-load time.

### Make rendering deterministic

The project emphasizes readable, diffable files. JSON object iteration order
can make rendered argument blocks or recovered schemas unstable.

Consider sorting keys when converting provider JSON back into m8 records, or
explicitly preserving insertion order everywhere. Stable output will improve
Git diffs and reproducibility.

### Add source locations to errors

Errors like `UnknownRunner`, `BadEnvironmentName`, and `TopMisplaced` would be
much more useful with:

* source path;
* record number;
* line and column;
* offending value;
* include/lineage path.

Instead of:

```text
m8: BadEnvironmentName
```

prefer something like:

```text
m8: invalid environment name `foo-bar`
  in ~/.config/m8/agents/pagey.md:18
  while reading shield `sandbox`
```

## Documentation and product shape

The README is strong, but it is doing three jobs:

1. manifesto/design rationale;
2. user manual;
3. format specification.

Consider splitting those into:

* a short practical README;
* `docs/design.md`;
* `docs/format.md`;
* `docs/security.md`;
* `docs/conformance.md`.

The current document is compelling, but a new user has to read a lot of
philosophy before finding the smallest useful workflow.

The most valuable next milestone is:

> Crash-safe storage + strict config validation + single/split parity tests + CI.

Those would strengthen the project's central claims without adding much
conceptual complexity.


# ==== [SUGGESTED]

## Highest-priority suggestions

### Create a concise “first five minutes” guide

The README is thoughtful but very large. Add a short path near the top:

```sh
m8 new my-chat
m8 my-chat
m8 show my-chat
m8 fork my-chat experiment
```

Show one complete provider/tool example and explain where files are stored.
Keep the manifesto, but make the first successful interaction nearly
effortless.

### Add `m8 doctor`

A diagnostic command could check:

* config paths and permissions;
* provider executability;
* missing commands in `commands.txt`;
* stale split binaries;
* malformed ledgers;
* terminal/stdin capabilities;
* sandbox availability.

This would dramatically improve bug reports and onboarding.

### Make ledger validation a first-class command

Something like:

```sh
m8 check file.m8
m8 repair file.m8
```

`check` should report the exact record, line, and invariant that failed. Since
the ledger is the project’s central promise, users need a dependable way to
validate it independently of a conversation run.

### Implement optimistic concurrency protection

Have read operations optionally emit a file hash or revision, and have edits
reject stale writes:

```text
edit(path, expected_sha256, old_text, new_text)
```

Exact replacement protects against many mistakes, but a file-level
compare-and-swap closes the read/edit race.

### Add first-class file operations

`delete`, `move`, and perhaps `mkdir` would make the tool ecosystem less
dependent on unrestricted shell commands. For deletion:

* refuse directories by default;
* require existence;
* display size and path;
* support `--dry-run`;
* optionally move to a trash directory instead of permanently deleting.

### Improve destructive-command controls

Since tools are intended for agents, consider policy distinctions such as:

* read-only;
* workspace-mutating;
* destructive;
* network-enabled.

Add timeouts and a compact changed-files report for shell commands. This aligns
especially well with the project’s “control” principle.

## Architecture and maintainability

### Reduce README conceptual repetition

The design is compelling, but several ideas recur: files over app state, one
grammar, composability, and provider neutrality. Consider moving the detailed
argument into `docs/design.md` and keeping the README structured as:

* what it is;
* five-minute example;
* format;
* commands;
* configuration;
* design principles;
* deeper rationale.

### Add compatibility fixtures

The grammar is important enough to warrant a corpus of sample files:

* valid minimal ledgers;
* every sigil;
* Unicode and shortcode forms;
* malformed headers;
* missing blank lines;
* escaped content;
* provider/tool exchanges;
* old-format examples.

Run every parser and codec against these fixtures. This will help preserve the
“implementable in an afternoon” promise.

### Test the split and monolithic builds equivalently

Since the two-build design is central, add tests that execute both forms against
the same scenarios and compare:

* stdout;
* stderr;
* exit status;
* generated ledger;
* filesystem changes.

This prevents architectural drift between the two modes.

### Make stale generated artifacts impossible or obvious

`zig build split` should probably clean or reconcile `zig-out/bin` before
installing. Alternatively, generate a manifest of expected binaries and have a
command report stale outputs.

## UX improvements

### Add a graph/history command

The `m8 threads` idea seems valuable:

```sh
m8 log --graph --all
m8 branches
m8 dangling
```

Start with graph structure, parent references, timestamps, and labels. Summaries
can come later. This would make the filesystem-backed conversation model much
easier to navigate.


Listing agents and mobs? Do we even? ls right?
```
m8 list agents [MOB]
Lists agents then sub-mob agents alphabetically.
```


### Use machine-readable diagnostics

Human output can remain pleasant, but add:

```sh
--format=plain
--format=json
--format=m8
```

JSON diagnostics would help scripts and editor integrations without
compromising the text-first design.

### Show compact diffs for edits

The proposed munge change output is excellent. Make it standard, with:

* changed line range;
* unified diff;
* explicit dry-run mode;
* clear failure suggestions when the match is near but not exact.

### Treat binary search results explicitly

Report skipped binaries rather than silently omitting them:

```text
(binary skipped: image.png)
```

A `--binary=skip|report|search` option would be a clean extension.

### Add shell completion

Completion for commands, config names, agents, sessions, and paths would make
a command-heavy interface feel much more approachable.

## Product positioning

### Define the smallest stable public surface

Decide what you are willing to support long-term:

* ledger grammar;
* filesystem layout;
* command names;
* provider stdin/stdout contract;
* tool contract.

Mark everything else experimental. This matters because the project’s strongest
appeal is durability.

### Publish a tiny reference implementation

Alongside the Zig implementation, provide a deliberately small parser/reader—
perhaps Python or POSIX shell—for the core ledger format. That would substantiate
the portability claim and make the format easier for others to adopt.

### Build one polished end-to-end demo

The Z-machine example is technically compelling, but a short demo involving:

* a file edit;
* a tool call;
* a fork;
* a provider response;
* a readable transcript;

would communicate the project faster to most users.

## Suggested prioritization

If prioritizing, start with:

1. first-five-minutes documentation;
2. `m8 doctor`;
3. ledger validation;
4. optimistic edit protection;
5. equivalence tests for split versus monolithic builds.
