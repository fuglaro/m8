# Shields

A shield is not a program that decides to restrict a
tool. It is the process the tool runs inside, so it
holds exactly the tool's authority and there is no
operation available to it for restoring a capability
its own parent lacked. Widening is not declined here;
it is unsayable. That is the same argument a provider
rests on, one level further down.

Everything follows from it. Restriction is
intersection, so the permitted set is the same however
the wrappers stack and a repeat means nothing. A name
runs one command, so a second definition of it is an
error once it is activated: a mob you have not read
cannot replace what it was given, and nothing runs.

```bash
__secures__="private airgap" m8 secure-shield secure bash -c "ls"
```

## Defining and activating

With a block it defines; with a value alone it
activates.

```m8
▐ 🛡️:deny
│ `false`

▐ 🛡️:deny                   now it is on
```

> * :shield::deny
>   > `false`
>
> * :shield::deny                   now it is on

A definition body holds a command spelled out in
backticks, a fenced block in some language, or another
🛡 to stand inside. Shields to stand inside may repeat,
and all of them stack around the one command.

```m8
▐ 🏃:bash
│ `m8` `call` `bash` `-e` `-c`

▐ 🏃:bash raw
│ `bash` `-e` `-c`

▐ 🛡️:passthrough
│ ```bash raw
│ exec "$@"
│ ```
```

> * :runner::bash
>   > `m8` `call` `bash` `-e` `-c`
>
> * :runner::bash raw
>   > `bash` `-e` `-c`
>
> * :shield::passthrough
>   > ```bash raw
>   > exec "$@"
>   > ```

A 🏃 is what makes a block runnable: an argv the code is
appended to, the way a shebang's interpreter is handed its
script. Whatever follows comes after the code, so for
`bash -c` the code is the script and `$0` is the next
argument, a shield's name.

A language that wants something after its code goes
through `sh`, which puts the code wherever it is needed:

```m8
▐ 🏃:foo
│ `sh` `-c` `exec foo "$0" --after-code "$@"`
```

> * :runner::foo
>   > `sh` `-c` `exec foo "$0" --after-code "$@"`

* It must be defined before a block names it, so a
  document reads in one pass.
* Defining one twice is an error rather than a question.
* Its name is the whole of a fence's info string, so
  ` ```bash raw ` names `bash raw` while a renderer still
  highlights bash.
* m8 ships none. What `bash` means is the agent's own:
  above, a tool's block answers through `m8 call`, and a
  shield's stays a transparent wrapper.

Every wrapper is handed the name it stands as and then
the command it wraps, as arguments. A wrapper whose first word is `m8` *is* an m8
command, and that word becomes this m8's path. `🛡️ask` is
`` `m8` `ask-shield` `` and nothing else.
A tool's own command is read the same way, as is the program
named by `m8 call`, so `` `m8` `call` `m8` `munge` … ``
reaches this build at both executable positions.

When launching providers and calls, m8 adds its absolute
launcher path as `M8`. Opaque program text stays opaque: a
shell script
that needs the current build runs `"$M8"`, and m8 does not
rewrite its source.

What a call said arrives in the environment, never in these
words, so no value a model wrote is read for a command.

The name is the shield's own, made safe for a folder.

* It is the shield whose command runs: `sandbox` stands
  as the shields it is made of.
* It is who a wrapper asks the person as, and what its
  answers are named for. See [Asking the Person](tools.md#asking-the-person).
* A name runs one command, so two of a kind are two
  names, such as `ask1` and `ask2`. A second command under
  one name is an error rather than a second wrapper.

A shield takes nothing else as words. What it was
activated with arrives in its environment, as a tool's
call does, so nothing in a shield's command is expanded.

`bash -c` binds `$0` to the first argument after the
script, which is the name, so a shell shield runs its
command as `"$@"`. A shield author is trusted, exactly
as a tool author is.

## Activation order

Activation order is wrapping order, and the first is
furthest out. It decides nothing about what is
permitted — intersection does not care — and everything
about what a person is shown, which is why `ask` is
worth activating last: innermost, it asks about the
bare command rather than about a stack of prefixes.

A shield stands once, however many times it is activated.

* It stands where it was first activated.
* Each later activation adds its values to what the shield
  is told, and nothing else.
* So `jail` is one `secure`, told every restriction, and a
  tool's own `airgap` joins that one's list.

## Where a shield is written

```m8
▐ 🛡️:jail                   the floor for this agent

