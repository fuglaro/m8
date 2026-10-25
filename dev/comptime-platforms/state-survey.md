# Configuration, state, and storage survey

Scope: selective source survey for planning; observations below describe the current implementation, not a proposed design.

## Observations

- **One ordered config-directory stack serves several roles.** `config.discover` (`src/config.zig:19-57`) returns nearest-first directories: project `.m8-st8` locations walking upward from the current working directory, then the user config (`XDG_CONFIG_HOME/m8-st8`, else `$HOME/.config/m8-st8`), then `/etc/m8-st8` if present. The Unix-style `:`-separated `M8_ST8_DIRS` overrides discovery; entries are filtered through registration checks except for child calls / user / system paths. Children are marked by `M8_CALL_ID` and inherit the validated directory list (`config.zig:19-57`; `converse.zig:105-124`).
- **Authored definitions and generated state are distinct trees under each root.** Logical names map to `@/<name>.md` for definitions and `+/<name>.md` for state (`config.zig:254-265`). Reads search the stack nearest-first (`config.zig:357-364`). State reads skip `/etc/m8-st8`; new writes select the nearest root, but do not write to the system root (`config.zig:60-68, 274-289`).
- **Provider configuration is separate from agent ledgers.** `core/` files are searched on the same config stack; singular core-file lookup chooses the nearest copy (`config.zig:78-107`). `providers.json` is merged across roots, nearest name wins, and m8 supplies no built-in entries (`config.zig:366-388`). Provider entries select command stages (`cmd`, optional `encode`, `parse`, `models`) and scalar values become `M8_PROVIDER_*` environment variables (`provider.zig:1-28, 73-119`). `converse.run` loads providers after expanding the request ledger, and resolves executable stages against core directories (`converse.zig:126-149`).
- **An agent definition is a document, not a separate serialized agent object.** Agent files can include other documents; `ledger.expand` walks names and records in order, preserving ledger lineage and deriving the first authored origin (`ledger.zig:1-23, 50-60`). `agent.load/project` projects that ledger into the active model/provider, parameters, tools, shields, and runners; last model/tool definitions and cumulative shields are noted in `agent.zig:1-60, 61-120`. The flattened ledger is request input; the provider codec/command boundary is where wire-specific representation enters (`provider.zig:1-23`).
- **Chat history is generated state, linked by names rather than copied transcripts.** `session.zig` describes `+/X/+/id.md` turns, `+/X/+.md` chat pointers, and `+/+.md` main pointer. A turn contains its own exchange and points to its parent; traversal in the ledger reconstructs the chain. Forks can share a parent. Pointer files move; turns are written as new records (`session.zig:1-28, 117-150`; `ledger.zig:1-23`). `keeping.Keeping` delegates each incremental piece and final turn to `address.tag` (`keeping.zig:1-43`); address logic chooses the chat/state location and movement semantics (`address.zig:235-354`).
- **Scratch is persistent per originating mob, not per run.** The origin from ledger expansion selects the definition root and mob path; `mobTmp` creates `+/mob/.tmpdir` and returns an absolute path (`config.zig:294-355`). Conversation setup exports it as `TMPDIR`, along with `M8_MOB_DIR` and `M8_MOB_ST8_DIR`, to provider and tool environments (`converse.zig:126-153`; tool setup also sets `TMPDIR`, `converse.zig:515-530`). It is intentionally not automatically cleaned (`config.zig:330-355`).
- **Filesystem and environment assumptions are visible in the implementation.** Paths use `/`, `/etc/m8-st8`, XDG/HOME conventions, and colon-separated path lists; current working directory is the starting point for project discovery. Project registration stores canonical paths in the user's private registry (`config.zig:31-57, 116-182`). Config files have a 4 MiB read bound (`config.zig:15`). Child processes receive inherited/augmented environments (`converse.zig:105-124, 147-153`; `provider.zig:132+`). Scratch and providers depend on subprocess/environment behavior; sandbox code derives its temporary base from `TMPDIR` or `/tmp` (`sandbox.zig:87`).

## Possible separable boundaries (discussion prompts, not recommendations)

- Config discovery/trust and precedence versus logical-name-to-file mapping and read/write policy (`config.zig`).
- Authored document/ledger semantics versus the request projection (`ledger.zig` → `agent.zig`) and provider transport/codec (`provider.zig`, `codec.zig`).
- Chat graph and durable persistence (`session.zig`, `address.zig`, `keeping.zig`) versus orchestration of a model/tool run (`converse.zig`).
- Persistent mob workspace/scratch policy versus generic child-process environment and sandbox setup (`config.zig`, `converse.zig`, `sandbox.zig`).

## Design questions for collaborative planning

- Are project, user, and system roots all intended to remain both configuration sources and (where permitted) state roots? Should precedence/trust be explicit per category rather than shared through `dirs`?
- Which platform/path abstractions are required beyond the current Unix-shaped environment and filesystem conventions? In particular, what should replace `:` path-list parsing and fixed system-root assumptions on other platforms?
- Is persistent mob scratch part of the user-visible state model, and should its lifecycle/cleanup or isolation differ between tools and providers? Which environment variables are contractual API versus implementation details?
- Should agent identity/origin, provider selection, and chat lineage remain derived from the same expanded document walk, or are there reasons to expose those as separate stable concepts?
- What consistency, concurrency, backup/migration, and portability expectations apply to pointer files and append-only turn files? How should malformed or partially written state be surfaced?
- Should provider configuration remain executable-command based and composable through `core/`, or does the platform survey imply a distinct provider discovery/configuration interface?

## Pointers

Primary files: `src/config.zig`, `src/provider.zig`, `src/agent.zig`, `src/ledger.zig`, `src/session.zig`, `src/address.zig`, `src/keeping.zig`, `src/converse.zig`, `src/sandbox.zig`.
