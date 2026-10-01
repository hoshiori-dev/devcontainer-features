# shellcheck shell=bash
# Helpers shared by the openspec test scripts. Sourced, never run: the dev container CLI copies
# this whole directory into the workspace folder, the directory every test script starts in.

# Not named PREFIX: nvm, which a scenario runs, refuses to work while a variable of that name is set.
PREFIX_DIR=/usr/local/lib/openspec
WRAPPER=/usr/local/bin/openspec
REGISTRY=https://registry.npmjs.org/

# The version the registry names as latest, read now. A release published between the build and
# this read fails the comparison with the installed version; a rerun fixes it.
registry_latest() {
  node -e '
    fetch(process.argv[1] + "@fission-ai%2fopenspec", { redirect: "error" })
        .then((response) => response.json())
        .then((document) => console.log(document["dist-tags"].latest));
  ' "$REGISTRY"
}

# What an openspec process sees of OPENSPEC_NO_UPDATE_CHECK and OPENSPEC_TELEMETRY, as one line
# such as "NO_UPDATE_CHECK=set:1 TELEMETRY=unset". The arguments are env(1) options and assignments
# that make up the caller's environment: -u NAME unsets, NAME=value sets, options before
# assignments. probe.cjs answers before OpenSpec loads, so no OpenSpec command other than --version
# ever runs.
seen_env() {
  env "$@" NODE_OPTIONS="--require=$PWD/probe.cjs" openspec --version | sed -n 1p
}

# The Node.js binary an openspec process runs on.
seen_node() {
  NODE_OPTIONS="--require=$PWD/probe.cjs" openspec --version | sed -n 2p
}

# Whether every package of the installed tree was downloaded from the public npm registry.
all_from_registry() {
  # shellcheck disable=SC2016
  node -e '
    const [lockfile, registry] = process.argv.slice(1);
    const packages = JSON.parse(require("node:fs").readFileSync(lockfile, "utf8")).packages;
    const entries = Object.entries(packages).filter(([entry]) => entry !== "");
    const elsewhere = entries.filter(([, value]) => !String(value.resolved).startsWith(registry));
    for (const [entry, value] of elsewhere) console.log(`${entry}: ${value.resolved}`);
    console.log(`${entries.length - elsewhere.length} of ${entries.length} entries resolved from ${registry}`);
    process.exit(entries.length > 0 && elsewhere.length === 0 ? 0 : 1);
  ' "$PREFIX_DIR/package-lock.json" "$REGISTRY"
}

# Whether nothing below the home names OpenSpec: no configuration, data, or cache of it.
home_without_openspec() {
  [ -z "$(find "$HOME" -iname '*openspec*' -print -quit 2>/dev/null)" ]
}

# Whether the home holds no npm cache entry, log, or configuration naming the OpenSpec package.
# The Node.js feature may leave an npm cache of its own there, which is not this feature's.
home_without_npm_traces() {
  ! grep -rqsF fission-ai "$HOME/.npm" "$HOME/.npmrc" "$HOME/.cache"
}

# Whether the workspace folder holds nothing `openspec init` would write: no openspec directory,
# no agent instruction file, and no hidden directory other than the test's own .devcontainer.
workspace_untouched() {
  [ ! -e openspec ] && [ ! -e AGENTS.md ] && [ ! -e CLAUDE.md ] \
    && [ -z "$(find . -mindepth 1 -maxdepth 1 -name '.*' ! -name .devcontainer -print -quit)" ]
}

# Whether one prefix and one wrapper exist, with no staging directory, set-aside tree, or
# unfinished wrapper next to them.
single_installation() {
  [ "$(echo "$PREFIX_DIR"* "$WRAPPER"*)" = "$PREFIX_DIR $WRAPPER" ]
}

# The version in the package.json of the installed OpenSpec package.
installed_version() {
  node -p 'require(process.argv[1]).version' "$PREFIX_DIR/node_modules/@fission-ai/openspec/package.json"
}
