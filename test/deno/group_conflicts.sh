#!/usr/bin/env bash
# Host-side regression test: failing feature installations cannot run as CLI scenarios.
# Mount the real installer and exercise account conflicts before any network access.
set -euo pipefail

feature_dir="$(cd "$(dirname "$0")/../../src/deno" && pwd)"
docker run --rm -i --mount "type=bind,source=${feature_dir},target=/feature,readonly" debian:12 bash -s <<'TEST'
set -euo pipefail
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
for command in apt-get curl; do
    printf '#!/bin/sh\ntouch /tmp/network-called\nexit 99\n' >"/tmp/network-trap/${command}"
    chmod 0755 "/tmp/network-trap/${command}"
done
reject_conflict() {
    local message="$1" status=0
    cp /etc/group /tmp/group-before
    PATH="/tmp/network-trap:$PATH" TMPDIR=/tmp/install-tmp _REMOTE_USER=devuser VERSION=latest \
        bash /feature/install.sh >/tmp/install-output 2>&1 || status=$?
    [ "${status}" = 1 ]
    grep -Fq "${message}" /tmp/install-output
    [ ! -e /tmp/network-called ]
    diff /tmp/group-before /etc/group
    stat -c '%u:%g:%a' /usr/local/share/deno /usr/local/share/deno/bin | diff /tmp/directories-before -
    sha256sum -c /tmp/files-before.sha256
    [ -z "$(ls -A /tmp/install-tmp)" ]
    echo "PASS: ${message}"
}

usermod -aG deno outsider
reject_conflict 'group deno belongs to another account: outsider'
gpasswd -d outsider deno
usermod -g deno outsider
reject_conflict 'group deno is the primary group of another account: outsider'
usermod -g outsider outsider
usermod -g deno devuser
reject_conflict "group deno is the primary group of 'devuser'"
usermod -g devuser devuser

# Safe reuse starts with an empty existing group and a same-version executable.
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl ca-certificates unzip
apt-get clean
rm -rf /var/lib/apt/lists/*
_REMOTE_USER=devuser VERSION=2.8.0 bash /feature/install.sh
su -s /bin/bash devuser -c 'test -w /usr/local/share/deno/bin'
for dir in /usr/local/share/deno /usr/local/share/deno/bin; do
    [ "$(stat -c '%U:%G:%a' "${dir}")" = root:deno:2775 ]
done
echo 'PASS: empty existing group is reused'

# Membership by name and the separate group GID must survive the CLI's remap.
old_gid="$(id -g devuser)"
old_uid="$(id -u devuser)"
sed -i "s/devuser:x:${old_uid}:${old_gid}:/devuser:x:23456:23456:/" /etc/passwd
sed -i "s/:${old_gid}:/:23456:/" /etc/group
chown -R 23456:23456 /home/devuser
_REMOTE_USER=devuser VERSION=2.8.0 bash /feature/install.sh
su -s /bin/bash devuser -c 'echo writable > /usr/local/share/deno/bin/remap-proof'
[ "$(cat /usr/local/share/deno/bin/remap-proof)" = writable ]
[ "$(cat /usr/local/share/deno/bin/kept-tool)" = 'existing tool' ]
echo 'PASS: supplementary membership, reinstall, and remapped access'

# A conflict does not change the existing root/absent-user path.
usermod -aG deno outsider
for remote in root absent-user; do
    rm -rf /usr/local/share/deno
    _REMOTE_USER="${remote}" VERSION=2.8.0 bash /feature/install.sh
    [ "$(stat -c '%U:%G:%a' /usr/local/share/deno/bin)" = root:root:755 ]
done
echo 'PASS: root and absent remote users do not need the deno group'
TEST
