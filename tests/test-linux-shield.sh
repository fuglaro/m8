#!/bin/sh
# End-to-end Linux read/write containment tests for a built m8 binary.
# Usage: dev/test-linux-shield.sh /absolute/path/to/m8
set -eu

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
[ "$#" -eq 1 ] || fail "usage: $0 /absolute/path/to/m8"
case $1 in /*) ;; *) fail 'binary path must be absolute' ;; esac
[ -x "$1" ] || fail "not an executable binary: $1"
M8=$1
command -v bwrap >/dev/null 2>&1 || fail 'bwrap is required (tests never skip when unavailable)'
command -v bash >/dev/null 2>&1 || fail 'bash is required'

BASE=$(mktemp -d "${TMPDIR:-/tmp}/m8-linux-shield.XXXXXXXX") || fail 'mktemp failed'
cleanup() { rm -rf "$BASE"; }
trap cleanup EXIT HUP INT TERM
WORK=$BASE/work
SCRATCH=$BASE/scratch
HOME_FIXTURE=$BASE/home
OUTSIDE=$BASE/unrelated
mkdir -p "$WORK/.git/objects" "$SCRATCH" "$HOME_FIXTURE/.local/bin" "$HOME_FIXTURE/.cargo/bin" "$HOME_FIXTURE/go/bin" "$OUTSIDE"
printf 'cwd-readable\n' >"$WORK/cwd-secret"
printf 'tmp-readable\n' >"$SCRATCH/tmp-secret"
printf 'home-secret\n' >"$HOME_FIXTURE/home-secret"
printf 'tool-secret\n' >"$HOME_FIXTURE/.local/bin/tool"
printf 'outside-secret\n' >"$OUTSIDE/outside-secret"
printf 'git-secret\n' >"$WORK/.git/objects/secret"
ln -s "$OUTSIDE/outside-secret" "$WORK/outside-link"

# Isolate m8's own configuration from the invoking user's config. Each command
# inherits the exact fixture HOME/TMPDIR and empty config directory list.
run() {
    profile=$1; shift
    ( cd "$WORK" && env HOME="$HOME_FIXTURE" TMPDIR="$SCRATCH" \
        M8_ST8_DIRS= M8_ST8_USER_ROOT="$HOME_FIXTURE/.m8" \
        M8_ST8_DATA_ROOT="$HOME_FIXTURE/.local/share/m8" \
        "$M8" secure-shield "$profile" bash -c "$*" )
}
expect_ok() {
    label=$1; profile=$2; script=$3; expected=$4
    if output=$(run "$profile" "$script" 2>&1); then :; else
        fail "$label: command should have succeeded (status/content check): $output"
    fi
    [ "$output" = "$expected" ] || fail "$label: expected <$expected>, got <$output>"
    printf 'ok: %s\n' "$label"
}
expect_denied() {
    label=$1; profile=$2; script=$3
    if output=$(run "$profile" "$script" 2>&1); then
        fail "$label: command unexpectedly succeeded: $output"
    fi
    printf 'ok: %s (denied)\n' "$label"
}

# Validate bwrap and the actual wrapped-command path up front. An unusable
# user namespace, broken bwrap, or unusable mount setup is a hard failure.
expect_ok 'bwrap smoke test' contain-reads 'cat cwd-secret' 'cwd-readable'
expect_ok 'cwd, TMPDIR, and system reads' contain-reads 'cat cwd-secret; cat "$TMPDIR/tmp-secret"; test -r /etc/hosts && printf system-readable' 'cwd-readable
tmp-readable
system-readable'
expect_denied 'unrelated directory hidden' contain-reads "cat '$OUTSIDE/outside-secret'"
expect_denied 'HOME hidden by contain-reads' contain-reads 'cat "$HOME/home-secret"'
expect_ok 'HOME readable by contain-reads-home' contain-reads-home 'cat "$HOME/home-secret"' 'home-secret'
expect_ok 'private still permits cwd and system reads' private 'cat cwd-secret; test -r /etc/hosts && printf system-readable' 'cwd-readable
system-readable'
expect_ok 'contain-reads exposes tool directory' contain-reads 'cat "$HOME/.local/bin/tool"' 'tool-secret'
expect_denied 'private hides tool directory' private 'cat "$HOME/.local/bin/tool"'
expect_denied 'strict then home remains strict' 'contain-reads-home contain-reads' 'cat "$HOME/home-secret"'
expect_denied 'home then strict remains strict' 'contain-reads contain-reads-home' 'cat "$HOME/home-secret"'
expect_denied 'private then home remains private' 'private contain-reads-home' 'cat "$HOME/home-secret"'
expect_denied 'home then private remains private' 'contain-reads-home private' 'cat "$HOME/home-secret"'
expect_denied 'cwd symlink cannot read outside target' contain-reads 'cat outside-link'

expect_ok 'read/write containment permits cwd and TMPDIR writes' 'contain-reads contain-writes' 'printf cwd-write > cwd-write; printf tmp-write > "$TMPDIR/tmp-write"; cat cwd-write; cat "$TMPDIR/tmp-write"' 'cwd-writetmp-write'
expect_denied 'read/write containment blocks HOME writes' 'contain-reads contain-writes' 'printf bad > "$HOME/should-not-exist"'
expect_denied 'read/write containment blocks unrelated writes' 'contain-reads contain-writes' "printf bad > '$OUTSIDE/should-not-exist'"
expect_ok 'private plus write containment permits TMP writes' 'private contain-writes-home' 'printf allowed > "$TMPDIR/private-write"; cat "$TMPDIR/private-write"' 'allowed'
expect_denied 'private reads plus HOME writes does not expose HOME' 'private contain-writes-home' 'cat "$HOME/home-secret"'
expect_denied 'no-writes blocks TMPDIR writes' 'contain-reads no-writes' 'printf bad > "$TMPDIR/no-write"'
expect_denied 'read-only empty root prevents new top-level trees' 'contain-reads no-writes' 'mkdir /escape'
expect_denied 'only-TMP writes blocks cwd writes' 'contain-reads only-tmp-writes' 'printf bad > cwd-denied'
expect_ok 'only-TMP writes plus HOME reads permits HOME read' 'only-tmp-writes contain-reads-home' 'cat "$HOME/home-secret"' 'home-secret'
expect_denied 'only-TMP writes plus HOME reads blocks HOME write' 'only-tmp-writes contain-reads-home' 'printf bad > "$HOME/should-not-exist"'

expect_ok 'no-edit-git leaves metadata readable' 'contain-reads no-edit-git' 'cat .git/objects/secret' 'git-secret'
expect_denied 'no-edit-git protects metadata writes' 'contain-reads no-edit-git' 'printf bad > .git/objects/secret'
expect_denied 'no-edit-git prevents metadata rename' 'contain-reads no-edit-git' 'mv .git .git-moved'
expect_ok 'no-edit-git still permits cwd writes' 'contain-reads no-edit-git' 'printf git-safe > ordinary-write; cat ordinary-write' 'git-safe'

# Exercise canonicalization of a symlinked HOME as well as the ordinary HOME
# mount path. This is Linux-only (the entire script requires Linux bwrap).
ln -s "$HOME_FIXTURE" "$BASE/home-alias"
(
    cd "$WORK"
    if output=$(env HOME="$BASE/home-alias" TMPDIR="$SCRATCH" M8_ST8_DIRS= \
        M8_ST8_USER_ROOT="$HOME_FIXTURE/.m8" M8_ST8_DATA_ROOT="$HOME_FIXTURE/.local/share/m8" \
        "$M8" secure-shield contain-reads-home bash -c 'cat "$HOME/home-secret"' 2>&1); then
        [ "$output" = 'home-secret' ] || fail "symlinked HOME read returned unexpected content: $output"
        printf 'ok: symlinked HOME read mount alias\n'
    else
        fail "symlinked HOME mount alias failed: $output"
    fi
    if output=$(env HOME="$BASE/home-alias" TMPDIR="$SCRATCH" M8_ST8_DIRS= \
        M8_ST8_USER_ROOT="$HOME_FIXTURE/.m8" M8_ST8_DATA_ROOT="$HOME_FIXTURE/.local/share/m8" \
        "$M8" secure-shield "contain-reads-home contain-writes-home" bash -c 'printf alias-write > "$HOME/alias-write"; cat "$HOME/alias-write"' 2>&1); then
        [ "$output" = 'alias-write' ] || fail "symlinked HOME write returned unexpected content: $output"
        [ "$(cat "$HOME_FIXTURE/alias-write")" = 'alias-write' ] || fail 'symlinked HOME write did not reach the fixture target'
        printf 'ok: symlinked HOME writable mount alias\n'
    else
        fail "symlinked HOME writable mount alias failed: $output"
    fi
)
# A missing backend must never trigger an unprotected execution fallback.
mkdir "$BASE/empty-path"
if output=$(cd "$WORK" && env HOME="$HOME_FIXTURE" TMPDIR="$SCRATCH" \
    PATH="$BASE/empty-path" "$M8" secure-shield private \
    /bin/sh -c 'printf bad > backend-fallback-marker' 2>&1); then
    fail "missing bwrap unexpectedly allowed execution: $output"
fi
[ ! -e "$WORK/backend-fallback-marker" ] || fail 'missing bwrap ran unprotected command'
printf 'ok: missing backend fails closed\n'
printf 'All Linux shield containment tests passed.\n'
