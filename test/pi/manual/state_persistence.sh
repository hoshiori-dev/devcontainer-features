#!/usr/bin/env bash
# Host-side two-container check of recreation and project isolation with synthetic fixtures only; no login, no real
# key, no network. $1 is an image built from this checkout's feature for the remote user vscode. Requires Docker.
set -euo pipefail

image="$1"
fixtures="$(cd "$(dirname "$0")/.." && pwd)"
volume="pi-fixture-$$"
isolated="pi-isolated-$$"
cleanup() { docker volume rm "${volume}" "${isolated}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Runs a networkless container as vscode with volume $1 at /var/lib/pi and the fixtures at /fixtures.
run_in() {
  local current="$1"
  shift
  docker run --rm --network none --user vscode --env HOME=/home/vscode \
    --mount "type=volume,src=${current},dst=/var/lib/pi" \
    --mount "type=bind,src=${fixtures},dst=/fixtures,readonly" "${image}" "$@"
}

for current in "${volume}" "${isolated}"; do docker volume create "${current}" >/dev/null; done
# The child shell expands HOME; the fixtures are synthetic and never reach a provider.
# shellcheck disable=SC2016
run_in "${volume}" bash -c '
  set -eu
  /usr/local/share/pi-feature/initialize
  install -m 0600 /fixtures/auth_fixture.json ~/.pi/agent/.auth.json.next
  mv ~/.pi/agent/.auth.json.next ~/.pi/agent/auth.json
  sessions=~/.pi/agent/sessions/--tmp-pi-session-fixture--
  mkdir -p "${sessions}" /tmp/pi-session-fixture
  cp /fixtures/session_fixture.jsonl "${sessions}/2026-10-23T00-00-00-000Z_fixture-session.jsonl"
  cd /tmp/pi-session-fixture
  printf "%s\n" "{\"type\":\"set_session_name\",\"name\":\"synthetic fixture name\"}" \
    | pi --offline --mode rpc --session-id fixture-session >/dev/null
  pi mcp add fixture --url https://example.invalid/mcp >/dev/null
'
# A new container must reopen the same credential, session, and configuration with private permissions.
# shellcheck disable=SC2016
run_in "${volume}" bash -c '
  set -eu
  /usr/local/share/pi-feature/initialize
  mkdir -p /tmp/pi-session-fixture && cd /tmp/pi-session-fixture
  test "$(pi auth check --provider anthropic --no-refresh)" = ready
  printf "%s\n" "{\"type\":\"get_entries\"}" | pi --offline --mode rpc --session fixture-session \
    | grep -q "synthetic fixture name"
  grep -q example.invalid ~/.pi/agent/mcp.json
  test "$(stat -c %a /var/lib/pi/agent/auth.json)" = 600
  test "$(stat -c %a /var/lib/pi)" = 700
  test "$(stat -c %a /var/lib/pi/agent)" = 700
'
# Another project's volume starts empty.
run_in "${isolated}" bash -c \
  '/usr/local/share/pi-feature/initialize && test ! -e /var/lib/pi/agent/auth.json'
printf 'Two-container credential, session, and configuration persistence, permissions, and isolation pass.\n'
