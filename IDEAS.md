# ==== DONE

Skills 2.0

#### :toolbox:load_skill
> `m8` `call` `m8` `--` `m8` `load` `@{{MOB}}skills/{{SKILL}}`
> * SKILL string

Skill file:
```md
#### :top:
#### :compass:
> Load the tight-docs skill when working on documentation or comments.
#### :top:
#### :raising_hand:
> Skill content…
```

New :top: sigil. If the very first sigil of the file being referenced, begins a top header section until the next :top: sigil. Subsequent tops in a single file is an error.

@agent and :brain: behaves as load (omitting any top on each file read) 
^agent and :books: behaves as top (only giving the top section, if it exists)
This behaviour recurses through deeper references.

# ==== DONE

So I'm thinking of, to keep us constrained to clean, separate, modular architectural guardrails - and to really fully acknowledge the "composable"
mission statement, of forcing us to build separate commands, with a lightweight sub command launcher.
e.g:

m8-call-edline
m8-call--
m8-shield-secure
m8-shield-check
m8--
m8

# ==== DONE
MUNGE EDITING TOOLS

#### :toolbox:read
> > Read the contents of a text file.
> > Read the whole file, or use pages to read a range at a time
> > or a number of pages starting at a string match anchor.
> `m8` `call` `munge` `read`
> * path String
>   Path of the file to read (relative, absolute, or ~).
> * pages? String
>   Page range to read e.g. "10-10" or "11-20" or "21-100", or
>   "2@string_match" to read 2 pages starting at string_match.
>   About 100 lines per page, fewer when lines are very long.
#### :toolbox:read BYTE_CAP 16000
—
* Pages terminate on every 100th line, or every 10000th character after the previous 100th line. If a line that started in the last third of a page would have the page end mid-line, the whole line is pushed into the next page.
* Page range parsing has a zero-failure parsing system: extracts out every digit sequence regardless of separators, and takes the lowest and highest numbers. A leading non-digit character makes it start at 1, while a trailing non-digit character makes it give the remainder.
* The anchor form, if it is valid, overrides parsing. It splits on the first @ and expects a positive or negative number on the left. Negative numbers give that many pages above.
* In anchor form, if the match is in the first 10 lines of the page, the previous page is included. For negative page counts, it does it for the last 10 lines and the subsequent page. Similarly, if only 1 page is requested, and it is in the last (or first for negative counts) 10 lines of the page, the count will be treated as if it was 2.
* A user message is appended after the content tool response:
```
[Pages 11-20 of 1-34. Lines 1101-2000. Use pages="21-30" to continue.]
[Pages 11-20 of 1-34. Lines 1084-2100. Opens mid-line 1180. Use pages="21-30" to continue.]
[Pages 11-20 of 1-34. Lines 1101-1908. Ends mid-line 2140. Use pages="21-30" to continue.]
[Pages 11-20 of 1-34. Lines 1084-1870. Opens mid-line 1180, ends mid-line 2140. Use pages="21-30" to continue.]
[Pages 30-34 of 1-34. Lines 3399-3712. Opens mid-line 3399. End of file.]
[Pages 30-34 of 1-34. Lines 3401-3712. End of file.]
[Pages 21-23 of 1-34. Lines 2001-2300. Returning fewer pages due to a 16000 byte cap. Use pages="24-33" to continue.]
```
* Continuation suggestion uses the same number of pages as requested.
* When pages are omitted, the user message is not given unless the BYTE_CAP is exceeded: `[Pages 1-23 of 1-34. Lines 1-4395. Returning fewer pages due to 16000 byte cap.]`
* Error responses guide the model: `[Pages 45-46 of 1-34: out of scope.]`
* Edmung is a single self-contained tool with multiple modes.

#### :toolbox:list
> > List the contents of a directory.
> `m8` `call` `munge` `read`
> * path String
>   Path of the directory to inspect (relative, absolute, or ~).
>   Use "." for the project root.
#### :toolbox:list BYTE_CAP 16000
* Returns a simple view of the contents of the directory.
—
```
path/dir/
path/small_file (12KB, 4400 lines, 1-44 pages)
path/large_file (23MB)
path/symlink -> dest
```
* Just gives size if the file is over BYTE_CAP*100 or if it is a binary file, and nothing if it is a special file.
* Uses the same underlying command as read tool, but just acts this way when given a directory instead of a file. Both tools will give the other result if given the wrong path type. Pages would be respected, but are not given as an option on this tool.

