#!/bin/sh
# Runs as the remote user once per container, before the user's creation commands.
# A failed repair must not stop container creation. Do not enable set -e.

volume=/var/lib/uv
warn() {
    echo "uv feature: warning: $volume: $* See the uv feature's NOTES.md for manual repair." >&2
}

uid=$(id -u) || { warn "cannot determine the remote user's UID."; exit 0; }
[ "$uid" != 0 ] || exit 0

fits=false
if [ -w "$volume" ] && [ -x "$volume" ]; then
    if command -v find >/dev/null 2>&1; then
        if foreign=$(find "$volume" -mindepth 1 ! -uid "$uid" -print -quit 2>&1); then
            [ -n "$foreign" ] || fits=true
        fi
    else
        # GNU ls on openSUSE sees hidden entries and escapes newlines in names. It does not
        # follow symbolic links; numeric ownership is field three of each entry's long format.
        if listing=$(LC_ALL=C ls -lnARb -- "$volume" 2>&1); then
            if printf '%s\n' "$listing" | awk -v uid="$uid" '
                $1 ~ /^[-bcdlps]/ && $3 != uid {foreign=1}
                END {exit foreign ? 1 : 0}
            '; then
                fits=true
            fi
        fi
    fi
fi
[ "$fits" = false ] || exit 0

if ! command -v sudo >/dev/null 2>&1; then
    warn "the volume does not fit this user and sudo is unavailable."
    exit 0
fi
if ! reason=$(sudo -n true 2>&1); then
    warn "passwordless sudo is unavailable: $reason"
    exit 0
fi
group=$(awk -F: '$1 == "uv" {print $3}' /etc/group)
owner=$uid
[ -z "$group" ] || owner="$uid:$group"
# -h prevents even a command-line symlink from changing an external target; recursive chown
# never follows links inside the volume. Modes and all paths outside the volume stay untouched.
if ! reason=$(sudo -n chown -hR "$owner" "$volume" 2>&1); then
    warn "could not change the volume's owner: $reason"
fi
exit 0
