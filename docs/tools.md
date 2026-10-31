# Tools

A tool is a program that reads m8 and writes m8. This is how a call reaches
one, how a tool asks the person something, and how a definition fixes its
defaults. What a tool may not do is [Shields](shields.md).

## Carrying the Call

What a call said reaches its tool in the environment,
and nowhere else. A tool written as an argv is the words
it was written as, one written as a fenced block is the
script it was written as, and m8 hands either to its
command unchanged.

A tool's command answers in m8, and how is the
definition's business.

* `m8 call` turns an ordinary program's output into a 🧾
  and a verdict.
* A command that writes m8 itself is named directly.
* m8 keeps no note of which is which. It reads what came
  back, retaining allowed tool records even without a verdict.
  If no explicit verdict names the call, m8 supplies 🟢 for
  exit status zero or 🚫 for a nonzero exit or interruption.
* For a single tool call, its allowed records are displayed as
  they arrive. Multi-call responses are displayed after completion.

```m8
▐ 🏃:bash
│ `m8` `call` `bash` `-e` `-c`

▐ 🧰:search
│ │ Look for something.
│
│ ```bash
│ grep -r "$__pattern__" .
│ ```
│ * pattern string
│   what to look for
```

> * :runner::bash
>   > `m8` `call` `bash` `-e` `-c`
>
> * :toolbox::search
>   > > Look for something.
>   >
>   > ```bash
>   > grep -r "$__pattern__" .
>   > ```
>   > * pattern string
>   >   what to look for

What a tool is handed:

* `__<NAME>__` per scalar, preserving the argument's
  original capitalization, when it is a portable identifier.
* `____`, always, carrying the whole call as JSON.
  Anything nested, dotted or arrayed has no scalar env
  spelling and lives here instead.
