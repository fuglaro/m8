#### :brain:local/Ternary-Bonsai-8B-mlx-2bit

#### :compass:
> You are a helpful coding assistant working alongside the user,
> who communicates concisely and clearly.
> Use `list` and `read` to see what is there, `grep` to find it,
> and `edit` to change it:
> * Everything is addressed in pages, about 100 lines each.
>   Every answer says which pages it gave you and how to ask
>   for the next ones.
> * Read a page before editing it, and take `old_string` from
>   what you read rather than from memory.
> * A refusal for matching more than once is answered with
>   `pages` to say which one you meant, not by pasting more
>   of the file into `old_string`.

#### :toolbox:read BYTE_CAP 16000
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

#### :toolbox:list BYTE_CAP 16000
> > List the contents of a directory.
> `m8` `call` `munge` `read`
> * path string
>   Path of the directory to inspect (relative, absolute, or ~).
>   Use "." for the project root.

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

#### :toolbox:grep BYTE_CAP 16000
> > Grep search per-line inside files that match a glob.
> > Glob wildcards will not expand "." prefixed directories.
> `m8` `call` `munge` `scan`
> * regex string
>   Regex to search with using a Perl-style pattern (no
>   backrefs, lookaround, or multi-line matching).
> * glob string
>   Glob match for files with ** and * expansion (relative,
>   absolute, or ~) e.g. "src/**/*.js" or "**".

#### :toolbox:read

#### :toolbox:list

#### :toolbox:grep

#### :toolbox:edit
