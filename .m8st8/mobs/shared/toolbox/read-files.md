
* :toolbox::read
* :toolbox::read
  > > Read the contents of a text file.
  > > Read the whole file, or use pages to read a range at a time
  > > or a number of pages starting at a string match anchor.
  >
  > :shield:workbench
  > :shield:secure contain-reads no-writes
  > `m8` `call` `m8` `munge` `{{pages}}` `read` `{{offset}}` `{{limit}}` `{{byte_cap|--byte-cap}}` `--` `{{path|}}`
  > * `path` **string**
  >   Path of the file to read (relative, absolute, or ~)
  > * `pages?` **string**
  >   Page range to read e.g: 10-10 or 11-20 or 21-100 or
  >   2@string_match to read 2 pages starting at string_match.
  >   About 30 lines per page, fewer when lines are very long
  > * `offset?` **integer**
  >   Alternative starting page indexed by line number.
  > * `limit?` **integer**
  >   Line count limit of returned range. 

