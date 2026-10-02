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
    # Keep one root process across the remap: the calling process retains its old UID.
    sudo -n bash -s -- "${old_uid}" "${old_gid}" "${new_uid}" "${new_gid}" <<'ROOT'
set -e
sed -i -e "s/vscode:x:$1:$2:/vscode:x:$3:$4:/" /etc/passwd
sed -i -e "s/:$2:/:$4:/" /etc/group
chown -R "$3:$4" /home/vscode
sudo -n -u vscode bash -c '
    set -e
    [ -w /usr/local/share/deno/bin ]
    script="$(mktemp -d)/hello.ts"
    echo "console.log(42);" >"${script}"
    deno install --global --name deno-remap-hello "${script}"
    [ "$(bash -lc deno-remap-hello)" = 42 ]
'
ROOT

}
check "global tools remain writable after a UID/GID remap" remap_and_install
reportResults
