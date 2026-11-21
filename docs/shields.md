# Shields

A shield is a command prefix: a wrapper that runs a tool, restricts it,
asks permission, or refuses to run it at all.

The simplest way to read one is to look at the command it builds:

```text
m8 ask-shield ask <tool executable> <tool arguments...>
│             │   └─ command to wrap
│             └─ names argument, added by the harness
└─ command from the shield definition
```

The wrapper consumes **one names argument**, then runs—or refuses to run—the
remaining command. What the names mean is up to the wrapper: `ask-shield` uses
a name to identify its question; `secure-shield` treats them as restrictions.

The harness arranges the wrappers. The wrappers do the work.

## Define it, then activate it

A shield record with a body defines a wrapper. The same record without a body
activates it:

```markdown
* :shield::ask
  > `m8` `ask-shield`

* :shield::ask
```

This runs tools as:

```sh
m8 ask-shield ask <tool command...>
```

When a tool is called, the harness follows this path:

```text
definition                 activation                 execution
what command to use   →    which wrapper to use   →   prefix + names + tool
```

Definitions alone do nothing. You can keep them in a shared document and include
that document without turning any shields on. An activation of an unknown shield
fails rather than running the tool unwrapped.

A top-level activation applies to toolboxes whose command definitions follow it
in ledger order. It does not reach backward to earlier toolboxes, and merely
offering a previously defined tool later does not bring it into scope. An
activation inside a tool adds a wrapper for that tool:

```markdown
* :shield::secure
  > `m8` `secure-shield`

* :shield::secure contain-writes

* :toolbox::inspect
  > > Inspect the project.
  >
  > :shield:secure contain-reads no-writes
  > `m8` `call` `inspect-project`
```

Top-level activations in scope at the tool's command definition are resolved
first, then the tool's own. A tool cannot remove a shield that is in scope for
it.

In stream spelling, the equivalent definition and activation are:

```m8
▐ 🛡️:secure
│ `m8` `secure-shield`

▐ 🛡️:secure contain-writes
```

## Names accumulate; wrappers run once

A bare activation uses the shield's identity as its names argument. Explicit
names replace that default; later activations append to them:

```markdown
* :shield::secure contain-writes

* :shield::secure airgap no-loop
```

Both activations contribute to the same wrapper:

```text
secure contain-writes ───┐
                         ├─→ "contain-writes airgap no-loop"
secure airgap no-loop ───┘               │
                                         ▼
                          one secure-shield invocation
```

The resulting command is:

```sh
m8 secure-shield "contain-writes airgap no-loop" <tool command...>
```

The quotes matter: that list is one argument. Names are space-separated words,
collected in activation order. A later bare activation adds nothing and does not
reset the list. Explicit names are passed literally, so `check crew/reviewer`
can name an agent with a path. Without explicit names, the default identity is
made safe for use in question IDs.

Names select how an already-defined wrapper behaves; they do not select a new
executable. The command in the definition stays unchanged, and model-supplied
tool arguments still arrive through the tool's environment.

## Compose wrappers

A shield definition can contain **up to one command and any number of other
shield activations**. It can be a wrapper, a composition, or both.

This one just groups other shields:

```markdown
* :shield::workbench
  > :shield:secure contain-writes-soft no-loop no-edit-git
  > :shield:contain-env
  > :shield:contain-home

* :shield::sandbox
  > :shield:workbench
  > :shield:secure private no-edit-m8-st8
  > :shield:freeze-toolbox

* :shield::jail
  > :shield:sandbox
  > :shield:secure airgap contain-writes
```

Activating `workbench` uses the softer write boundary: cwd and scratch (TMP) are
writable; on macOS it also permits `/private/tmp` and native
`DARWIN_USER_TEMP_DIR`, while Linux maps scratch over `/tmp` for runtimes that
ignore `TMPDIR`. `sandbox` inherits that write boundary and additionally
restricts reads and protects configuration.
Activating `jail` expands `sandbox` and adds `airgap` and strict
`contain-writes` to the same `secure` invocation. There is no need to define an
alias for every restriction. Names belong to the shield they follow: names
supplied to a composition are not automatically forwarded to its children.

The first wrapper encountered is outermost. With `secure` followed by `ask`,
the command looks like this:

```text
m8 secure-shield "private airgap" m8 ask-shield ask <tool command...>
└─────────── secure ────────────┘ └──── ask ──────┘ └──── tool ─────┘
```

Read it from the outside in:

```text
secure   applies the sandbox, then runs…
  ask    asks permission, then runs…
    tool does the actual work
```

These are not three commands the harness runs independently. It launches the
outer wrapper, which runs the rest. Put `ask` last if you want it to show the
bare tool command rather than the wrappers around it.

Each shield keeps its first position, even when later activations contribute
more names. A definition may mix a command and references to other shields,
but each shield identity may contribute at most one command. Defining a second
command under that identity is an error, not a replacement. Circular compositions
are errors too.

## Write a shell wrapper

For `bash -c`, the names argument becomes `$0`, and the wrapped command is
`"$@"`:

