#!/usr/bin/env bash
# Installs the OpenSpec CLI (npm package @fission-ai/openspec) as an npm project tree in
# /usr/local/lib/openspec, reached through the wrapper /usr/local/bin/openspec. Runs as root at
# image build time; options arrive as VERSION, DISABLEUPDATECHECK, and DISABLETELEMETRY.
#
# Every install builds and verifies a new tree in a staging directory and replaces the prefix and
# the wrapper only after every check passed, so a failure leaves an earlier installation as it was
# and a second install replaces the first. Nothing here weakens or skips a verification.
set -euo pipefail
umask 022

VERSION="${VERSION:-latest}"
DISABLEUPDATECHECK="${DISABLEUPDATECHECK:-true}"
DISABLETELEMETRY="${DISABLETELEMETRY:-false}"

PACKAGE="@fission-ai/openspec"
REGISTRY="https://registry.npmjs.org/"
PREFIX="/usr/local/lib/openspec"
WRAPPER="/usr/local/bin/openspec"
# What the current OpenSpec releases require; named when no Node.js is found. With a Node.js at
# hand, the requirement of the selected version is read from the registry instead.
NODE_MINIMUM="20.19.0"
# The npm that Node.js 20.19.0 ships, the oldest the verification was observed with.
NPM_MINIMUM="10.8.2"
# One exact version: MAJOR.MINOR.PATCH with an optional pre-release suffix. Checked against the
# `version` option here and against the version the registry document selects.
EXACT_VERSION='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'

fail() {
  echo "error: $*" >&2
  exit 1
}

# Whether version $1 is lower than $2, comparing MAJOR.MINOR.PATCH and ignoring any suffix.
older_than() {
  local -a have want
  local i
  IFS=. read -r -a have <<<"${1%%[-+]*}"
  IFS=. read -r -a want <<<"${2%%[-+]*}"
  for i in 0 1 2; do
    if ((10#${have[i]:-0} < 10#${want[i]:-0})); then return 0; fi
    if ((10#${have[i]:-0} > 10#${want[i]:-0})); then return 1; fi
  done
  return 1
}

# --- Checks that need no network: platform, version format, Node.js, npm ---------------------

os_names=unknown
if [ -r /etc/os-release ]; then
  # shellcheck source=/dev/null
  os_names=$(. /etc/os-release && echo "${ID:-unknown} ${ID_LIKE:-}")
fi
case " $os_names " in
  *" debian "*) ;;
  *)
    fail "unsupported distribution: ${os_names%% *}. The openspec feature supports Debian and Ubuntu" \
      "(ID or ID_LIKE in /etc/os-release naming debian)."
    ;;
esac

machine=$(uname -m)
case "$machine" in
  x86_64 | amd64 | aarch64 | arm64) ;;
  *) fail "unsupported architecture: $machine. The openspec feature supports amd64 and arm64." ;;
esac

if [ "$VERSION" != latest ] && ! [[ "$VERSION" =~ $EXACT_VERSION ]]; then
  fail "version \"$VERSION\" is not accepted: only latest or an exact version such as 1.13.2 is accepted," \
    "not a range, a partial version, or another dist-tag."
fi

TMP=""
STAGING=""
PREVIOUS=""
cleanup() {
  rm -rf "$TMP" "$STAGING" "$PREVIOUS" "$WRAPPER.new"
}
trap cleanup EXIT

TMP=$(mktemp -d)
mkdir "$TMP/home" "$TMP/config" "$TMP/cache" "$TMP/tmp"
: >"$TMP/userconfig"
: >"$TMP/globalconfig"
# The new tree is built next to the prefix and replaces it only after every check passed. Its
# directory is named like the prefix's, because npm records that name in package-lock.json.
STAGING=$(mktemp -d "$PREFIX.staging.XXXXXX")
TREE="$STAGING/${PREFIX##*/}"
mkdir "$TREE"
chmod 755 "$STAGING" "$TREE"

