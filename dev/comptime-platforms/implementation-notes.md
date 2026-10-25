# Storage step: implementation notes

This implements the agreed storage/resolution change only. Execution-platform interfaces and test relocation remain out of scope. The other survey files record the pre-migration architecture.

## Implemented contract

- `core/providers/NAME.json` is one complete provider object. The filename supplies the name; same-name files shadow rather than merge.
- Discovery selects at most the nearest project `.m8-st8`, plus user and system roots. Project registration remains required. An unregistered nearest project does not expose ancestor project configuration.
- Core resources resolve per file, including `config.json`; absent keys do not fall through.
- Definitions are `mobs/MOB/AGENT.md`. Mobs are one level; authored agents may nest, but no agent path component may begin with `.` or `_`. Logical `//` introduces a subchat and maps to the reserved `/_/` boundary in generated state.
- The first `mobs/MOB/` directory owns the whole mob, even when empty. Missing files never fall through to another layer.
- `config.Dirs` explicitly carries roots, source-layer identity, data home, and optional pinned mob scope. Ledger expansion pins its mob/layer and rejects cross-mob references, including skills and generated lineage. Writes and pointer following validate their scope too.
- A new command invocation can activate another mob independently; mob scope is not inherited as a global execution restriction.
- Project state lives in `mobs/MOB/.chats/`; persistent workspace is sibling `.mob-space/`. User/system state lives in `$XDG_DATA_HOME/m8-st8/{user,system}/mobs/MOB/`, defaulting to `~/.local/share/m8-st8/`.
- Explicit addresses use `:MOB/AGENT`. Agent/subchat tagging, side questions, reset, fresh starts, following, immutable turns, snips, and incremental keeping remain. Global/main chat selection and `@` addresses are removed; bare `m8` shows help.
- Stateless model references remain available. Stored model-directed conversations retain their explicit mob owner even when their lineage no longer reaches an authored definition; they never fall back to global storage.

## Process-context detail

`M8_ST8_DIRS` is accompanied by `M8_ST8_USER_ROOT` and `M8_ST8_DATA_ROOT`. These serialize the validated context across native process boundaries, without pinning a child to the parent's mob. They preserve source-layer/state identity when a shield narrows HOME or XDG variables. Child environment overlays cannot replace them. Unsetting `M8_ST8_DIRS` requests fresh discovery, ignoring the accompanying metadata.

## Repository migration

- Moved tracked definitions from `@/` to `mobs/` and split provider configuration.
- Moved formerly top-level model aliases into `crew/`; copied shared shield definitions into that consuming mob and rewired its references.
- Updated the image tool to write `$M8_MOB_DIR/.uploads/`.
- Updated generated-state ignores, command help and current README/docs examples.
- Copied this checkout's existing crew histories/uploads and persistent workspace into the new locations. Originals under the ignored legacy `+/` are left untouched as a local backup and because this running session still has old paths in its environment. They are not searched by the new implementation. Old unscoped experimental chats were not guessed into new mobs.

No automatic migration of arbitrary user/system configuration outside this repository, and no legacy-layout lookup fallback, is included.

## Verification

- `zig build test`: 375 passed, 7 skipped (382 total).
- `zig build`: passed.
- Native CLI smoke through the toy provider: explicit project chat, subchat/reset, relocated user chat/workspace, mob shadowing, cross-mob refusal, no default/main chat: passed.
- All-split command build and the same native smoke checks: passed.
- Small build: passed.
- Repeat the native checks with `bash plans/comptime-platforms/storage-smoke.sh`; `M8_BIN` optionally selects another built launcher. The fixtures stay under ignored `scratch/storage-smoke/`.
