

====
```
@AGENT - ask an agent, resetting it's named chat.
+CHAT - continue a chat.
... @CHAT - creates freshly named chat if an agent of the same name doesn't exist.

^SKILL - include agent as skill (book in m8)

-- [QUERY] ... - supply user prompt
```

====

```
.m8/@/[MOB]/AGENT.m8
.m8/@/+/CHAT.m8
.m8/@/=/REF.m8
```

Agents search for peers by relative reference going outwards up mob levels.

====

# Integrate restrictions

* rename call -w and --with to -l and --lock and move it directly under m8.
  * this is cumulative with top level locks.
  * it moves up and out of just being under call,
    so all the 🔌 templates change to ["m8", "{{lock:-l}}", "call", …]
* add support to define locks inside toolbox definitions:
  * 🔒 :lock:
  * value: comma separated list
  * "lock" becomes an inbuilt/restricted property that can't be defined as one supplied.
* add support for locks at the top m8 level:
  * behavior: cumulative on lineage of top level locks
    and only the last toobox definition for that tool name.

# Standard restrictions improvements and refactor

* only reply-side sigils are ever honoured from a model's output — 🤖, 💭, 🔏, 📲 and its 📦,
  while definition side sigils are always filtered from the reply.
* change the location of the m8 config folder to be:
  * .m8-st8 in relative paths,
  * m8-st8 in HOME or XDG_CONFIG_HOME.
* Respect a top level only (core is top level only) m8-st8/core/mac-sandbox.sb config override file.
* Ensure the mac-sandbox.sb rules deny write to `(deny file-write* (regex #"(^|/)\.?m8-st8/core($|/)"))`
  (untagged with any ;;!!) so core is always protected
  from agent manipulaton even if no-edit-m8-st8 is omitted.
* Move our src/contain-env-allowed.txt and src/mac-sandbox.sb under src/core/.
  These should be compiled into the output binary.

# Close restrictions

* add no-edit-git (included in sandbox and jail):
  * ```(deny file-write* (regex #"(^|/)\.git($|/)"))```
* add freeze-toolbox (included in sandbox and jail):
  * reject as a hard error any tool calls that emit 🧰, 🔓, 🧠 or 📚.
* add no-edit-m8-st8 (included in sandbox and jail):
  * ```(deny file-write* (regex #"(^|/)\.?m8-st8($|/)"))```
  * add test so can't hack with move from a staging area into a .m8-st8
  * add test so can't hack with symlink to .m8-st8.
* add `agent-check=<agent>` that asks that agent if something looks safe to run.
  * the checker agent is expected to have a system prompt such that it ends up saying:
    * `allow` - if it deems execution reasonably safe.
    * anything else should be raw (non-m8) text which will be included in an error response:
      `Failed agentic check: <response>`.
  * ensure top level locks are passed through to the call to the sub agent.
  * the checker agent never gets it's output included in the receipt.
* add contain-env (included in sandbox and jail; update comment that it's addressed)
  * respect a m8-st8/core/contain-env-allowed.txt config override file,
  * otherwise respect the bundled src/core/.
* add ask (prompts user to run any tool).
  * when there is no tty, this operates like a full deny.
* add deny (blocks any tool use)
* make call output m8, unless a --raw flag is specifically added:
  * stdout becomes receipt text.
  * stdout is captured and becomes error text if return code is not 0.
* ensure no agent can escape it's responses in such a way that it can define it's own toolbox,
   unless it has already got access to tools without freeze-toolbox, sandbox, and jail.

# Clear and concise documentation

* A ## Locks section, in the README's voice:
  * The subtraction invariant, stated once and made to cover everything: a lock only ever removes, so any combination is safe and order never matters.
  * Where a lock can be written — top level, 🧰, -l on the command line — and how they compose: top-level cumulative over lineage, per-tool last-wins, effective set is the union of the floor and the tool's own.
  * lock as a reserved property, and why: so the model can't choose its own.
  * The categorisation of enforcement location (not a table), for each lock, what it removes and where it's enforced — kernel or m8 — with one line on what that means when a tool spawns something. Including rationale how m8 level restrictions are ratioalised:
    * deny is self-enforcing — no tools means no child process, so there's nothing to inherit to.
    * ask gates the decision at the point the decision is made. Anything downstream runs because the user already said yes to something that could do it.
    * freeze-toolbox applies to each m8's parse of its own model's reply, which is where it belongs, at every depth independently.
  * A worked pair: one agent that can't widen, one that defines its own tools, so the two setups from your question are readable side by side.
  * The checker's position in the trust path, as guidance rather than mechanism: it reads attacker-influenced text, so give it what it needs and no more — and here's the jailed-validator pattern, because that's the good use.
  * A list of considerations and recommendations for thinking through setting up a trust framework.



