# shellcheck shell=bash
# Assertions shared by composition scenarios; the Node Feature supplies its own defaults without Antigravity options.
node_cli_and_initializer() {
  agy --version && /usr/local/share/antigravity-feature/initialize
}
node_default_tools() {
  local version
  version="$(pnpm --version)"
  [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && command -v npm >/dev/null \
    && command -v python3 >/dev/null && command -v make >/dev/null && command -v g++ >/dev/null
}