▐ 🧰:deploy
│ 🛡️airgap                 and this tool as well
```

> * :shield::jail                   the floor for this agent
>
> * :toolbox::deploy
>   > :shield:airgap                 and this tool as well

* **Top level**, in an agent. Cumulative over the
  lineage, and inclusion can only tighten.
* **In a 🧰**, for one tool, on top of the floor.

There is no third place and no flag. A shield is written
down where it applies, so what a run may not do is a
fact about the agent rather than about how it was
invoked.

## A shields file

m8 defines no shield. A name means what an agent, or
something it includes, says it means.

* `mobs/demo/shields.md` is an ordinary document holding
  definitions and activating none of them.
* An agent that wants them includes it with `🧠demo/shields`.
* A name nothing defines is refused, so a tool under one
  does not run.

What `jail` means there is a composition you can read:

```m8
▐ 🛡️:sandbox
│ 🛡️freeze-toolbox
│ 🛡️private
│ 🛡️contain-writes
│ 🛡️no-loop
│ 🛡️no-edit-git
│ 🛡️no-edit-m8-st8
│ 🛡️contain-env
│ 🛡️contain-home

▐ 🛡️:jail
│ 🛡️sandbox
│ 🛡️airgap
```

> * :shield::sandbox
>   > :shield:freeze-toolbox
>   > :shield:private
>   > :shield:contain-writes
>   > :shield:no-loop
>   > :shield:no-edit-git
>   > :shield:no-edit-m8-st8
>   > :shield:contain-env
>   > :shield:contain-home
>
> * :shield::jail
>   > :shield:sandbox
>   > :shield:airgap

Each of those atoms is `secure` with one more value
appended to its variable, and `m8 secure-shield` turns
that variable into lines removed from the sandbox
profile:

```
contain-reads        no reading outside cwd, TMP, system and tool dirs
contain-reads-home   as above, with HOME readable too
private              as contain-reads, and tool dirs go too
contain-writes       writes confined to cwd and TMP
contain-writes-home  writes confined to cwd, TMP and HOME
only-tmp-writes      writes confined to TMP
no-writes            no filesystem writes, including TMP
airgap               no internet; loopback and unix sockets stay
no-loop               no loopback or unix sockets; internet stays
no-edit-git           no writing to the nearest .git entry from cwd upward
no-edit-m8-st8        no writing to a config directory anywhere
```

Those are atoms and the profile knows nothing else. Each
one only takes permissions away, so combinations silently
take the most restrictive form: `contain-writes` together
with `contain-writes-home` is `contain-writes`; `only-tmp-writes`
with either containment flag still allows writes only to TMP, and
`no-writes` wins over every other write flag (including
`only-tmp-writes`). A level is
a composition in the language, where it can be read,
overridden or taken apart — and a value `secure` does not
recognise is refused rather than ignored, so not
understanding what was asked for is never a reason to
apply less than was asked for.

`contain-home` and `contain-env` are not atoms. Each is a
wrapper that changes the environment before the tool starts:

```m8
▐ 🛡️:contain-home
│ `bash` `-c` `HOME=$TMPDIR exec "$@"`

