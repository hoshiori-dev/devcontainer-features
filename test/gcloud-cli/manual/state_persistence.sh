#!/usr/bin/env bash
# Unattended two-container file persistence check. $1 is an image built with this checkout's gcloud-cli Feature for
# vscode.
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "usage: $0 <image>" >&2
  exit 2
fi
image="$1"
volume="gcloud-cli-fixture-$$"
isolated="gcloud-cli-isolated-$$"
cleanup() {
  docker volume rm "${volume}" "${isolated}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker volume create "${volume}" >/dev/null
docker volume create "${isolated}" >/dev/null
for current in "${volume}" "${isolated}"; do
  docker run --rm --network none --user root --mount "type=volume,src=${current},dst=/var/lib/gcloud-cli" \
    "${image}" chown -R vscode:vscode /var/lib/gcloud-cli
done

# Write real gcloud config and synthetic credential fixtures in container 1 with no network access.
# Single-quoted bash -c script expands ~ inside the target container.
# shellcheck disable=SC2016
docker run --rm --network none --user vscode --env HOME=/home/vscode \
  --mount "type=volume,src=${volume},dst=/var/lib/gcloud-cli" "${image}" bash -c '
  set -euo pipefail
  /usr/local/share/gcloud-cli-feature/initialize
  gcloud config set core/project persistence-fixture-proj >/dev/null
  printf "synthetic cred fixture\n" > ~/.config/gcloud/credentials.db.next
  mv ~/.config/gcloud/credentials.db.next ~/.config/gcloud/credentials.db
  printf "synthetic adc fixture\n" > ~/.config/gcloud/application_default_credentials.json.next
  mv ~/.config/gcloud/application_default_credentials.json.next ~/.config/gcloud/application_default_credentials.json
  /usr/local/share/gcloud-cli-feature/initialize >/dev/null
'

# A fresh container mounting the same volume must see the same config, synthetic bytes, and private modes.
# Single-quoted bash -c script expands ~ and command substitutions inside the target container.
# shellcheck disable=SC2016
docker run --rm --network none --user vscode --env HOME=/home/vscode \
  --mount "type=volume,src=${volume},dst=/var/lib/gcloud-cli" "${image}" bash -c '
  set -euo pipefail
  /usr/local/share/gcloud-cli-feature/initialize
  test "$(gcloud config get-value core/project 2>/dev/null)" = "persistence-fixture-proj"
  test "$(cat ~/.config/gcloud/credentials.db)" = "synthetic cred fixture"
  test "$(cat ~/.config/gcloud/application_default_credentials.json)" = "synthetic adc fixture"
  test "$(stat -c %a /var/lib/gcloud-cli)" = 700
  test "$(stat -c %a /var/lib/gcloud-cli/config/credentials.db)" = 600
  test "$(stat -c %a /var/lib/gcloud-cli/config/application_default_credentials.json)" = 600
'

# An independent volume sees none of the first volume's configuration or credential fixtures.
# Single-quoted bash -c script expands command substitution inside the target container.
# shellcheck disable=SC2016
docker run --rm --network none --user vscode --env HOME=/home/vscode \
  --mount "type=volume,src=${isolated},dst=/var/lib/gcloud-cli" "${image}" bash -c '
  set -euo pipefail
  /usr/local/share/gcloud-cli-feature/initialize
  test ! -e /var/lib/gcloud-cli/config/credentials.db
  test ! -e /var/lib/gcloud-cli/config/application_default_credentials.json
  test -z "$(gcloud config get-value core/project 2>/dev/null || true)"
'

printf 'Two-container fixture persistence, permissions, and project isolation pass.\n'
