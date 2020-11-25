#!/bin/bash

error() { echo "ERROR:" "$@" >&2; }
fail() { [ $# -gt 0 ] && error "$@"; exit 1; }
modmkdir() { local MOD="$1"; shift; mkdir "$@" && chmod "$MOD" "$@"; }
isset() { local i; for i; do [ -z "${!i}" ] && error "Missine environment variable $i." && return 1; done; return 0; }
fixTrailingSlash() { [ "${1:${#1}-1}" = "/" ] && echo "${1::-1}" || echo "$1"; }
boolanOrString() { [ "$1" != "true" ] && [ "$1" != "false" ] && echo '"'"$1"'"' || echo "$1"; }

[ -d ~/.ssh ] || modmkdir 0700 ~/.ssh
if isset SSH_KEY 2>/dev/null; then
    isset SSH_KEY_FILE 2>/dev/null && fail "Environment variables SSH_KEY and SSH_KEY_FILE are mutually exclusive."
    export SSH_KEY_FILE=~/.ssh/id_rsa
    echo "$SSH_KEY" > "$SSH_KEY_FILE"
    chmod 0400 "$SSH_KEY_FILE"
fi

isset TARGET_USER TARGET_HOST TARGET_PATH SSH_KEY_FILE || fail

cat >> ~/.ssh/config <<EOF
Host $TARGET_HOST
     User $TARGET_USER${TARGET_SSH_PORT:+
     Port $TARGET_SSH_PORT}
     IdentityFile $SSH_KEY_FILE
     CheckHostIP no
EOF
AK=
if [ -z "$HOST_KEY" ]; then
    ssh "$TARGET_HOST" -o StrictHostKeyChecking=accept-new true 2>/dev/null >&2 || AK=1
else
    cat >> ~/.ssh/known_hosts <<<"$(
        [ "${TARGET_SSH_PORT:-22}" -eq 22 ] && echo "$TARGET_HOST" || echo "[$TARGET_HOST]:$TARGET_SSH_PORT"
    ) $(
        echo $HOST_KEY | awk '{print $1" "$2}'
    )"
fi
echo "ssh $TARGET_HOST${AK:+ -o StrictHostKeyChecking=accept-new}" >> ~/.bash_history

echo "${EXCLUDES:-"*~"}" > ~/lsyncd.excludes
cat > ~/lsyncd.conf.lua <<EOF
settings {
    statusFile  = "$HOME/lsyncd.status",
    nodaemon    = true,
    insist      = true,
    inotifyMode = "${INOTIFY_MODE:-CloseWrite}",
}
sync {
    default.rsyncssh,
    source      = "$(fixTrailingSlash "${SOURCE_PATH:-/var/source}")/",
    host        = "$TARGET_HOST",
    targetdir   = "$(fixTrailingSlash "$TARGET_PATH")/",
    delay       = ${SYNC_DELAY:-0},
    excludeFrom = "$HOME/lsyncd.excludes",
    delete      = $(boolanOrString "${DELETE:-running}"),
    rsync           = {
        archive     = ${RSYNC_ARCHIVE:-true},
        compress    = ${RSYNC_COMPRESS:-false},
        -- excludeFrom = "$HOME/lsyncd.excludes",
    }
}
EOF

tee -a ~/.ash_history ~/.bash_history >/dev/null <<EOF
lsyncd $HOME/lsyncd.conf.lua
ssh $TARGET_HOST${AK:+ -o StrictHostKeyChecking=accept-new}
EOF

exec "$@"
