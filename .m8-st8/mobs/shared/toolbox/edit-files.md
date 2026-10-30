
* :toolbox::write
* :toolbox::write
  > > Edit a file. Either replace matches of an old_string, or
  > > leave old_string empty to append into a new or existing file.
  > > Attempt exact matches to avoid falling below match tolerance.
  > > Must only match once if using multiple lines to replace.
  > > Pages may be used to scope matches.
  >
  > :shield:workbench
  > :shield:secure contain-reads
  > `m8` `call` `--md` `m8` `munge` `{{pages}}` `write` `{{old_string|--old}}` `--` `{{path|}}` `{{new_string|}}`
  > * path string
  >   Path of the file to edit or create (relative, absolute, or ~).
  > * new_string string
  >   The text to insert.
  > * old_string? string
  >   The text to replace. Omit to write or append.
  > * pages? string
  >   Page range to scope the matches during replace e.g.
  >   "10-10" or "11-20" or "21-100", or "2@string_match" to
  >   scope within 2 pages starting at string match.

