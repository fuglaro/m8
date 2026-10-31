# Providers

A provider is a command. It reads a request on stdin and
writes a response on stdout — the same shape a tool has, a
filter that stays in a pipeline. Reaching a url is one such
command rather than the privileged path, so anything you can
write a program for is a provider.

`core/providers/toy.json`:

```json
{
  "cmd": [
    "m8",
    "toy-provider"
  ],
  "models": [
    "m8",
    "toy-provider",
    "--models"
  ]
}
```

`core/providers/local.json`:

```json
{
  "cmd": [
    "m8",
    "url-provider"
  ],
  "encode": [
    "m8",
    "encode",
    "openai-responses"
  ],
  "parse": [
    "m8",
    "parse",
    "openai-responses"
  ],
  "url": "http://127.0.0.1:8000/v1/responses",
  "models-url": "http://127.0.0.1:8000/v1/models",
  "models": [
    "sh",
    "-c",
    "\"$M8\" url-provider --get \"$M8_PROVIDER_MODELS_URL\" | tr ',' '\\n' | sed -n 's/.*\"id\" *: *\"\\([^\"]*\\)\".*/\\1/p'"
  ],
  "header-authorization": "echo Bearer $(cat ~/.omlx/key)"
}
```

`core/providers/anthropic.json`:

```json
{
  "cmd": [
    "m8",
    "url-provider"
  ],
  "encode": [
    "m8",
    "encode",
    "anthropic-messages"
  ],
  "parse": [
    "m8",
    "parse",
    "anthropic-messages"
  ],
  "url": "https://api.anthropic.com/v1/messages",
  "header-anthropic-version": "echo 2023-06-01",
  "header-x-api-key": "security find-generic-password -s anthropic-api-key -w"
}
```

Four entries name commands directly:

