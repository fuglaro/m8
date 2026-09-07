
# ==== DONE

```
# Shell accessible m8 parser that expands whole chats ledgers.
m8 +mathy encode m8
m8 +mathy encode m8 >full-ledger-copy.md # raw when not tty
m8 decode m8 # null operation

# Shell accessible api conversion.
# Can be lossy as it can forget the target model through an encode/decode.
m8 +mathy encode openai
m8 encode openai-completions <full-ledger-copy.md >openai.json
m8 decode openai-completions <openai.json # reverses operation

# Shell accessible redirect to provider interaction.
m8 decode openai-completions <openai.json | m8 send [PROVIDER/MODEL]
```

Command line inclusions like +mathy and what comes after -- are appended to any stdin.
Providers api entry should change from openai to openai-completions.
  It makes the api field and the codec name the same namespace.
  The codec should own the URL suffix too.
  Allow models to override the provider api key with their own api key.
m8 is always a ledger: retain record order, shift any reordering/combining to model apis,
  because every api encoding are projections of it.
m8 is truth: avoid dropping things from the history.
Fix: "Tool calls are dropped from history" - tool calls should stay in m8.
  Calls that have already been responded to are not called again.


# ==== DONE

`m8 [-l LOCKS] [@AGENT|+CHAT] [COMMAND [ARGS]] [-- PROMPT]` -> sorry, is confusing things.
I need to separate some concepts so I'm not asking for spaghetti:
```
  m8 [-l LOCKS] [[@AGENT|+CHAT] MSG_CMD|RUN_CMD] [ARGS]

msg_cmds:
  --     consults an agent...
  cat    ...
  encode ...
  send   ...

  Respects stdin as m8 or raw prompt and assembles a ledger and prompt.


run_cmds:
  call   ...
  ... 
```
And maybe we should just move ask as a native inbuilt inder the call cmd:
```
m8 call ask ...
```

Assembly of ledger (with `STDIN | m8 [@/+NAME] -- PROMPT`):
 - no STDIN: assembles `NAME(fallback to last chat) → -- prompt`
 - detected m8 STDIN: assembles `NAME(no fallback) → STDIN → [-- prompt](runs even without)`
 - other STDIN: assembles `NAME(no fallback) → [-- prompt](runs even without) + STDIN appended to prompt`
We detect on initial ligature, so the detected m8 STDIN can still error on malformed.

# ==== DONE

can't run, and it reports that honestly rather than silently.
The one real loss. openai → m8 → openai is byte-identical except max_tokens, which came from your provider config and isn't on the wire.



* New model only form starts with @/: `@/local/Ternary-Bonsai-1.7B-mlx-2bit,context:32768,max_tokens:8192`
* Parameters are expected to be the provider api's form.
* Considered an unnammed agent so not chat is automatically made.
* No longer falls back to a model if an agent isn't found with the old form.
* Models can no longer have their own api defined, it can only be defined at a provider level.
* Multiple providers can be defined each with a different api to give access to multi-api-providers.
* Users can always make agents with matching names that simply reference the
  model so an agent form is accessible `@Ternary-Bonsai-1.7B-mlx-2bit` or even
  like it was by making a mob `@local/Ternary-Bonsai-1.7B-mlx-2bit`.
* providers.json no longer supports the models entry. Much simpler and everything moves into m8.
* Chamge to `m8 send PROVIDER` since we don't need to specify the model anymore.
* When doing this migrate .m8-st8 and make the agent aliases
  like `@local/Ternary-Bonsai-1.7B-mlx-2bit` for compatibility.

# ==== DONE

Consider:
m8 → openai → m8 also loses 🔌 — so a decoded tool
Won't do. By design.

# ==== DONE

COMMAND PROVIDERS

Support custom providers and api converters with plugin commands in core m8-st8.

* Move providers.json under m8-st8/core/.
* Change the providers.json format so it runs via commands
  which takes api-formatted request as stdin
  and outputs the response in it's own api-format e.g: `m8 providers PROVIDER`
