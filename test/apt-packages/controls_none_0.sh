#!/bin/sh
# Verify installed packages and retained metadata under non-default controls.
set -eu
dpkg-query -W bc file >/dev/null
find /var/lib/apt/lists -name "*_Packages*" | grep -q .
echo "installation controls passed"
