#!/bin/sh
# Verify installed packages and retained metadata under non-default controls.
set -eu
apk info -e tree >/dev/null
grep -qx tree /etc/apk/world
find /var/cache/apk-packages -type f \( -name "APKINDEX.*.tar.gz" -o -name "*.adb" \) | grep -q .
if find /var/cache/apk-packages -name "*.apk" 2>/dev/null | grep -q .; then echo "package files were not cleaned" >&2; exit 1; fi
echo "installation controls passed"
