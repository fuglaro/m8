# Platform boundaries: first broad survey

This is a discussion map, not an agreed architecture or implementation plan. Selective source reading only; no tests or Wasm builds were run. Production code is unchanged.

The agreed storage step is now implemented; see [implementation notes](implementation-notes.md). This survey describes the original architecture before that step.

Supporting notes: [state/configuration](state-survey.md), [commands/execution](commands-survey.md), [Z-machine/browser](zmachine-survey.md).

## Main finding

There are already meaningful interfaces: m8 documents, `Command.run(Ctx)`, provider request/reply streams, tool definitions and call results, linked conversation turns, and the yielding Z-machine. The difficulty is that the implementations of those interfaces still obtain authority and resources through directories, environment variables, process inheritance and standard descriptors. The task is not necessarily to invent interfaces everywhere; it is to decide which existing contracts should become independent of their Unix representation.

## Things to consider together

| Area | Current shape | Architectural question |
| --- | --- | --- |
| Command entry | `api.Ctx` already supplies input bytes, output/error writers and optional interaction, but also `std.Io`, a process environment, executable identity and argv. Some commands read real stdin themselves. | Is the portable interface a command invocation, a domain operation, or both? Which parts of context are actual inputs versus native-host wiring? |
| Command composition | `at` and `query` orchestrate assembly/run/keeping directly. CLI filters expose the same concepts independently. Split builds reach sibling executables. Definitions can recursively invoke m8. | Separate logical invocation from whether it runs in-process, as a sibling executable, or as an external program? Preserve input ownership and re-entrant call context. |
| Configuration | Discovery, root precedence, registration/trust and lookup share `config.zig`; commands discover independently. Provider entries merge by name, ordinary files use nearest match. | What constitutes a resolved configuration context, and when is it established? Do not accidentally erase different merge rules. |
| Definitions | `@/` documents expand into a ledger; agent projection derives model, tools, runners and shields from records. | Which aspects are stable document semantics, and which are location-dependent resolution? |
| Durable chat state | `+/` holds linked immutable turns and moving chat/main pointers. Keeping can happen after each model/tool result. | Is persistence expressed as files, named documents, or chat-graph operations? Preserve publication ordering, lineage and interruption behavior. |
| Workspace | Origin selects persistent per-mob `+/mob/.tmpdir`; absolute paths are exported to children alongside mob definition/state paths. | Workspace is not simply disposable scratch. Who owns it, what may tools share, and how does it relate to chat/session identity? |
| Providers | An executable encode/cmd/parse pipeline with scalar config passed through `M8_PROVIDER_*`. HTTP transport can use curl or Zig HTTP; header values are shell commands. | Can a logical provider endpoint have process, in-memory, and browser implementations without requiring shell/Unix configuration for all of them? |
| Tools/runners | Tool schema and call arguments are distinct from argv or script-block implementation. Arguments reach children through environment variables/JSON. | Which portable call contract remains after removing subprocess mechanics? What happens to a definition requiring an unavailable runner? |
| Shields/trust | Wrappers implement asking, refusal and confinement; restrictions rely on nested processes inheriting limited authority. Native confinement is macOS-specific. | Alternate dispatch must not bypass restrictions merely because it avoids spawning. Unsupported enforcement must be explicit, not silently ignored. |
| Interaction | Document output, diagnostics and human interaction are already separate. Questions use exit 75 plus `QUESTION:` stderr and answer env vars. | Can questions be represented as suspension/resumption, with the CLI protocol as one adapter? |
| Scheduling/lifecycle | Provider/tool streaming, signals, cancellation, process cleanup, watch polling and riff terminal/session control have distinct host dependencies. | Replacing files/spawn alone will not give a browser-compatible event loop. What can yield, and who drives it? |
| Z-machine | Core accepts bytes/seed/input and yields at input or quit; `play` rebuilds/replays from input history. Files/config live in adapters. | Browser engine demo versus browser m8 conversation are different scopes. Live machine versus deterministic replay is also a separate decision. |

## Comptime versus runtime: keep the axes separate

- **Build-time capability/implementation choices:** native/browser/test host, command inclusion, protocol codecs, process/HTTP/terminal adapters. Existing split-command and HTTP build options provide precedents.
- **Runtime configuration:** provider selection, trusted sources, definitions, credentials, current project/workspace.
- **Runtime session state:** chat pointers, call identity, pending question, cancellation, VM state/input history.

A comptime-selected implementation can still have multiple independent runtime instances. A test should not need a different architecture from production merely to supply controlled state. Whether the mechanism is generic types, injected interfaces, a host API, or a combination remains open.

## Testing direction to evaluate

- Exercise public command/domain interfaces using controlled definitions, storage and provider/tool responses; assert document output, state changes and emitted interaction.
- Use the same behavioral scenarios against native and alternate implementations where their supported capabilities overlap.
- Retain a smaller native integration suite for real pipes, executable resolution, signals, confinement and filesystem publication. In-memory tests cannot prove those adapters correct.
- Avoid tests coupled to exact sequences of low-level read/write/spawn calls when the intended contract is a completed turn, graph change or tool answer.

## Questions to start our discussion

1. Which identities/lifetimes do we want: configuration context, authored agent/mob, workspace, conversation, individual run and tool call?
2. Which relationships between those concepts are intentional, versus consequences of sharing one directory stack?
3. Should portable execution consume existing CLI/env protocols directly, or should those become native encodings of richer invocations/results?
4. Which capabilities may legitimately be unavailable on a platform, and how should that be represented to definitions and callers?

These are starting points for the user's broader model, not an order of work. No migration slice is chosen yet.