* Passes provider args as env vars on launch with M8_PROVIDER_ prefix.
  All args matching a specific format are provided in the env on top of the inherited env:
    * When values are strings.
    * When keys are lowercase with hyphen,
      and they convert to uppercase with underscores in the env var name.
* Has a fallback approach to finding the command path to run:
  * If the command starts with the "m8" value, it is expanded to the full path
    of the m8 executable that launched it.
  * Otherwise if the first value in cmd starts with a "/", it runs as a full path executable.
  * Otherwise if the first value exists as a file relative to m8-st8/core/,
    it runs as the full path to that file, and if that file is not executable, it errors.
  * Otherwise if the first value contains no "/", it is PATH-searched.
  * Otherwise failure.
* Providers may fail with a return code and stderr message if, for example, the api is not supported.
* Failure mode is an exit non-zero, propagated.
* Support an overridable default src/core/providers.json similar to the other core configs:
  ```
    "inbuilt": {
      "cmd": ["m8", "providers", "inbuilt"],
      "api": "m8",
    }
  ```
* Args `cmd` and `api` become the only special ones known to m8:
  * Both are used for knowing the command and formatting to encode and parse,
    while cmd is not passed through while api is, purely due to format expectatons.
  * Any `key` arg (M8_PROVIDER_KEY) is provided from the providers.json to the command verbatim,
    if it is a string, and is not considered any kind of special parameter,
    except to the provider command itself, if it expects it.
* Current providers in providers.json get a cmd added of `["m8", "providers", "url"]`.
* Get rid of Codec.suffix and move it to the providers.json config.
  For current configs, migrate by extening the url with "chat/completions".
* Providers SHOULD support streaming, and all included ones in m8 do, if it's possible.
* Support direct accesss to default url providers with `m8 providers url`.
* Add response parsing back to m8 with new `m8 parse API` RUN_CMD.
  * Internal defined only with cli over it, since custom API support,
    can only be done with custom providers that speak m8.
  * If the response API format supports streaming, the parse command
    MUST support streaming to m8.
  * If response API can give both streaming and non-streaming forms,
    the response must be inspected to determine parse mode.
* Add test models to inbuilt provider (`m8 providers inbuilt`):
  * `m8 @/inbuilt/echo` says back last ledger entry.
  * `m8 @/inbuilt/you-are` always responds "I know you are but what am I?"
  * `m8 @/inbuilt/runner` calls tools for last message (if a user messge)
     for lines matching `RUN;;;toolname;;;property=val;;;...`
     without support for escaping separators.
* Locks do not apply to provider commands.
* Document appropriately, including noting:
  * rule: mobs travel with agents; providers are yours.
  * Provider commands are exclued from locks,
    since trust is managed at the protected core folder level,
    and details about why it is safe.
  * a provider declaring api: "m8" receives the whole ledger, 🔌 and 🔒 included,
    rather than a projection of it.

# ==== DONE

Hone Prior Art into existance justification and put into README.
  Done as ## Why. PRIOR-ART.md removed.

# ==== DONE

additional fun inbuilt models

```
m8 @/inbuilt/elisa  # responses as that old school AI bot.
m8 @/inbuilt/text-adventure-some-mit-flavour-one
```

# ==== DONE

REJECTED IDEA: Change :receipt: to :outbox_tray:
Change :computer: to :compass:

# ====
Tools  2.0

Locks change to Shields (Tool Wrappers)

#### :runner:bash
> `m8` `call` `bash` `-c` `{{CODE}}` `bash`
— runner (value) resolves inline codes into an executable command, substituting {{CODE}}, for subsequent code blocks on interpretation of the code block, forked from searching the PATH, and executing without an interpreter)

#### :shield:deny
> `false`
#### :shield:ask
> ```bash
> exec m8 shield ask -- "$@"
> ```
— the block quote form just defines the shield, it must still be subsequently activated.
— the block quote form defines wrapper commands for tools.
— a shield can be defined multiple times and acts cumulatively as stacked wrappers.
— the block quote can contain lines of inline codes defining wrapper commands.
— the block quote can contain a code block which must define a language that refers to a previously defined runner.
— subsequent shields and the toolbox command will be suffixed as arguments.
— multiple shields defined with the same name stack cumulatively.
— multiple commands stack cumulatively.

