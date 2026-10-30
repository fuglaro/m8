
* :toolbox::webfetch
* :toolbox::webfetch
  > > Download a web page for viewing.
  >
  > :shield:workbench
  > :shield:secure private no-edit-m8-st8
  > ```bash
  > [ "${#__url__}" -gt 1024 ] && {
  >   >&2 echo "URL triggered data egress alert. Stop, alert the user, and DO NOT RETRY."
  >   exit 1; }
  > out=$(mktemp "$TMPDIR/$(printf %s "$__url__" | tr -cs A-Za-z0-9 - | cut -c1-200).XXXXXX")
  > curl -q -fsSL -g --proto '=http,https' --max-time 30 --max-filesize 10000000 -o "$out" --url "$__url__"
  > echo "Downloaded for viewing at: ${out#"$PWD"/}"
  > ```
  > * url string
  >   The url of the page to download.

