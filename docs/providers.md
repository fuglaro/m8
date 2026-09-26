# Setting up providers

A provider is a command, and `core/providers.json` names it. These are
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

Then a model is a 🧠 like any other, and a file is how it comes
to have a name:

```m8
▄ 🧠/anthropic/claude-opus-5,max_tokens:16000,thinking:{"type":"adaptive","display":"summarized"}
```

A parameter may be JSON, and a `,` inside it is the JSON's
rather than the form's, so an object goes on a 🧠 whole.

`display` is worth writing down. It is `omitted` by default on
every current model, which streams a thought with no text in
it — so without this a 💭 reaches the ledger carrying nothing
but its 🔏, and a terminal shows a long pause and then an
answer. Thinking happens and is billed the same either way;
the only question is whether the ledger gets to record it.

```bash
m8 @claude "Tell me about the Riemann Sphere."
m8 @/anthropic/claude-haiku-4-5,max_tokens:1024 "In one line."
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
plan. So the entry is a url and a command that reads the token:

```json
"codex": {
  "cmd": ["m8", "providers", "url"],
  "api": "openai-responses",
  "url": "https://chatgpt.com/backend-api/codex/responses",
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
That is the whole reason `m8 providers url` can reach it at all.

Two things the codec sends without being asked, because every
client that speaks this api sends them and a ledger cannot do
without either: `store` off, so the conversation stays yours
rather than being kept and replayed by id at the far end, and
`include` naming `reasoning.encrypted_content`, without which a
💭 comes home with nothing to sign it. A 🧠 that names either
overrules it. One gotcha that is neither: the subscription
endpoint refuses `max_output_tokens`, so do not put one on a
🧠 aimed at it.

An api key instead, which reaches the same codec:

```json
"openai": {
  "cmd": ["m8", "providers", "url"],
  "api": "openai-responses",
  "url": "https://api.openai.com/v1/responses",
  "header-authorization": "echo Bearer $(security find-generic-password -s openai-api-key -w)"
}
```

```bash
m8 @gpt "Tell me about the Riemann Sphere."
m8 @/codex/gpt-5.6-luna "In one line."
```

GPT-5.6 is three models rather than one: `sol` is the
flagship, `terra` the balanced middle, `luna` the fast and
cheap one — the same three tiers as opus, sonnet and haiku,
and a file each. Which of them a subscription endpoint serves,
and whether it wants a `-codex` variant of the name instead,
is that endpoint's business rather than this file's.
