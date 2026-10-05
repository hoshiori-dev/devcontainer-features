# shellcheck shell=bash
# Sourced by the openspec test scripts, never run: the installed locations, the assertions more than one test script
# uses, and the probe call those assertions share. The dev container CLI copies this whole directory into the
# workspace folder, the directory every test script starts in.

# Not named PREFIX: nvm, which a scenario runs, refuses to work while a variable of that name is set.
readonly PREFIX_DIR="/usr/local/lib/openspec"
readonly WRAPPER="/usr/local/bin/openspec"
readonly REGISTRY="https://registry.npmjs.org/"

# Prints what an openspec process sees: on line 1 "NO_UPDATE_CHECK=<state> TELEMETRY=<state>" for
# OPENSPEC_NO_UPDATE_CHECK and OPENSPEC_TELEMETRY, each state "unset" or "set:<value>", and on line 2 the Node.js
# binary the process runs on. probe.cjs prints both and exits before OpenSpec loads. The arguments are env(1) options
# and assignments that make up the caller's environment: -u NAME unsets, NAME=value sets, options before assignments.
openspec_probe() {
  env "$@" NODE_OPTIONS="--require=${PWD}/probe.cjs" openspec --version
}

# Whether an openspec process sees the variable $1 (OPENSPEC_NO_UPDATE_CHECK or OPENSPEC_TELEMETRY) in the state $2,
# "unset" or "set:<value>". The remaining arguments make up the caller's environment, as openspec_probe takes them.
openspec_sees() {
  local variable="$1"
  local state="$2"
  local seen
  local -a lines
  shift 2
  seen="$(openspec_probe "$@")" || return
  readarray -t lines <<<"${seen}"
  printf '%s\n' "the openspec process sees ${lines[0]}"
  [[ " ${lines[0]} " == *" ${variable#OPENSPEC_}=${state} "* ]]
}

# Whether an openspec process runs on the Node.js binary $1.
openspec_runs_on() {
  local seen
  local -a lines
  seen="$(openspec_probe)" || return
  readarray -t lines <<<"${seen}"
  printf '%s\n' "the openspec process runs on ${lines[1]}"
  [[ "${lines[1]}" == "$1" ]]
}

# Whether `openspec --version` succeeds and prints exactly the version $1. The remaining arguments change the
# caller's environment, as openspec_probe takes them.
openspec_reports_version() {
  local version="$1"
  local reported
  shift
  reported="$(env "$@" openspec --version)" || return
  printf '%s\n' "openspec --version prints ${reported}"
  [[ "${reported}" == "${version}" ]]
}

# Whether the package installed as @fission-ai/openspec is at exactly the version $1, as its package.json states it.
openspec_package_is_at() {
  local installed
  installed="$(
    node -p 'require(process.argv[1]).version' "${PREFIX_DIR}/node_modules/@fission-ai/openspec/package.json"
  )" || return
  printf '%s\n' "the installed package is at ${installed}"
  [[ "${installed}" == "$1" ]]
}

# Whether every package of the installed tree was downloaded from the public npm registry: each entry of the
# installed package-lock.json, the root aside, has a `resolved` URL under REGISTRY. Prints the entries that have not.
all_from_registry() {
  node - "${PREFIX_DIR}/package-lock.json" "${REGISTRY}" <<'EOF'
const [lockfile, registry] = process.argv.slice(2);
const packages = JSON.parse(require("node:fs").readFileSync(lockfile, "utf8")).packages;
const entries = Object.entries(packages).filter(([entry]) => entry !== "");
const elsewhere = entries.filter(([, value]) => !String(value.resolved).startsWith(registry));
for (const [entry, value] of elsewhere) console.log(`${entry}: ${value.resolved}`);
console.log(`${entries.length - elsewhere.length} of ${entries.length} entries resolved from ${registry}`);
process.exit(entries.length > 0 && elsewhere.length === 0 ? 0 : 1);
EOF
}

# Whether the prefix and the wrapper are the only paths that start with their names: no staging directory, set-aside
# previous prefix, or unfinished wrapper of an install is left next to them.
single_installation() {
  local -a paths=("${PREFIX_DIR}"* "${WRAPPER}"*)
  printf 'found %s\n' "${paths[@]}"
  [[ "${paths[*]}" == "${PREFIX_DIR} ${WRAPPER}" ]]
}
