# The language

The format, in enough detail to write a parser from. An agent, a transcript,
a wire request and a tool exchange are all written in it.

## Language and Schema

Agent definition:

```m8
▐ 🧠:Address, Agent Name or Model

▐ 🧰:Tool Name
│ │ Tool Description
│
│ 🛡️ShieldName
│ `m8` `call` `cmd` `{{propertyname|--flag}}`
│ * PropertyName string
│   Property Description
│ * Other? integer
│   Optional, so ? on the name

▐ 🏃:bash
│ `m8` `call` `bash` `-e` `-c`

▐ 🧰:Tool Name
│ │ A fenced block runs through the 🏃 it names.
│
│ ```bash
│ echo "$__propertyname__"
│ ```
│ * PropertyName celsius|fahrenheit
│   An enum is its values, which may hold a space
│ * PropertyName string[]
│   Arrays suffix []
│ * ParentName object
│   Mandatory Parent Def
│ * ParentName.PropertyName integer
│   Nested

▐ 🧰:Tool Name

▐ 🛡️:ShieldName

▐ 🧭:
│ System Prompt
│ A record is a header and a content block, and
│ content is verbatim, so this line may begin with
│ anything at all.
│ A , separates a fixed number of fields, so the
│ last field may hold one safely.

▐ 🧭:
│ Included Agents inject Tools and System
│ Prompts.
```

> * :brain::Address, Agent Name or Model
>
> * :toolbox::Tool Name
>   > > Tool Description
>   >
>   > :shield:ShieldName
>   > `m8` `call` `cmd` `{{propertyname|--flag}}`
>   > * PropertyName string
>   >   Property Description
>   > * Other? integer
>   >   Optional, so ? on the name
>
> * :runner::bash
>   > `m8` `call` `bash` `-e` `-c`
>
> * :toolbox::Tool Name
>   > > A fenced block runs through the 🏃 it names.
>   >
>   > ```bash
>   > echo "$__propertyname__"
>   > ```
>   > * PropertyName celsius|fahrenheit
>   >   An enum is its values, which may hold a space
>   > * PropertyName string[]
>   >   Arrays suffix []
>   > * ParentName object
>   >   Mandatory Parent Def
>   > * ParentName.PropertyName integer
>   >   Nested
>
> * :toolbox::Tool Name
>
> * :shield::ShieldName
>
> * :compass::
>   > System Prompt
>   > A record is a header and a content block, and
>   > content is verbatim, so this line may begin with
>   > anything at all.
>   > A , separates a fixed number of fields, so the
>   > last field may hold one safely.
>
> * :compass::
>   > Included Agents inject Tools and System
>   > Prompts.

A shield activation is `ShieldName [Names...]`. The optional names replace its
default identity argument and accumulate across activations; the wrapper runs
once and receives the names as one space-separated argument. See [Shields](shields.md).

Required top-level tool enums are checked before the command runs, using the
converted argument strings (so `true` and `"true"` match the same enum item).
Optional enums, nested fields, and enum arrays are not checked.

Query:

```m8
▐ 🧠:Agent or Model Name

▐ 🙋:
│ User Content Text

▐ 💭:
│ Assistant Thoughts
│ 🔏`Optional Signature`

▐ 🤖:
│ Assistant Content Text

▐ 📲:Called Tool Name,Call ID

▐ 🚫:Call ID
│ Error response

▐ 📲:Called Tool Name,Call ID
│ * Argument Name `value`
│ * Argument Name
│ * Argument Name
│   ```
│   a value over
│   more than one line
│   ```

▐ 🧾:Call ID
│     Response

▐ 🔗:Call ID
│ <path/to/file.jpeg

▐ 🟢:Call ID
```

> * :brain::Agent or Model Name
>
> * :raising_hand::
>   > User Content Text
>
> * :thought_balloon::
>   > Assistant Thoughts
>   > :lock_with_ink_pen:`Optional Signature`
>
> * :robot::
>   > Assistant Content Text
>
> * :calling::Called Tool Name,Call ID
>
> * :no_entry_sign::Call ID
>   >     Error response
>
> * :calling::Called Tool Name,Call ID
>   > * Argument Name `value`
>   > * Argument Name
>   > * Argument Name
>   >   ```
>   >   a value over
>   >   more than one line
>   >   ```
>
> * :receipt::Call ID
>   >     Response
>
> * :link::Call ID
>   > <path/to/file.jpeg
>
> * :green_circle::Call ID

