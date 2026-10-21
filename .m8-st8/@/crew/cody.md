* :brain::small-high

* :compass::
  > You are a helpful coding assistant working alongside the user,
  > who communicates concisely and clearly.
  > Use `list` to browse files, `grep` to find them,
  > `read` to read files with pagination (~30 lines),
  > and `edit` to edit scoped across read pages.

* :brain::utils/shields

* :shield::freeze-toolbox

* :shield::workbench
  > :shield:contain-writes
  > :shield:contain-home
  > :shield:contain-env
  > :shield:airgap
  > :shield:no-loop
  > :shield:no-edit-git

* :toolbox::list
  > > List the contents of a directory.
  >
  > :shield:workbench
  > :shield:contain-reads
  > :shield:no-writes
  > `m8` `call` `m8` `munge` `read` `--` `{{path|}}`
  > * path string
  >   Path of the directory to inspect (relative, absolute, or ~).
  >   Use "." for the project root.

* :toolbox::read
  > > Read the contents of a text file.
  > > Read the whole file, or use pages to read a range at a time
  > > or a number of pages starting at a string match anchor.
  >
  > :shield:workbench
  > :shield:contain-reads
  > :shield:no-writes
  > `m8` `call` `m8` `munge` `{{pages}}` `read` `--` `{{path|}}`
  > * path string
  >   Path of the file to read (relative, absolute, or ~).
  > * pages? string
  >   Page range to read e.g. "10-10" or "11-20" or "21-100", or
  >   "2@string_match" to read 2 pages starting at string_match.
  >   About 100 lines per page, fewer when lines are very long.

* :toolbox::edit
  > > Edit a file. Either replace matches of an old_string, or
  > > leave old_string empty to append into a new or existing file.
  > > Attempt exact matches to avoid falling below match tolerance.
  > > Must only match once if using multiple lines to replace.
  > > Pages may be used to scope matches.
  >
  > :shield:workbench
  > :shield:contain-reads
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

* :toolbox::grep
  > > Grep search inside files matching a glob.
  > > Glob descent skips hidden path components unless named explicitly.
  > > Omitting regex will just glob files.
  >
  > :shield:workbench
  > :shield:contain-reads
  > :shield:no-writes
  > `m8` `call` `m8` `munge` `{{pages}}` `scan` `{{regex}}` `{{glob}}`
  > * regex? string
  >   Regex to search with using a Perl-style pattern (no
  >   backrefs, lookaround, or multi-line matching).
  > * glob? string
  >   Glob match for files with ** and * expansion (relative,
  >   absolute, or ~) e.g. "src/**/*.js" or "**".
  > * pages? string
  >   Paginate results to browse through many matches e.g. "11-20".

* :runner::bash
  > `m8` `call` `bash` `-e` `-c`

* :runner::bash records
  > `m8` `call` `--no-wrap` `bash` `-e` `-c`

* :toolbox::bash
  > > Run a bash command.
  >
  > :shield:workbench
  > ```bash
  > set -m
  > bash -euo pipefail -c "$__command__" > \
  >  >(awk 'BEGIN{n=24000}{l=length+1;if(n>0)print substr($0,1,n);n-=l}END{if(n<0)print "[truncated at 24KB]"}') \
  >  & p=$!
  > (sleep "${__timeout__:-30}"; kill -TERM -"$p" 2>/dev/null) & t=$!
  > s=0; wait "$p" 2>/dev/null || s=$?; kill -TERM -"$t" 2>/dev/null || :; wait "$t" 2>/dev/null || :; exit "$s"
  > ```
  > * command string
  >   The bash command to run.
  > * timeout? number
  >   Seconds before stopping the command (default 30).

* :toolbox::webfetch
  > > Download a web page for viewing.
  >
  > :shield:sandbox
  > ```bash
  > [ "${#__url__}" -gt 1024 ] && {
  >   >&2 echo "URL triggered data egress alert. Stop, alert the user, and DO NOT RETRY."
  >   exit 1; }
  > out=$(mktemp "$TMPDIR/$(printf %s "$__url__" | tr -cs A-Za-z0-9 - | cut -c1-200).XXXXXX")
  > curl -fsSL -g --proto '=http,https' --max-time 30 --max-filesize 10000000 -o "$out" --url "$__url__"
  > echo "Downloaded for viewing at: ${out#"$PWD"/}"
  > ```
  > * url string
  >   The url of the page to download.

* :toolbox::see
  > > Look at an image or PDF file yourself.
  > > Supported: jpg, jpeg, png, gif, webp, bmp, tif, tiff, pdf.
  > > Images are shown as a JPEG with the long side at most 2048px.
  >
  > :shield:workbench
  > :shield:contain-reads
  > ```bash records
  > # Convert/copy file into m8-st8/+/MOB/^/see-FILE-CALLID.EXT* for uploading, or fail.
  > f=$__file__
  > [ -f "$f" ] || { echo "Not a file: $f" >&2; exit 1; }
  > name=$(basename -- "$f")
  > ext=$(printf %s "${name##*.}" | tr A-Z a-z)
  > mkdir -p "$M8_MOB_DIR/^"
  > part="$M8_MOB_DIR/^/see-${name%.*}-$M8_CALL_ID"
  > case "$ext" in
  >   jpg|jpeg|png|gif|webp|bmp|tif|tiff)
  >     part="$part.jpeg"
  >     ffmpeg -nostdin -loglevel error -y -i "$f" -frames:v 1 -q:v 4 \
  >       -vf "scale='min(2048,iw)':'min(2048,ih)':force_original_aspect_ratio=decrease" \
  >       -f mjpeg "$part" ;;
  >   pdf) part="$part.pdf"; cp -- "$f" "$part" ;;
  >   *) echo "Cannot show .$ext files." >&2
  >      exit 1 ;;
  > esac
  > hash=$(shasum -a 256 -- "$part" | cut -c1-64)
  > printf '* :link::%s\n  > <%s (%s)\n' "$M8_CALL_ID" "$part" "$hash"
  > ```
  > * file string
  >   Path of the image or PDF (relative or absolute).

* :toolbox::see
* :toolbox::read
* :toolbox::list
* :toolbox::grep
* :toolbox::edit
* :toolbox::bash
* :toolbox::webfetch