* `M8_CALL_ID`, which call this is.
* `M8_EXCLAMATION_1` and up, what the person answered the
  call. See [Asking the Person](#asking-the-person).

An inherited `__<NAME>__` environment variable is available
as a fallback when the call does not supply that argument.

An argument that was not supplied is unset rather than
empty, which is the whole of what optional means to
whatever reads it. A required one that is missing is
refused before a command is built at all.

### Commands That Want Flags

A shell reads its environment. `curl` and `git` do not,
and turning variables back into flags for them is a
command's own business rather than the framework's.
`m8 call` is the one m8 ships for it.

```m8
▐ 🧰:bash
│ │ Run a bash command.
│
│ `m8` `call` `bash` `-euo` `pipefail` `{{command|-c}}`
│ * command string
│   The bash command to run.
```

> * :toolbox::bash
>   > > Run a bash command.
>   >
>   > `m8` `call` `bash` `-euo` `pipefail` `{{command|-c}}`
>   > * command string
>   >   The bash command to run.

Given `__command__=echo hi`:

```
{{command}}       --command "echo hi"
{{command|-c}}    -c "echo hi"
{{command|}}      "echo hi"
{{deep?--deep}}   --deep, when the value is exactly true
{{}}              -- followed by the whole call as JSON
{{|}}             the whole call as JSON, without a flag
```

The flag a bare placeholder carries is the argument's
own name, preserving its spelling. An empty name is the
whole call: `{{}}` gives it the `--` flag, while `{{|}}`
injects it directly.

A placeholder is a whole argument and is never spliced
into a larger one, so a value cannot become syntax in
what runs. Only an explicit `m8 call` expands one; the
harness passes every other command as written, and a shield
reads what it was told from its environment.

* An unset variable leaves nothing behind. An empty one
  is a value a command was given, and is passed as an
  empty argument.
* Only `?` reads a value: `true` emits the flag, `false`
  emits nothing, and anything else is an error naming
  what arrived, because a call that looked like it
  succeeded while ignoring what was asked is worse than
  one that failed.
* Only a whole argv word shaped as `{{name}}` is looked at,
  so values are never spliced into larger words. Other brace
  expressions survive — `m8 call awk '{{print $1}}' f` runs
  the awk program it was handed.

None of this is privileged. An argv is passed on as it
was written, so a toolbox naming some other expander
works the same way, and deleting `call` leaves the
framework whole.

### Definition variables

A tool definition can supply fixed environment values without
putting them on the definition header. Each value gets its own
blockless header, and a final bare header offers the tool:

```m8
▐ 🧰:read
│ │ Read a file or directory.
│
│ `m8` `call` `m8` `munge` `read` `{{page_lines|--page-lines}}` `--` `{{path|}}`
│ * path string

▐ 🧰:read page_lines 100
▐ 🧰:read
```

> * :toolbox::read
>   > > Read a file or directory.
>   >
>   > `m8` `call` `m8` `munge` `read` `{{page_lines|--page-lines}}` `--` `{{path|}}`
>   > * path string
>
> * :toolbox::read page_lines 100
> * :toolbox::read

Definition variables and call parameters share the `__name__`
environment convention. Definitions are written with logical names,
for example `read PAGE_LINES 100` or `sandbox byte_cap 20000`.
If both provide the same name, their values are joined with a space,
with definition values first and call values last. Shields use the
same convention, so their definition values participate in that merge.

* Content defines, a variable header configures, and a bare header offers.
  * The three stay apart, so a definition with several defaults still reads.
  * A defining header cannot also carry a variable.
* Several variable headers may be written.
* A variable reaches a command the way a call's own values do: in the
  environment, and as flags wherever the command line names it.

### Asking the Person

A tool that needs something from the person asks through
the ledger, so the question and its answer are part of the
conversation.

```m8
▐ 📲:deploy,c1
│ * target `"prod"`

▐ ❓:tool,c1
│ deploy to prod?

▐ ❗:tool,c1
│ yes

▐ 🧾:c1
│     deployed
▐ 🟢:c1
```

> * :calling::deploy,c1
>   > * target `"prod"`
>
> * :question::tool,c1
>   > deploy to prod?
>
> * :exclamation::tool,c1
>   > yes
>
> * :receipt::c1
>   >     deployed
> * :green_circle::c1

* A tool asks by ending in a particular way.
  * Exit status 75.
  * Nothing on stdout.
  * A stderr that opens `QUESTION:tool:`, with the question
    after it.
* A shield asks the same way, under its own name.
  * `QUESTION:shield_ask:` is `🛡️ask` asking.
  * Every shield receives one names argument before the command it wraps.
    It defaults to the shield's identity (`ask` here); activation names
    replace that default. `ask-shield` makes it safe for question/answer IDs.
* The ❓ says who asked and of which call: `❓tool,c1`.
* The run stops on the ❓.
  * Calls the model made alongside it are written down
    first, unanswered.
  * No model is told anything: the call is still owed.
* Whatever is said next is the ❗, to whoever asked.
  * It takes the place of a 🙋 whenever a ledger ends in a ❓.
  * Whoever says it is who answered. A person, a script
    and another agent are all the same to m8.
* The call is then run again, from the start.
  * A tool is safe to repeat up to the point it asks.
  * The owed calls follow it, and then the model.
* A tool asks as many times as it needs.
  * Each run is handed every answer so far.
  * A tool and the shields it stands inside each ask their
    own, and each finds only what was said to it.
  * Questions are asked in the same order every run, which
    is what makes the second answer the second question's.
* Exit status 75 without a question, once answered, is the
  tool saying no.
  * Its result is written as any failure is.
  * Calls made alongside it lean on each other, so the ones
    still owed are not run. Each is closed with a 🚫 saying
    another was refused.
  * The conversation goes to the person, not the model, so
    a refusal is followed by what to do instead.

What the person answered is in the call's environment:

```
M8_EXCLAMATION_1          the tool's first answer
M8_EXCLAMATION_2          its second
M8_EXCLAMATION_1_ask      a shield's first
```

* The tool and every shield around it are handed the same
  ones.
  * None set is nothing answered yet.
  * They are made from the ledger every run, so the ledger
    is the only place an answer lives.
* An answer has to fit in an environment.
  * One too long for it is a call that fails to start.
* A run of `m8` starts with none.
  * It drops any it was handed, so an agent run by a tool
    never takes that tool's answers as its own.

```bash
[ -n "${M8_EXCLAMATION_1+x}" ] || { echo "QUESTION:tool: deploy to prod?" >&2; exit 75; }
```
