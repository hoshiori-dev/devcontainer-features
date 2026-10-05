#!/bin/sh
# Verify installed packages and retained metadata under non-default controls.
set -eu
rpm -q bc file >/dev/null
find /var/cache/dnf /var/cache/libdnf5 -name repomd.xml 2>/dev/null | grep -q .
if find /var/cache/dnf /var/cache/libdnf5 -name "*.rpm" 2>/dev/null | grep -q .; then echo "package files were not cleaned" >&2; exit 1; fi
echo "installation controls passed"
