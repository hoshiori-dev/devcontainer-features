#!/usr/bin/env bash
# Scenario test_fixture_repositories (scenarios.json): the feature is installed with an empty list. The image's two
# repositories share no package name and set no Usage, so this script adds three local repositories of its own to the
# container, with package files it builds and signs with a key it adds to the keyring, and then runs install.sh. A
# stand-in before pacman on PATH records each call and then runs the real pacman. Spec scenarios "Qualified entry
# resolves in the named repository", "Qualified entry is not a pin", "Qualified entry offering an older version", "Same
# qualified entry with a newer version in an earlier repository", "Qualified entry reaches a repository not enabled
# for installation", "Dependency only in a repository not enabled for installation fails", "Unqualified entry does not
# reach a repository not enabled for installation", and "Image configuration ending in a repository section".
#
# The repositories, in their configured order after the image's own:
#   newer  fx-c 9.0-1, fx-e 9.0-1, fx-lib 1.0-1
#   older  fx-c 1.0-1, fx-e 1.0-1, fx-prov 1.0-1 (provides fx-virtual), fx-g1 and fx-g2 1.0-1 (group fx-group),
#          fx-d 1.0-1 (depends on fx-lib), fx-f 1.0-1
#   nouse  with Usage = Sync Search, so not enabled for installation: fx-b 1.0-1, fx-a 1.0-1 (depends on fx-dep),
#          fx-dep 1.0-1, and fx-unsigned 1.0-1, which has no signature
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly FIXTURE_DIR="/srv/pacman-packages-fixture"
# The key that signs the fixture packages lives in a keyring of its own; only its public part goes to pacman's.
export GNUPGHOME="/opt/pacman-packages-test/gnupg"

# Builds the package file of the package $2 at version $3 in the repository $1: a package without files, whose
# .PKGINFO also holds the lines given after them ("depend = fx-lib").
fixture_package() {
  local repository="$1" name="$2" version="$3" work_dir
  shift 3
  work_dir="$(mktemp -d /opt/pacman-packages-test/package.XXXXXX)"
  {
    printf 'pkgname = %s\npkgver = %s\n' "${name}" "${version}"
    printf 'pkgdesc = pacman-packages test fixture\nurl = https://example.invalid\nbuilddate = 0\n'
    printf 'packager = pacman-packages tests\nsize = 0\narch = any\n'
    if [[ "$#" -gt 0 ]]; then printf '%s\n' "$@"; fi
  } >"${work_dir}/.PKGINFO"
  mkdir -p "${FIXTURE_DIR}/${repository}"
  bsdtar -C "${work_dir}" --zstd -cf "${FIXTURE_DIR}/${repository}/${name}-${version}-any.pkg.tar.zst" .PKGINFO
  rm -rf "${work_dir}"
}