#### :toolbox:edit
> > Edit a file. Either replace exact matches of an old_string, or
> > leave old_string empty to append into a new or existing file.
> > Must only match once if using multiple lines to replace.
> > Pages may be used to scope matches.
> `m8` `call` `munge` `write`
> * path String
>   Path of the file to edit or create (relative, absolute, or ~).
> * old_string? String
>   The text to replace. Omit to write or append.
> * new_string String
>   The text to insert.
> * pages? String
>   Page range to scope the matches during replace e.g.
>   "10-10" or "11-20" or "21-100", or "2@string_match" to
>   scope within 2 pages starting at string match.
—
```
[Replaced 1 match on page 30]
[Replaced 1 match on page 30. Matched ignoring indentation]
[Replaced 1 match across pages 30-31]
[Replaced 4 matches across pages 3-9]
[DENIED: Found 2 matches but multi-line replacements must be unique]
[Created a new file with 2 pages]
[Appended to page 40]
[Appended to pages 40-43]
[Removed 1 match on page 30]
```
—
* Reciept acknowledges any fuzzy matching it performed.
* When appending, always appends to a new line.
* Appending or writing new files always ensures a trailing newline.
* Creates new files and leading directories as needed.
* Fuzzy matches with compounding forgiveness:
  * Exact matches.
  * Trailing and leading line whitespace equivalence.
  * Total whitespace equivalence.
  * Unescape \n, \t, \r and escaped quotes — but only when the block holds no real newline.
  * If a match line starts with "number:", also matches if that prefix is treated as a line number within 100 lines away.
  * Multi-line block forgiveness - a 25% line mismatch rate is tolerated within the first and last whole lines of at least 8 non-whitespace characters.

#### :toolbox:grep
> > Grep search per-line inside files that match a glob.
> > Glob wildcards will not expand "." prefixed directories.
> `m8` `call` `munge` `scan`
> * regex  String
>   Regex to search with using a Perl-style pattern (no
>   backrefs, lookaround, or multi-line matching).
> * glob String
>   Glob match for files with ** and * expansion (relative,
>   absolute, or ~) e.g. "src/**/*.js" or "**".
—
```
path/to/file.ext (2KB, 3433 lines, 1-34 pages) has 5 matches:
* 4 matches on pages 30-32 in lines:
    2998:…prefixed/suffixed for mid-line page breaks…
    3055:line with matching string.
    3166:another line with matching string.
    3211:last line with a match on consecutive matching pages.
* 1 match on pages 34-34 in lines:
    3423:last line of file with match.
path/to/another/file.ext (564B, 233 lines, 1-2 pages) has 1 match:
* 1 match on pages 1-1 in lines:
    34:line with a matching string.
```
* Skips binary files.
* Fast scans but still a simple tool.
* Doesn't descend into directories prefixed with a ".", or symlinks to directories, when matching * or ** patterns.
* Glob silently supports {a,b} and ? syntax.
—
* Includes a bundled regex that is fast, simple and small.
- Single line, whole-match offsets only. No capture slots.
- Byte-oriented. ASCII `\w \d \s`, ASCII-only `(?i)`.
- Syntax: literals, `.`, `[a-z]`, `[[:alpha:]]`, `\d \w \s \D \W \S`, `^ $ \b \B`, `|`, `(...)`, `(?:...)`, `* + ? {n} {n,} {n,m}`, lazy `*? +? ??`, inline `(?i)` and `(?i:...)`.
- Leftmost-first alternation, not leftmost-longest.
- Parse → AST → bytecode → Pike VM.
- AST arena-allocated, freed after compile. Bytecode persists.
- Five ops: `byte`, `class`, `split`, `jmp`, `match`. Classes as 256-bit bitsets in a side table.
- `{n,m}` expands by duplicating the subtree.
- `Thread = struct { pc: u32, start: u32 }` — 8 bytes, copy to fork.
- Two preallocated thread lists sized to program length, swapped per byte.
- Sparse set for pc dedupe; clear is `len = 0`. Bounds threads to program size → O(n×m).
- No allocation in the match loop. No timeout needed — linear time is structural.
- Prefilter: extract required leading literal from AST, `std.mem.indexOf` to candidates, run VM only there.
- Whole pattern literal → skip compilation, `indexOf` and return.
- `^` anchored → try position 0 only. No required literal → run VM from each position.
- Return compile errors verbatim; name the unsupported construct.
- Defer: lazy DFA, Aho-Corasick multi-literal, `\p{...}`, Unicode case folding, capture groups.
- Reject patterns containing literal `\n` at compile time — never silently return no matches.
—

