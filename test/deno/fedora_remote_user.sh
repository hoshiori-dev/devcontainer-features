#!/usr/bin/env bash
# Group-based access for a non-root remote user on dnf 4.
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib
check "the remote user is devuser" test "$(id -un)" = devuser
tools_access() {
    [ "$(stat -c %U:%G:%a /usr/local/share/deno)" = root:deno:2775 ] &&
        [ "$(stat -c %U:%G:%a /usr/local/share/deno/bin)" = root:deno:2775 ]
}
member() { case " $(id -nG) " in *" deno "*) return 0 ;; *) return 1 ;; esac; }
check "tools directories are root:deno with setgid access" tools_access
check "devuser is in deno" member
script="$(mktemp -d)/hello.ts"
echo 'console.log("group access");' >"${script}"
check "devuser installs a global tool" deno install --global --name deno-group-hello "${script}"
tool_runs() { [ "$(bash -c deno-group-hello)" = "group access" ]; }
check "the tool runs from a new shell" tool_runs
reportResults