A call is answered by what the tool said and then by
how it went. 🧾 is the saying, and it is written while
the tool is still speaking; 🟢 and 🚫 are the verdict,
which nothing can know until it stops.

📜 is a 🧾 meant to be read as markdown. A 🧾 is literal,
so its block is indented four spaces inside the quote, and
anything rendering the file shows it as code. 🚫's optional
verdict block is indented the same way. A 📜 is carried
as it is. A tool may answer with both, and the
model is handed them joined in order; one mixing literal
blocks into markdown writes a single 📜 with its own
fences.

That order is the reason there are three. A record
names its kind on its first line, so a single record
meaning "it worked, and here is what it said" cannot
be started until the program has finished — which is
to say the output would have to be held in full,
however large it is, so that the first line could be
written last. Splitting the verdict off is what lets
the answer be written as it arrives.

A tool that says nothing is answered by its verdict
alone. 🧾 without a verdict under it is a tool that
spoke and was cut off; it still answers the call,
because running it again to find out how it would
have ended would do whatever it does a second time.

What a call supplies is a bullet per argument, including any
parameter the model supplied that the tool does not define.
Property order is preserved. The spelling carries the type;
reading a call does not require the tool's schema.

An absent argument has no bullet. Null has a bare bullet,
with nothing after its name. Inline values are JSON inside
code spans: numbers and booleans are unquoted, strings are
quoted, and the empty string is a span containing `""`.
Thus a string spelling `"123"` or `"null"` stays a string.
There is no special bare `""` form.

A string needing JSON escapes for quotes, backslashes, tabs
or newlines uses a `text` fence with its literal contents.
If it contains non-portable control characters, such as NUL
or carriage return, it instead uses a `json` fence holding a
JSON-escaped string. Unicode escapes are supported there.
A `text` fence always means a string; a `json` fence, like a
code span, is parsed as JSON. Unlabelled fences are not an
argument spelling.

Arrays and objects use compact JSON in a span. When the
rendered line would exceed 100 characters, they instead use
pretty-printed JSON in a `json` fence.

Fences are indented under the bullet. The closing fence ends
the value, so the newline before it is framing. A literal
string ending in a newline has a blank line before the close.

A call that does not read this way is malformed. It is kept
as written and answered with a ❌, and an api is sent it with
no arguments.

Backticks are CommonMark's, so a span opens with a run
longer than any run inside it and a fence with one at
least as long as anything it holds:

```
``"`"``      a string that is one backtick
``"a`b"``    a run ends at a run of its own length
```

So a human reads the value with nothing escaped but its
quotes, and what m8 reads is what the thing rendering the
document shows. That is the whole reason for taking
CommonMark's rule rather than a simpler one: the moment
they differ, a document says one thing to a person and
another to m8.

Simple example query with definition:

```m8
▐ 🧠:/local/Ternary-Bonsai-8B-mlx-2bit,max_output_tokens:8192

▐ 🧭:
│ You are a mathematics expert that will answer questions,
│ give insight, and advise on any relevant technique.
│ Describe concepts with analogies and spatial models
│ that can be imagined by a human and include how it relates
│ to the components, equations, and relationships in
│ the mathematical equations.

