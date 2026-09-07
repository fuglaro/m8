# HANDOVER

The toolbox grammar landed — see CONFIRM_LATER.md, round four. This is
what is left.

`zig build test` is 202 green and the tree runs. Nothing is committed.

## Next

**The README readapt.** I have kept it honest rather than rewritten it.
Locks became Shields, 🔝 and `^` are documented, the 🧰 example and
`## Types` and `## Command Templates` are the new grammar, and 🔌 and 🎁
are gone from the sigil table. But it is still a document that grew by
accretion, and you said it wants a proper go over.

**Two things I would look at while you are in there.** `## Command
Templates` is now a section about one of two command forms, and it is
longer than the form deserves. And `### Four formats were always one`
predates shields, so the argument it makes is now stronger than the way
it is put.

## Small, known, and deliberate

* **`m8 shield ask` is untested against a real terminal.** The profile
  allows `/dev/tty` under `jail` — verified by reading `mac-sandbox.sb`,
  and the block carries no tags so nothing removes it — but this session
  has no tty, so the round trip is unproven. One minute with a terminal.
* **`freeze-toolbox` names four sigils.** If a sigil is ever added that
  can carry a definition, that composition needs it too. There is no test
  that would catch the omission.
* **An old tool file degrades quietly rather than erroring.** See
  CONFIRM_LATER, round five — the fix is one rule in `toolbox.parse` if
  you want it.
* **A tool's `,m8` and its env-var extension share a header.** `,` splits
  the format and space splits the variable, so `:toolbox:make,m8 SECURES
  airgap` has to keep reading cleanly. The comma half has a test; both
  together do not.