# Writes a detached signature beside every package file of the repository $1 that has none.
sign_packages() {
  local file
  for file in "${FIXTURE_DIR}/$1"/*.pkg.tar.zst; do
    if [[ ! -e "${file}.sig" ]]; then gpg --batch --quiet --detach-sign --no-armor "${file}"; fi
  done
}

# Writes the database of the repository $1 from its package files.
build_database() {
  repo-add --quiet "${FIXTURE_DIR}/$1/$1.db.tar.gz" "${FIXTURE_DIR}/$1"/*.pkg.tar.zst
}

every_one_installed() {
  local package
  for package in "$@"; do
    installed "${package}" || return
  done
}

none_installed() {
  local package
  for package in "$@"; do
    not_installed "${package}" || return
  done
}

# The last section header of /etc/pacman.conf names a repository.
configuration_ends_in_repository_section() {
  local header
  header="$(grep '^\[' /etc/pacman.conf | tail -n 1)"
  echo "the last section of /etc/pacman.conf is ${header}"
  [[ "${header}" != "[options]" ]]
}

# The keyring of the image has no secret key to certify another key with, so it gets one, and with it certifies the
# key that signs the fixture packages. The repositories below then stay under the signature level the image sets.
mkdir -p /opt/pacman-packages-test
mkdir -m 700 "${GNUPGHOME}"
gpg --batch --quiet --passphrase '' --quick-generate-key 'pacman-packages test fixture <fixture@example.invalid>' \
  ed25519 sign never
fixture_key="$(gpg --batch --with-colons --list-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
pacman-key --init >/dev/null 2>&1
gpg --batch --export "${fixture_key}" | pacman-key --add - >/dev/null 2>&1
pacman-key --lsign-key "${fixture_key}" >/dev/null 2>&1

fixture_package newer fx-c 9.0-1
fixture_package newer fx-e 9.0-1
fixture_package newer fx-lib 1.0-1
fixture_package older fx-c 1.0-1
fixture_package older fx-e 1.0-1
fixture_package older fx-prov 1.0-1 "provides = fx-virtual"
fixture_package older fx-g1 1.0-1 "group = fx-group"
fixture_package older fx-g2 1.0-1 "group = fx-group"
fixture_package older fx-d 1.0-1 "depend = fx-lib"
fixture_package older fx-f 1.0-1
fixture_package nouse fx-b 1.0-1
fixture_package nouse fx-a 1.0-1 "depend = fx-dep"
fixture_package nouse fx-dep 1.0-1
for repository in newer older nouse; do
  sign_packages "${repository}"
done
fixture_package nouse fx-unsigned 1.0-1
for repository in newer older nouse; do
  build_database "${repository}"
done
# pacman downloads as the user the image's DownloadUser names.
chmod -R a+rX "${FIXTURE_DIR}"
cat >>/etc/pacman.conf <<EOF

[newer]
Server = file://${FIXTURE_DIR}/newer

[older]
Server = file://${FIXTURE_DIR}/older

[nouse]
Usage = Sync Search
Server = file://${FIXTURE_DIR}/nouse
EOF

create_stand_in real
image_value="$(pacman-conf ParallelDownloads)"
check "premise: none of the fixture packages is installed" \
  none_installed fx-a fx-b fx-c fx-d fx-dep fx-e fx-f fx-g1 fx-g2 fx-lib fx-prov fx-unsigned
check "premise: the repositories are core, extra, newer, older, nouse, in that order" \
  test "$(pacman-conf --repo-list | tr '\n' ' ')" = "core extra newer older nouse "
check "premise: the repository nouse is synchronized and not enabled for installation" \
  test "$(pacman-conf --repo=nouse Usage | tr '\n' ' ')" = "Sync Search "

# Qualified entries for a package, a provided name, a group, and a package with a constraint; newer, earlier in the
# configured order, offers fx-e at 9.0-1.
run_install_with_stand_in PACKAGES="older/fx-e,older/fx-virtual,older/fx-group,older/fx-d>=1.0"
check "older/fx-e,older/fx-virtual,older/fx-group,older/fx-d>=1.0 installs" exited_with 0
check "fx-e is installed at 1.0-1, the version older offers, although newer offers 9.0-1" has_version fx-e 1.0-1
check "fx-prov, which provides fx-virtual in older, is installed" installed fx-prov
check "every package of the group fx-group in older is installed" every_one_installed fx-g1 fx-g2
check "fx-d is installed at 1.0-1, which satisfies >=1.0" has_version fx-d 1.0-1
check "fx-lib, a dependency of fx-d that only newer offers, is installed as for any other entry" installed fx-lib

# The same qualified entry three times; newer offers fx-c at 9.0-1.
run_install_with_stand_in PACKAGES=older/fx-c
check "the first installation of older/fx-c succeeds" exited_with 0
check "after the first, fx-c is at 1.0-1, the version older offers" has_version fx-c 1.0-1
check "fx-e, which this installation does not name, is upgraded to 9.0-1 like any other package" has_version fx-e 9.0-1
run_install_with_stand_in PACKAGES=older/fx-c
check "the second installation of older/fx-c succeeds" exited_with 0
check "it finds the entry satisfied and skips it" printed "fx-c-1.0-1 is up to date -- skipping"
check "the qualified entry is not a pin: the system upgrade moves fx-c to 9.0-1 from the earlier repository" \
  has_version fx-c 9.0-1
run_install_with_stand_in PACKAGES=older/fx-c
check "the third installation of older/fx-c, with a newer fx-c installed, succeeds" exited_with 0
check "pacman reports that it replaces fx-c with the older version" printed "downgrading package fx-c (9.0-1 => 1.0-1)"
check "after the third, fx-c is at 1.0-1 again, the version older offers" has_version fx-c 1.0-1
check "the feature passed no argument that forces or prevents the replacement" \
  pacman_received "${PACMAN_ARGUMENTS[@]}" older/fx-c

database_before="$(local_database)"
run_install_with_stand_in PACKAGES=nouse/fx-a
check "nouse/fx-a, whose dependency fx-dep only nouse offers, fails" failed
check "pacman reports the dependency it cannot satisfy" printed "unable to satisfy dependency 'fx-dep'"
check "fx-a and fx-dep are not installed" none_installed fx-a fx-dep
run_install_with_stand_in PACKAGES="fx-dep,nouse/fx-b"
check "the unqualified fx-dep, which only nouse offers, fails beside nouse/fx-b" failed
check "pacman reports that it finds no target fx-dep" printed "target not found: fx-dep"
check "fx-dep and fx-b are not installed" none_installed fx-dep fx-b
run_install_with_stand_in PACKAGES=nouse/fx-unsigned
check "nouse/fx-unsigned, a package without a signature, fails under the signature level the image sets" failed
check "fx-unsigned is not installed" not_installed fx-unsigned
check "the failed installations installed and upgraded nothing" local_database_is "${database_before}"
remove_caches
run_install_with_stand_in PACKAGES=nouse/fx-b
check "nouse/fx-b, which needs no dependency, installs from the repository not enabled for installation" exited_with 0
check "fx-b is installed at 1.0-1" has_version fx-b 1.0-1

# /etc/pacman.conf now ends in the section of the repository nouse.
check "premise: /etc/pacman.conf ends in a repository section" configuration_ends_in_repository_section
check "premise: the image does not set ParallelDownloads to 3 (it sets ${image_value})" test "${image_value}" != 3
configuration_with_fixture="$(pacman-conf)"
temporary_before="$(temporary_files)"
run_install_with_stand_in PACKAGES=older/fx-f PARALLELDOWNLOADS=3
check "older/fx-f installs with parallelDownloads=3" exited_with 0
check "the configuration pacman resolves for the call has ParallelDownloads = 3" resolved_parallel_downloads 3
check "the configuration pacman resolves for the call has the repositories of /etc/pacman.conf, in their order" \
  test "$(tr '\n' ' ' <"${RECORD_DIR}/repositories")" = "core extra newer older nouse "
check "the resolved configuration equals the one of /etc/pacman.conf in everything but ParallelDownloads" \
  resolved_configuration_equals_except_parallel_downloads "${configuration_with_fixture}"
check "fx-f is installed" installed fx-f
check "the temporary configuration is removed" temporary_files_are "${temporary_before}"

reportResults
