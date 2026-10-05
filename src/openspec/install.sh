#!/usr/bin/env bash
# Installs the OpenSpec CLI: the npm package @fission-ai/openspec and its dependencies, which npm downloads from the
# public npm registry at https://registry.npmjs.org/ and verifies against the registry's integrity hashes, registry
# signatures, and published provenance attestations, to /usr/local/lib/openspec, with the command at
# /usr/local/bin/openspec. Runs as root at image build time; the option `version` arrives as VERSION,
# `disableUpdateCheck` as DISABLEUPDATECHECK, and `disableTelemetry` as DISABLETELEMETRY.
set -euo pipefail

readonly PACKAGE="@fission-ai/openspec"
readonly REGISTRY_URL="https://registry.npmjs.org/"
# The package's registry document, the one request this script makes itself; npm makes every other one.
readonly DOCUMENT_URL="${REGISTRY_URL}${PACKAGE/\//%2f}"
# Sigstore's TUF repository, which npm reads the registry signing keys and the Sigstore trust root from during
# `npm audit signatures`. The script never passes it to npm; its log and failure lines name it.
readonly TUF_MIRROR_URL="https://tuf-repo-cdn.sigstore.dev"
readonly PREFIX="/usr/local/lib/openspec"
readonly WRAPPER="/usr/local/bin/openspec"
# Created during an install and removed on every exit: the directory the new tree is built in, the directory a
# previous prefix is set aside in, and the wrapper before it takes its place.
readonly STAGING_TEMPLATE="${PREFIX}.staging.XXXXXX"
readonly PREVIOUS_TEMPLATE="${PREFIX}.previous.XXXXXX"
readonly UNFINISHED_WRAPPER="${WRAPPER}.new"
# What the current OpenSpec releases require, named when no Node.js is found. With a Node.js at hand, the requirement
# of the selected version is read from the registry instead.
readonly NODE_MINIMUM="20.19.0"
# The npm that Node.js 20.19.0 ships, the oldest the verification was observed with.
readonly NPM_MINIMUM="10.8.2"
# One exact version: MAJOR.MINOR.PATCH with an optional pre-release suffix. The option `version` and the version the
# registry names as latest are both matched against it.
readonly EXACT_VERSION_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
# What `node --version`, after its leading v, and `npm --version` print: MAJOR.MINOR.PATCH with an optional
# pre-release or build suffix.
readonly TOOL_VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$'
# The user and group the build-time `openspec --version` check runs as, so no package code runs as root.
readonly UNPRIVILEGED_ID=65534
# How to fix a failed registry request.
readonly NETWORK_HINT="check that the build reaches ${REGISTRY_URL} directly: the build's proxy and certificate \
variables and the user, global, and project npm configuration are not used"

VERSION="${VERSION-latest}"
DISABLEUPDATECHECK="${DISABLEUPDATECHECK-true}"
DISABLETELEMETRY="${DISABLETELEMETRY-false}"

# The temporary directory: HOME, TMPDIR, the npm cache, and the npm configuration files of every Node.js and npm call.
tmp=""
# The directory made from STAGING_TEMPLATE, and the npm project tree inside it that becomes the prefix.
staging=""
tree=""
# The directory made from PREVIOUS_TEMPLATE.
previous=""
# The Node.js binary found on PATH, symbolic links followed, and the versions that Node.js and npm report.
node_bin=""
node_version=""
npm_version=""
# The version to install, its publish time, and the Node.js range it requires, as the registry document gives them.
openspec_version=""
published=""
node_range=""

log() {
  printf 'openspec: %s\n' "$*"
}

fail() {
  printf 'openspec: error: %s\n' "$*" >&2
  exit 1
}

# Removes the temporary directory and whatever an unfinished install left next to the prefix and the wrapper, on
# every exit, success or failure.
cleanup() {
  if [[ -n "${tmp}" ]]; then rm --recursive --force "${tmp}"; fi
  if [[ -n "${staging}" ]]; then rm --recursive --force "${staging}"; fi
  if [[ -n "${previous}" ]]; then rm --recursive --force "${previous}"; fi
  rm --force "${UNFINISHED_WRAPPER}"
}

# Runs node with PATH, a HOME and a TMPDIR in the temporary directory, and nothing else of the build's environment, so
# no NODE_*, proxy, or certificate variable reaches it.
run_node() {
  # TMPDIR keeps what Node.js and npm write to a temporary directory, such as the compile cache, out of the image.
  env --ignore-environment PATH="${PATH}" HOME="${tmp}/home" TMPDIR="${tmp}/tmp" node "$@"
}

