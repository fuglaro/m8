
# ====

## Munge honing

As the model says:

- bulk or structural rewrites where the existing `edit` interface became awkward.
- replacing a large function required a very large exact string;
- the same text occurred more than once, so `edit` rejected the replacement;
- page scoping sometimes made a match unexpectedly unavailable;
- `edit` does not support a first-class “replace this range between these anchors” operation;
- After edits, I sometimes reasoned from an earlier read. Consider clear and full post edit state with
  path, pages, and lines affected, along with what landed. They asked for a diff that landed. Maybe give the pages affected - with consectutive pages unified.

The “must match exactly once” rule is good protection, but common operations were cumbersome:
- insert before a named function;
- replace a function body;
- append after a known declaration;
- replace the last occurrence of a repeated block;
- replace a range between two anchors.
I would add explicit edit modes:
```text
insert_before: "fn list("
insert_after: "const PageConfig"
replace_between: ["fn list(", "/// What a file"]
replace_occurrence: 2
```

After an edit, the result should include something like:
```text
Replaced 1 occurrence.
Changed lines 370-412.
```
Ideally also:
```text
old match: found
new text: written
```
The tool did report failures, but I failed to respect one of them. A stronger result could make it harder to continue as though a failed edit succeeded.

A dry-run mode would help
For complex changes:
```text
dry_run: true
```
could report the matched range and resulting diff without modifying the file.

A patch tool would be valuable
For multi-file changes, a unified-diff application tool would be clearer than repeated exact string replacements. It could:
- reject stale context;
- show the patch;
- report rejected hunks;
- avoid shell/Python editing.


* [DONE] Make multi-line edit uniqueness also activate on multi-line new_string.

### Post edit failure

Had cases where munge edit came back denied but the model (Luna) shrugged and moved on.
One case was wrong page, another wrong match.

Consider giving advice, detect if match is found on surrounding pages,
and suggest the pages value and say check pages and retry.

If near-match found on page, suggest checking old_string match and retry.

And just be really explicit. Change did not apply, check, adjust, and try again.

### Post edit success

### Read range clarity

* Add trailing metadata lines for each subsequent page returned:
  `[Page 2 (lines 90-130) begins at: Line text up to 150 characters...]`

### Juggling pagination

- For a function spanning multiple pages, I had to read one range, then another, then reconstruct the exact replacement.
* Extend use pages=2-4 to continue to "... to continue or pages 1-4 to reread a larger area"



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


Saw a harness use PositiveInt as a type, and altough clearly a hint, shouldn't we also use Pascal Case for type? Make sure the providers sanity check or clean type so we don't get a kick back.

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

Other common LLM providers / Anthropic / OpenAI / Google?
setup api.

# ====

COMMON TOOLBOXES

Standard ones out there esp for coding.

Think about standardised file sectioning for anything that supports comments, etc.
(`.* ___...--->>>> # SECTION HEADING NAME <<<<---...___ .*`).
Built into tools.

Plugin support -> look first for tool cmds in m8-st8 folders? Think about tool freezing...

# ====

MOB DOWNLOADER

Mob downloader with lock enforcer.
Mob level locks -> "everything under here inherits this brain fragment".

# ====

CROSS OS SUPPORT

* Windows -> anything that locks in a container way falls back to a DENY.
* Linux -> initially like Windows, eventually implementing it's own containerisation system.

# ====

COMMAND ARGS EXTRA

Support ^SKILL
Support session creation?
User calling a tool at a chat?

```
@AGENT - ask an agent, resetting it's named chat.
+CHAT - continue a chat.
... @CHAT - creates freshly named chat if an agent of the same name doesn't exist.

^SKILL - include agent as skill (book in m8)

-- [QUERY] ... - supply user prompt
```

# ====

ORGANISE M8-ST8

Agent definitions search for peers by relative reference going outwards up mob levels.


Note that in the future we may implement persistant chats ongoing between
agents using send_message to each other by referencing

?? How shoud send_message (to another agent) work?
Do we set up persistent chats under a mob?

```
.m8-st8/@/=/REF.m8
.m8-st8/@/+/CHAT.m8
.m8-st8/@/[MOB]/AGENT.m8

.m8-st8/@/+/[SESSION]/CHAT.m8
```

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


# ====

Named Chats

Making a named chat:
m8 @quick +chat-session-name -- …
m8 +chat-session-name -- …

So essentially
m8 @quick …
Is just shorthand for:
m8 @quick +quick …

Forking a chat to a new name:
m8 @=/xxx +chat-session-name
m8 +chat-session-name -- …

====
Listing

m8 list agents [MOB]
Lists agents then sub-mob agents alphabetically.

m8 list chats [MOB]

…

# ====

Mob chats

IDEAS CURRENTLY ALL OVER THE PLACE

m8 @quick +teamy/
m8 @review +teamy/
m8 @thinker +teamy/
m8 @big ^plan ^manager ??????? +teamy/orchistrator
m8 +teamy/orchistrator -- 'get everyone to do something cool'

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



# ====

Specify the format independently of the Zig implementation, sooner than
  feels necessary. The moat is the data model and the format collapse,
  not the CLI, and a second implementation is the proof of it.

# ====

~/.config/m8-st8/core/providers.json has a good default for url.
Should we add to the default one some basic setups like for claude / openai etc?
Is that too opinionated?
There are some Mac commands in there for key access.
Maybe we just make a folder of example setups.


# ====
Rename CALL_ID with propper prefix M8_CALL_ID

# ==== DONE

Inline `{{ARG}}` injection in an argv comes out of the framework. The
environment is the only way a call is carried, and `m8 call args` expands it
from outside. Specified above under M8 CALL ARGS.
