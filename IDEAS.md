
==== DONE

```
# Shell accessible m8 parser that expands whole chats ledgers.
m8 +mathy encode m8
m8 +mathy encode m8 >full-ledger-copy.md # raw when not tty
m8 decode m8 # null operation

# Shell accessible api conversion.
# Can be lossy as it can forget the target model through an encode/decode.
m8 +mathy encode openai
m8 encode openai-completions <full-ledger-copy.md >openai.json
m8 decode openai-completions <openai.json # reverses operation

# Shell accessible redirect to provider interaction.
m8 decode openai-completions <openai.json | m8 send [PROVIDER/MODEL]
```

Command line inclusions like +mathy and what comes after -- are appended to any stdin.
Providers api entry should change from openai to openai-completions.
  It makes the api field and the codec name the same namespace.
  The codec should own the URL suffix too.
  Allow models to override the provider api key with their own api key.
m8 is always a ledger: retain record order, shift any reordering/combining to model apis,
  because every api encoding are projections of it.
m8 is truth: avoid dropping things from the history.
Fix: "Tool calls are dropped from history" - tool calls should stay in m8.
  Calls that have already been responded to are not called again.


==== DONE

`m8 [-l LOCKS] [@AGENT|+CHAT] [COMMAND [ARGS]] [-- PROMPT]` -> sorry, is confusing things.
I need to separate some concepts so I'm not asking for spaghetti:
```
  m8 [-l LOCKS] [[@AGENT|+CHAT] MSG_CMD|RUN_CMD] [ARGS]

msg_cmds:
  --     consults an agent...
  cat    ...
  encode ...
  send   ...

  Respects stdin as m8 or raw prompt and assembles a ledger and prompt.


run_cmds:
  call   ...
  ... 
```
And maybe we should just move ask as a native inbuilt inder the call cmd:
```
m8 call ask ...
```

Assembly of ledger (with `STDIN | m8 [@/+NAME] -- PROMPT`):
 - no STDIN: assembles `NAME(fallback to last chat) → -- prompt`
 - detected m8 STDIN: assembles `NAME(no fallback) → STDIN → [-- prompt](runs even without)`
 - other STDIN: assembles `NAME(no fallback) → [-- prompt](runs even without) + STDIN appended to prompt`
We detect on initial ligature, so the detected m8 STDIN can still error on malformed.

==== DONE

can't run, and it reports that honestly rather than silently.
The one real loss. openai → m8 → openai is byte-identical except max_tokens, which came from your provider config and isn't on the wire.



* New model only form starts with @/: `@/local/Ternary-Bonsai-1.7B-mlx-2bit,context:32768,max_tokens:8192`
* Parameters are expected to be the provider api's form.
* Considered an unnammed agent so not chat is automatically made.
* No longer falls back to a model if an agent isn't found with the old form.
* Models can no longer have their own api defined, it can only be defined at a provider level.
* Multiple providers can be defined each with a different api to give access to multi-api-providers.
* Users can always make agents with matching names that simply reference the
  model so an agent form is accessible `@Ternary-Bonsai-1.7B-mlx-2bit` or even
  like it was by making a mob `@local/Ternary-Bonsai-1.7B-mlx-2bit`.
* providers.json no longer supports the models entry. Much simpler and everything moves into m8.
* Chamge to `m8 send PROVIDER` since we don't need to specify the model anymore.
* When doing this migrate .m8-st8 and make the agent aliases
  like `@local/Ternary-Bonsai-1.7B-mlx-2bit` for compatibility.

====

Consider:
m8 → openai → m8 also loses 🔌 — so a decoded tool

====

Support custom api converters with plugin commands in m8-st8?

====
```
@AGENT - ask an agent, resetting it's named chat.
+CHAT - continue a chat.
... @CHAT - creates freshly named chat if an agent of the same name doesn't exist.

^SKILL - include agent as skill (book in m8)

-- [QUERY] ... - supply user prompt
```

user calling a tool at a chat?

====

```
.m8-st8/@/=/REF.m8
.m8-st8/@/+/CHAT.m8
.m8-st8/@/[MOB]/AGENT.m8

.m8-st8/@/+/[SESSION]/CHAT.m8
```

Agent definitions search for peers by relative reference going outwards up mob levels.


Note that in the future we may implement persistant chats ongoing between
agents using send_message to each other by referencing

?? How shoud send_message (to another agent) work?
Do we set up persistent chats under a mob?



====

# default "inbuilt" provider

```
{
  "inbuilt": {
    "api": "inbuilt",
    "models": {
      "echo": {},
      "elisa":  {},
      "adventure":  {},
    }
  }
}
```

```
m8 @inbuilt/echo
m8 @inbuilt/elisa
m8 @inbuilt/text-adventure-some-mit-flavour-one
```
