#!/bin/sh
# Verify installed packages and retained metadata under non-default controls.
set -eu
pacman -Q tree >/dev/null
find /var/lib/pacman/sync -name "*.db" | grep -q .
if find /var/cache/pacman/pkg -name "*.pkg.tar.*" 2>/dev/null | grep -q .; then echo "package files were not cleaned" >&2; exit 1; fi
echo "installation controls passed"