```markdown
* :shield::contain-home
  > `bash` `-c` `HOME=$TMPDIR exec "$@"`
```

The harness constructs:

```text
bash -c 'HOME=$TMPDIR exec "$@"' contain-home <tool command...>
                                 └─── $0 ───┘ └──── "$@" ─────┘
```

`$0` is the wrapper's names argument, not the tool executable. `"$@"` is the
command to forward, with its argument boundaries intact.

The harness does not insert `exec "$@"` for you. A script that never forwards
the command never runs the tool. `false` is therefore a complete deny shield:

```markdown
* :shield::deny
  > `false`
```

For longer scripts, define a runner before using its name in a fence:

````markdown
* :runner::bash wrapper
  > `bash` `-e` `-c`

* :shield::passthrough
  > ```bash wrapper
  > exec "$@"
  > ```
````

The runner's argv is followed by the script text, then the names argument and
wrapped command. The whole fence info string (`bash wrapper` here) identifies
the runner. Unknown runners and duplicate runner definitions are errors.
Unlike a tool runner, a wrapper runner normally does not use `m8 call`: it
forwards the wrapped tool's output rather than turning it into another receipt.

A command beginning with `m8` resolves to the running m8 executable. Inside
scripts, use `"$M8"` to reach that same executable; script text is not rewritten.

## Sandbox restrictions

`secure-shield` combines all supplied names into **one sandbox invocation**.
On macOS it uses `sandbox-exec`; separate sandbox profiles cannot be nested.
On Linux it uses Bubblewrap (`bwrap`, installed separately) and requires working
unprivileged user namespaces. Missing backends, unsupported platforms and
unsupported restrictions fail rather than run without protection.

### Linux (Bubblewrap)

The Linux backend supports filesystem read and write restrictions:

* `contain-reads`: expose cwd, scratch (TMP), system runtime paths and tool
  directories; other host paths are absent from the sandbox.
* `contain-reads-home`: additionally expose HOME.
* `private`: as `contain-reads`, without tool directories or the extra HOME
  allowance. Combining it with a home-aware policy still takes the stricter
  result.
* `contain-writes` and `contain-writes-soft`: writable cwd and scratch (TMP).
  When scratch is writable, Bubblewrap binds it over `/tmp`; the host `/tmp` is
  never exposed by that compatibility alias. Linux has no Darwin temp allowance,
  so these two policies are equivalent.
* `contain-writes-home`: writable cwd, TMP and HOME.
* `only-tmp-writes`: writable TMP only.
* `no-writes`: no writable filesystem trees.
* `no-edit-git`: the nearest `.git` entry is mounted read-only.

Write policies intersect: `contain-writes` removes the extra HOME allowance,
`only-tmp-writes` removes cwd/HOME, and `no-writes` removes every allowance.
Paths are canonicalized before mounting. Writable grants inside a protected
`.git` tree are rejected. Write grants never widen the read allowlist: for
example, `private contain-writes-home` does not expose HOME unless it is
already covered by cwd or TMP.

Read containment starts with an empty root, mounting only allowed paths. System
paths include `/usr/bin`, `/usr/sbin`, `/usr/lib`, `/usr/lib64`, `/usr/share`,
their `/bin`, `/sbin`, `/lib`, `/lib64` aliases, and selected runtime files under
`/etc` (hosts, resolver, NSS, linker cache, timezone, passwd, group, and SSL).
Tool paths are `/usr/local/bin`, `/usr/local/lib`, `/usr/local/opt`, plus
`~/.local/bin`, `~/.cargo/bin` and `~/go/bin`. Missing paths grant nothing.
Custom runtimes outside those paths must be inside cwd/TMP or use an appropriate
HOME allowance. Symlinks do not grant access to targets outside the allowlist.

Unlike macOS's separate read/write rules, Linux bind mounts cannot provide
write-only access to hidden host trees. Consequently, read containment also
limits where host filesystem writes are possible. Without a write restriction,
exposed mounts remain writable subject to ordinary Unix permissions. The
synthetic root itself is read-only. Host paths outside the allowlist are hidden,
including their metadata; this differs from macOS's unrestricted stat access.

```sh
m8 secure-shield "private contain-writes no-edit-git" bash -c 'ls'
```

`no-edit-m8-st8`, `airgap` and `no-loop` are **not supported on Linux** yet.
Bubblewrap's network namespace switch alone cannot preserve either split
internet/loopback policy, so these names are rejected, not approximated.
Consequently the example `workbench`, `sandbox` and `jail` compositions above
are not portable unchanged. Filesystem restrictions do not scrub environment
variables or impose network policy. Read containment hides filesystem socket
paths outside the allowlist, but does not isolate the network or abstract Unix
sockets. Standard input/output and deliberately inherited file descriptors are
not made private by hiding their original filesystem paths.

#### Testing on Linux

Run the end-to-end tests with a built Linux binary and installed `bwrap`:

```sh
dev/test-linux-shield.sh /absolute/path/to/m8
```

The tests create and remove native-filesystem fixtures; unavailable Bubblewrap
or namespaces fail the test rather than silently skip it. To test from an
Apple Silicon Mac using Lima:

```sh
brew install lima
limactl start --name=m8-bwrap-test --vm-type=vz --cpus=2 --memory=2 \
  --disk=12 --mount-none --containerd=none --tty=false template:ubuntu
limactl shell m8-bwrap-test -- sudo apt-get update
limactl shell m8-bwrap-test -- sudo apt-get install -y bubblewrap
zig build -Dtarget=aarch64-linux-musl -p zig-out/linux-bwrap
limactl copy zig-out/linux-bwrap/bin/m8 m8-bwrap-test:/tmp/m8
limactl copy dev/test-linux-shield.sh m8-bwrap-test:/tmp/test-linux-shield.sh
limactl shell m8-bwrap-test -- sh /tmp/test-linux-shield.sh /tmp/m8
limactl stop m8-bwrap-test
```

Use an architecture matching your VM. For subsequent runs, start the existing
VM with `limactl start m8-bwrap-test`, then rebuild, copy and run the tests.
The VM needs no shared host directories or privileged container configuration.

### macOS (sandbox-exec)

On macOS, `contain-writes-soft` also permits `/private/tmp` (the target of
`/tmp`) for runtimes that hard-code `/tmp`, as well as the native temp directory
resolved from `getconf DARWIN_USER_TEMP_DIR`. Apple's developer-tool launchers
use that shared cache independently of `TMPDIR`. Lookup failure grants no extra
access.

Strict `contain-writes` keeps writes limited to cwd and scratch (TMP), even
when combined with `contain-writes-soft`. Under strict containment, xcrun may
emit cache-write complaints while still exiting successfully; no cache-control
environment variable is injected.

| Name | Restriction |
|---|---|
| `contain-reads` | Read only cwd, TMP, system and tool directories |
| `contain-reads-home` | As above, with HOME readable too |
| `private` | As `contain-reads`, without tool directories |
| `contain-writes` | Write only cwd and scratch (TMP) |
| `contain-writes-soft` | Write only cwd, scratch (TMP), `/private/tmp`, and native `DARWIN_USER_TEMP_DIR` |
| `contain-writes-home` | Write only cwd, TMP and HOME |
| `only-tmp-writes` | Write only the current tool's TMP |
| `no-writes` | No filesystem writes, including TMP |
| `airgap` | No internet; loopback and Unix sockets remain |
| `no-loop` | No loopback or Unix sockets; internet remains |
| `no-edit-git` | Protect the nearest `.git` entry at or above cwd |
| `no-edit-m8-st8` | Protect home and registered config directories |

Restrictions only remove permissions. Combining them takes the stricter result:
`no-writes` wins over every write-containment option. Unknown names are errors.
A bare `secure` activation has no valid restriction name; supply restrictions
explicitly.

Other wrappers handle things outside the sandbox profile. `contain-home`
changes HOME; `contain-env` removes environment variables; `freeze-toolbox`
filters tool output:

```markdown
* :shield::freeze-toolbox
  > `bash` `-euo` `pipefail` `-c` `"$@" | "$M8" cat --pack | { grep -vE '^- :(toolbox|brain|books)::' || test "$?" -eq 1; } | "$M8" cat`
```

That filter buffers whole records before matching: `cat --pack` parses the input
as m8 and puts each valid record on one physical line for `grep` to filter;
the final `cat` normalizes retained records to block spelling, including plain
sigils. It removes tool definitions and inclusion records that could bring in
more tools; ordinary text remains. The status check accepts grep's status 1
when there are no matching records, while preserving real grep errors.

## Ask a person or an agent

`ask-shield` asks the person before running the command. `y` or `yes` allows
execution; anything else refuses it and returns control to the person. It uses
the conversation's question/answer protocol, not a terminal prompt. See
[Asking the Person](tools.md#asking-the-person).

An agent check can be a shell wrapper too. Its one required agent name comes
from `$0`:

```markdown
* :shield::check
  > `bash` `-e` `-c` `said=$("$M8" query --no-advance ":$0" "$*"); [ "$(printf %s "$said" | tr A-Z a-z)" = allow ] || { echo "Failed agentic check: $said" >&2; exit 1; }; exec "$@"`
```

Activate it with `:shield:check crew/reviewer`. This wrapper expects exactly one
agent, not a list: the response must be `allow` (case-insensitive) before it
runs the command. Agent checks inspect potentially attacker-controlled text;
use them as an additional check, not a substitute for kernel restrictions or
human approval.

## The security boundary

The harness arranges wrappers; the wrapper programs enforce their promises.
A shell wrapper is not automatically a sandbox. Kernel restrictions apply to
children too, so spawning another program cannot escape them.

Definitions are executable configuration. Read a config directory before
registering it with `m8 register`; merely finding `.m8st8` in a checkout does
not make it trusted. Registration is not a human-only gate—an agent with command
permissions may run it. Cross-mob document references are not allowed; copy
shared definitions into the consuming mob.

Choose the agent's baseline restrictions first, then let individual tools add
their own. Compositions such as `sandbox` and `jail` keep that policy readable
without repeating the same list in every tool.