# Runs npm in the same environment as run_node, so no npm_config_* variable reaches it either, with the flags no call
# varies; every call adds --prefix, the directory npm takes as its project.
run_npm() {
  # Two distinct empty files stand for the user and the global configuration, and the cache is in the temporary
  # directory. With --prefix, npm reads no project configuration from the build's working directory.
  env --ignore-environment PATH="${PATH}" HOME="${tmp}/home" TMPDIR="${tmp}/tmp" \
    npm \
    "--registry=${REGISTRY_URL}" \
    --strict-ssl=true \
    "--userconfig=${tmp}/userconfig" \
    "--globalconfig=${tmp}/globalconfig" \
    --ignore-scripts \
    --engine-strict \
    --no-audit \
    --no-update-notifier \
    "--cache=${tmp}/cache" \
    "$@"
}

# Succeeds when version $1 is lower than version $2, both MAJOR.MINOR.PATCH with an optional suffix, which is ignored.
older_than() {
  local -a have
  local -a want
  local component
  IFS=. read -r -a have <<<"${1%%[-+]*}"
  IFS=. read -r -a want <<<"${2%%[-+]*}"
  for component in 0 1 2; do
    if ((10#${have[component]} < 10#${want[component]})); then return 0; fi
    if ((10#${have[component]} > 10#${want[component]})); then return 1; fi
  done
  return 1
}

# Fails unless the image is Debian or a derivative of it on amd64 or arm64. Runs before VERSION becomes readonly:
# /etc/os-release assigns it too.
detect_platform() {
  local os_id
  local os_like
  local machine
  [[ -r /etc/os-release ]] || fail "cannot read /etc/os-release; use a Debian or Ubuntu image"
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  os_like="$(. /etc/os-release && printf '%s\n' "${ID_LIKE:-}")"
  [[ " ${os_id} ${os_like} " == *" debian "* ]] \
    || fail "unsupported distribution \"${os_id}\" (ID_LIKE \"${os_like}\");" \
      "use a Debian or Ubuntu image, or another whose /etc/os-release names debian in ID or ID_LIKE"
  machine="$(uname --machine)"
  case "${machine}" in
    x86_64 | aarch64) ;;
    *) fail "unsupported architecture \"${machine}\"; use an amd64 (x86_64) or arm64 (aarch64) image" ;;
  esac
}

validate_options() {
  if [[ "${VERSION}" != latest && ! "${VERSION}" =~ ${EXACT_VERSION_RE} ]]; then
    fail "option version is \"${VERSION}\", but only \"latest\" or an exact version is accepted;" \
      "set it to \"latest\" or to one published version such as 1.13.2"
  fi
  readonly VERSION
  [[ "${DISABLEUPDATECHECK}" =~ ^(true|false)$ ]] \
    || fail "option disableUpdateCheck is \"${DISABLEUPDATECHECK}\"; set it to true or false"
  readonly DISABLEUPDATECHECK
  [[ "${DISABLETELEMETRY}" =~ ^(true|false)$ ]] \
    || fail "option disableTelemetry is \"${DISABLETELEMETRY}\"; set it to true or false"
  readonly DISABLETELEMETRY
}

# Creates the temporary directory with what run_node and run_npm name in it, and an empty directory that npm takes
# as its project until the staging tree exists.
create_work_dir() {
  tmp="$(mktemp --directory)"
  mkdir "${tmp}/home" "${tmp}/tmp" "${tmp}/cache" "${tmp}/project"
  touch "${tmp}/userconfig" "${tmp}/globalconfig"
}

# Finds Node.js, npm, and setpriv on PATH, without any network access, and fails unless npm is NPM_MINIMUM or newer.
find_runtime() {
  local node_on_path
  node_on_path="$(command -v node)" \
    || fail "Node.js is required, but no node is on PATH; install Node.js ${NODE_MINIMUM} or newer before this" \
      "feature, as its dependency ghcr.io/devcontainers/features/node does"
  node_bin="$(readlink --canonicalize "${node_on_path}")"
  node_version="$(run_node --version)" \
    || fail "node --version failed (${node_bin}); put a working Node.js ${NODE_MINIMUM} or newer first on PATH"
  node_version="${node_version#v}"
  [[ "${node_version}" =~ ${TOOL_VERSION_RE} ]] \
    || fail "node reports the version \"${node_version}\" (${node_bin});" \
      "put a released Node.js ${NODE_MINIMUM} or newer first on PATH"

  command -v npm >/dev/null \
    || fail "npm ${NPM_MINIMUM} or newer is required, but no npm is on PATH;" \
      "install the npm that Node.js ${NODE_MINIMUM} or newer ships"
  npm_version="$(run_npm --prefix "${tmp}/project" --version)" \
    || fail "npm ${NPM_MINIMUM} or newer is required, but npm --version failed;" \
      "install the npm that Node.js ${NODE_MINIMUM} or newer ships"
  if [[ ! "${npm_version}" =~ ${TOOL_VERSION_RE} ]] || older_than "${npm_version}" "${NPM_MINIMUM}"; then
    fail "npm ${NPM_MINIMUM} or newer is required, but npm ${npm_version} was found;" \
      "install the npm that Node.js ${NODE_MINIMUM} or newer ships"
  fi

  command -v setpriv >/dev/null \
    || fail "setpriv is required to check the installation as an unprivileged user, but none is on PATH;" \
      "use an image that has util-linux"
}

# Fails when a directory is at the wrapper's path, before any network access and before anything of an earlier
# installation is touched: the wrapper could not take that path.
check_wrapper_path() {
  # A symbolic link is replaced like a file, whatever it points to.
  if [[ -d "${WRAPPER}" && ! -L "${WRAPPER}" ]]; then
    fail "${WRAPPER} is a directory, so the command openspec cannot be installed there;" \
      "remove that directory from the image before this feature is installed"
  fi
}

# Reads the package's registry document once, relying on TLS alone and following no redirect, and takes from it the
# version to install, its publish time, and the Node.js range it requires.
select_version() {
  local selection
  local -a selected
  # The document only selects what is installed; the packages are verified after the install.
  log "reading ${DOCUMENT_URL} to select the version for \"${VERSION}\""
  selection="$(
    run_node - "${VERSION}" "${EXACT_VERSION_RE}" "${PACKAGE}" "${DOCUMENT_URL}" "${NETWORK_HINT}" <<'EOF'
const [requested, exactVersion, name, url, networkHint] = process.argv.slice(2);
function fail(message) {
    console.error(`openspec: error: ${message}`);
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
        if (response.status !== 200) fail(`${url} answered ${response.status}; ${networkHint}`);
        document = await response.json();
    } catch (error) {
        const cause = error.cause ? ` (${error.cause.code ?? error.cause.message})` : "";
        fail(`cannot read ${url}: ${error.message}${cause}; ${networkHint}`);
    }
    let version = requested;
    if (requested === "latest") {
        version = document["dist-tags"]?.latest;
        if (typeof version !== "string" || !new RegExp(exactVersion).test(version)) {
            fail(
                `the registry names ${JSON.stringify(version)} as latest of ${name}, which is not an exact ` +
                    "version; set the option version to one published version",
            );
        }
    }
    const versions = document.versions ?? {};
    if (!Object.hasOwn(versions, version)) {
        fail(
            `${name} ${version} is not published on the npm registry; ` +
                'set the option version to "latest" or to a version the registry lists',
        );
    }
    const time = document.time?.[version];
    const published = new Date(typeof time === "string" ? time : NaN);
    if (Number.isNaN(published.getTime())) {
        fail(
            `the registry gives no publish time for ${name} ${version}, which bounds its dependencies; ` +
                "set the option version to another published version",
        );
    }
    const engine = versions[version].engines?.node;
    console.log(version);
    console.log(published.toISOString());
    console.log(typeof engine === "string" ? engine.replace(/\s+/g, " ").trim() : "");
})();
EOF
  )"
  readarray -t selected <<<"${selection}"
  openspec_version="${selected[0]}"
  published="${selected[1]}"
  # The third line is empty, and so missing here, when the version declares no Node.js range.
  node_range="${selected[2]-}"

  # The usual form of the range is compared here, for a message naming both versions; --engine-strict makes npm
  # enforce every form of it during the install.
  if [[ "${node_range}" =~ ^\>=\ ?([0-9]+\.[0-9]+\.[0-9]+)$ ]] \
    && older_than "${node_version}" "${BASH_REMATCH[1]}"; then
    fail "OpenSpec ${openspec_version} requires Node.js ${node_range}, but Node.js ${node_version} was found" \
      "(${node_bin}); put a Node.js in that range first on PATH"
  fi
  log "selected ${PACKAGE} ${openspec_version}, published ${published}, for Node.js ${node_version} (${node_bin})" \
    "and npm ${npm_version}"
}

