
* :toolbox::list
* :toolbox::list
  > > List the contents of a directory.
  >
  > :shield:workbench
  > :shield:secure contain-reads no-writes
  > `m8` `call` `m8` `munge` `read` `--` `{{path|}}`
  > * `path` **string**
  >   Path of the directory to inspect (relative, absolute, or ~).
  >   Use ./ for the project root

* :toolbox::grep
* :toolbox::grep
  > > Grep search inside files matching a glob.
  > > Glob descent skips hidden path components unless named explicitly.
  >
  > :shield:workbench
  > :shield:secure contain-reads no-writes
  > `m8` `call` `m8` `munge` `{{pages}}` `scan` `{{pattern|--regex}}` `{{path|--glob}}`
  > * `pattern` **string**
  >   Regex to search content using a Perl-style pattern (no
  >   backrefs, lookaround, or multi-line matching)
  > * `path?` **string**
  >   Glob match for files with ** and * expansion (relative,
  >   absolute, or ~) e.g: src/**/*.js
  > * `pages?` **string**
  >   Paginate output to browse through many matches e.g: 11-20

* :toolbox::glob
* :toolbox::glob
  > :shield:workbench
  > :shield:secure contain-reads no-writes
  > `m8` `call` `m8` `munge` `{{pages}}` `scan` `{{pattern|--glob}}`
  > * `pattern` **string**
  > * `pages?` **string**
  >   Paginate output to browse through many matches e.g: 11-20
