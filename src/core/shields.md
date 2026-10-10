#### :shield:deny
> `false`

#### :shield:ask
> `m8` `shield` `ask` `{{SHIELD}}` `--`

#### :shield:secure
> `bash` `-e` `-c` `exec {{M8}} shield secure "${__secures__}" -- "$@"` `bash`

#### :shield:check
> `bash` `-e` `-c` `exec {{M8}} shield check "${__checks__}" -- "$@"` `bash`

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
> :shield:secure secures contain-env

#### :shield:filter-toolbox
> `bash` `-euo` `pipefail` `-c` `"$0" "$@" | {{M8}} filter out toolbox`

#### :shield:filter-brain
> `bash` `-euo` `pipefail` `-c` `"$0" "$@" | {{M8}} filter out brain`

#### :shield:filter-books
> `bash` `-euo` `pipefail` `-c` `"$0" "$@" | {{M8}} filter out books`

#### :shield:freeze-toolbox
> :shield:filter-toolbox
> :shield:filter-brain
> :shield:filter-books

#### :shield:sandbox
> :shield:freeze-toolbox
> :shield:private
> :shield:contain-writes
> :shield:no-loop
> :shield:no-edit-git
> :shield:no-edit-m8-st8
> :shield:contain-env

#### :shield:jail
> :shield:sandbox
> :shield:airgap