# Installs the selected version with npm into a staging tree next to the prefix.
install_staged() {
  staging="$(mktemp --directory "${STAGING_TEMPLATE}")"
  # mktemp creates the directory for root alone, and the unprivileged version check has to reach the tree in it.
  chmod 0755 "${staging}"
  # The tree's directory is named like the prefix's, because npm records that name in package-lock.json.
  tree="${staging}/${PREFIX##*/}"
  mkdir "${tree}"
  log "installing ${PACKAGE}@${openspec_version} and its dependencies, none published after ${published}," \
    "from ${REGISTRY_URL} to ${tree}"
  # --before bounds every package, dependencies included, to what the registry had published when this OpenSpec
  # version was released; npm checks each tarball against the sha512 integrity of its registry manifest.
  if ! run_npm --prefix "${tree}" install "--before=${published}" "${PACKAGE}@${openspec_version}" 2>&1 \
    | tee "${tmp}/install.log"; then
    # Known failure mode: a tarball does not match the hash in its registry manifest, which npm reports as EINTEGRITY.
    if grep --quiet EINTEGRITY "${tmp}/install.log"; then
      fail "integrity verification failed: a package does not match the sha512 hash the npm registry publishes for" \
        "it (EINTEGRITY above); build again, and check the connection to ${REGISTRY_URL} if it fails again"
    fi
    fail "npm install of ${PACKAGE}@${openspec_version} failed (npm's error is above); ${NETWORK_HINT}"
  fi
}