#### :toolbox:glob
> > Glob scan for matching file paths.
> > Glob wildcards will not expand "." prefixed directories.
> `m8` `call` `munge` `scan`
> * glob String
>   Glob match for files with ** and * expansion (relative,
>   absolute, or ~) e.g. "src/**/*.js" or "**".
* Uses the same underlying command as grep which changes the output format when the regex is omitted: 
```
path/to/file.ext (2KB, 3433 lines, 1-34 pages)
path/to/another/file.ext (564B, 233 lines, 1-2 pages)
path/to/large/binary/file (23MB)
```

—

# ====


Try to squash out remaining {{CODE}} and {{M8}} framework level placeholders.

# ====


Saw a harness use PositiveInt as a type, and altough clearly a hint, shouldn't we also use Pascal Case for type? Make sure the providers sanity check or clean type so we don't get a kick back.

# ====

m8 to enforce required params regardless of whether the command does. So required for some models and not others!

tool extension skills - Scaling flexibility by what we tell the model.

# ====

All inbuilt tools take args as well as envs (M8_ARG_FOO=blah or --foo blah),
so one can be driven by hand from a shell.

Parameter expansion itself is settled below, under M8 CALL ARGS.

# ====

Make toolbox activation only when providing no value or quoted block so we can template the setting of env vars.
Make sure that value mechanism of setting of env vars also prefixes M8_ARG_

Cleanup in pagey -> `BYTE_CAP 16000` sits on the definition header of toolbox.

Want 2 modes to toolbox.
1: stack on definition.
2: activate.

Adding an env var is 1, not 2.

# ====

#### :toolbox:bash
> > Run a bash command.
> `m8` `call` `args` `bash` `-euo` `pipefail` `{{M8_ARG_COMMAND|-c}}`
> * command String
>   The bash command to run.

# ==== DONE

M8 CALL ARGS

A call is carried one way, in the environment. A tool's argv reaches its command
verbatim, and `m8 call args` is what turns an environment back into flags for a
command that wants them.

It is an example rather than a dependency. Delete it and the framework still
works — every inbuilt tool already reads `M8_ARG_*` directly — so anything else
may fill the same slot, which is the whole claim about being composable.

A placeholder is a whole argv element and expands from the environment:

```
{{M8_ARG_COMMAND}}       --command VALUE
{{M8_ARG_COMMAND|-c}}    -c VALUE
{{M8_ARG_COMMAND|}}      VALUE
{{M8_ARG_DEEP?--deep}}   --deep, only when the value is exactly `true`
{{M8_ARGS}}              the whole call as JSON, one element
```