#### :shield:deny
#### :shield:ask
— shield sigils without a block quote  enable the shield without changing its definition.
— shields like "ask" may be activated last to avoid the user being queried about long shield wrapper prefix lists.

#### :shield:filter-toolbox
> `bash` `-euo` `pipefail` `-c` `"$0" "$@" | m8 filter out toolbox`
#### :shield:filter-unlock
> `bash` `-euo` `pipefail` `-c` `"$0" "$@" | m8 filter out unlock`
— filter also filters out entire :brain: sigils if they contain anything filtered out.

#### :shield:secure
> ```bash
> exec m8 shield secure "${SECURES}" -- "$@"
> ```
#### :shield:secure SECURES airgap
#### :shield:secure SECURES no-writes
— shield sigils with additional values (space separated) activate the shield and append those values to that environment variable, which is passed to the shield wrapper with the env command.

#### :shield:sandbox
> :shield:secure SECURES private contain-writes no-loop no-edit-git no-edit-m8-st8 contain-env
#### :shield:jail
> :shield:sandbox
> :shield:airgap
> :shield:no-loop
— shields can also be defined as a composition of other shields.

Toolbox syntax changes.

#### :toolbox:tool
> > DESCRIPTION
> :shield:ask
> ```bash
> grep -r "$M8_ARG_PATTERN" .
> ```
> * pattern string
>   what to look for
> * ignore_case? boolean
>   optional, so unset rather than empty when not supplied
— first, the blocked quote is the description
— then, additional shields (no block quote form)
— then, a code block or inline blocks is the command to run.
— then arguments as bullet points, NAME<?> TYPE, then description on continuation lines.
— name is up to the first space, type is the rest of the line, so an enum may hold a space.
— ? on the name carries optional, replacing :package: and :gift:. Type carries [] and | as before.
— a toolbox inherits all previously activated shields and can activate further shields.
— arguments never substitute into the command. Nothing m8 builds ever contains model text.
— inline code form: {{ARG}} raw expands as separate arguments, one argv element per value.
— code block form: no placeholders. Arguments arrive in the environment instead, so the block
  is run verbatim and any language reads them natively.
— M8_ARG_<NAME> per scalar: the name uppercased, when it is a portable identifier
  ([A-Za-z_][A-Za-z0-9_]*). Optional and not supplied means unset, not empty.
— M8_ARGS always carries the whole call as JSON, which is what nested, dotted and [] arguments
  use. No flattening, no separator to collide with.
— a name with no portable env spelling gets no scalar var and lives in M8_ARGS only. Two names
  colliding on one env name is an error when the toolbox is defined, not at call time.

#### :toolbox:tool ENV_VAR appending-value
— similar to shields, toolboxes can have environment variables added with appending values (space separated).

#### :call:tool CALLID
> * argument `value`
> * argument
>   ```
>   value line
>   value line
>   ```
— code block values always drop one newline at the end.

Locks are therefore no longer needed as arguments to m8.

CALL_ID is always put into the environment of a tool call, and propagates through contain_env.

m8 call m8 -- PROGRAM
— will call a program from the environment that creates m8. :receipt: :green_circle: :no_entry_sign: will have CALL_ID added if they don't already, and :green_circle: :no_entry_sign: will be added if missing.

# ====
Skills 2.0

#### :toolbox:load_skill
> `m8` `call` `m8` `--` `m8` `load` `@{{MOB}}skills/{{SKILL}}`
> * SKILL String

Skill file:
```md
#### :top:
#### :compass:
> Load the tight-docs skill when working on documentation or comments.
#### :top:
#### :raising_hand:
> Skill content…
```

New :top: sigil. If the very first sigil of the file being referenced, begins a top header section until the next :top: sigil. Subsequent tops in a single file is an error.

@agent and :brain: behaves as load (omitting any top on each file read) 
^agent and :books: behaves as top (only giving the top section, if it exists)
This behaviour recurses through deeper references.





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

# ====

Consider removing support for inline code line injection of {{ARG}} formats
now that we went with env pass-ins.