# Fails unless package-lock.json holds the package itself at exactly the selected version and every entry came from
# the public registry.
check_sources() {
  # `npm audit signatures` skips a package that does not come from a registry, so this check is what keeps a git or
  # URL dependency out.
  run_node - "${tree}/package-lock.json" "${PACKAGE}" "${openspec_version}" "${REGISTRY_URL}" <<'EOF'
const [lockfile, name, version, registry] = process.argv.slice(2);
const packages = JSON.parse(require("node:fs").readFileSync(lockfile, "utf8")).packages;
function fail(message) {
    console.error(`openspec: error: ${message}`);
    process.exit(1);
}
const main = packages[`node_modules/${name}`];
if (!main) fail(`package-lock.json has no entry node_modules/${name}`);
if (main.name !== undefined) fail(`node_modules/${name} is an alias of ${main.name}, not ${name} itself`);
if (main.version !== version) fail(`node_modules/${name} is at version ${main.version}, not the selected ${version}`);
for (const [entry, value] of Object.entries(packages)) {
    if (entry === "") continue;
    if (typeof value.resolved !== "string" || !value.resolved.startsWith(registry)) {
        fail(
            `${entry} was resolved from ${JSON.stringify(value.resolved)}, not from ${registry}; check that the ` +
                `build reaches ${registry} directly and that the npmrc built into the Node.js installation sets no ` +
                "registry for this package, and build again",
        );
    }
}
EOF
}

# Has npm verify the registry signature and each published provenance attestation of every installed package.
verify_signatures() {
  log "verifying the registry signatures and provenance attestations of the packages in ${tree}, published at" \
    "${REGISTRY_URL}, with the signing keys from ${TUF_MIRROR_URL}"
  # --prefer-offline: the audit runs on the cache the install filled, so npm verifies the package documents the
  # install took each integrity hash from.
  run_npm --prefix "${tree}" audit signatures --prefer-offline \
    || fail "signature verification failed: npm audit signatures did not verify the registry signature and the" \
      "published provenance attestations of every installed package (npm's report is above);" \
      "check that the build reaches ${TUF_MIRROR_URL} directly, and build again"
}