* Matching is on the `M8_ARG` prefix, which covers both names in one test and
  cannot collide with a templating language's own braces — `m8 call args awk
  '{{print $1}}' f` passes through untouched. That is also what retires the
  `{{{…}}}` literal escape, which existed for exactly that collision.
* `|` also separates enum values in a type, in a different position, so there is
  no parse conflict — but it is the one character in this language doing two
  unrelated jobs.
* Unset omits the element entirely. An empty string emits the flag and an empty
  element. Keeping them apart is the whole of what optional means to a command.
* `?` is strict: `true` emits the flag alone, `false` and unset omit it, and
  anything else is an error naming what arrived. Silent omission would let a
  call look like it succeeded while ignoring what was asked, which is worse than
  failing. `callEnv` writes JSON `true` and JSON `"true"` to the same bytes, so
  a stringly-typed provider still passes.
* Only `?` reads a value. Every other form passes any bytes through.
* No flags of its own, ever, so the first word is always the command and there
  is no `--` to remember.

Objects and arrays have no environment spelling and get no expansion here.
Structure lives in `M8_ARGS` and is read with jq inside a block, which keeps
`args` free of a JSON parser.

Taking expansion out of the framework is one arm of one switch:

* `converse.zig` — the `.argv` case becomes the argv, unchanged.
* `toolbox.zig` — `expand`, `emit`, `pushFlag`, `scalar` and their tests go, and
  `{{}}` for the whole call goes with them.
* Required-property enforcement stays. It is the one part of carrying a call
  that belongs to the framework.
* `{{CODE}}` and `{{M8}}` stay for now, so `{{…}}` means m8's own word rather
  than a call's, and a reader can tell which layer acts on a placeholder from
  its name alone. Squashing those two is its own idea above.
* Errors move from load time to call time. That is the trade and it is accepted;
  a broken definition failing loudly on use is not worth a validation pass.

A shield must not clobber `M8_*`, or it breaks the tool and every shield inside
it. Once the environment is the only way a call is carried, that contract wants
saying in `shield`'s help and the README's shield section, with the inbuilt
shields tested against it. `contain-env` allowing `M8_*` is one instance of the
rule rather than the rule itself, and user-defined shields can only be told.

—
# ====

#### :toolbox:webfetch
> > Download a web page for viewing.
> ```bash
> out=$(mktemp "$TMPDIR/$(printf %s "$M8_ARG_URL" | tr -cs A-Za-z0-9 - | cut -c1-200).XXXXXX")
> curl -fsSL --max-time 30 --max-filesize 10000000 -o "$out" "$M8_ARG_URL"
> echo "Downloaded for viewing at: ${out#"$PWD"/}"
> ```
> * url String
>   The url of the page to download.

* `mktemp` picks the name and creates the file in one atomic step, so two
  fetches at once cannot land on one path. Six X, because busybox's `mktemp`
  is a wrapper over `mkstemp`, which wants exactly that many.
* Announcing the path only after the fetch succeeds is what keeps a reader
  from ever seeing a half-written file, and `-e` on the 🏃 is what makes the
  separate `echo` line say so.
* The slug is a label rather than a reference, so two urls sharing one costs
  nothing. `cut` leaves room for the suffix.
* `mktemp` over `uuidgen`, which is util-linux and absent from busybox.

# ==== DONE

MOB TMPDIR

A mob's own scratch directory, under `.m8-st8/.tmp-dir/`, with a subdirectory
per mob. m8 makes it before a tool runs and never removes it. Persistence is
the whole point: a tool that writes a file and answers with its path is only
useful if the next call can open it, and a directory of this call's own means
it never can.

* Made unconditionally, as a contract of the framework rather than a side
  effect of building a sandbox invocation, so a tool has one whether it stands
  inside a 🛡 or not.
* Guaranteed to exist, and guaranteed without a trailing slash, so a tool needs
  neither a `mkdir` nor a `${TMPDIR%/}` of its own.
* Built by m8 from the mob's own location rather than inherited, so it is a real
  path rather than one reached through a symlink — which is what the profile's
  `TMP` has to match, and what an inherited macOS `/var/folders` TMPDIR does
  not, so TMP is not actually writable today.
* The throwaway HOME points at the same directory, so a tool wanting a dotfile
  or a cache has somewhere real to put it and never reaches the person's own.
* No cleanup. A tool tidies up after itself or leaves something meant to last;
  resetting a mob is the eraser, and it is the user's to reach for.
* Keeping it out of version control is a repository's business rather than
  m8's. A `.gitignore` inside the config directory is the suggestion, and this
  repo carries one: the rule travels with the folder, and a project root needs
  nothing said in it.

The profile needs a carve-out, because `no-edit-m8-st8` denies writing to any
path holding `m8-st8` — which would make the one directory m8 guarantees
writable the one directory a tool may never write. It reads as one statement
alongside the permanent deny already there:

* `core/` is never writable, and no flag subtracts that.
* `.tmp-dir/` is always writable, and no flag subtracts that either.
* Everything between them is writable until `no-edit-m8-st8` is active.

The cost is that `.tmp-dir` becomes a reserved name inside a config directory.

Open: how the per-mob subdirectory is spelled for a mob nested below the top.

# ====

Nudge the model to make multiple calls in a single response.
Nudge it to use string match anchors when doing multiple changes in the same file.


# ====

Inbuilt optional toolbox - file interaction.

#### :compass:
> You are a helpful coding assistant working alongside the user,
> who communicates concisely and clearly. 
> Use the `view` tool to examine file and directory contents,
> and the `edit` tool to make subsequent changes:
> * A denial means your picture of the file is wrong,
>   not that you should recount anything. View before retrying.

#### :toolbox:view
> > Lists lines of files or alphabetically sorted directory content. 
> > File lines have a line number prefix (1-indexed): `=123|LINE`.
> > An end of a file newline shows as an empty numbered line.
> > Directory content lines are prefixed with `/` and have
> > suffixes based on their types:
> > * Directories suffix `/`.
> > * Symlinks to directories suffix `/ ->DESTINATION`.
> > * Symlinks to files suffix ` ->DESTINATION`.
> > * Normal files suffix ` (SIZE)` in bytes.
> `m8` `call` `view`
> * path string
>   The relative or absolute path to the file or directory to inspect.
> * offset? number
>   The number of lines into the result to start viewing.
> * limit? number
>   More lines than this are truncated
>   with a final unnumbered `~~~` line. Defaults to 400.
> * width? number
>   Lines over this length truncate with `~~~`. Defaults to 400.
> * grep? string
>   Activates search mode for matching file lines.
>   When `path` is a file this filters for lines with a match.
>   When `path` is a directory,
>   it switches to depth-first traversal, only returning files
>   that include a match (shown as its path from `path` without
>   suffix, to match how edit takes a context), then the matching
>   file lines, and then a line indicating the number of
>   occurrences in that file: `*6|STRING`.
>   Directories starting with `.` and symlinks are not traversed.
> * after? number
>   Also include this many additional file lines after a matching
>   grep file line.
> * before? number
>   Also include this many additional file lines before a matching
>   grep file line.
> * find? string
>   Activates search mode for matching file or directory names,
>   answering with directory content lines, suffixes and all.

#### :toolbox:edit
> > Modifies files, creating them and any missing
> > parent directories if they don't exist.
> `m8` `call` `edit`
> * path string
>   The relative or absolute path to a file or directory
>   as the base context for edits.
> * changes string
>   Lines describing the changes to make.
>   A context line sets the file subsequent lines apply to,
>   relative to `path`:
>   * `/subpath` sets a file.
>   Contexts are independent and may appear in any order.
>   Before any context line, the context is `path` itself,
>   which must then be a file. A change reaching across files
>   is a context each.
>   Substitution lines replace text within the current file:
>   * `*6|STRING` followed by `:SUBSTITUTION` lines replaces
>     every occurrence of `STRING` with the substitution,
>     failing unless exactly 6 are found in that file, as the
>     view tool would give.
>   * Search matches within lines only, but can substitute in
>     any number, with multiple `:SUBSTITUTION` lines
>     joining with newlines.
>   Line edits apply to the current file:
>   * `=123|LINE` asserts line 123 is `LINE`, and anchors an
>     insert after it.
>   * `-123|LINE` removes line 123, asserting it is `LINE`.
>   * `|LINE` inserts `LINE` after the line referenced by the
>     preceding `=` or `-`. Consecutive inserts land in order.
>     Use `=0|` to anchor at the start of the file, and anchor
>     to the last content line to append.
>   All line numbers reference the file before any change is made,
>   and must match what the view tool would give.
>   All changes are validated first, then substitutions are applied,
>   then removals and inserts. The entire edit fails unless every
>   assertion holds, and fails if a substitution and a line edit
>   affect the same line.

On failure it reports what didn't hold, and only that. What
was expected is what the edit asserted, so only the actual
is reported. A denial is a rejection rather than a view, and
says the picture of the file is stale, so it is not written
in the form view gives and is never edited against:
```
Denied - line 333 is `foo foo`
Denied - 4 occurrences of `getUser`
```

# ====

The bet — line addressing rather than multi-line matching.

A search stays within a line. Other formats match across
lines because they refuse line numbers, and a block of
surrounding context is how they say "this one, not the other
five". m8 says that with the number and asserts it, so a
multi-line search is a second mechanism for a job already
done — and the one imported to work around the bet.

What the bet protects is the correspondence. `*6|getUser`
out of a view grep is the same line going into an edit, and
that holds because a count is of a single-line literal. A
search spanning lines either drags grep across them too, or
makes the correspondence conditional, and "sometimes
identical" is a weaker thing to have built.

The bet is on models rather than on the format, so an
evaluation settles it and an argument does not. Adding a
multi-line search later stays compatible, and removing one
does not, so it waits until something forces it.

What forces it is a file of identical lines with a change
wanted to one of them. Nothing within a line separates them
and only the number can, so a model either reaches for a
line edit, widens until it finds it cannot, or tries to
spell a search across lines and is denied. A first wrong
attempt says nothing. A second of the same shape after a
denial is the format failing to teach itself, and is what a
multi-line search would be bought with.

# ====

M8_ARG_FOO=blah M8_ARG_BAR=grrr m8 call -k foo -a bar – echo
–foo=blah grrr

Also parsing out things.

Ideally replacing the placeholder expansion defined in the inline code span toolbox language.

# ====

Tools for move, copy, delete.

# ====

So the paper gap is there. Nobody has measured how often a human edits a file while an agent has it in context, and nobody has compared edit-format robustness under that condition. The specific contribution you'd be making:
Line-assertion as fine-grained OCC — sits between STORM's file-level versioning (over-rejects) and CRDT merging (silently produces semantic conflicts). Nobody occupies that middle.
Human-in-the-loop concurrency, which the multi-agent literature systematically ignores because worktree isolation solves their version and can't solve yours.
The transcription-vs-hallucination distinction — still unmeasured as far as any of these searches go, and it's the empirical claim the whole field's line-number rejection rests on.
The cheapest credible experiment for #3 alone: same model, same tasks, your format vs. a search/replace baseline, with a scripted process making small edits to target files at random intervals to simulate a human. Measure denial rate, denial reason, and silent-wrong-edit rate. That last number is the one nobody has, and it's the one that would make the paper.

# ====
Attach binary files like images?

# ====
Allowed minions and peers?

# ====
How deal with Linux vs osx on sandbox

# ====
m8-st8 core and open areas. core can never be written to by a tool.
defaults inside @/core/defaults/
#### :brain:/core/defaults/
# ====
sandbox-exec with a process-exec filter

# ====
Allow some git commands by only unlocking .git when it's constrained. How does this mix with glob limited commands.

# ====

In  chat subagent forking with > > 

# ====
match workstreams with agents and mobs chats.

# ====
Concurrent edit resilient editing
(stamp read state uuid? timestamp? Updated on write? Check opened? writeIf)
====

@.../ -> load all skills and sub-agent (if md) or all sub-agents in mob.
Agents need to be able to advertise themselves as sub-agents though
A way to call a sub agent in the sandox… and not.

# ====
# Tightening

# ====
 the anthropic-messages codec places a breakpoint on the last record before the first 🙋. That's derivable from the ledger alone, needs no new sigil, and matches the "stable prefix first" ordering you already have. A codec is allowed to know its own api's quirks; that's what a codec is.

# ====
Skill finder minion - auto post :raising_hand: minions?


# ====

sigil for loading a file and sending it as an attachment - like an image etc.
use a reference.
ensure it complies with sandboxing...



# ====
Spin zmachine off into an isolated subcommand. Z-machine-m8 and do the same for everything else.
— commands become
m8-call—


# ====

m8 cat … (gives full file)
m8 top … (gives top only)
m8 load … (gives bottom only)

# ====

Consider swarm name. Mob->Swarm? Use for something else?
Swarm intelligence?

# ====

Sub (@) and peer (@+) agents with protections and agent access controls.
Allow agent to spawn a peer agent session from a sub agent?
Native sigils projected to tool calls?

# ====

git friendly storage of .m8-st8 of a project.

e.g: + sessions always changing?
changing an agent changes chat histories?

# ====

Other common LLM providers / Anthropic / OpenAI / Google?
setup api.

# ====

COMMON TOOLBOXES

Standard ones out there esp for coding.

Think about standardised file sectioning for anything that supports comments, etc.
(`.* ___...--->>>> # SECTION HEADING NAME <<<<---...___ .*`).
Built into tools.