▐ 🙋:
│ Tell me about the Riemann Sphere in detail.
```

> * :brain::/local/Ternary-Bonsai-8B-mlx-2bit,max_output_tokens:8192
>
> * :compass::
>   > You are a mathematics expert that will answer questions,
>   > give insight, and advise on any relevant technique.
>   > Describe concepts with analogies and spatial models
>   > that can be imagined by a human and include how it relates
>   > to the components, equations, and relationships in
>   > the mathematical equations.
>
> * :raising_hand::
>   > Tell me about the Riemann Sphere in detail.

System Prompt is stable by design.
Volatile data such as the time or when reading
files, should be put into the query,
with user content text or a user added tool request.
📚Skills can also be included, which are predefined
sections of query, including tool requests to be invoked,
and which are referenceable by name.

A record is a header line and at most one content
block. The header is a sigil, a `:`, and its value;
the content is the block quoted beneath it. In
markdown the header is a list item and the quote is
indented two spaces under it, so a renderer shows each
record as one item holding its block. A sigil without
its `:` is an error, which is also what lets a first line
tell a document from a bulleted prompt. That is the
whole of the harness. Content never nests further
and records never interleave.

Exactly one space follows the quote and is stripped,
so content is verbatim and a line that looks like a
record is only a line. Missing that space is an
error. A bare quote with no space is an empty
content line. A 🧾's lines are indented four spaces
more, which is stripped the same way; missing them is
an error too, except on an empty line. A fully blank line closes the block.
Headers may follow one another without a blank line;
writers may use blank lines between records for
readability.

Sigils are a closed set, written as one codepoint
within U+1F300 to U+1FAFF or U+2700 to U+27BF, or as
`:word:`. An unknown sigil in either spelling is an
error.

An emoji sigil may be followed by presentation
modifiers — a variation selector, a skin tone, or a
joiner binding another codepoint into the glyph — and
they belong to the sigil, not to the value behind it.
A renderer adds them without being asked: Slack shows
🙋 as 🙋‍♀️. Text pasted back from one still reads as
the sigil it looks like.

A `,` separates a fixed number of fields, so the
last field may hold one safely. What a content block
means is decided by the sigil above it.

A \r immediately before a \n is stripped, exactly
one, so \r\r\n ends content in a literal \r.

## Packed spelling

* Packed spelling keeps each record on one physical line.
  * Its header starts with `- ` instead of `* `.
  * Each physical newline inside a record becomes `↵`;
    quote prefixes and indentation are retained.
  * A literal `↵` is written `↵↵`, including in header values.
  * The physical newline ending a packed record is framing, not content.
* For example, these records carry the same content:

```text
* :robot::
  > first
  > second

- :robot::↵  > first↵  > second
```

* Packed and block records may be mixed in one markdown document.
  * Separator newlines between records are unchanged by `m8 cat`.
  * An unpacked record's literal arrows need no escaping.

* Providers receive only block spelling.
  * The harness normalizes packed records before invoking a provider or encoder.

## Unwrapped projection

* `m8 cat --unwrap` projects records to ordinary Markdown.
  * A nonempty value becomes a `# VALUE` heading.
  * Content follows the heading after a blank line, without its quote framing.
  * No value means no heading; no content means just the heading.
  * Literal receipt content keeps its four-space indent.
  * Packed records are decoded before projection.
  * Adjacent records are separated by a blank line.
* This is a reading format, not parsable m8 syntax.
* A question such as `- :question::tool,call_123↵  > Which directory?`
  becomes:

```markdown
# tool,call_123

Which directory?
```

## Sigils

Every sigil has two spellings, an emoji and a plain
one. Both are accepted anywhere a sigil is accepted
and they mean the same thing. Output is emoji by
default, and either form can be asked for.

The emoji is the default because a tool's output is
the language itself. The raw bytes are what a human
reads, so a column of emoji down the left edge is
the formatting. One glyph per record kind, told
apart at a glance, with no renderer, no colour and
no pager. The records need no pretty-printing because
m8 already looks like that; a terminal only colours the
markdown inside them.

The plain form exists to ease typing from scratch.
The one real cost is paid at the keyboard,
and so it is answered at the keyboard
rather than by giving up the display.

The two spellings never mix. A document is `m8` or
it is `m8.md`, decided by its first line and held
for the rest of it, and a line in the other spelling
is an error. Files and piped streams are `m8.md`,
which is also valid markdown, so anything that
renders markdown renders them. A tty gets `m8`.

* ▐ header -> `*`
* │ content -> `  >`
* 🧠 agent -> `:brain:`
* 🙋 user -> `:raising_hand:`
* 🤖 bot -> `:robot:`
* 💭 thinking -> `:thought_balloon:`
  * 🔏 signature -> `:lock_with_ink_pen:`
* 📲 call -> `:calling:`
* 🧾 result -> `:receipt:`
  * 📜 scroll -> `:scroll:`
* 🔗 link -> `:link:`
* 🟢 ok -> `:green_circle:`
* 🚫 failed -> `:no_entry_sign:`
* 📚 skill -> `:books:`
* 🔝 top -> `:top:`
* 🧭 system -> `:compass:`
* 🛡️ shield -> `:shield:`
* 🏃 runner -> `:runner:`
* 🧰 tool -> `:toolbox:`
* ❓ question -> `:question:`
  * ❗ exclamation -> `:exclamation:`

