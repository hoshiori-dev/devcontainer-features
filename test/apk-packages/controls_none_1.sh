#!/bin/sh
# Verify installed packages and retained metadata under non-default controls.
set -eu
apk info -e tree >/dev/null
grep -qx tree /etc/apk/world
find /var/cache/apk-packages -type f \( -name "APKINDEX.*.tar.gz" -o -name "*.adb" \) | grep -q .
echo "installation controls passed"
