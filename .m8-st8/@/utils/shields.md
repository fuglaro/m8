#### :shield:deny
> `false`

#### :shield:ask
> `m8` `shield` `ask` `{{SHIELD}}` `--`

#### :shield:secure
> `bash` `-e` `-c` `exec {{M8}} shield secure "${__secures__}" -- "$@"` `bash`

#### :shield:check
> `bash` `-e` `-c` `said=$({{M8}} ref "@$__checks__" "$*" | {{M8}} send | {{M8}} tail --sigil robot --block); [ "$(printf %s "$said" | tr A-Z a-z)" = allow ] || { echo "Failed agentic check: $said" >&2; exit 1; }; exec "$@"` `bash`

#### :shield:contain-reads
> :shield:secure secures contain-reads

#### :shield:private
> :shield:secure secures private

#### :shield:contain-writes
> :shield:secure secures contain-writes

#### :shield:no-writes
> :shield:secure secures no-writes

#### :shield:airgap
> :shield:secure secures airgap

#### :shield:no-loop
> :shield:secure secures no-loop

#### :shield:no-edit-git
> :shield:secure secures no-edit-git

#### :shield:no-edit-m8-st8
> :shield:secure secures no-edit-m8-st8

#### :shield:contain-env
> `bash` `-c` `for v in $(compgen -e); do case $v in __*|M8_*|TMPDIR|PATH|HOME|LANG|LC_*|TERM|COLORTERM|NO_COLOR|CLICOLOR|COLUMNS|LINES|TZ) ;; *) unset "$v";; esac; done; exec "$0" "$@"`

#### :shield:contain-home
> `bash` `-c` `HOME=$TMPDIR exec "$0" "$@"`

#### :shield:freeze-toolbox
> `bash` `-euo` `pipefail` `-c` `"$0" "$@" | {{M8}} exclude --sigil toolbox --sigil brain --sigil books`

#### :shield:sandbox
> :shield:freeze-toolbox
> :shield:private
> :shield:contain-writes
> :shield:no-loop
> :shield:no-edit-git
> :shield:no-edit-m8-st8
> :shield:contain-env
> :shield:contain-home

#### :shield:jail
> :shield:sandbox
> :shield:airgap
