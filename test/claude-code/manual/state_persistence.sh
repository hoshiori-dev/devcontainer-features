#!/usr/bin/env bash
# Unattended two-container file persistence check. $1 is an image built with this checkout's Feature for vscode.
set -euo pipefail
image="$1"
volume="claude-code-fixture-$$"
isolated="claude-code-isolated-$$"
cleanup() { docker volume rm "${volume}" "${isolated}" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker volume create "${volume}" >/dev/null
docker volume create "${isolated}" >/dev/null
for current in "${volume}" "${isolated}"; do
  docker run --rm --network none --user root --mount "type=volume,src=${current},dst=/var/lib/claude-code" \
    "${image}" chown vscode:vscode /var/lib/claude-code
done
# The child shell expands HOME and generates only a fake fixture, never a real login.
# shellcheck disable=SC2016
docker run --rm --network none --user vscode --env HOME=/home/vscode \
  --mount "type=volume,src=${volume},dst=/var/lib/claude-code" "${image}" bash -c '
  set -eu
  /usr/local/share/claude-code-feature/initialize
  umask 077
  printf "synthetic credential fixture\n" > ~/.claude/.credentials.json.next
  mv ~/.claude/.credentials.json.next ~/.claude/.credentials.json
  printf "synthetic session fixture\n" > ~/.claude/session-fixture
  claude mcp add --scope user --transport http recreation-fixture http://127.0.0.1:9 >/dev/null
'
# A new container must see the same bytes and permissions without accessing an account.
# shellcheck disable=SC2016
docker run --rm --network none --user vscode --env HOME=/home/vscode \
  --mount "type=volume,src=${volume},dst=/var/lib/claude-code" "${image}" bash -c '
  set -eu
  /usr/local/share/claude-code-feature/initialize
  test "$(cat ~/.claude/.credentials.json)" = "synthetic credential fixture"
  test "$(cat ~/.claude/session-fixture)" = "synthetic session fixture"
  test "$(stat -c %a ~/.claude/.credentials.json)" = 600
  test "$(stat -c %a /var/lib/claude-code)" = 700
  claude mcp get recreation-fixture >/dev/null
'
docker run --rm --network none --user vscode --env HOME=/home/vscode \
  --mount "type=volume,src=${isolated},dst=/var/lib/claude-code" "${image}" bash -c \
  '/usr/local/share/claude-code-feature/initialize && test ! -e /var/lib/claude-code/session-fixture'
printf 'Two-container fixture persistence, permissions and project isolation pass.\n'
