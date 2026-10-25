# CONFIRM_LATER

Where you can land guesses which aren't pivotal for later confirmation or adjustment.


## README split (2026-10-25)

* The README is now an index: what it is, mission, getting started, a tour, a map.
  * The reference moved to `docs/` mostly verbatim, under the old headings.
  * why, building, commands, language, tools, shields, configs, providers.
* `docs/toolboxes.md` is gone, folded in.
  * Its header-form rules are bullets under Definition variables in `docs/tools.md`.
  * Its 🔗 `printf` example is under Handing Over Files in `docs/language.md`.
* Moves that could have gone elsewhere:
  * Uploading is in `docs/providers.md`, since `upload` is an entry key.
  * Models and Environment are in `docs/configs.md`, where they sat before.
* Entropy fixed in passing:
  * stats and provider stderr were each said twice in Providers; now once.
  * The `M8_PROVIDER_*` key rules became bullets.
  * The `{{…}}` placeholder bullets had drifted under Definition variables; back
    under Commands That Want Flags.
  * `parse` was introduced twice in Encoding.
  * "behavior is unchanged" dropped from Turns and chats.
* "Tools talk to the user on `/dev/tty`" became "through the ledger".
  * Riff says CMD has no terminal, and Asking the Person goes through the ledger.
* Getting started is verified: user-layer toy provider, `eliza`, from a clean
  `XDG_CONFIG_HOME`.
* Noticed, not changed:
  * Examples use `:demo/mathy`, `:demo/pagey` and `:demo/critic`, but the repo
    ships `crew`, `games` and `local`. The provider is `local-omlx`, not `local`.
  * `src/zmachine/README.md` still says `m8 ref @` and `@zork`.
  * `dev/SIZE_REPORT.md` says 537.7 KiB and `m8-providers*`; the tree has 517,040
    bytes and `m8-toy-provider`.
  * The docs bodies are still the old prose. `language.md` and `commands.md` most
    want a bullets pass.
