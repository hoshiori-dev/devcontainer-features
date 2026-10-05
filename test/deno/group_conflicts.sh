#!/usr/bin/env bash
# Host-side regression test, run by hand: a failing feature installation cannot be a CLI scenario. It mounts the real
# installer into a debian:12 container and exercises the group conflicts and the group command precondition, which must
# fail before any network access, and then the group paths that must install.
set -euo pipefail

feature_dir="$(cd "$(dirname "$0")/../../src/deno" && pwd)"
docker run --rm -i --mount "type=bind,source=${feature_dir},target=/feature,readonly" debian:12 bash -s <<'TEST'
set -euo pipefail

# A PATH without /usr/sbin and /sbin, where debian:12 keeps groupadd and usermod: it hides both from the installer.
readonly NO_GROUP_COMMANDS_PATH=/usr/local/bin:/usr/bin:/bin

groupadd deno
useradd -m devuser
useradd -M outsider
mkdir -p /usr/local/share/deno/bin /etc/profile.d /tmp/network-trap /tmp/install-tmp
printf '#!/bin/sh\necho "deno 2.8.0 (stable, release, x86_64-unknown-linux-gnu)"\n' >/usr/local/bin/deno
chmod 0755 /usr/local/bin/deno
echo 'existing tool' >/usr/local/share/deno/bin/kept-tool
echo '# existing profile' >/etc/profile.d/deno.sh
sha256sum /usr/local/bin/deno /usr/local/share/deno/bin/kept-tool /etc/profile.d/deno.sh >/tmp/files-before.sha256
stat -c '%u:%g:%a' /usr/local/share/deno /usr/local/share/deno/bin >/tmp/directories-before

# Either prerequisite installation or a Deno request records an unexpected network attempt.
for network_command in apt-get curl; do
  printf '#!/bin/sh\ntouch /tmp/network-called\nexit 99\n' >"/tmp/network-trap/${network_command}"
  chmod 0755 "/tmp/network-trap/${network_command}"
done

# Installs for devuser with the network traps ahead of PATH $2. The installation must exit with status 1 and a message
# holding $1, before any network access, and leave the groups, the tools directories, and the existing files unchanged.
install_is_rejected() {
  local message="$1"
  local install_path="$2"
  local status
  cp /etc/group /tmp/group-before
  if PATH="/tmp/network-trap:${install_path}" TMPDIR=/tmp/install-tmp _REMOTE_USER=devuser VERSION=latest \
    bash /feature/install.sh >/tmp/install-output 2>&1; then
    status=0
  else
    status=$?
  fi
  [[ "${status}" == 1 ]]
  grep -Fq "${message}" /tmp/install-output
  [[ ! -e /tmp/network-called ]]
  diff /tmp/group-before /etc/group
  stat -c '%u:%g:%a' /usr/local/share/deno /usr/local/share/deno/bin | diff /tmp/directories-before -
  sha256sum -c /tmp/files-before.sha256
  [[ -z "$(ls -A /tmp/install-tmp)" ]]
  printf '%s\n' "PASS: ${message}"
}

# Scenarios "Existing group belongs to another account" and "Remote user has deno as its primary group".
usermod -aG deno outsider
install_is_rejected 'group deno belongs to another account: outsider' "${PATH}"
gpasswd -d outsider deno
usermod -g deno outsider
install_is_rejected 'group deno is the primary group of another account: outsider' "${PATH}"
usermod -g outsider outsider
usermod -g deno devuser
install_is_rejected "group deno is the primary group of 'devuser'" "${PATH}"
usermod -g devuser devuser

# Scenario "Group command missing": usermod while devuser is not in the existing group, groupadd while no group exists.
install_is_rejected 'usermod is missing' "${NO_GROUP_COMMANDS_PATH}"
groupdel deno
install_is_rejected 'groupadd is missing' "${NO_GROUP_COMMANDS_PATH}"
groupadd deno

# Scenario "Existing group is reserved for the feature": safe reuse starts with an empty existing group and a
# same-version executable.
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl ca-certificates unzip
apt-get clean
rm -rf /var/lib/apt/lists/*
_REMOTE_USER=devuser VERSION=2.8.0 bash /feature/install.sh
su -s /bin/bash devuser -c 'test -w /usr/local/share/deno/bin'
for dir in /usr/local/share/deno /usr/local/share/deno/bin; do
  [[ "$(stat -c '%U:%G:%a' "${dir}")" == root:deno:2775 ]]
done
echo 'PASS: empty existing group is reused'

# Scenario "Group prepared in the image": devuser is now the only member of group deno, so an installation that finds
# neither groupadd nor usermod succeeds, and devuser installs a global tool.
PATH="${NO_GROUP_COMMANDS_PATH}" _REMOTE_USER=devuser VERSION=latest bash /feature/install.sh
su -s /bin/bash devuser -c '
  set -euo pipefail
  export DENO_INSTALL_ROOT=/usr/local/share/deno
  script="$(mktemp -d)/hello.ts"
  echo "console.log(42);" >"${script}"
  deno install --global --name deno-prepared-hello "${script}"
  [[ "$(/usr/local/share/deno/bin/deno-prepared-hello)" == 42 ]]
'
echo 'PASS: prepared group installs without groupadd and usermod'

# Membership by name and the separate group GID must survive the CLI's remap.
old_gid="$(id -g devuser)"
old_uid="$(id -u devuser)"
sed -i "s/devuser:x:${old_uid}:${old_gid}:/devuser:x:23456:23456:/" /etc/passwd
sed -i "s/:${old_gid}:/:23456:/" /etc/group
chown -R 23456:23456 /home/devuser
_REMOTE_USER=devuser VERSION=2.8.0 bash /feature/install.sh
su -s /bin/bash devuser -c 'echo writable > /usr/local/share/deno/bin/remap-proof'
[[ "$(cat /usr/local/share/deno/bin/remap-proof)" == writable ]]
[[ "$(cat /usr/local/share/deno/bin/kept-tool)" == 'existing tool' ]]
echo 'PASS: supplementary membership, reinstall, and remapped access'

# Scenario "Root or absent remote user": a conflict does not change the root and absent-user path.
usermod -aG deno outsider
for remote_user in root absent-user; do
  rm -rf /usr/local/share/deno
  _REMOTE_USER="${remote_user}" VERSION=2.8.0 bash /feature/install.sh
  [[ "$(stat -c '%U:%G:%a' /usr/local/share/deno/bin)" == root:root:755 ]]
done
echo 'PASS: root and absent remote users do not need the deno group'
TEST
