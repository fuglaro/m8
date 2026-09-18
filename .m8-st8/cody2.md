#### :brain:/codex/gpt-5.6-luna,reasoning:{"summary":"auto"}

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
> `m8` `call` `edline` `view`
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
> `m8` `call` `edline` `edit`
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

#### :toolbox:view

#### :toolbox:edit
