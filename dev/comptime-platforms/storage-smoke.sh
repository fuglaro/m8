#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
root="$repo/scratch/storage-smoke"
rm -rf "$root"
mkdir -p "$root/project/mobs/demo" "$root/config/m8-st8/mobs/useronly" "$root/project/core/providers" "$root/config/m8-st8/mobs/demo"
printf '* :brain::/toy/echo\n' > "$root/project/mobs/demo/echo.md"
printf '* :brain::/toy/echo\n' > "$root/config/m8-st8/mobs/useronly/echo.md"
printf '* :brain::/toy/echo\n' > "$root/config/m8-st8/mobs/demo/hidden.md"
printf '{"cmd":["m8","toy-provider"],"models":["m8","toy-provider","--models"]}\n' > "$root/project/core/providers/toy.json"
export XDG_CONFIG_HOME="$root/config" XDG_DATA_HOME="$root/data" HOME="$root/home"
export M8_ST8_DIRS="$root/project:$root/config/m8-st8" M8_CALL_ID=storage-smoke
unset M8_ST8_USER_ROOT M8_ST8_DATA_ROOT
m8=${M8_BIN:-"$repo/zig-out/bin/m8"}
"$m8" say --answer --unwrap :demo/echo hello > "$root/reply"
grep -q hello "$root/reply"
# Riff pipes each submission to `say -r -i`: rendered output must retain
# the submission even though stdin (and, here, stdout) is not a terminal.
printf 'riff submission\n' | "$m8" say -r -i --no-advance :demo/echo > "$root/rendered"
grep -q '🙋' "$root/rendered"
grep -q 'riff submission' "$root/rendered"
# Explicit reply-only and unwrapped presentations must not gain a prompt.
printf 'riff answer\n' | "$m8" say -r -i --no-advance --answer :demo/echo > "$root/answer"
if grep -q '🙋' "$root/answer"; then exit 1; fi
printf 'riff unwrap\n' | "$m8" say -i --no-advance --unwrap :demo/echo > "$root/unwrap"
if grep -q '🙋\|:raising_hand:' "$root/unwrap"; then exit 1; fi
cp "$root/project/mobs/demo/.chats/echo/+.md" "$root/pointer"
turns_before=$(find "$root/project/mobs/demo/.chats/echo/+" -type f | wc -l | tr -d ' ')
"$m8" say --no-advance --answer --unwrap :demo/echo stateless > "$root/stateless"
grep -q stateless "$root/stateless"
cmp "$root/pointer" "$root/project/mobs/demo/.chats/echo/+.md"
turns_after=$(find "$root/project/mobs/demo/.chats/echo/+" -type f | wc -l | tr -d ' ')
test "$turns_after" -gt "$turns_before"
test -f "$root/project/mobs/demo/.chats/echo/+.md"
test -d "$root/project/mobs/demo/.mob-space"
rm -rf "$root/project/mobs/demo/.mob-space"
"$m8" say --answer --unwrap :demo/echo model-head > "$root/model-head"
grep -q model-head "$root/model-head"
test -d "$root/project/mobs/demo/.mob-space"
"$m8" say --answer --unwrap :demo/echo//job next > "$root/subreply"
test -f "$root/project/mobs/demo/.chats/echo/_/job/+.md"
"$m8" say :demo/echo//job-
test ! -f "$root/project/mobs/demo/.chats/echo/_/job/+.md"
"$m8" say --new :demo/echo//job
test -f "$root/project/mobs/demo/.chats/echo/_/job/+.md"
grep -q 'demo/echo' "$root/project/mobs/demo/.chats/echo/_/job/+.md"
# The bare address shorthand reaches the same promptless reset.
"$m8" :demo/echo//job- </dev/null
test ! -f "$root/project/mobs/demo/.chats/echo/_/job/+.md"
"$m8" say --answer --unwrap :demo/echo//job again > "$root/subreply"
"$m8" :demo/echo//job-- </dev/null
grep -qx '\* :brain::demo/echo' "$root/project/mobs/demo/.chats/echo/_/job/+.md"
"$m8" say --answer --unwrap :useronly/echo relocated > "$root/userreply"
grep -q relocated "$root/userreply"
test -f "$root/data/m8-st8/user/mobs/useronly/.chats/echo/+.md"
test -d "$root/data/m8-st8/user/mobs/useronly/.mob-space"
test ! -d "$root/config/m8-st8/mobs/useronly/.chats"
cat > "$root/project/mobs/demo/runner.md" <<'DEFINITION'
* :brain::/toy/runner

* :toolbox::delegate
  > `m8` `call` `sh` `-c` `HOME="$TMPDIR" XDG_CONFIG_HOME=/narrow XDG_DATA_HOME=/narrow "$M8" say --answer --unwrap :useronly/echo//delegated "$__message__"`
  > * message string

* :toolbox::delegate
DEFINITION
"$m8" say --answer --unwrap :demo/runner 'RUN;;;delegate;;;message=delegated' > "$root/delegation"
grep -q Done "$root/delegation"
test -f "$root/data/m8-st8/user/mobs/useronly/.chats/echo/_/delegated/+.md"
test -f "$root/project/mobs/demo/.chats/runner/+.md"
if "$m8" @ > "$root/unexpected" 2> "$root/error"; then exit 1; fi
if "$m8" at > "$root/unexpected" 2> "$root/error"; then exit 1; fi
"$m8" </dev/null > "$root/help"
grep -q 'MOB/AGENT' "$root/help"
(
  unset M8_CALL_ID M8_ST8_DIRS M8_ST8_USER_ROOT M8_ST8_DATA_ROOT
  export XDG_CONFIG_HOME="$root/registry"
  outer="$root/work"
  inner="$outer/child"
  mkdir -p "$outer/.m8-st8/mobs/outer" "$inner/.m8-st8/mobs/inner"
  printf '* :brain::/toy/echo\n' > "$outer/.m8-st8/mobs/outer/echo.md"
  printf '* :brain::/toy/echo\n' > "$inner/.m8-st8/mobs/inner/echo.md"
  cd "$inner"
  "$m8" register > "$root/registered"
  "$m8" say --no-send :inner/echo > "$root/nearest"
  if "$m8" say --no-send :outer/echo > "$root/unexpected" 2> "$root/error"; then exit 1; fi
  # Even a registered ancestor is not a fallback for an unregistered nearest project.
  export XDG_CONFIG_HOME="$root/registry2"
  cd "$outer"
  "$m8" register > "$root/registered2"
  cd "$inner"
  if "$m8" say --no-send :outer/echo > "$root/unexpected" 2> "$root/error"; then exit 1; fi
)
echo 'storage CLI smoke: passed'
