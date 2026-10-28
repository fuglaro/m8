* :shield::deny
  > `false`

* :shield::ask
  > `m8` `ask-shield`

* :shield::secure
  > `m8` `secure-shield`

* :shield::check
  > `bash` `-e` `-c` `said=$("$M8" query --no-advance ":$0" "$*"); [ "$(printf %s "$said" | tr A-Z a-z)" = allow ] || { echo "Failed agentic check: $said" >&2; exit 1; }; exec "$@"`

* :shield::contain-env
  > `bash` `-c` `for v in $(compgen -e); do case $v in __*|M8|M8_*|TMPDIR|PATH|HOME|LANG|LC_*|TERM|COLORTERM|NO_COLOR|CLICOLOR|COLUMNS|LINES|TZ) ;; *) unset "$v";; esac; done; exec "$@"`

* :shield::contain-home
  > `bash` `-c` `HOME=$TMPDIR exec "$@"`

* :shield::freeze-toolbox
  > `bash` `-euo` `pipefail` `-c` `"$@" | "$M8" exclude --sigil toolbox --sigil brain --sigil books`

* :shield::sandbox
  > :shield:freeze-toolbox
  > :shield:secure private contain-writes no-loop no-edit-git no-edit-m8-st8
  > :shield:contain-env
  > :shield:contain-home

* :shield::jail
  > :shield:sandbox
  > :shield:secure airgap