▐ 🛡️:contain-env
│ `bash` `-c` `for v in $(compgen -e); do case $v in __*|M8|M8_*|TMPDIR|PATH|HOME|LANG|LC_*) ;; *) unset "$v";; esac; done; exec "$@"`
```

> * :shield::contain-home
>   > `bash` `-c` `HOME=$TMPDIR exec "$@"`
>
> * :shield::contain-env
>   > `bash` `-c` `for v in $(compgen -e); do case $v in __*|M8|M8_*|TMPDIR|PATH|HOME|LANG|LC_*) ;; *) unset "$v";; esac; done; exec "$@"`

* `contain-home` points `HOME` at the mob's scratch.
* `contain-env` drops every variable its body does not name.
  * The names are written in the body rather than passed as
    values, because values add up across activations and a
    list that could grow would be a way to widen.
  * A second definition is a second filter, so stacking
    still only tightens.
  * `__*` and `M8_*` are what a call said and what the person
    answered, so a definition keeps them.

`freeze-toolbox` is written in the language too, and
shows what the mechanism buys. A tool may hand back 🧰
records — that is how a toolmaker works — and closing
that channel is a pipe rather than a rule:

```m8
▐ 🛡️:freeze-toolbox
│ `bash` `-euo` `pipefail` `-c` `"$@" | "$M8" exclude --sigil toolbox --sigil brain --sigil books`
```

> * :shield::freeze-toolbox
>   > `bash` `-euo` `pipefail` `-c` `"$@" | "$M8" exclude --sigil toolbox --sigil brain --sigil books`

`m8 exclude` takes out every record of the kinds it is
told. Both forms of 🧰 go with the one name, which is the
point of their sharing a sigil: there is no spelling of
"define but do not offer" for a reply to reach for.
Including an agent or a skill *is* a way to acquire a
toolbox, so 🧠 and 📚 are named alongside 🧰 rather
than being resolved to see what they happen to carry. What
is not m8 at all is handed through untouched: most of
what a tool says is text, and text has no records in it
to take out.

## The two that could not be written in the shell

Most shields are programs you already have, which is
why `deny` is `/usr/bin/false` and a filter is a pipe.
Two need m8 itself:

```bash
m8 secure-shield NAME CMD   the profile, from __secures__
m8 ask-shield NAME CMD      the person
```

`ask-shield` puts the command to the person as a ❓, the way any
tool asks. See [Asking the Person](tools.md#asking-the-person).

* `y` or `yes` runs it.
* Anything else does not, and the person is asked what to
  do instead.
* It needs no terminal, so it asks the same under a pipe,
  a riff or anything else that can answer the conversation.

Putting a command to another agent is a shield written in
the language: a block that pipes `m8 ref` into `m8 send`
and runs the command when the reply is `allow`.

* It runs inside every shield already standing, so it is
  never more capable than what invoked it.
* A checker reads text an attacker may have shaped, so it
  belongs beside `ask` rather than instead of it.

## Two agents

One that cannot widen, whatever it includes or is asked
to do:

```m8
▐ 🧠:demo/shields

▐ 🛡️:jail

▐ 🧠:demo/helpers

▐ 🧠:/local/Ternary-Bonsai-8B-mlx-2bit,max_output_tokens:8192
```

> * :brain::demo/shields
>
> * :shield::jail
>
> * :brain::demo/helpers
>
> * :brain::/local/Ternary-Bonsai-8B-mlx-2bit,max_output_tokens:8192

`demo/helpers` may define whatever tools and shields it
likes, and whatever model: the one named last is the one
that answers. They all run jailed, because activating adds and
defining stacks, and neither can subtract. Nothing this
agent is told can add a tool, because a reply is never
read for definitions and `jail` composes
`freeze-toolbox`, which closes the tool response
channel too.

One that builds its own:

```m8
▐ 🧠:/local/Ternary-Bonsai-27B-mlx-2bit

▐ 🧰:toolmaker
│ │ Write a new tool and return its definition.
│
│ `make-tool`
│ * spec string
│   What the tool should do

▐ 🧰:toolmaker
```

> * :brain::/local/Ternary-Bonsai-27B-mlx-2bit
>
> * :toolbox::toolmaker
>   > > Write a new tool and return its definition.
>   >
>   > `make-tool`
>   > * spec string
>   >   What the tool should do
>
> * :toolbox::toolmaker

No 🛡 at all, so `toolmaker` may hand back 🧰 records
— a definition, and the blockless one that offers it —
and they are honoured. `make-tool` writes m8 itself,
verdict included, reading `__spec__`. The two live happily in one
config, and neither can become the other.

## Thinking it through

* Decide the floor first. A 🛡 at the top of an agent
  is the only thing that cannot be argued with later.
* Prefer a level to a list. `sandbox` and `jail` say
  what they mean and pick up whatever is added to their
  composition; a hand-written list does not.
* Kernel restrictions survive anything a tool spawns.
  If something has to hold three processes deep, it
  needs to be one of those rather than a wrapper the
  tool could simply not call.
* A definition included within your mob can define tools and shields.
  Your floor is what makes that inclusion safe. Cross-mob document
  references are not permitted; copy shared definitions into the mob.
* `no-edit-m8-st8` protects the user's config and applicable registered config
  directories from tool writes. Unregistered configs are not trusted
  or included in the sandbox's config protection set.
* Config files can define what runs, what a shield means, and which command a
  provider is; register only config directories you trust.
* Running m8 in a directory uses only `.m8-st8` directories that have
  been explicitly registered with `m8 register`.
  * It arrives with a `git clone` like anything else, but does not become trusted
    merely by being present.
  * Registration is not a human-only gate; an agent with command permissions
    may run it.
  * Read a config directory before registering it.
