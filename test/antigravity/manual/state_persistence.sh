#!/usr/bin/env bash
# Unattended two-container file persistence check. $1 is an image built with this checkout's Feature for vscode.
set -euo pipefail
image="$1"
volume="antigravity-fixture-$$"
isolated="antigravity-isolated-$$"
cleanup() { docker volume rm "${volume}" "${isolated}" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker volume create "${volume}" >/dev/null
docker volume create "${isolated}" >/dev/null
for current in "${volume}" "${isolated}"; do
  docker run --rm --network none --user root --mount "type=volume,src=${current},dst=/var/lib/antigravity" \
    "${image}" chown -R vscode:vscode /var/lib/antigravity
done
# The child shell expands HOME and writes only synthetic fixtures; without a network the CLI reaches no service.
# shellcheck disable=SC2016
docker run --rm --network none --user vscode --env HOME=/home/vscode \
  --mount "type=volume,src=${volume},dst=/var/lib/antigravity" "${image}" bash -c '
  set -eu
  /usr/local/share/antigravity-feature/initialize
  printf "synthetic token fixture\n" > ~/.gemini/antigravity-cli/antigravity-oauth-token.next
  mv ~/.gemini/antigravity-cli/antigravity-oauth-token.next ~/.gemini/antigravity-cli/antigravity-oauth-token
  printf "synthetic plugin secret\n" > ~/.config/antigravity/plugin-secrets.json.next
  mv ~/.config/antigravity/plugin-secrets.json.next ~/.config/antigravity/plugin-secrets.json
  agy mcp add --type http recreation-fixture http://127.0.0.1:9 >/dev/null
  /usr/local/share/antigravity-feature/initialize >/dev/null
'
# A new container must see the same bytes and permissions without accessing an account.
# shellcheck disable=SC2016
docker run --rm --network none --user vscode --env HOME=/home/vscode \
  --mount "type=volume,src=${volume},dst=/var/lib/antigravity" "${image}" bash -c '
  set -eu
  /usr/local/share/antigravity-feature/initialize
  test "$(cat ~/.gemini/antigravity-cli/antigravity-oauth-token)" = "synthetic token fixture"
  test "$(cat ~/.config/antigravity/plugin-secrets.json)" = "synthetic plugin secret"
  test "$(stat -c %a /var/lib/antigravity/cli/antigravity-oauth-token)" = 600
  test "$(stat -c %a /var/lib/antigravity/plugin-secrets/plugin-secrets.json)" = 600
  test "$(stat -c %a /var/lib/antigravity)" = 700
  agy mcp list | grep -q recreation-fixture
'
# shellcheck disable=SC2016
docker run --rm --network none --user vscode --env HOME=/home/vscode \
  --mount "type=volume,src=${isolated},dst=/var/lib/antigravity" "${image}" bash -c '
  set -eu
  /usr/local/share/antigravity-feature/initialize
  test ! -e /var/lib/antigravity/cli/antigravity-oauth-token
  test ! -e /var/lib/antigravity/gemini-config/mcp_config.json
'
printf 'Two-container fixture persistence, permissions and project isolation pass.\n'