# Node.js and npm see PATH and a HOME in the temporary directory, and nothing else of the build's
# environment: no NODE_*, npm_config_*, proxy, or certificate variable reaches them. TMPDIR is the
# feature's own, so npm's compile cache (Node.js 22 and later) goes with the temporary directory
# instead of staying in the image's /tmp.
clean() {
  env -i PATH="$PATH" HOME="$TMP/home" TMPDIR="$TMP/tmp" "$@"
}

# The user and global npm configuration are two distinct empty files, the project configuration is
# the empty staging tree's, and the cache with its logs is in the temporary directory.
NPM_FLAGS=(
  "--registry=$REGISTRY"
  --strict-ssl=true
  "--userconfig=$TMP/userconfig"
  "--globalconfig=$TMP/globalconfig"
  --ignore-scripts
  --engine-strict
  --no-audit
  --no-update-notifier
  "--cache=$TMP/cache"
  "--prefix=$TREE"
)

if ! command -v node >/dev/null 2>&1; then
  fail "Node.js is required: no node was found on PATH. OpenSpec needs Node.js $NODE_MINIMUM or newer, which" \
    "the dependency ghcr.io/devcontainers/features/node installs."
fi
NODE_BIN=$(readlink -f "$(command -v node)")
node_version=$(clean "$NODE_BIN" --version) || fail "$NODE_BIN --version failed."
node_version=${node_version#v}
[[ "$node_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || fail "$NODE_BIN reports the version \"$node_version\"."

if ! command -v npm >/dev/null 2>&1; then
  fail "npm $NPM_MINIMUM or newer is required: no npm was found on PATH."
fi
npm_version=$(clean npm --version "${NPM_FLAGS[@]}") \
  || fail "npm $NPM_MINIMUM or newer is required: npm --version failed."
if ! [[ "$npm_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || older_than "$npm_version" "$NPM_MINIMUM"; then
  fail "npm $NPM_MINIMUM or newer is required: found npm $npm_version."
fi

command -v setpriv >/dev/null 2>&1 \
  || fail "setpriv (util-linux) is required to check the installation as an unprivileged user."

# --- npm's configuration, before the first download -------------------------------------------

# No flag replaces the npmrc built into npm's own installation, so what npm reports under the flags
# above is checked instead.
clean npm config list --json "${NPM_FLAGS[@]}" >"$TMP/npm-config.json" \
  || fail "npm config list failed, so npm's configuration cannot be checked."
clean "$NODE_BIN" - "$TMP/npm-config.json" "$REGISTRY" <<'EOF'
const config = JSON.parse(require("node:fs").readFileSync(process.argv[2], "utf8"));
const keys = [];
if (config["strict-ssl"] !== true) keys.push("strict-ssl");
if (config.registry !== process.argv[3]) keys.push("registry");
for (const key of ["ca", "cafile", "proxy", "https-proxy"]) {
    if (config[key] !== null) keys.push(key);
}
for (const key of Object.keys(config)) {
    if (key.endsWith(":registry")) keys.push(key);
}
if (keys.length > 0) {
    console.error(
        `error: npm's configuration sets ${keys.join(", ")}, which the feature's flags do not override. ` +
            "A certificate authority, proxy, or scoped registry in the npmrc built into the Node.js " +
            "installation would change where packages come from or how certificates are checked; " +
            "remove the setting from that file.",
    );
    process.exit(1);
}
EOF

# --- Version selection: one read of the registry document ------------------------------------

# TLS alone, no redirect followed. The document only selects the version, its publish time, and
# the Node.js it requires; the packages are verified below.
selection=$(
  clean "$NODE_BIN" - "$VERSION" "$EXACT_VERSION" "$PACKAGE" "$REGISTRY" <<'EOF'
const [requested, pattern, name, registry] = process.argv.slice(2);
const url = registry + name.replace("/", "%2f");
function fail(message) {
    console.error(`error: ${message}`);
    process.exit(1);
}
(async () => {
    let document;
    try {
        const response = await fetch(url, {
            redirect: "error",
            headers: { accept: "application/json" },
            signal: AbortSignal.timeout(120000),
        });
        if (response.status !== 200) fail(`${url} answered ${response.status}.`);
        document = await response.json();
    } catch (error) {
        const cause = error.cause ? ` (${error.cause.code ?? error.cause.message})` : "";
        fail(`could not read ${url}: ${error.message}${cause}.`);
    }
    const latest = document?.["dist-tags"]?.latest;
    if (requested === "latest" && (typeof latest !== "string" || !new RegExp(pattern).test(latest))) {
        fail(`the registry names ${JSON.stringify(latest)} as latest of ${name}, which is not an exact version.`);
    }
    const version = requested === "latest" ? latest : requested;
    const versions = document?.versions ?? {};
    if (!new RegExp(pattern).test(version) || !Object.hasOwn(versions, version)) {
        fail(`${name} ${version} is not published on the npm registry (requested version: ${requested}).`);
    }
    const time = document?.time?.[version];
    const published = new Date(typeof time === "string" ? time : NaN);
    if (Number.isNaN(published.getTime())) {
        fail(`the registry gives no publish time for ${name} ${version}.`);
    }
    const engine = versions[version]?.engines?.node;
    console.log(version);
    console.log(published.toISOString());
    console.log(typeof engine === "string" ? engine.replace(/\s+/g, " ").trim() : "");
})();
EOF
)
mapfile -t selected <<<"$selection"
OPENSPEC_VERSION=${selected[0]:-}
PUBLISHED=${selected[1]:-}
NODE_RANGE=${selected[2]:-}
[[ "$OPENSPEC_VERSION" =~ $EXACT_VERSION ]] \
  || fail "the selected version \"$OPENSPEC_VERSION\" is not an exact version."
[[ "$PUBLISHED" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$ ]] \
  || fail "the publish time \"$PUBLISHED\" of $PACKAGE $OPENSPEC_VERSION is not a date."

# The usual form of the requirement is compared here, for a message naming both versions; npm's
# --engine-strict enforces every form of it during the install.
if [[ "$NODE_RANGE" =~ ^\>=\ ?([0-9]+\.[0-9]+\.[0-9]+)$ ]] && older_than "$node_version" "${BASH_REMATCH[1]}"; then
  fail "OpenSpec $OPENSPEC_VERSION requires Node.js $NODE_RANGE: found Node.js $node_version at $NODE_BIN."
fi

echo "Installing $PACKAGE $OPENSPEC_VERSION (published $PUBLISHED) on Node.js $node_version, npm $npm_version."

# --- Install into the staging directory ------------------------------------------------------

# --before bounds every package, dependencies included, to what the registry had published when
# this OpenSpec version was released. npm checks each tarball against the sha512 integrity of its
# registry manifest; no install script runs.
if ! clean npm install "${NPM_FLAGS[@]}" "--before=$PUBLISHED" "$PACKAGE@$OPENSPEC_VERSION" 2>&1 \
  | tee "$TMP/install.log"; then
  if grep -q EINTEGRITY "$TMP/install.log"; then
    fail "integrity verification failed: a package does not match the sha512 hash the npm registry publishes" \
      "for it (EINTEGRITY above)."
  fi
  fail "npm install of $PACKAGE@$OPENSPEC_VERSION failed; see npm's error above."
fi

# npm audit signatures skips a package that does not come from a registry, so the source of every
# entry is checked here, together with what was installed under the package's name.
clean "$NODE_BIN" - "$TREE/package-lock.json" "$PACKAGE" "$OPENSPEC_VERSION" "$REGISTRY" <<'EOF'
const [lockfile, name, version, registry] = process.argv.slice(2);
const packages = JSON.parse(require("node:fs").readFileSync(lockfile, "utf8")).packages ?? {};
function fail(message) {
    console.error(`error: ${message}`);
    process.exit(1);
}
const main = packages[`node_modules/${name}`];
if (!main) fail(`package-lock.json has no entry node_modules/${name}.`);
if (main.name !== undefined) {
    fail(`node_modules/${name} is an alias of ${main.name}, not ${name} itself.`);
}
if (main.version !== version) {
    fail(`node_modules/${name} is at version ${main.version}, not the selected ${version}.`);
}
for (const [entry, value] of Object.entries(packages)) {
    if (entry === "") continue;
    if (typeof value.resolved !== "string" || !value.resolved.startsWith(registry)) {
        fail(`${entry} was resolved from ${JSON.stringify(value.resolved)}, not from ${registry}.`);
    }
}
EOF

# Registry signatures and provenance attestations, on the cache the install filled, so that npm
# verifies the package documents the install took each integrity hash from.
if ! clean npm audit signatures "${NPM_FLAGS[@]}" --prefer-offline 2>&1 | tee "$TMP/audit.log"; then
  fail "signature verification failed: npm audit signatures did not verify the registry signature and the" \
    "published provenance attestations of every installed package; see npm's report above."
fi

# The only package code the build runs, as an unprivileged user and never as root.
reported=$(
  cd / && env -i PATH="$PATH" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" \
    OPENSPEC_TELEMETRY=0 OPENSPEC_NO_UPDATE_CHECK=1 \
    setpriv --reuid=65534 --regid=65534 --clear-groups --no-new-privs \
    "$NODE_BIN" "$TREE/node_modules/$PACKAGE/bin/openspec.js" --version
) || fail "openspec --version of the new installation failed as uid 65534; it is never run as root."
if [ "$reported" != "$OPENSPEC_VERSION" ]; then
  fail "the new installation reports version \"$reported\", not the selected $OPENSPEC_VERSION."
fi

# --- Replace the prefix and the wrapper ------------------------------------------------------

# The wrapper runs the Node.js resolved above, whatever the current Node.js is later, and passes
# the caller's environment through. An option sets its variable only while the caller has not set
# it; an empty value counts as set.
quote() {
  printf "'%s'" "${1//\'/\'\\\'\'}"
}
update_check=""
telemetry=""
if [ "$DISABLEUPDATECHECK" = true ]; then
  # shellcheck disable=SC2016
  update_check='[ "${OPENSPEC_NO_UPDATE_CHECK+set}" = set ] || export OPENSPEC_NO_UPDATE_CHECK=1'
fi
if [ "$DISABLETELEMETRY" = true ]; then
  # shellcheck disable=SC2016
  telemetry='[ "${OPENSPEC_TELEMETRY+set}" = set ] || export OPENSPEC_TELEMETRY=0'
fi
cat >"$TMP/wrapper" <<EOF
#!/bin/sh
# Written by the openspec dev container feature; every install rewrites it.
# Runs OpenSpec $OPENSPEC_VERSION on the Node.js found on PATH when the feature was installed.
node=$(quote "$NODE_BIN")
if [ ! -x "\$node" ]; then
  echo "openspec: \$node, the Node.js it was installed with, is missing." \\
    "Rebuild the container or install the openspec feature again." >&2
  exit 127
fi
$update_check
$telemetry
exec "\$node" $(quote "$PREFIX/node_modules/$PACKAGE/bin/openspec.js") "\$@"
EOF
install -o root -g root -m 0755 "$TMP/wrapper" "$WRAPPER.new"

if [ -e "$PREFIX" ]; then
  PREVIOUS=$(mktemp -d "$PREFIX.previous.XXXXXX")
  mv "$PREFIX" "$PREVIOUS/tree"
fi
if ! mv "$TREE" "$PREFIX"; then
  if [ -n "$PREVIOUS" ]; then
    mv "$PREVIOUS/tree" "$PREFIX"
  fi
  fail "could not move the new installation to $PREFIX."
fi
mv -f "$WRAPPER.new" "$WRAPPER"

echo "Installed OpenSpec $OPENSPEC_VERSION: $WRAPPER runs it on $NODE_BIN."
