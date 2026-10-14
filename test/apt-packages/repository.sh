# shellcheck shell=bash
# Sourced, after installer.sh, by the apt-packages scenario scripts that need releases, versions, and packages of their
# own, so that no check depends on what a public mirror offers when it runs. The script builds small packages, publishes
# them as suites of one signed repository in the container, and makes those suites the image's only sources. The
# scenario's Dockerfile adds the two tools this takes, apt-ftparchive and gpg.

readonly REPOSITORY="/tmp/repository"
readonly REPOSITORY_KEYRING="${REPOSITORY}/key.gpg"
readonly REPOSITORY_SOURCES="/etc/apt/sources.list.d/repository.list"

# Prints the path of a new package tree for the suite $1: the package $2 at version $3, for every architecture. Further
# arguments are control fields, such as "Depends: other". The caller may add files to the tree before it calls pack.
package_tree() {
  local tree="${REPOSITORY}/trees/$1/$2_$3"
  mkdir -p "${tree}/DEBIAN" "${REPOSITORY}/pool/$1"
  printf '%s\n' "Package: $2" "Version: $3" "Architecture: all" "Maintainer: Scenario <scenario@example.invalid>" \
    "Description: package of an apt-packages scenario" "${@:4}" >"${tree}/DEBIAN/control"
  echo "${tree}"
}

# Builds the package tree $1 into the pool of its suite.
pack() {
  local suite
  suite="$(basename "$(dirname "$1")")"
  dpkg-deb --build --root-owner-group "$1" "${REPOSITORY}/pool/${suite}" >/dev/null
}

# Adds to the suite $1 the package $2 at version $3, which ships no file. Further arguments are control fields.
add_package() {
  local tree
  tree="$(package_tree "$@")"
  pack "${tree}"
}

# Adds to the suite $1 the package $2 at version $3 with the conffile /etc/$2.conf, whose content names the version.
add_conffile_package() {
  local tree
  tree="$(package_tree "$@")"
  mkdir "${tree}/etc"
  echo "packaged by $2 $3" >"${tree}/etc/$2.conf"
  echo "/etc/$2.conf" >"${tree}/DEBIAN/conffiles"
  pack "${tree}"
}

# Publishes the packages added to the suite $1 as a signed release with the codename $2 and the version $3. Further
# arguments are Release fields in apt-ftparchive's spelling, such as NotAutomatic=yes.
publish_suite() {
  local suite="$1" architecture field
  local release_fields=()
  architecture="$(dpkg --print-architecture)"
  if [[ ! -f "${REPOSITORY_KEYRING}" ]]; then
    GNUPGHOME="$(mktemp -d)"
    export GNUPGHOME
    gpg --batch --quiet --pinentry-mode loopback --passphrase '' --quick-generate-key 'apt-packages scenario' \
      ed25519 sign never
    gpg --batch --quiet --export --output "${REPOSITORY_KEYRING}"
  fi
  mkdir -p "${REPOSITORY}/dists/${suite}/main/binary-${architecture}"
  (cd "${REPOSITORY}" && apt-ftparchive packages "pool/${suite}") \
    >"${REPOSITORY}/dists/${suite}/main/binary-${architecture}/Packages"
  for field in "Suite=${suite}" "Codename=$2" "Version=$3" "Components=main" "Architectures=${architecture}" "${@:4}"; do
    release_fields+=(-o "APT::FTPArchive::Release::${field}")
  done
  apt-ftparchive "${release_fields[@]}" release "${REPOSITORY}/dists/${suite}" >"${REPOSITORY}/dists/${suite}/Release"
  gpg --batch --quiet --pinentry-mode loopback --passphrase '' --clearsign \
    --output "${REPOSITORY}/dists/${suite}/InRelease" "${REPOSITORY}/dists/${suite}/Release"
}

# Makes the suites given the image's only sources, each verified with the repository's key, and drops any index.
use_suites() {
  local suite
  as_root sh -c 'rm -rf /etc/apt/sources.list /etc/apt/sources.list.d/* /var/lib/apt/lists/*'
  for suite in "$@"; do
    echo "deb [signed-by=${REPOSITORY_KEYRING}] file:${REPOSITORY} ${suite} main"
  done | as_root tee "${REPOSITORY_SOURCES}" >/dev/null
}

version_of() {
  dpkg-query -W -f='${Version}' "$1"
}

has_version() {
  if [[ "$(version_of "$1")" != "$2" ]]; then
    echo "$1 is at $(version_of "$1"), not $2" >&2
    return 1
  fi
}
