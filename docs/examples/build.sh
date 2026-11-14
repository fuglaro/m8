#!/usr/bin/env bash
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$here"

# The SVGs record their canvas sizes and animation, but not the exact command
# line. These speeds are chosen to closely match the animated examples' lengths.
cast() {
    local source=$1 output=$2
    shift 2
    m8 encode < "$source" | m8 cast "$@" > "$output"
}

cast coop/zork+.md coop/zork.svg --skip-snips \
    --size 90x30 --speed '30l,🤖80w'
cast coop/zork-player+.md coop/zork-player.svg --skip-snips \
    --size 90x30 --speed '100w,📲800b,📜0b,🟢2000b,🙋200c'
cast haiku/devyn+.md haiku/devyn.svg --skip-snips \
    --size 90x22 --no-riff :crew/devyn --static
cast haiku/devyn+.md haiku/devyn-riff.svg --skip-snips \
    --size 90x25 --static