A sigil takes a value, a content block, or both — or, for the
one that is a fence rather than a record, neither. A 💭 without a
block uses its value as a compact one-line thought. Its `snip` value
is special only when that same 💭 also has a block; otherwise it is
simply the one-line thought `snip`. 🧰 has three separate header
forms: a content-bearing header defines a tool, a blockless header
with a variable and values configures that tool, and a bare blockless
header offers it. A definition header may not combine content and
variable configuration.

* Value only: 🧠 📚 🔏 🟢 💭
* Content only: 🙋 🧭
* Both: 🤖 🧰 📲 🧾 📜 🔗 🚫 🛡️ 🏃 ❓ ❗
* Neither: 🔝

### Stopping Short

A reply the model did not finish ends with a 🤖 that has a
value and nothing under it.

```m8
▐ 🤖:
│ Moonlight on still ponds
│ Crickets stitch the

▐ 🤖:(cut off at max_output_tokens)
```

> * :robot::
>   > Moonlight on still ponds
>   > Crickets stitch the
>
> * :robot::(cut off at max_output_tokens)

* The value is `(words term)`.
  * The words are for whoever reads the transcript.
  * The last word is the provider's own term, untouched.
* Finishing, and asking for tools, say nothing - the ledger
  already shows both.
* A provider that returns neither a reply nor a tool call leaves
  `🤖(no response)`. The invocation happened, so the ledger says so.
* m8 carries it and never reads it.
  * No loop decision is made on it - a call made while
    bailing runs as asked.
  * It is between the provider and the reader, or whatever
    matches on the last word.
* No api takes it back, so encoding drops it.
* Each codec says its own terms:
  * `cut off at` - out of output tokens
  * `context full at` - out of context window
  * `filtered by` - a content filter
  * `declined with` - a refusal
  * `declined by CATEGORY` - a refusal naming its policy
  * `paused at` - a paused server-side turn
  * `MESSAGE - failed with` - an error from the api,
    with what it said ahead of the words
  * `stopped at` - a stop sequence, or a term not yet known

### Kept Aside

A 💭 whose value is `snip` and which has a block asks for what it
holds to be kept out of the way. Keeping it writes a snip, and leaves
the 🧠 naming it in its place. Without a block, `💭snip` is simply the
compact one-line thought "snip".

```m8
▐ 💭:snip
│ 🔏`c2lnbmF0dXJl`

▐ 🧠:demo/mathy/+/snip-oniwhbxumk
```

> * :thought_balloon::snip
>   > :lock_with_ink_pen:`c2lnbmF0dXJl`
>
> * :brain::demo/mathy/+/snip-oniwhbxumk

A compact thought keeps its text on the header:

```m8
▐ 💭:Checking the result
```

> * :thought_balloon::Checking the result

Providers should use this compact form for one-line thought summaries when
possible, and must interpret a value-only 💭 as thought text when reading it.

* Which thoughts ask is the codec's decision.
  * A signature is the case today - it exists only to be handed back.
* A snip is a file holding the `💭snip` as it was written.
  * Its name is `snip-` and ten random letters.
  * `snip-` and a turn's ten letters never collide.
* The 🧠 is an inclusion like any other.
  * Nothing reads a snip specially.
  * Reading a ledger gives a codec exactly what it wrote.
  * Keeping what was read keeps it aside again.
* A snip goes beside the turn that names it, in its `+/`.
* `m8 :MOB/AGENT` keeps one as it arrives.
  * The 🧠 shown is the file written.
* `m8 send` keeps nothing, so what it writes carries the `💭snip` whole.
  * `tag` writes the snip with the turn.

### Handing Over Files

A 🔗 hands files to the model beside what a tool said.

```m8
▐ 📲:see,c1
│ * file `"shot.png"`

▐ 🔗:c1
│ <+/crew/^/see-shot-c1.jpeg (9f86d081b8…)

▐ 🟢:c1
```

> * :calling::see,c1
>   > * file `"shot.png"`
>
> * :link::c1
>   > <+/crew/^/see-shot-c1.jpeg (9f86d081b8…)
>
> * :green_circle::c1

