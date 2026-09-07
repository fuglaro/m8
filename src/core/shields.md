#### :runner:bash
> `bash` `-c` `{{CODE}}` `bash`

#### :shield:deny
> `false`

#### :shield:ask
> ```bash
> exec "$M8_SELF" shield ask -- "$@"
> ```

#### :shield:secure
> ```bash
> exec "$M8_SELF" shield secure "${SECURES}" -- "$@"
> ```

#### :shield:check
> ```bash
> exec "$M8_SELF" shield check "${CHECKS}" -- "$@"
> ```

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
> `bash` `-euo` `pipefail` `-c` `"$0" "$@" | "$M8_SELF" filter out toolbox`

#### :shield:filter-unlock
> `bash` `-euo` `pipefail` `-c` `"$0" "$@" | "$M8_SELF" filter out unlock`

#### :shield:filter-brain
> `bash` `-euo` `pipefail` `-c` `"$0" "$@" | "$M8_SELF" filter out brain`

#### :shield:filter-books
> `bash` `-euo` `pipefail` `-c` `"$0" "$@" | "$M8_SELF" filter out books`

#### :shield:freeze-toolbox
> :shield:filter-toolbox
> :shield:filter-unlock
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
