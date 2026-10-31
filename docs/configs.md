# Configs

There are three layers, ordered project → user → system:

* The **nearest** `.m8-st8/` from the working directory upward. It participates
  only when registered with `m8 register`; ancestor projects are not additional
  overlay layers. `m8 register -l` lists candidates and their trust status.
* `$XDG_CONFIG_HOME/m8-st8/`, defaulting to `~/.config/m8-st8/`.
* `/etc/m8-st8/`, built in at compile time (configurable with `-Dsystem-config-dir` at build time).

Registration is machine-local and records canonical paths in the user's
private config registry. A cloned project does not become trusted merely by
existing. Children inherit the validated roots through `M8_ST8_DIRS`; unset it
for fresh discovery. An explicit list still contains at most one project.

## Core resources

`core/` resolves **per file**, nearest first. A selected file is taken whole;
missing keys do not fall through to another layer.

* `core/providers/NAME.json` holds one provider object, named by its filename.
  Different names may come from different layers; the same name is never merged.
  * An explicit `parent` inherits another selected provider's keys recursively.
    See [Inheriting a provider](providers.md#inheriting-a-provider).
* `core/config.json` holds optional `tui` and `highlights` settings.
* `core/mac-sandbox.sb` supplies the native sandbox profile, with the built-in
  profile used when no file exists.
* m8 carries no provider configuration.

For example:

```json
{ "highlights": "quote:fgt4bg255+i_!/,list:fg244,table:pipe:fgt8,wrap:literal:70,wrap:word:90" }
```

Highlight entries are comma-separated `name:style` pairs. Names include `quote`,
`list`, `hash`, `heading`, `strong`, `em`, `strike`, `code`, `link`, `rule`,
`table:pipe`, `table:head`, `fence`, `block`, `diff:add`, `diff:remove`,
`diff:hunk`, `diff:context`, `json:string`, `json:key`, `json:atom`, `json:sep`,
and `indent`. JSON fences get best-effort string, key, atom and separator
highlighting; `json:sep` styles key delimiters and escape introducers. JSON
contents are not validated.
Styles combine `fgN`/`bgN` (0–255),
`fgtN`/`bgtN` terminal palette indices (0–15), and modifiers `+` (bold),
`-` (faint), `i` (italic), `_` (underline), `!` (inverse), `/` (strike).
Styles are read left to right; bold and faint are mutually exclusive, with
the last taking effect. Duplicate entries also use the last value. Each
supplied style replaces that style; unspecified styles retain defaults.

Wrapping thresholds share the same comma-separated string:

* `wrap:literal:70` breaks before an opening inline code span at 70% full.
* `wrap:word:90` breaks before a new word at 90% full.
* These are the defaults; each accepts an integer from 0 to 100.
  * `0` disables that early-break rule, not ordinary hard wrapping.
  * `100` waits until the content area is full.
* Percentages use terminal cells after the repeated quote and indent prefix.
  * Thresholds round up to a whole cell; a nonzero threshold is at least one.
  * The first content on a line never causes an early break.
* Early breaks are streaming guesses, not a guarantee that a span will fit.
  * Code spans stay whole and can overflow; tables and literal blocks keep
    their own layout.
  * Existing spaces are preserved, including spaces before an inserted break.
* Wrapping needs a known terminal width and enabled reflow.
  * `render --parsable` disables it; `--no-highlight` only disables colour.

## Mobs

A mob keeps related agents and their conversations together. Definitions and
state have different lookup rules:

* **Definitions:** take the first matching file, searching project → user →
  system. A missing definition falls through to the next layer.
* **State:** the first `mobs/NAME/` directory places the mob. Chats, turns and
  workspace stay at that layer; they never fall through.

An empty project mob directory is enough to keep conversations in the project,
even when every agent definition comes from the user or system layer. Creating
it starts a separate home for those conversations; it does not move or resume
state from a higher layer.

```
.m8-st8/
  core/
    providers/local.json
    config.json
  mobs/
    demo/
      mathy.md                     :demo/mathy
      tight-docs.md                :demo/tight-docs
      .chats/
        mathy/+.md                 mathy's movable chat pointer
        mathy/+/tduyxbutjb.md       an immutable turn
        mathy/_/aside/+.md         a subchat pointer
        mathy/_/aside/+/qgivwhgxnh.md  an immutable subchat turn
        .uploads/                  files prepared for provider upload
      .mob-space/                  persistent workspace shared by mob tools
```

There are no top-level agents or nested mobs. Agent definitions may nest within
one mob, for example `mobs/demo/utils/shields.md` is `:demo/utils/shields`.
Path components cannot begin with `.`; authored-agent components also cannot
begin with `_`, at any depth. Logical `//` starts a subchat path and maps to a
reserved `_/` directory beneath the agent's generated state, keeping it
separate from nested authored agents. `/+/TURN` names a turn in that chat.
The movable pointer is still stored as `+.md`; chat addresses need no trailing `/+`.

## Compose across layers

An authored agent can include definitions from another mob with 🧠 or 📚.
Nothing makes the included file a special kind of agent: a mob used only for
shared instructions or tools is still an ordinary mob.

Each reference searches from the project layer again. A project definition can
therefore customize a dependency used by a user- or system-level definition.
The included definition does not change where the caller's state lives.

A direct reference to the same name and part instead searches **above the
current definition's layer**. This lets a definition build on its higher-level
namesake. For example, a project `mobs/team/dev.md` can contain:

```markdown
* :brain::team/dev

* :compass::
  > Follow this project's conventions.
```

The first record includes the user definition of `team/dev`, or the system
one if no user definition exists. A user definition can do the same to build on
the system definition. If no higher definition exists, the reference is a
missing agent. An indirect return to the same file and part is still a loop.
A body referring to its own 📚 top uses ordinary lookup: the two parts are
separate.

Chats and turns do not gain cross-mob lookup. References from a chat or turn
stay within its mob, and an authored agent cannot include another mob's chat
or turn. To operate on another mob's conversation, invoke a separate command.

## Agents as commands

A tool can invoke another mob with a command such as
`m8 say --answer --unwrap :other/reviewer "MESSAGE"`. That activation has its own mob state.
A tool can also resolve a shared document and emit its contents: what the tool
returned is then recorded in the conversation, rather than a live reference
that could change on a later read.

An agent needs no special way to spawn another: a 🧰 whose command invokes
an agent is a subagent, running inside that tool's shields.

* `m8 say --new --answer --unwrap :team/reviewer//job "MESSAGE"` starts fresh from the authored
  agent. Without `--new`, it carries that chat on, including answering a
  question the agent asked.
* `--no-advance` asks without advancing the chat.
* The caller receives the reply as text, not a ledger. Only the explicitly
  addressed chat moves; the caller's conversation is not taken over.

## State and workspace locations

Project mobs keep writable state inside their project mob directory. User and
system mobs keep it under `$XDG_DATA_HOME/m8-st8/`, defaulting to
`~/.local/share/m8-st8/`:

```
<project>/.m8-st8/mobs/demo/.chats/
<project>/.m8-st8/mobs/demo/.mob-space/
<data>/m8-st8/user/mobs/demo/.chats/
<data>/m8-st8/user/mobs/demo/.mob-space/
<data>/m8-st8/system/mobs/demo/.chats/
<data>/m8-st8/system/mobs/demo/.mob-space/
```

Here `<data>` is `XDG_DATA_HOME` or `~/.local/share`. The nearest mob directory
selects the state location, regardless of which layers supply its definitions.
Relocated state is never searched as an independent overlay. A user mob placed
ahead of a system mob has separate state.

Tools and provider stages receive:

* `M8_MOB_ST8_DIR`: absolute config root containing the nearest mob directory.
* `M8_MOB_DIR`: absolute `.chats` state directory. Uploads go in
  `$M8_MOB_DIR/.uploads/`.
* `TMPDIR`: the pre-created, persistent sibling `.mob-space/` workspace.

Nothing automatically deletes the workspace. Ignore generated project state
with `mobs/*/.chats/` and `mobs/*/.mob-space/` in `.m8-st8/.gitignore`.

## Turns and chats

* A chat is a `+.md` pointer. A turn is an immutable file in that chat's `+/`
  history directory; logical names remain `MOB/AGENT/+/ID`.
* A chat with no pointer inherits its parent's head. The parent of an agent's
  own chat is its authored agent.
* Promptless `say CHAT-` removes a chat's pointer; `say CHAT--` starts it from
  the authored agent. `say --parent CHAT` and `say --new CHAT` are equivalent.
* A side question advances nothing. Forks share parent turns without copying
  transcripts. Snips remain alongside the turns that refer to them.
* `say` keeps progress incrementally; only the explicitly addressed
  chat moves. A model call is saved as a turn, and a tool call as two: the 📲
  as it is made, then its answer. An interrupted run keeps what happened so far.
  * A tool call left unanswered when a run died is closed on continuation with
    a 🚫, never automatically rerun: it may already have had side effects.
    The model decides what to do next.
  * Ctrl-C lets the tool stop however it stops, records the outcome, closes
    calls that will not now run, and ends the run. A second Ctrl-C stops
    immediately where it stands.
* There is no global/main pointer. Bare `m8` shows help; to resume a chat,
  explicitly name it with `m8 :MOB/AGENT` (or its subchat address).

Inclusion and lineage expand in record order with loop detection, not an
arbitrary depth limit. Authored inclusions can cross mobs; lineage cannot.

## Models

A 🧠 written with a leading `/` names a model rather than an
agent, and carries whatever the api should be asked for:

```m8
▐ 🧠:/local/Ternary-Bonsai-8B-mlx-2bit,max_output_tokens:8192,temperature:0.7
```

> * :brain::/local/Ternary-Bonsai-8B-mlx-2bit,max_output_tokens:8192,temperature:0.7

Parameters are the api's own words, passed through as
written. m8 translates none of them and knows none of them
by name, so one it has never heard of works, and one that
came back off a wire goes out again unchanged. `,` separates
them, and a value may be JSON — quote it if it holds a comma.

A model is not a name. Nothing declares its own name in m8,
a file is what it is called, and a model has no file. So it
has no name, keeps no chat, and is written out in full
wherever it is used.

Writing a file is how it comes to have one, like everything
else, and that is also how a model is configured once and
used everywhere:

Stored chats always belong to an agent in a mob; there is no global storage
fallback for a bare model. Addressed runs are made with `say`; read-only model
references can be composed with `say --no-send`.

```
.m8-st8/
  mobs/local/Ternary-Bonsai-8B-mlx-2bit.md   :local/Ternary-Bonsai-8B-mlx-2bit
  mobs/demo/tiny.md                               :demo/tiny
```

```m8
▐ 🧠:/local/Ternary-Bonsai-1.7B-mlx-2bit,max_output_tokens:2048
```

> * :brain::/local/Ternary-Bonsai-1.7B-mlx-2bit,max_output_tokens:2048

An agent file is the only kind of alias there is, so it also
composes: put a model after an agent you include and the
model wins, since the last model named is the one that
answers — the same rule as a tool's last definition.

```m8
▐ 🧠:demo/mathy
▐ 🧠:/local/Ternary-Bonsai-27B-mlx-2bit,max_output_tokens:16384
```

> * :brain::demo/mathy
> * :brain::/local/Ternary-Bonsai-27B-mlx-2bit,max_output_tokens:16384

A chat is the same: a model piped in after one runs it, and
every turn after that is still on it, because the model is
later in the ledger than the agent it took over from.

## Environment

What m8 itself reads:

```
XDG_CONFIG_HOME   your own config, as m8-st8 under it
HOME              that, when XDG_CONFIG_HOME says nothing:
                  ~/.config/m8-st8
PATH              where a provider or tool named as a bare
                  word is looked for, and where m8 finds itself
TMPDIR            the selected mob's persistent .mob-space workspace
```

What m8 adds when launching a provider or a call:

```
M8               absolute path of the m8 launcher running it;
                  an inherited value is always overwritten
M8_VERBOSITY      1 under -v, 2 under -vv; a tool is handed
                  it too, and an m8 started with it set says
                  as much without being asked
M8_ST8_DIRS       validated project/user/system roots, : between
M8_ST8_USER_ROOT  the user config root associated with that list
M8_ST8_DATA_ROOT  the resolved XDG data root, including /m8-st8
```

And what a provider's commands are handed as well:

```
M8_PROVIDER_*     every string the entry said
```

The two m8 ships with read `M8_PROVIDER_URL` and
`M8_PROVIDER_HEADER_*` between them, and `m8 url-provider
--help` says what each is for. A provider you write reads
whatever its entry says, under its own name.

Every tool is handed the mob's scratch as `TMPDIR`, and its
`HOME` is left alone.

Moving `HOME` or dropping what was inherited is a shield's
business. See `contain-home` and `contain-env` in [Shields](shields.md#a-shields-file).
