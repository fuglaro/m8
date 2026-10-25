# Setting up providers

A provider is a command, and `core/providers/NAME.json` names it; the filename supplies NAME. These are
the ones worth having written down; see Providers in the README for what
the entries mean.

## Bonsai setup on oMLX

```bash
# Check metal is available so fast kernels install.
brew tap jundot/omlx https://github.com/jundot/omlx
brew install jundot/omlx/omlx --with-custom-kernel --with-grammar
```


## Claude setup on the Anthropic api

The entry above reaches `https://api.anthropic.com/v1/messages`
and needs an api key. A Claude subscription does not include
one — the api is a separate product with its own billing — so
take a key from platform.claude.com/settings/keys and put it
where `header-x-api-key` looks:

```bash
security add-generic-password -s anthropic-api-key -a "$USER" -w
```

That header is a command, so anywhere else you already keep
secrets works as well — `pass`, `op read`, `gpg -d`, an
environment variable, a file only you can read.

Then put the model in `mobs/demo/claude.md` to give it the address
`:demo/claude`:

```m8
▐ 🧠:/anthropic/claude-opus-5,max_tokens:16000,thinking:{"type":"adaptive","display":"summarized"}
```

> * :brain::/anthropic/claude-opus-5,max_tokens:16000,thinking:{"type":"adaptive","display":"summarized"}

A parameter may be JSON, and a `,` inside it is the JSON's
rather than the form's, so an object goes on a 🧠 whole.

`display` is worth writing down. It is `omitted` by default on
every current model, which streams a thought with no text in
it — so without this a 💭 reaches the ledger carrying nothing
but its 🔏, and a terminal shows a long pause and then an
answer. Thinking happens and is billed the same either way;
the only question is whether the ledger gets to record it.

```bash
m8 :demo/claude -- "Tell me about the Riemann Sphere."
m8 :demo/claude -- "In one line."
```

## Codex setup on a ChatGPT plan

Unlike a Claude subscription, a ChatGPT plan reaches the api:
OpenAI has publicly backed third-party harnesses on a plan,
and GPT-5.5 is subscription-auth only with no api key at all.
It is tolerated rather than contracted, so the token shape is
theirs to change and this is the entry most likely to need a
line moved.

`codex login` writes an OAuth token to `~/.codex/auth.json`,
and requests carrying it reach the responses api billed to the
plan. So `core/providers/codex.json` is a single object with a url and a command that reads the token:

```json
{
  "cmd": ["m8", "url-provider"],
  "encode": ["m8", "encode", "openai-responses"],
  "parse": ["m8", "parse", "openai-responses"],
  "url": "https://chatgpt.com/backend-api/codex/responses",
  "models-url": "https://chatgpt.com/backend-api/codex/models?client_version=99.0.0",
  "models": ["sh", "-c", "\"$M8\" url-provider --get \"$M8_PROVIDER_MODELS_URL\" | tr ',' '\\n' | sed -n 's/.*\"slug\" *: *\"\\([^\"]*\\)\".*/\\1/p'"],
  "header-authorization": "echo Bearer $(...access_token from ~/.codex/auth.json...)",
  "header-chatgpt-account-id": "...the account id claim in that token...",
  "header-originator": "echo m8",
  "header-openai-beta": "echo responses=experimental",
  "header-accept": "echo text/event-stream"
}
```

None of that is a published api, so it is worth saying where it
came from: it is what Pi sends, and Pi is a harness reaching the
same endpoint for the same reason. `originator` is the client
naming itself — Pi sends `pi`, so m8 sends `m8`, and copying
somebody else's would be a lie told to a server that asked.

The endpoint speaks websockets first and falls back to server-sent
events, so posting to it is a supported path rather than a trick.
That is the whole reason `m8 url-provider` can reach it at all.

Two things the codec sends without being asked, because every
client that speaks this api sends them and a ledger cannot do
without either: `store` off, so the conversation stays yours
rather than being kept and replayed by id at the far end, and
`include` naming `reasoning.encrypted_content`, without which a
💭 comes home with nothing to sign it. A 🧠 that names either
overrules it. One gotcha that is neither: the subscription
endpoint refuses `max_output_tokens`, so do not put one on a
🧠 aimed at it.

`m8 models codex` lists what the plan serves:

* The list is a sibling url, asked with the same headers.
* It refuses a request with no `client_version`, and shows
  a client naming an old one fewer models. So the entry
  names a high one.
