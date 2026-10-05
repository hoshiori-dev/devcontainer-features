#!/bin/sh
# Verify installed packages and retained metadata under non-default controls.
set -eu
rpm -q bc file >/dev/null
found=false
for f in /var/cache/zypp/solv/*/solv; do [ ! -s "$f" ] || found=true; done
[ "$found" = true ]
for f in /var/cache/zypp/packages/*/*.rpm /var/cache/zypp/packages/*/*/*.rpm; do
  [ ! -f "$f" ] || { echo "package files were not cleaned" >&2; exit 1; }
done
echo "installation controls passed"
