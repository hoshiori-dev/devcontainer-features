#!/bin/sh
# Scenario: filled-volume repair, failure paths, and preservation of modes and external targets.
set -e
if [ -z "${FEATURE_TEST_BASH:-}" ]; then
    FEATURE_TEST_BASH=1 exec bash "$0" "$@"
fi
# shellcheck source=/dev/null
. dev-container-features-test-lib
umask 022
repair=/usr/local/share/uv-feature/repair-volume
volume=/var/lib/uv
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
snapshot() {
    find "$volume" -printf '%P %m\n' | sort
}
foreign_snapshot() {
    find "$volume" -printf '%P %U %G %m\n' | sort
}
warning_names_reason() {
    grep -q '^uv feature: warning: /var/lib/uv:' "$work/warning" && grep -q "$1" "$work/warning" && grep -q NOTES.md "$work/warning"
}
check "the scenario is non-root" [ "$(id -u)" != 0 ]
check "fill with a managed interpreter" uv venv --managed-python "$work/first"
check "fill the cache with a package" uv pip install --python "$work/first/bin/python" pycowsay
sudo mkdir -p /tmp/uv-repair-external-dir
sudo touch /tmp/uv-repair-external-file /tmp/uv-repair-external-dir/file
ln -s /tmp/uv-repair-external-file "$volume/cache/external-file"
ln -s /tmp/uv-repair-external-dir "$volume/cache/external-dir"
external_before=$(stat -c '%u %g %a' /tmp/uv-repair-external-file /tmp/uv-repair-external-dir /tmp/uv-repair-external-dir/file)
sudo chown -hR 23457:23457 "$volume"
before=$(sudo find "$volume" -printf '%P %m\n' | sort)
foreign_before=$(sudo find "$volume" -printf '%P %U %G %m\n' | sort)
# shellcheck disable=SC2016
check "foreign ownership really breaks uv" sh -c 'if uv venv --managed-python "$1" >"$2" 2>&1; then exit 1; fi; grep -q "Failed to initialize cache" "$2"' sh "$work/broken" "$work/broken.log"
mkdir "$work/stubs"
cat >"$work/stubs/sudo" <<'STUB'
#!/bin/sh
[ "$1" = -n ] || exit 99
if [ "$2" = true ]; then
    [ "$SUDO_MODE" != denied ] && exit 0
    echo 'password required' >&2
    exit 1
fi
echo 'simulated chown failure' >&2
exit 1
STUB
chmod +x "$work/stubs/sudo"
check "no passwordless sudo still exits zero" env PATH="$work/stubs:$PATH" SUDO_MODE=denied "$repair" 2>"$work/warning"
check "warning names passwordless sudo" warning_names_reason 'passwordless sudo'
check "failed sudo leaves all state unchanged" [ "$(sudo find "$volume" -printf '%P %U %G %m\n' | sort)" = "$foreign_before" ]
check "failed chown still exits zero" env PATH="$work/stubs:$PATH" SUDO_MODE=failed "$repair" 2>"$work/warning"
check "warning includes failed chown reason" warning_names_reason 'simulated chown failure'
check "failed chown leaves state unchanged" [ "$(sudo find "$volume" -printf '%P %U %G %m\n' | sort)" = "$foreign_before" ]
check "the filled volume is repaired" "$repair"
# shellcheck disable=SC2016
check "everything now has the user and group uv" sh -c 'test -z "$(find /var/lib/uv ! -uid "$(id -u)" -print -quit)" && test -z "$(find /var/lib/uv ! -group uv -print -quit)"'
check "all modes stay unchanged" [ "$(snapshot)" = "$before" ]
check "external link targets stay unchanged" [ "$(stat -c '%u %g %a' /tmp/uv-repair-external-file /tmp/uv-repair-external-dir /tmp/uv-repair-external-dir/file)" = "$external_before" ]
check "the preserved interpreter creates an offline environment" uv venv --offline --managed-python "$work/offline"
check "the package installs from the preserved cache offline" uv pip install --offline --python "$work/offline/bin/python" pycowsay
check "a further interpreter installs" uv python install 3.13
cat >"$work/stubs/sudo" <<'STUB'
#!/bin/sh
: >"$SUDO_RECORD"
exit 1
STUB
fits_before=$(foreign_snapshot)
check "a fitting volume exits zero" env PATH="$work/stubs:$PATH" SUDO_RECORD="$work/called" "$repair" 2>"$work/warning"
check "a fitting volume never runs sudo" test ! -e "$work/called"
check "a fitting volume prints no warning" test ! -s "$work/warning"
check "a fitting volume changes nothing" [ "$(foreign_snapshot)" = "$fits_before" ]
sudo mkdir -p "$volume/cache/deep/root"
sudo touch "$volume/cache/deep/root/file"
check "root-owned entries are repaired" "$repair"
check "the deep file now belongs to the remote user" [ "$(stat -c %u "$volume/cache/deep/root/file")" = "$(id -u)" ]
reportResults
