#!/bin/sh
# Verify installed packages and retained metadata under non-default controls.
set -eu
rpm -q bc file >/dev/null
found=false
for f in /var/cache/zypp/solv/*/solv; do [ ! -s "$f" ] || found=true; done
[ "$found" = true ]
echo "installation controls passed"
