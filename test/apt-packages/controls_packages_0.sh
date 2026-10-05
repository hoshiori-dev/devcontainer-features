#!/bin/sh
# Verify installed packages and retained metadata under non-default controls.
set -eu
dpkg-query -W bc file >/dev/null
find /var/lib/apt/lists -name "*_Packages*" | grep -q .
if find /var/cache/apt/archives -name "*.deb" 2>/dev/null | grep -q .; then echo "package files were not cleaned" >&2; exit 1; fi
echo "installation controls passed"
