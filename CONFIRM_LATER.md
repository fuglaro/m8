# CONFIRM_LATER

Where you can land guesses which aren't pivotal for later confirmation or adjustment.


## riff Enter sends

* Ctrl-d still sends as well as Enter.
* Enter with nothing written does nothing.
* In a paste, backspace, ctrl-c and ctrl-d bytes are dropped rather than acted on.
* A key's sequence cut short by a read is held for the next one, up to 16 bytes.


## Command reshape: ref, tail, exclude, render, reset, query

Guesses made landing the list in IDEAS.md under BITTY ISSUES.

### What moves

* `m8 tag @turn` and `m8 tag @/model` keep the turn beside its parent and point nothing.
  * They pointed the main chat at it; only `@` and the prompt move the main chat now.
* `m8 query @` moves whatever `m8 tag @` moves.
  * Kept equal to its pipeline, so it is the one query that can move the main chat.
* `m8 query --new` and `--parent` only choose where the run reads from.
  * Advancing, the chat moves to the new turn; with `--no-advance` no pointer is written.
* `m8 reset --new` writes the agent's name into the chat's pointer.
* `m8 reset --to @turn` checks the turn is there; a chat or a model is taken as named.

### What is read

* `m8 ref` reads stdin whenever it is not a terminal, as `cat @x` did.
  * It waits on a stdin that is an open pipe nobody closes.
* `m8 query` reads no stdin: its message is its arguments.
  * Run by a tool, stdin is that tool's and not its to wait on.
* Words after the address are joined with one space, and stdin prose follows on a new line.
* A model address is not looked for; only a turn and an agent are.
* `m8 tag` refuses a lone 🧠 naming a turn that is not there.

### What is written

* `m8 query` answers only from what this run said.
  * Its pipeline spelling, `tail` over the expanded chat, can hand back an earlier reply.
* `m8 query -vv` writes the turn on stderr in markdown, and says no `-v` lines beside it.
* `m8 tail` reads the whole document rather than streaming it.
* `m8 tail --value` and `--block` end what they write with one newline.
* Every command writes markdown at a terminal: `call`, `parse`, `decode`, `encode`, `save` too.
  * `riff` is the only command still told what stdout is.

### Shields

* `filter-toolbox`, `filter-brain` and `filter-books` are gone from `core/shields.md`.
  * `freeze-toolbox` is one `m8 exclude` pipe naming all three.
  * A config of your own naming a `filter-*` shield no longer finds one; none of yours does.

### Left alone

* `m8 exclude` with nothing named still says so twice, as `filter` did.
* `zig-out/bin/m8-cat` and `m8-filter` are stale binaries from an earlier split build.
* IDEAS.md is untouched, including the list this came from.
