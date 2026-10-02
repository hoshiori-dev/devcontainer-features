#!/usr/bin/env bash
# Reproduce updateRemoteUserUID even on a host whose UID matches the image's.
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib
remap_and_install() {
    local old_uid old_gid new_uid=23456 new_gid=23456
    old_uid="$(id -u vscode)"
    old_gid="$(id -g vscode)"
    while getent passwd "${new_uid}" >/dev/null; do new_uid=$((new_uid + 1)); done
    while getent group "${new_gid}" >/dev/null; do new_gid=$((new_gid + 1)); done
    sudo -n sed -i -e "s/vscode:x:${old_uid}:${old_gid}:/vscode:x:${new_uid}:${new_gid}:/" /etc/passwd
    sudo -n sed -i -e "s/:${old_gid}:/:${new_gid}:/" /etc/group
    sudo -n chown -R "${new_uid}:${new_gid}" /home/vscode
    sudo -n -u vscode bash -c '
        set -e
        [ -w /usr/local/share/deno/bin ]
        script="$(mktemp -d)/hello.ts"
        echo "console.log(42);" >"${script}"
        deno install --global --name deno-remap-hello "${script}"
        [ "$(bash -c deno-remap-hello)" = 42 ]
    '
}
check "global tools remain writable after a UID/GID remap" remap_and_install
reportResults
