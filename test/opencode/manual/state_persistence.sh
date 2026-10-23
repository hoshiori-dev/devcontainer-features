#!/usr/bin/env bash
# Host-side two-container check of recreation and project isolation with synthetic fixtures only; no login, no real
# key, no network. $1 is an image built from this checkout's feature for the remote user vscode. Requires Docker.
set -euo pipefail

image="$1"
fixtures="$(cd "$(dirname "$0")/.." && pwd)"
volume="opencode-fixture-$$"
isolated="opencode-isolated-$$"
cleanup() { docker volume rm "${volume}" "${isolated}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Runs a networkless container as vscode with volume $1 at /var/lib/opencode and the fixtures at /fixtures.
run_in() {
  local current="$1"
  shift
  docker run --rm --network none --user vscode --env HOME=/home/vscode \
    --mount "type=volume,src=${current},dst=/var/lib/opencode" \
    --mount "type=bind,src=${fixtures},dst=/fixtures,readonly" "${image}" "$@"
}

for current in "${volume}" "${isolated}"; do docker volume create "${current}" >/dev/null; done
# The child shell expands HOME; the fixtures are synthetic and never reach a provider.
# shellcheck disable=SC2016
run_in "${volume}" bash -c '
  set -eu
  /usr/local/share/opencode-feature/initialize
  mkdir -p /tmp/opencode-session-fixture && cd /tmp/opencode-session-fixture
  opencode auth import --standalone /fixtures/credential_fixture.json >/dev/null
  opencode session import --standalone /fixtures/session_fixture.json >/dev/null
  printf "{\"autoupdate\":false}\n" > ~/.config/opencode/opencode.json.next
  mv ~/.config/opencode/opencode.json.next ~/.config/opencode/opencode.json
'
# A new container must reopen the same credential, session, and configuration with private permissions.
# shellcheck disable=SC2016
run_in "${volume}" bash -c '
  set -eu
  /usr/local/share/opencode-feature/initialize
  mkdir -p /tmp/opencode-session-fixture && cd /tmp/opencode-session-fixture
  opencode auth list --standalone | grep -q "Synthetic fixture"
  opencode session list --standalone --format json | grep -q ses_fixture0000000000000000001
  test "$(cat ~/.config/opencode/opencode.json)" = "{\"autoupdate\":false}"
  test "$(stat -c %a /var/lib/opencode/data/opencode.db)" = 600
  test "$(stat -c %a /var/lib/opencode)" = 700
'
# Another project's volume starts empty.
run_in "${isolated}" bash -c \
  '/usr/local/share/opencode-feature/initialize && test ! -e /var/lib/opencode/data/opencode.db'
printf 'Two-container credential, session, and configuration persistence, permissions, and isolation pass.\n'