# Runs `openspec --version` of the staged tree, the only package code the build runs, as an unprivileged user and
# fails unless it prints the selected version.
check_staged_version() {
  local reported
  # The user has no supplementary groups, telemetry and the update check are off, and HOME and XDG_CONFIG_HOME point
  # into the temporary directory, which that user cannot enter.
  # The one call that names the resolved Node.js binary instead of the command `node`: the check must run the binary
  # the wrapper pins. The path is an argument of setpriv, like the script it runs.
  reported="$(
    env --ignore-environment --chdir=/ PATH="${PATH}" HOME="${tmp}/home" XDG_CONFIG_HOME="${tmp}/config" \
      OPENSPEC_TELEMETRY=0 OPENSPEC_NO_UPDATE_CHECK=1 \
      setpriv "--reuid=${UNPRIVILEGED_ID}" "--regid=${UNPRIVILEGED_ID}" --clear-groups --no-new-privs \
      "${node_bin}" "${tree}/node_modules/${PACKAGE}/bin/openspec.js" --version
  )" || fail "openspec --version of the new installation failed as uid ${UNPRIVILEGED_ID};" \
    "the check never runs as root, so use a build that can switch to that user"
  [[ "${reported}" == "${openspec_version}" ]] \
    || fail "the new installation reports version \"${reported}\", not the selected ${openspec_version}"
}

# Writes the wrapper, which runs OpenSpec on the Node.js binary found at install time whatever the current Node.js is
# later, next to its final path.
write_wrapper() {
  local node_word
  local update_check_line=""
  local telemetry_line=""
  # No option value is written into the wrapper: the Node.js path is the only text that varies. A true option adds
  # one fixed line, which sets its variable only while the caller has not set it; an empty value counts as set.
  # The path as one single-quoted word of the wrapper; a single quote inside it is written as '\''.
  node_word="'${node_bin//\'/\'\\\'\'}'"
  if [[ "${DISABLEUPDATECHECK}" == true ]]; then
    # The wrapper expands this when it runs, so the text is kept literal here.
    # shellcheck disable=SC2016
    update_check_line='if [ "${OPENSPEC_NO_UPDATE_CHECK+set}" != set ]; then export OPENSPEC_NO_UPDATE_CHECK=1; fi'
  fi
  if [[ "${DISABLETELEMETRY}" == true ]]; then
    # The wrapper expands this when it runs, so the text is kept literal here.
    # shellcheck disable=SC2016
    telemetry_line='if [ "${OPENSPEC_TELEMETRY+set}" != set ]; then export OPENSPEC_TELEMETRY=0; fi'
  fi
  log "writing the wrapper to ${UNFINISHED_WRAPPER}; it runs OpenSpec on ${node_bin}"
  cat >"${tmp}/wrapper" <<EOF
#!/bin/sh
# Written by the openspec dev container feature; every install rewrites it.
# Runs OpenSpec on the Node.js that was first on PATH when the feature was installed.
node=${node_word}
if [ ! -x "\${node}" ]; then
  printf 'openspec: error: %s, the Node.js it was installed with, is missing; rebuild the container\n' "\${node}" >&2
  exit 127
fi
${update_check_line}
${telemetry_line}
exec "\${node}" "${PREFIX}/node_modules/${PACKAGE}/bin/openspec.js" "\$@"
EOF
  install --owner root --group root --mode 0755 "${tmp}/wrapper" "${UNFINISHED_WRAPPER}"
}

# Replaces the prefix as a whole with the staged tree, then the wrapper with the one written for it.
replace_installation() {
  log "replacing ${PREFIX} with the verified tree and ${WRAPPER} with ${UNFINISHED_WRAPPER}"
  if [[ -e "${PREFIX}" ]]; then
    previous="$(mktemp --directory "${PREVIOUS_TEMPLATE}")"
    mv "${PREFIX}" "${previous}/tree"
  fi
  # Known failure mode: the new tree cannot take the prefix's place after a previous one was set aside. The previous
  # one is put back, so the earlier installation stays as it was.
  if ! mv "${tree}" "${PREFIX}"; then
    if [[ -n "${previous}" ]]; then mv "${previous}/tree" "${PREFIX}"; fi
    fail "cannot move the new installation to ${PREFIX}"
  fi
  # --no-target-directory: the wrapper takes the path itself and is never moved into a directory found there.
  mv --force --no-target-directory "${UNFINISHED_WRAPPER}" "${WRAPPER}"
  log "installed OpenSpec ${openspec_version} to ${PREFIX}; ${WRAPPER} runs it on ${node_bin}"
}

main() {
  umask 022
  detect_platform
  validate_options
  trap cleanup EXIT
  create_work_dir
  find_runtime
  check_wrapper_path
  select_version
  install_staged
  check_sources
  verify_signatures
  check_staged_version
  write_wrapper
  replace_installation
}

main "$@"
