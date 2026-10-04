#### :shield:deny
> `false`

#### :shield:ask
> `m8` `shield` `ask` `--`

#### :shield:secure
> `bash` `-e` `-c` `exec {{M8}} shield secure "${M8_ARG_SECURES}" -- "$@"` `bash`

#### :shield:check
> `bash` `-e` `-c` `exec {{M8}} shield check "${M8_ARG_CHECKS}" -- "$@"` `bash`

#### :shield:contain-reads
> :shield:secure SECURES contain-reads

#### :shield:private
> :shield:secure SECURES private

#### :shield:contain-writes
> :shield:secure SECURES contain-writes

#### :shield:no-writes
> :shield:secure SECURES no-writes

#### :shield:airgap
> :shield:secure SECURES airgap

#### :shield:no-loop
> :shield:secure SECURES no-loop

#### :shield:no-edit-git
> :shield:secure SECURES no-edit-git

#### :shield:no-edit-m8-st8
> :shield:secure SECURES no-edit-m8-st8

#### :shield:contain-env
> :shield:secure SECURES contain-env

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
