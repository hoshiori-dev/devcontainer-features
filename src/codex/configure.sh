#!/usr/bin/env bash
# Uses Codex's native configuration API to preserve TOML and enforce managed policy without logging private values.
set -euo pipefail

server_pid=""
server_input=""
server_output=""
request_id=0
reply=""

log() { printf 'codex: %s\n' "$*"; }
fail() { printf 'codex: error: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "${server_pid}" ]]; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
  fi
}

# Sends one request and retains its result in reply; upstream errors may contain private configuration values.
request() {
  local method="$1" params="$2" message
  request_id=$((request_id + 1))
  jq --compact-output --null-input --argjson id "${request_id}" --arg method "${method}" --argjson params "${params}" \
    '{id: $id, method: $method, params: $params}' >&"${server_input}"
  while IFS= read -r -t 20 message <&"${server_output}"; do
    jq --exit-status 'type == "object"' >/dev/null 2>&1 <<<"${message}" \
      || fail "unsupported configuration protocol; select a supported stable release"
    if [[ "$(jq --raw-output '.id // empty' <<<"${message}")" == "${request_id}" ]]; then
      jq --exit-status 'has("error") | not' >/dev/null <<<"${message}" \
        || fail "cannot configure file credentials; inspect Codex configuration and managed policy locally"
      reply="$(jq --compact-output '.result' <<<"${message}")"
      return
    fi
  done
  fail "configuration is unavailable or timed out; inspect Codex syntax and managed policy locally"
}

configure_credentials() {
  local managed config profile profile_store backend key_path actual
  request initialize '{"clientInfo":{"name":"codex_feature","version":"1.0.0"}}'
  printf '%s\n' '{"method":"initialized"}' >&"${server_input}"
  request configRequirements/read '{}'
  managed="$(jq --raw-output '.requirements.cliAuthCredentialsStore // empty' <<<"${reply}")"
  [[ -z "${managed}" || "${managed}" == file ]] \
    || fail "managed policy conflicts with file credentials; ask its administrator"
  request config/read '{"includeLayers":false}'
  config="$(jq --compact-output '.config' <<<"${reply}")"
  profile="$(jq --raw-output '.profile // empty' <<<"${config}")"
  profile_store="$(jq --raw-output --arg profile "${profile}" \
    '.profiles[$profile].cli_auth_credentials_store // empty' <<<"${config}")"
  backend="${profile_store:-$(jq --raw-output '.cli_auth_credentials_store // empty' <<<"${config}")}"
  [[ -z "${backend}" || "${backend}" == file || "${backend}" == auto ]] \
    || fail "credential configuration conflicts; select file storage explicitly before retrying"
  if [[ "${backend}" != file ]]; then
    key_path="cli_auth_credentials_store"
    if [[ -n "${profile_store}" ]]; then
      key_path="profiles.$(jq --compact-output --null-input --arg profile "${profile}" '$profile').cli_auth_credentials_store"
    fi
    log "selecting file credential storage in the private configuration"
    request config/value/write "$(jq --compact-output --null-input --arg key "${key_path}" \
      '{keyPath:$key,value:"file",mergeStrategy:"replace"}')"
    request config/read '{"includeLayers":false}'
    actual="$(jq --raw-output --arg profile "${profile}" \
      '.config | .profiles[$profile].cli_auth_credentials_store // .cli_auth_credentials_store // empty' <<<"${reply}")"
    [[ "${actual}" == file ]] \
      || fail "file credentials remain overridden; resolve the conflicting configuration before retrying"
  fi
}

main() {
  trap cleanup EXIT
  cd "${HOME:-$(getent passwd "$(id --user)" | cut --delimiter=: --fields=6)}"
  coproc configuration_server { exec codex app-server --listen stdio:// 2>/dev/null; }
  server_pid=$!
  exec {server_input}>&"${configuration_server[1]}"
  exec {server_output}<&"${configuration_server[0]}"
  configure_credentials
}

main "$@"
