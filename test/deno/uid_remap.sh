#!/usr/bin/env bash
# Scenario: version 2.8.0 on base:ubuntu24.04 as vscode. Reproduces updateRemoteUserUID, also on a host whose UID
# matches the image's, and installs a global tool afterwards.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

global_tool_installs_after_remap() {
  local old_uid old_gid
  local new_uid=23456
  local new_gid=23456
  old_uid="$(id -u vscode)"
  old_gid="$(id -g vscode)"
  while getent passwd "${new_uid}" >/dev/null; do
    new_uid=$((new_uid + 1))
  done
  while getent group "${new_gid}" >/dev/null; do
    new_gid=$((new_gid + 1))
  done
  # Keep one root process across the remap: the calling process retains its old UID. The root script reads the old UID
  # and GID as $1 and $2 and the new ones as $3 and $4.
  sudo -n bash -s -- "${old_uid}" "${old_gid}" "${new_uid}" "${new_gid}" <<'ROOT'
set -euo pipefail
sed -i -e "s/vscode:x:$1:$2:/vscode:x:$3:$4:/" /etc/passwd
sed -i -e "s/:$2:/:$4:/" /etc/group
chown -R "$3:$4" /home/vscode
sudo -n -u vscode bash -c '
  set -euo pipefail
  [[ -w /usr/local/share/deno/bin ]]
  script="$(mktemp -d)/hello.ts"
  echo "console.log(42);" >"${script}"
  deno install --global --name deno-remap-hello "${script}"
  [[ "$(bash -lc deno-remap-hello)" == 42 ]]
'
ROOT
}
check "the remote user installs a global tool after its UID and GID change" global_tool_installs_after_remap

reportResults
