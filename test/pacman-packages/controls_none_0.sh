#!/bin/sh
# Verify installed packages and retained metadata under non-default controls.
set -eu
pacman -Q tree >/dev/null
find /var/lib/pacman/sync -name "*.db" | grep -q .
echo "installation controls passed"