Plugin support -> look first for tool cmds in m8-st8 folders? Think about tool freezing...

# ====

MOB DOWNLOADER

Mob downloader with lock enforcer.
Mob level locks -> "everything under here inherits this brain fragment".

# ====

CROSS OS SUPPORT

* Windows -> anything that locks in a container way falls back to a DENY.
* Linux -> initially like Windows, eventually implementing it's own containerisation system.

# ====

COMMAND ARGS EXTRA

Support ^SKILL
Support session creation?
User calling a tool at a chat?

```
@AGENT - ask an agent, resetting it's named chat.
+CHAT - continue a chat.
... @CHAT - creates freshly named chat if an agent of the same name doesn't exist.

^SKILL - include agent as skill (book in m8)

-- [QUERY] ... - supply user prompt
```

# ====

ORGANISE M8-ST8

Agent definitions search for peers by relative reference going outwards up mob levels.


Note that in the future we may implement persistant chats ongoing between
agents using send_message to each other by referencing

?? How shoud send_message (to another agent) work?
Do we set up persistent chats under a mob?

```
.m8-st8/@/=/REF.m8
.m8-st8/@/+/CHAT.m8
.m8-st8/@/[MOB]/AGENT.m8

.m8-st8/@/+/[SESSION]/CHAT.m8
```

