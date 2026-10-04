#!/bin/sh
# Verify installed packages and retained metadata under non-default controls.
set -eu
rpm -q bc file >/dev/null
find /var/cache/dnf /var/cache/libdnf5 -name repomd.xml 2>/dev/null | grep -q .
echo "installation controls passed"
