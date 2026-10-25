# Building

`zig build` makes one binary with every command in it. Everything below is a
choice about what goes where, and none of it changes the command line or the
stored data. [dev/SIZE_REPORT.md](../dev/SIZE_REPORT.md) reads the result.

## One launcher, and programs beside it

Composable is a claim about the command line, and it is
cheap to make while every command is one binary calling
itself. So any command can be built as a program of its
own, and the sizes of those are the guardrail rather than
the optimisation.

* `m8 NAME` runs a command the binary holds by calling it.
* One it does not hold is `m8-NAME` beside it.
  * m8 becomes that program rather than waiting on it.
  * It looks beside itself and nowhere else, so an m8
    installed anywhere reaches its own commands and not
    whichever are on a `PATH`.
  * A command the binary holds wins over a program of the
    same name.
* `m8 --help` lists both.
  * A program beside it is asked for its page, and the first
    line of that says what it is: `m8 NAME - SUMMARY`.
  * So a program of your own named `m8-NAME` is a command,
    listed with the rest.
* `-Dsplit` chooses which commands are programs, as below.

A command that reaches into another command's module still
compiles. Built on its own, it is a program suddenly
carrying a stack it has no business carrying.

* `zig build -Dsmall=true -Dsplit=all` builds every command
  apart, and the sizes in `zig-out/bin` are a reading of the
  architecture.
* Most sit within a few kilobytes of a hello-world against
  this std, and the ones that do not say why: the codecs
  are in the ones that speak to a model.
* In the default build the command that posts to a url is
  not among them, because the posting is curl's.
  `-Dno-curl-dep=true` deliberately puts the
  standard-library HTTP client in that command instead.

Nothing about the command line changes with what is built
where. Symlink `m8-tail` to a binary that holds `tail` and
it *is* `m8-tail`, the way busybox is: same output, same
status.

The url transport is another build-time choice:

```bash
# Small, stripped default: curl is required at runtime.
zig build -Dsmall=true

# Self-contained url provider: no curl executable is required.
zig build -Dsmall=true -Dno-curl-dep=true

# The choices apply to commands built apart too.
zig build -Dsmall=true -Dno-curl-dep=true -Dsplit=url-provider
```

Every artifact is compiled single-threaded. m8 composes concurrent work as
processes and uses none of Zig's in-process concurrency operations, so the
standard I/O implementation keeps its file, terminal, process, random and
network operations without carrying a worker-thread runtime. `small` selects
`ReleaseSmall` and explicitly omits debug symbols; on Darwin it also removes
the local symbols Mach-O retains after linking. Neither choice changes the
command line or stored data. `small` does narrow the wire formats and
builds the toy provider apart, as below.

`no-curl-dep` is comptime-selected in `url-provider`. The
unused transport is not linked, so the default does not carry
`std.http` and the self-contained build does not carry the curl
launcher. The latter is larger because TLS and certificate
validation have to live somewhere, but only the url command
pays for them when it is built apart.

The wire formats are a build-time choice too:

```bash
# Only the formats named, for `encode` and `parse` alike.
zig build -Dformats=anthropic-messages
zig build -Dformats=openai-completions,openai-responses
```

* With no `formats`, all of them are built in.
* `small` with no `formats` builds `openai-responses` alone.
  `-Dsmall=true -Dformats=...` says otherwise.
* `m8` is the language itself, so it is always there.
* A format left out is not compiled, and naming it at
  `m8 encode` or `m8 parse` says there is no such format.
* `m8 encode --help` lists what a build has.

Which commands the binary holds is one as well:

```bash
# `m8-toy-provider` beside `m8`, and out of it.
zig build -Dsplit=toy-provider
zig build -Dsplit=toy-provider,riff
zig build -Dsplit=all
```

* With no `split`, the binary holds every command.
* A command named is built as `m8-NAME` beside `m8`, and
  is not compiled into it.
  * Nothing is lost: `m8 NAME` reaches it there.
  * Leaving one out altogether is not installing its
    program.
* `small` with no `split` builds `toy-provider` apart.
  `-Dsmall=true -Dsplit=` says otherwise.
* The names are the files in `src/command`: one file is one
  command, and what it keeps to itself is in a folder
  beneath.

Two more name a small build with less in the binary:

```bash
zig build -Dminimal=true    # small, with munge and the shields apart
zig build -Dcore=true       # minimal, with riff apart
```

* Each only chooses what `small`, `formats` and `split`
  default to, so any of those can still be said.
* With `riff` nowhere, an address alone at a terminal says
  its one message the plain way.
* `zig build test` is of the sources: it is handed every
  command whatever is built apart.