# ====

CONSIDER DISCARED MODEL RESPONSE PARAMS

  No — the turn is about a quarter of it. A chat-completions response is four things:

  1. The turn — choices[0].message: content, tool_calls, and depending on provider refusal and reasoning content. This is the only part m8 keeps.
  2. How it stopped — finish_reason: stop, length, tool_calls, content_filter. (Anthropic: stop_reason — end_turn, max_tokens, tool_use, refusal.)
  3. What actually answered — model resolved to a concrete build, since asking for an alias gets you a dated snapshot back; plus id, system_fingerprint, service_tier.
  4. Accounting — usage: prompt/completion/total, and details like cached prompt tokens and reasoning tokens.

  Streaming is the same shape with delta for message, and usage only arrives in a final chunk if you ask via stream_options.include_usage.

  Sorted by the line you just drew

  Same distinction as requests — what happened, versus what belonged to this run:

  - finish_reason is a ledger fact, and m8 drops it. provider.zig reads content and tool_calls and nothing else. So when a reply is cut off at max_tokens, the ledger records a 🤖 that is
    indistinguishable from a complete answer — it says the model finished when it didn't. Worse than cosmetic: continuing that chat silently feeds the model its own severed sentence as
    though it had meant to stop there. That's the one I'd call an actual "ledger is truth" violation.
  - Resolved model is arguably a ledger fact too. The 🧠 says what was asked for; the response says what answered. Recording it is what lets a replay know which build produced the text.
  - usage is real but it's about the run, not about what was said.
  - id, fingerprint, service tier are run metadata with no business in a ledger.

  One thing already anticipated, one constraint in the way

  💭 and 🔏 are already in the sigil table and map exactly onto reasoning content plus its signature — which some providers require you to send back verbatim or they reject the turn. The
  ledger foresaw the one part of a response that's neither text nor a call. Nothing populates them yet, but the slot is there.

  finish_reason has no such slot, and there's a constraint: 🤖 is content-only — takesValue() is false for .bot — so it can't ride on the header without touching the sigil table, and the
  sigil set is deliberately closed. That's a design question rather than a fix, so I'd rather put it to you than pick.

