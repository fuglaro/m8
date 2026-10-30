
* :toolbox::list
* :toolbox::list
  > > List the contents of a directory.
  >
  > :shield:workbench
  > :shield:secure contain-reads no-writes
  > `m8` `call` `m8` `munge` `read` `--` `{{path|}}`
  > * path string
  >   Path of the directory to inspect (relative, absolute, or ~).
  >   Use "." for the project root.

* :toolbox::grep
* :toolbox::grep
  > > Grep search inside files matching a glob.
  > > Glob descent skips hidden path components unless named explicitly.
  > > Omitting regex will just glob files.
  >
  > :shield:workbench
  > :shield:secure contain-reads no-writes
  > `m8` `call` `m8` `munge` `{{pages}}` `scan` `{{regex}}` `{{glob}}`
  > * regex? string
  >   Regex to search with using a Perl-style pattern (no
  >   backrefs, lookaround, or multi-line matching).
  > * glob? string
  >   Glob match for files with ** and * expansion (relative,
  >   absolute, or ~) e.g. "src/**/*.js" or "**".
  > * pages? string
  >   Paginate results to browse through many matches e.g. "11-20".

* :toolbox::read
* :toolbox::read
  > > Read the contents of a text file.
  > > Read the whole file, or use pages to read a range at a time
  > > or a number of pages starting at a string match anchor.
  >
  > :shield:workbench
  > :shield:secure contain-reads no-writes
  > `m8` `call` `m8` `munge` `{{pages}}` `read` `{{byte_cap|--byte-cap}}` `--` `{{path|}}`
  > * path string
  >   Path of the file to read (relative, absolute, or ~).
  > * pages? string
  >   Page range to read e.g. "10-10" or "11-20" or "21-100", or
  >   "2@string_match" to read 2 pages starting at string_match.
  >   About 30 lines per page, fewer when lines are very long.

