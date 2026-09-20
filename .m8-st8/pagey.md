#### :brain:/codex/gpt-5.6-luna,reasoning:{"summary":"auto"}

#### :compass:
> You are a helpful coding assistant working alongside the user,
> who communicates concisely and clearly.
> Use `list` to browse files, `grep` to find them,
> `read` to read files with pagination (~100 lines),
> and `edit` to edit scoped across read pages.

#### :toolbox:read
> > Read the contents of a text file.
> > Read the whole file, or use pages to read a range at a time
> > or a number of pages starting at a string match anchor.
> `m8` `call` `munge` `read`
> * path string
>   Path of the file to read (relative, absolute, or ~).
> * pages? string
>   Page range to read e.g. "10-10" or "11-20" or "21-100", or
>   "2@string_match" to read 2 pages starting at string_match.
>   About 100 lines per page, fewer when lines are very long.
#### :toolbox:read PAGE_LINES 100
#### :toolbox:read PAGE_BYTES 10000
#### :toolbox:read BYTE_CAP 20000

#### :toolbox:list
> > List the contents of a directory.
> `m8` `call` `munge` `read`
> * path string
>   Path of the directory to inspect (relative, absolute, or ~).
>   Use "." for the project root.
#### :toolbox:list PAGE_LINES 100
#### :toolbox:list PAGE_BYTES 10000
#### :toolbox:list BYTE_CAP 20000

#### :toolbox:edit
> > Edit a file. Either replace exact matches of an old_string, or
> > leave old_string empty to append into a new or existing file.
> > Must only match once if using multiple lines to replace.
> > Pages may be used to scope matches.
> `m8` `call` `munge` `write`
> * path string
>   Path of the file to edit or create (relative, absolute, or ~).
> * old_string? string
>   The text to replace. Omit to write or append.
> * new_string string
>   The text to insert.
> * pages? string
>   Page range to scope the matches during replace e.g.
>   "10-10" or "11-20" or "21-100", or "2@string_match" to
>   scope within 2 pages starting at string match.

#### :toolbox:grep
> > Grep search inside files matching a glob.
> > Glob descent skips hidden path components unless named explicitly.
> > Omitting regex will just glob files.
> `m8` `call` `munge` `scan`
> * regex? string
>   Regex to search with using a Perl-style pattern (no
>   backrefs, lookaround, or multi-line matching).
> * glob? string
>   Glob match for files with ** and * expansion (relative,
>   absolute, or ~) e.g. "src/**/*.js" or "**".
> * pages? string
>   Paginate results to browse through many matches e.g. "11-20".
#### :toolbox:grep PAGE_LINES 100
#### :toolbox:grep PAGE_BYTES 10000
#### :toolbox:grep BYTE_CAP 20000

#### :toolbox:bash
> > Run a bash command.
> `m8` `call` `args` `bash` `-euo` `pipefail` `{{M8_ARG_COMMAND|-c}}`
> * command string
>   The bash command to run.

#### :toolbox:webfetch
> > Download a web page for viewing.
> ```bash
> out=$(mktemp "$TMPDIR/$(printf %s "$M8_ARG_URL" | tr -cs A-Za-z0-9 - | cut -c1-200).XXXXXX")
> curl -fsSL --max-time 30 --max-filesize 10000000 -o "$out" "$M8_ARG_URL"
> echo "Downloaded for viewing at: ${out#"$PWD"/}"
> ```
> * url string
>   The url of the page to download.

#### :toolbox:read
#### :toolbox:list
#### :toolbox:grep
#### :toolbox:edit
#### :toolbox:bash
#### :toolbox:webfetch