# ==== ZMachine Extras

- **Procedural generation.** A generator plus a seed yields infinite graded
  tasks — the real insight behind TextWorld (MIT licensed; its generation
  approach is legally reusable, though note its Z-machine backend wraps
  Jericho, which is GPLv2 via Frotz). Since the ledger already registers a
  seed derived from the first message, a ledger becomes a fully
  self-describing, portable game session.
- **Agent-as-user.** Recasting an agent as the user side and having two agents
  converse, with sandboxing. This wanted message roles to be first-class in the
  ledger rather than implied by position — which m8 already does: 🙋 and 🤖 are
  sigils, and the provider reads roles rather than counting positions. Nothing
  to build.
  The composition needs no new machinery either. An agent under test is given a
  🧰 whose 🔌 is `["m8", "+zork", "--", "{{command}}"]`; `+` carries the chat
  from turn to turn, and the tested agent never learns it is talking to a VM
  rather than to a model.
- **Glulx provider.** Separate VM, larger address space, Glk I/O including
  hyperlink events. Roughly doubles reach into modern IFComp entries.


# ====

Editor tools

Need to pick one.

Maybe need to make a few if models are tuned for them...

Not sure if the following is the right pick:

Implement a str_replace_based_edit_tool (Anthropic's text-editor tool convention).
Stateless interface: every call is fully self-contained (explicit path every time — no implicit cursor/current-file). Any state (undo history) lives server-side, keyed by file path, not in the conversation.
Commands (dispatched via a command field):
view — path (required), view_range (optional [start, end]). If path is a file, return numbered lines in that range (or whole file if omitted). If path is a directory, list contents up to 2 levels deep, skipping hidden files.
create — path, file_text (required). Fails if path already exists.
str_replace — path, old_str (required — must match exactly once in the file; error if zero or multiple matches, telling the caller to add more context), new_str (optional, empty = delete).
insert — path, insert_line (required — insert after this line number), new_str (required).
undo_edit — path only. Reverts the last edit made to that file.
Implementation requirements:
Maintain a small server-side history/snapshot per file path (e.g. save previous content before each mutating op) so undo_edit has something to revert to. This is the only real state — everything else is derived fresh from the filesystem each call.
Truncate very long view output with a note suggesting the caller grep for line numbers first, rather than dumping the whole file.
Return clear errors, not silent failures, on old_str uniqueness violations, missing files, or invalid line numbers.

# ====


# ====

Named Chats

Making a named chat:
m8 @quick +chat-session-name -- …
m8 +chat-session-name -- …

So essentially
m8 @quick …
Is just shorthand for:
m8 @quick +quick …

Forking a chat to a new name:
m8 @=/xxx +chat-session-name
m8 +chat-session-name -- …

====
Listing

m8 list agents [MOB]
Lists agents then sub-mob agents alphabetically.

m8 list chats [MOB]

…

# ====

Mob chats

IDEAS CURRENTLY ALL OVER THE PLACE

m8 @quick +teamy/
m8 @review +teamy/
m8 @thinker +teamy/
m8 @big ^plan ^manager ??????? +teamy/orchistrator
m8 +teamy/orchistrator -- 'get everyone to do something cool'

m8 @quick @teamA/coder
m8 @think @teamA/review
m8 @big @teamA/lead
m8 @teamA/ ??? who is the lead??

Or maybe we keep the argument interface simpler and put the complexity in the mob definition. Certainly anything that can be done there shouldn't be also done in the arguments.

LONG FORM:
m8 call minion -m {mob} -a {AGENT} [--as CHAT] -- {prompt}
m8 call mate -m {mob} -c {CHAT} [--as CHAT] -- {prompt}

TOOL: minion
m8 @{mob}AGENT -- "prompt"

TOOL: mate
m8 +{mob}AGENT -- "prompt"

Use minion to reset a peer.
Use minion to reset yourself.
m8 @{self}

m8_st8/+/MOB/

* Support magic tool parameter {mob} (same mob as agent, adds /suffix if not top level)
* Are tool parameter values comparable with templates?


Where to record progress?



# ====

Specify the format independently of the Zig implementation, sooner than
  feels necessary. The moat is the data model and the format collapse,
  not the CLI, and a second implementation is the proof of it.

# ====

~/.config/m8-st8/core/providers.json has a good default for url.
Should we add to the default one some basic setups like for claude / openai etc?
Is that too opinionated?
There are some Mac commands in there for key access.
Maybe we just make a folder of example setups.


# ====
Rename CALL_ID with propper prefix M8_CALL_ID

# ==== DONE

Inline `{{ARG}}` injection in an argv comes out of the framework. The
environment is the only way a call is carried, and `m8 call args` expands it
from outside. Specified above under M8 CALL ARGS.
