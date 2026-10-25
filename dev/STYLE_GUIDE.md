# Style guide

m8's code and docs keep the discipline the [mission](../README.md#the-mission)
asks of the harness: small, plain, and opinionated only about form.

## Code

* Keep detail where it happens.
  * Stream or write a thing in place when it has one use.
  * A helper earns its distance by naming a real boundary, not by saving a few
    nearby lines or making a unit test easy.
  * A one-use helper is suspect until it removes a real conceptual boundary.
* Tests may hold complexity; they do not push it into the program.
  * When testing simple code needs awkward setup, the setup lives in the test.
  * Everything is testable offline: `toy` answers locally.
* Stream rather than gather.
  * Hold one record, not the document; what a command is handed may not fit
    in memory.
* The framework holds no opinion.
  * A command reports what happened and leaves what ought to happen to the
    agent definition.
  * What a command may not do is a shield around it, not a condition inside it.
* Concurrency is processes.
  * Every artifact is single-threaded, and none of Zig's in-process
    concurrency is used.
* Nothing is a dependency that is not the toolchain.
  * `build.zig.zon` declares none, and nothing is vendored or fetched.

## Size is the guardrail

* `zig build -Dsmall=true -Dsplit=all` builds every command apart, and the sizes
  are a reading of the architecture.
* A command reaching into another command's module still compiles, and shows up
  as weight it has no business carrying.
* A command that does not sit near a hello-world says why.
* [SIZE_REPORT.md](SIZE_REPORT.md) is the current reading.

## Comments

* A file opens with a `//!` doc saying what it is for and why it is shaped that
  way.
* Comments narrate intent, never logic retold as pseudo-code.
* Present tense: git carries history, so no "now", "used to" or "unchanged".
* No thought journalling: a comment states the design, not the debate that
  reached it.

## Docs

* The doctrine is
  [fuglaro/agents documentation.md](https://raw.githubusercontent.com/fuglaro/agents/refs/heads/main/documentation.md).
  * Docs are done: updated before work is called finished.
  * Now is now: present tense, with history left to git.
  * Structures are clean: bullets and newlines over walls, and no numbered
    lists.
  * Intent is narrated: the rationale, in a sentence where possible.
  * Detail is localised under hierarchical summary.
* The README is a navigable index, not the reference.
  * Detail lives in [docs/](../docs), or beside the code it describes.
  * A `--help` page is the one place a command's options are spelled out.
* One short point per line, nested under an anchor.
  * A bullet holding a paragraph is still a wall.
* m8 examples are written in both spellings.
  * A fenced `m8` block as a terminal shows it, then the same records as a
    markdown quote as a file holds them.
* Link across docs with relative paths, never "see above".

## Working notes

* [IDEAS.md](IDEAS.md) holds what may come next.
* [CONFIRM_LATER.md](CONFIRM_LATER.md) holds guesses that were not pivotal,
  for confirming or adjusting later.