* Its value is the call it answers, as a 🧾's is.
* Each line opening with `<` names a file.
  * m8 reads no further: the rest is between the tool that
    wrote it and the entry's `upload`.
  * In what `encode` hands a codec, each is written over as
    `>MIME URI NAME`, as `upload` said it. See [Uploading](providers.md#uploading).
* Cody's `see` and the [upload scripts](providers.md#uploading) agree on
  `<path (SHA-256)`.
  * The path is absolute, or relative to a config
    directory, found nearest first as a name is.
  * The hash is what the file held when it was linked. The
    scripts refuse a file that holds anything else, so a
    tool hands over only what it could read.
  * An `upload` that skips the check trusts every tool's
    links, whatever they name.
* Where a file lives, and whether it stays, is the tool's.
  * `see` writes directly into `$M8_MOB_DIR/.uploads/` as
    `see-STEM-CALL_ID.jpeg` (or `.pdf`), with the input's
    final extension removed from its filename to form `STEM`.
* A tool writes its 🔗 itself, through `m8 call --no-wrap`.
  See [Calling](commands.md#calling).
  * A `bash records` block, for a file it keeps under `$M8_MOB_DIR/.uploads/`:
    ```bash
    printf '* :link::%s\n  > <%s (%s)\n' "$M8_CALL_ID" "$part" "$hash"
    ```
  * The runner adds the verdict.
* How a file reaches a model is the provider entry's
  `upload`. See [Uploading](providers.md#uploading).
  * Chat completions shows them in a message of the
    person's after the answers, since a tool message holds
    text alone.

### Tops

A file may open with a 🔝 and close it with a second one.
What is between them is that file's top: what it says
about itself, rather than what it says.

```m8
▐ 🔝:

▐ 🧭:
│ Load tight-docs when working on documentation.

▐ 🔝:

▐ 🧭:
│ Keep every doc comment to one line.
```

> * :top::
>
> * :compass::
>   > Load tight-docs when working on documentation.
>
> * :top::
>
> * :compass::
>   > Keep every doc comment to one line.

Two sigils reach into another file and the mark decides
which half comes back. 🧠 wants what the file says; 📚
wants what it says about itself. On the command line
those are `m8 say --no-send :MOB/AGENT` and `m8 top :MOB/AGENT`.

A file with no 🔝 is all body and has no top at all, so
📚 naming one yields nothing rather than the whole of
it. There is no advertisement, so nothing is advertised.

The fence is why it is two sigils and not one closing
delimiter: a reader knows which half it is in from the
first record rather than from the end of the file, so a
top is read without holding a body nobody asked for.
One 🔝 that nothing closes is an error, and so is one
anywhere but at the head.

The mark decides at every reference rather than being
inherited, so a top may advertise what it builds on and
a body may pull in a skill's advertisement. Neither
drags in the other, and a 🔝 never reaches a ledger.

## Types

An argument is a bullet: `* NAME TYPE`, and its
description on the lines indented under it. The name
runs to the first space and the type to the first comma,
so the last field may hold one safely and an enum keeps
whatever spaces its values have.

A type is JSON Schema's own and goes to the wire exactly
as it is written, so it is lowercase: `string`, `number`,
`integer`, `boolean`, `object`. There is no keyword for an
enum — a type holding a `|` is one, and its values are what
it lists.

Anything else JSON Schema says goes after the type as
`,key:value` extras — `* limit integer,minimum:0` — split
and read the way a 🧠's parameters are, so a value may be
JSON with commas of its own. m8 has no vocabulary for
them and checks none of it, a type included: a mistake
is found at the provider.

Type rules compose, so `Type[]` covers `object[]`.

* An array `[]` suffix applies to the whole field, and
  arrayness lives only on the parent type — children use
  plain dots.
* Enum values cannot contain a `|` or a `,`.
* Extras go on the outermost node, so an array's are the
  array's own; a key for its items is written as
  `items:{...}`.
* An extra sharing a key m8 writes itself, such as
  `description` over the lines under the bullet, stays in
  the ledger but loses on the wire: m8's own codecs send
  one key, and it is m8's.
* Nesting is flat dotted paths, and parents are always
  declared, never inferred.
* Optionality is a `?` on the name and applies at every
  depth, so an optional object with required children is
  either absent or complete.

There is no oneOf. A discriminator enum with optional
fields constrains better, and lets the tool return a real
error instead of a schema rejection.