* Each model is named by its `slug` there, where the public
  api says `id`.

An api key instead, in `core/providers/openai.json`, reaches the same codec:

```json
{
  "cmd": ["m8", "url-provider"],
  "encode": ["m8", "encode", "openai-responses"],
  "parse": ["m8", "parse", "openai-responses"],
  "url": "https://api.openai.com/v1/responses",
  "header-authorization": "echo Bearer $(security find-generic-password -s openai-api-key -w)"
}
```

```bash
m8 :demo/gpt -- "Tell me about the Riemann Sphere."
m8 :demo/gpt -- "In one line."
```

GPT-5.6 is three models rather than one: `sol` is the
flagship, `terra` the balanced middle, `luna` the fast and
cheap one — the same three tiers as opus, sonnet and haiku,
and a file each. Which of them a subscription endpoint serves,
and whether it wants a `-codex` variant of the name instead,
is that endpoint's business rather than this file's.

## Stats commands

Stats configuration is an ordinary provider value to the generic framework.
It serializes the object as JSON in `M8_PROVIDER_STATS`; only `m8 url-provider`
interprets it. A custom provider command can use that value for
its own purposes. For the url transport, an optional object can select
response metadata and name a formatter:

```json
"stats": {
  "headers": ["x-request-id"],
  "body": ["usage.input_tokens", "response.usage.input_tokens"],
  "cmd": ["awk", "...inline program..."]
}
```

`headers` selects response headers case-insensitively. `body` selects object
fields by dot-separated paths: from the whole JSON response, or from each
JSON SSE `data:` event. Missing paths and non-JSON events (including
`[DONE]`) produce nothing. Selected objects are allowed too; this is not a
query language and does not traverse arrays or escape dots in field names.

The formatter receives named, JSON-valued lines on stdin:

```text
header.x-request-id: "req_123"
body.response.usage.input_tokens: 1200
```

Each value occupies one physical line, including strings with escaped
newlines. Names retain their configured spelling. Headers come first, in
selection order; repeated headers produce repeated lines. Body events retain
arrival order, with paths emitted in configuration order within each event.
A later value does not erase an earlier line: retaining counts or doing
arithmetic is the formatter's business. Anthropic, for example, supplies
input/cache counts at message start and updates output counts later.

The formatter's stdout is status output, not ledger content. Complete lines
beginning `::stats::` written to provider stderr are routed to the existing
converse log and verbosity handling. Other stderr is ordinary diagnostics.
Formatter errors do not change the HTTP command's exit status. Without
`stats`, curl's stdout and stderr are inherited unchanged and the response
body is not captured.

With stats enabled, curl response chunks continue to stdout unchanged. The
body is retained in memory only when `body` selectors are configured; it is
never prefixed with headers or otherwise altered. Selected headers use curl's
`--dump-header /dev/stderr`; `std.Io.File.MultiReader` drains the response and
stderr pipes while keeping header metadata separate from curl diagnostics.
The stdlib HTTP transport uses its header iterator and an optional in-memory
body copy. In either transport, after the response reaches EOF the formatter
runs with selected lines on stdin, stdout forwarded to stderr, and its stderr
preserved as diagnostics. Stats therefore describe the completed response;
no live-timing guarantee is made.

### Examples

[The Anthropic stats fragment](examples/stats-anthropic.json) is self-contained:
its inline POSIX awk formatter handles whole-response and streaming usage,
retaining counts across events. The existing
[Codex configuration](../.m8-st8/core/providers/codex.json) shows OpenAI usage.
Neither requires an installed helper script.

### Watching stats

`m8 watch` keeps polling the pointer and tails new complete `::stats::` lines
from its sibling `+.log`, forwarding them unchanged to stderr. Ledger output
stays on stdout. Existing stats are not replayed when watch starts.
Logged stats prefix the detail field with the latest saved ledger reference,
for example `::stats::✥80▆1K::+/abcdefghij: 1200 in, 80 out`; the compact panel
and provider formatter are unchanged. Without a saved stage, stats stay unlinked.

The log carries stats only, not pointer changes or resets. It is advisory, not
another ledger: no locks, transactions, or delivery guarantees.
Concurrent or interrupted writes may leave malformed lines, and watch ignores
unrecognized records. The pointer remains authoritative even when the log is
missing or truncated.