* `cmd` gets the request answered.
* `encode` makes the ledger a request.
* `parse` makes the answer a turn.
* `models` lists what it serves. See [Listing models](#listing-models).

The first three are one pipeline, each one's output the next
one's input:

* m8 writes the ledger in, as m8.
* m8 reads the turn out, as m8.
* With no `encode` or `parse`, `cmd` is handed m8 and
  answers in it, as `toy` does.
* The harness normalizes packed records into block spelling before handing
  the ledger to a provider command or its encoder.
  * Third-party providers and encoders support only the block form.
* Which apis there are is no list m8 holds.
  The ones it ships are `m8 encode` and `m8 parse`,
  named the way a command of your own would be.

What a stage says on stderr is diagnostic, held until the turn is in and
then passed on.

* A failed provider has its stderr given as the reason.
* A complete `::stats::` line is the one exception. It goes to the chat's
  `+.log`, and to the terminal under `-v`. See [Stats commands](#stats-commands).
* `-v` reaches every stage as `M8_VERBOSITY`, so each says no more than was
  asked for.

`cmd`, `encode`, `parse` and `models` name pipeline commands; `parent` is
loader metadata. Every other key reaches the stages as `M8_PROVIDER_*`,
and means whatever the command makes of it.

* A key is lowercase letters, digits and hyphens: `api-version` arrives as
  `M8_PROVIDER_API_VERSION`.
* A scalar arrives as written, numbers and booleans as JSON text.
* An object or array arrives as JSON, so `stats` is `M8_PROVIDER_STATS`, and
  only `m8 url-provider` gives it a meaning.
* An unnameable key, or a null, is left out.

`header-` is nothing special to m8. It is `m8
url-provider`'s one convention rather than the language's, and it is
the entry beside the url that knows it: a key named
`header-x-api-key` arrives as `M8_PROVIDER_HEADER_X_API_KEY`,
what it says is run, and its output is that header's value.

Each is a command rather than a value so a config can commit
safely and still reach a keychain, and a constant is `echo`.
A command that fails or says nothing leaves its header off,
so a machine with no key configured still reaches a provider
that wants none.

A bearer token, an api version, a beta flag and a tenant are
all just headers, and not one of them is a format's business
— which is the same reason there is no path m8 appends. So
none of them is known about here and there is one rule rather
than a field per vendor habit.

A provider you write reads whatever its own entry says,
under its own `M8_PROVIDER_` name, and owes none of this.

## Listing models

```bash
m8 models                  every provider that can say
m8 models local codex      the ones named
```
```m8
* :brain::/local/Ternary-Bonsai-8B-mlx-2bit
* :brain::/codex/gpt-5.5
```

> * :brain::/local/Ternary-Bonsai-8B-mlx-2bit
> * :brain::/codex/gpt-5.5

* `models` in an entry is a command that prints one model
  name a line.
  * It is handed the entry as `M8_PROVIDER_*`, as `cmd` is.
  * `$M8` names the m8 that is running.
* `m8 models` runs each and writes a 🧠 per name, spelled
  the way one is asked for.
* m8 knows no api's shape for a list.
  * Reaching the list and picking the names out of it are
    the command's business, beside the url that needs them.
  * A list that cannot be fetched is a `printf` of names.
* `m8 url-provider --get URL` asks a url with the entry's
  headers, so a key is not spelled out twice. `--upload`
  posts a file the same way; see [Uploading](#uploading).
  * `models-url` is no key of m8's: it arrives as
    `M8_PROVIDER_MODELS_URL` like any other string.
* A provider with no `models` is left out.
* m8 says nothing of its own: what a command says on
  stderr is passed on.

There is no path m8 appends to a url. Which api lives where is
a fact about a provider, not about a format, and m8 keeps no
table of those. The whole endpoint goes in `url`.

Which models a provider serves is the ledger's business,
written on the 🧠 that names one, so nothing here has to be
kept in step with what a provider offers.

A provider that speaks two apis is two entries pointing at one
url, rather than a second kind of override.

## Inheriting a provider

A provider may name another provider as its `parent`:

```json
{
  "parent": "openai-responses",
  "url": "http://127.0.0.1:8000/v1/responses",
  "stats": {
    "cmd": ["my-stats"]
  }
}
```

* `parent` names a provider file without `.json`.
  * Parents may have parents; missing parents and cycles are errors.
  * A parent must name an object, not another JSON type.
* Objects merge recursively, with the child's subkeys winning.
  * This example replaces `stats.cmd` while retaining the parent's selectors.
* Arrays and scalars replace the inherited value, rather than appending.
* An explicit `null` replaces an inherited value too.
  * It disables an inherited setting rather than falling back to it.
* File selection happens first, nearest file per provider name.
  * Same-named files in different config layers are not merged.
  * Parent names resolve against those selected files.
* `parent` is loader metadata and never reaches `M8_PROVIDER_*`.

The repository's `openai-responses.json` holds the shared transport, encoder,
parser, stats, inline upload and model-list command for `local-omlx.json` and `codex.json`.
The model-list command accepts `id` or `slug` and runs only when `models-url`
is set, so the base itself emits no models.
Copy the parent file along with a provider that inherits it.

## Finding the command

The first word of `cmd` is looked for in order:

* `m8` is the m8 that is running, so a provider reaches this
  build rather than whichever one is on a `PATH`, or none.
* An absolute path is one.
* A name that names a file in a `core/` is that file, nearest
  first — and if it is not executable, that is an error rather
  than a fall-through to something else of the same name.
* A bare word is searched for on `PATH`.
* Anything else fails.

So a provider you write lives beside the config that names it,
in `core/`, and is reached as `["my-provider"]`.

## Speaking m8

A provider declaring `api: "m8"` is handed the ledger itself
rather than a projection of it — 🧰 with its command and its 🛡
included — and answers in the same language.

Worth knowing in both directions: it is more capable, and it
means a shim that forwards what it receives will forward your
local command lines. A provider speaking m8 is responsible for
projecting before anything leaves the machine.

## Shields

Shields are not applied to a provider command. That is safe
rather than generous, and the reason matters:

A shield is a process the child is launched inside, and
`sandbox-exec` is one way — a provider inherits whatever m8 is
already inside and can never shed it. So the rule only ever
means m8 adds nothing. A jailed agent's tool that reaches a
provider is still jailed, because it is a descendant of a
jailed process; what the rule buys is that a jailed *agent*
can still reach its own model, since an agent's shields are
applied to its tools rather than to m8.

Worked entries for oMLX, Anthropic and a ChatGPT plan
are in [Setting up](#setting-up).

## The ones m8 ships with

```bash
m8 url-provider              post the request to $M8_PROVIDER_URL
m8 url-provider --get URL    ask a url, with the same headers
m8 toy-provider              answer it here
m8 toy-provider --models     its models, one name a line
```

* Each is a command like any other, with a page of its own
  under `--help`.
* A provider command reads a request on stdin.
  * A terminal there is nobody piping one, so it says what
    it is instead of waiting for an end of file that is not
    coming.
* Which models a provider serves is in no config; `m8 models` asks.

`toy` is configured like any other, in `core/providers/toy.json` at the top.
It speaks m8 and answers without a network, which is
what makes the loop, tool calling, and picking up a call that
was never answered testable rather than only demonstrable. Create
`mobs/demo/echo.md`, `runner.md`, and `eliza.md` with the respective
model records `/toy/echo`, `/toy/runner`, and `/toy/eliza`;
`mobs/games/zork.md` contains `/toy/Z-Machine/zork1`:

```bash
m8 :demo/echo -- hello     # says the last thing said
m8 :demo/runner -- 'RUN;;;say;;;text=hi'
m8 :demo/eliza -- "I am not sleeping well."
m8 :games/zork -- "I would like to play"
```

`eliza` is Weizenbaum's doctor of 1966: a keyword found in
what you said, whatever followed it with its pronouns
turned around, and a sentence to put the two into. Which
of a rule's replies comes back is decided by how many
times you have spoken, which the ledger already says — so
she varies through a conversation while remembering
nothing outside it, and a conversation replays exactly.
It is a chat that is worth having a few turns of while
the loop around it is being worked on.

A name ending in `...` is a family rather than one model, and
what follows the prefix is that model's own business. There is
one: `Z-Machine`, which takes the name of a story file and is a
Z-machine — Zork, and forty years of interactive fiction after
it. It has no weights. It is a virtual machine wearing a model's
interface, and it is here because a model api is stateless and
so is it.

Which is the whole of the design. A model is sent the messages
every time, so the machine is rebuilt every time and the ledger
is replayed through it. Nothing is kept between calls because
there is nowhere to keep it — so the chat is the save file,
forking a chat forks the world, and two runs of the same words
cannot differ. Saving is not implemented and does not need to
be: `m8 say --no-send :games/zork | m8 encode m8 >save.md` already is one, and
`m8 tag :games/zork <save.md` restores that mob's conversation.

The first thing you say is not played. It is hashed, and the
hash is the seed the world is built from, so "hello" and
"hello!" are two different games.

```
.m8-st8/core/Z-Machine/       nearest first, like everything
~/.config/m8-st8/core/Z-Machine/
```

m8 ships with no story files: it plays whichever are there,
`.z1` through `.z8`. The name is the file's own and the folder's,
spelled the way they are, like every other name in m8.
Zork I to III are MIT-licensed source from Microsoft and their
repositories carry the compiled files. `m8 toy-provider
--models` lists what it can find.

[src/zmachine/README.md](../src/zmachine/README.md) is the rest of it: the seam between
the machine and the provider, the invariant every stored
ledger rests on, and what a headless Z-machine has to decide.

`runner` calls a tool for every line of the last thing said
reading `RUN;;;tool;;;property=value;;;...`. Deliberately
witless — `;;;` separates and nothing escapes it — because it
exists to drive m8's own tool path from a test rather than to
be a language.

## Uploading

An entry's `upload` says how each file a 🔗 names reaches the
api: carried whole in every request, or uploaded once and
named by the id the api gave back.

```json
"openai": {
  "cmd": ["m8", "url-provider"],
  "encode": ["m8", "encode", "openai-responses"],
  "parse": ["m8", "parse", "openai-responses"],
  "url": "https://api.openai.com/v1/responses",
  "files-url": "https://api.openai.com/v1/files",
  "upload": "…one of the scripts below, as one string…",
  "header-authorization": "echo Bearer $(cat ~/.openai/key)"
}
```

* `upload` is a command that says one line of a file:
  `MIME URI NAME`.
  * `$1` is the 🔗's line after its `<`, as written.
  * `$2` is the config directory m8 keeps things in, the
    nearest, for whatever the command keeps.
  * It arrives as `M8_PROVIDER_UPLOAD`, as any string does,
    and `encode` runs it.
  * One that fails, or says no such line, fails the encode,
    which is how an entry turns down a file its models do
    not take.
* `encode` runs `upload` for every file before the codec
  sees the ledger.
* With no `upload`, a 🔗 fails the encode.
  * Set `"upload": null` in a child to disable inherited attachment support.
* m8 holds no view of the line. The codecs it ships read it:
  * a `data:` url carries the file whole;
  * `ref:` and an id names a file the api has;
  * any other url is for the api to fetch.
  * NAME is the file's, for an api that wants one.
  * A type opening with `image/` goes as an image, anything
    else as a file.
  * Chat completions names no image by id, so a `ref:`
    image fails there.

Both read `<path (SHA-256)`, resolve relative paths against
`M8_MOB_ST8_DIR`, and refuse a file whose hash differs from
the link.

This one carries a file whole, as the shared Responses provider does.
It tries GNU/Linux then BSD/macOS `stat` to detect ordinary concurrent
changes; a failed command's output is
discarded. It does not defend against adversarial timing:

```bash
p=${1% (*} h=${1##* (} h=${h%)}; n=${p##*/}
case $n in
  *.jpeg|*.jpg) m=image/jpeg ;; *.png) m=image/png ;; *.gif) m=image/gif ;;
  *.webp) m=image/webp ;; *.pdf) m=application/pdf ;;
  *) echo "upload: no type for $n" >&2; exit 1 ;;
esac
case $p in /*) f=$p ;; *) f=$M8_MOB_ST8_DIR/$p ;; esac

stamp() { stat -c '%d:%i:%s:%Y:%Z' -- "$1" 2>/dev/null || stat -f '%d:%i:%z:%m:%c' -- "$1"; }
before=$(stamp "$f") || exit
[ "$({ sha256sum 2>/dev/null || shasum -a 256; } <"$f" | cut -c1-64)" = "$h" ] || { echo "upload: $p is not the file linked" >&2; exit 1; }
printf '%s data:%s;base64,' $m $m; base64 <"$f" | tr -d '\n'; printf ' %s' "$n"
after=$(stamp "$f") || exit
[ "$before" = "$after" ] || { echo "upload: $p changed while encoding" >&2; exit 1; }
```

This one uploads to OpenAI, once per file:

```bash
p=${1% (*} h=${1##* (} h=${h%)}; n=${p##*/}
case $n in
  *.jpeg|*.jpg) m=image/jpeg ;; *.png) m=image/png ;; *.gif) m=image/gif ;;
  *.webp) m=image/webp ;; *.pdf) m=application/pdf ;;
  *) echo "upload: no type for $n" >&2; exit 1 ;;
esac
case $p in /*) f=$p ;; *) f=$M8_MOB_ST8_DIR/$p ;; esac

t=$(mktemp -d) && trap 'rm -rf "$t"' EXIT && c=$t/$n && cat -- "$f" >"$c" || exit
[ "$(shasum -a 256 <"$c" | cut -c1-64)" = "$h" ] || { echo "upload: $p is not the file linked" >&2; exit 1; }
u=$M8_PROVIDER_FILES_URL k=$M8_MOB_ST8_DIR/cache/$M8_PROVIDER_NAME/${M8_PROVIDER_ACCOUNT:-_}/uploads/$h.txt
id() { grep -o '"id": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/'; }
i=$(cat "$k" 2>/dev/null)
[ -n "$i" ] && [ "$("$M8" url-provider --get "$u/$i" | id)" = "$i" ] && { echo "$m ref:$i $n"; exit; }
case $m in image/*) q=vision ;; *) q=user_data ;; esac
i=$("$M8" url-provider --upload "$u" "$c" purpose=$q | id)
[ -n "$i" ] || { echo "upload: no id for $n" >&2; exit 1; }
mkdir -p "${k%/*}" && printf %s "$i" >"$k" && echo "$m ref:$i $n"
```

* `m8 url-provider --upload URL FILE [NAME=VALUE]...` posts a
  file as a form, with the entry's headers.
  * The temporary copy keeps the verified bytes stable while
    the remote upload runs; a later local failure cannot undo
    a remote upload.
* Remembering what was uploaded is the command's business.
  * This one keeps each id in the owning config's `cache/`,
    grouped by `M8_PROVIDER_NAME` (the selected provider
    entry's name), account, and the verified SHA-256.
  * `account` in the entry names whose ids they are, `_`
    when unsaid, so two keys never share one.
  * An image goes up as `vision` and a pdf as `user_data`,
    the purposes OpenAI names for each.
  * Before using an id again it asks whether the api still
    has the file, and uploads it again when it does not.
  * Anthropic's files api takes no `purpose`; a script for
    it leaves that field off.

## Setting up

The entries worth having written down.

### Bonsai setup on oMLX

```bash
# Check metal is available so fast kernels install.
brew tap jundot/omlx https://github.com/jundot/omlx
brew install jundot/omlx/omlx --with-custom-kernel --with-grammar
```


### Claude setup on the Anthropic api

The `anthropic.json` entry at the top reaches `https://api.anthropic.com/v1/messages`
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

### Codex setup on a ChatGPT plan

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
