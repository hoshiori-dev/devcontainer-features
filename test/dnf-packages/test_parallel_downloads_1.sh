#!/usr/bin/env bash
# Scenario test_parallel_downloads_1 (scenarios.json): this script serves a copy of a few of the image's packages from
# a loopback address, one second per package file, counts the package downloads that run at the same time, and runs
# install.sh against that repository alone. Spec scenarios "Explicit parallel downloads reach package downloads",
# "Repository setting does not replace the bound", and "Per-mirror limit still applies".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# Packages that no compatibility image has installed, and the repositories the image enables.
readonly LOCAL_PACKAGES="bc ed patch time tree unzip zip"
readonly IMAGE_REPOSITORIES="appstream,baseos,extras"
readonly LOCAL_REPOSITORY="/etc/yum.repos.d/local.repo"
readonly LOCAL_ROOT="/srv/local"
readonly LOCAL_PORT=8098
readonly SERVER="/tmp/slow_repository.py"
readonly DOWNLOADS="/tmp/simultaneous-downloads"

# Writes the repository file of the local repository, disabled like the repositories the option is meant for, with the
# lines given as arguments added to its section. The packages keep the signatures of the image's distribution.
write_local_repository() {
  local key
  key="$(grep --no-filename '^gpgkey=' /etc/yum.repos.d/*.repo | sort --unique | head -n 1)"
  printf '%s\n' "[local]" "name=local" "baseurl=http://127.0.0.1:${LOCAL_PORT}/" "enabled=0" "gpgcheck=1" "${key}" \
    "$@" >"${LOCAL_REPOSITORY}"
}

local_repository_listens() {
  (exec 3<>"/dev/tcp/127.0.0.1/${LOCAL_PORT}") 2>/dev/null
}

# Removes the packages the local repository holds and forgets the downloads counted so far.
reset_local_packages() {
  local names
  readarray -t names < <(rpm --query --package --queryformat '%{NAME}\n' "${LOCAL_ROOT}"/*.rpm)
  rpm --erase "${names[@]}"
  : >"${DOWNLOADS}"
}

# Prints the highest number of package files the local repository served at the same time since the last reset.
peak_downloads() {
  sort --numeric-sort "${DOWNLOADS}" | tail -n 1
}

# Runs install.sh for the local packages with the image's repositories left out and the local one enabled, and with
# the environment assignments given.
install_from_local_repository() {
  run_install PACKAGES="${LOCAL_PACKAGES// /,}" DISABLEREPOSITORIES="${IMAGE_REPOSITORIES}" ENABLEREPOSITORIES=local \
    "$@"
}

# The server delays every package file by one second and adds the number of package files it is serving to DOWNLOADS
# each time one starts.
cat >"${SERVER}" <<'EOF'
import http.server
import socketserver
import sys
import threading
import time

ROOT, PORT, DOWNLOADS = sys.argv[1], int(sys.argv[2]), sys.argv[3]
lock = threading.Lock()
active = 0


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def do_GET(self):
        global active
        if not self.path.endswith(".rpm"):
            super().do_GET()
            return
        with lock:
            active += 1
            with open(DOWNLOADS, "a") as downloads:
                downloads.write(f"{active}\n")
        try:
            time.sleep(1)
            super().do_GET()
        finally:
            with lock:
                active -= 1

    def log_message(self, *args):
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


Server(("127.0.0.1", PORT), Handler).serve_forever()
EOF

# Preparation with the image's own repositories: the tools, then the package files, which dnf keeps in its cache.
dnf install --assumeyes --setopt=install_weak_deps=False python3 createrepo_c
dnf clean packages
read -r -a local_packages <<<"${LOCAL_PACKAGES}"
dnf install --assumeyes --downloadonly --setopt=install_weak_deps=False "${local_packages[@]}"
readarray -t package_files < <(cached_package_files)
mkdir -p "${LOCAL_ROOT}"
cp "${package_files[@]}" "${LOCAL_ROOT}/"
createrepo_c "${LOCAL_ROOT}"
dnf clean all
write_local_repository
python3 "${SERVER}" "${LOCAL_ROOT}" "${LOCAL_PORT}" "${DOWNLOADS}" &
server_pid=$!
# The wait ends after 30 s, so a server that never comes up fails the premise below.
waited=0
until local_repository_listens || [[ "${waited}" -ge 30 ]]; do
  sleep 1
  waited=$((waited + 1))
done
check "premise: the local repository listens on 127.0.0.1:${LOCAL_PORT}" local_repository_listens
check "premise: the local repository holds at least seven package files (${#package_files[@]})" \
  test "${#package_files[@]}" -ge 7
configuration_before="$(dnf_configuration)"

install_from_local_repository
check "the packages install from the local repository without parallelDownloads" exited_with 0
check "premise: without the option the image's own bound of three shows at the local repository" \
  test "$(peak_downloads)" -eq 3

reset_local_packages
install_from_local_repository PARALLELDOWNLOADS=2
check "the packages install with parallelDownloads=2" exited_with 0
check "with parallelDownloads=2 never more than two packages are downloaded at the same time" \
  test "$(peak_downloads)" -eq 2

reset_local_packages
install_from_local_repository PARALLELDOWNLOADS=1
check "the packages install with parallelDownloads=1" exited_with 0
check "with parallelDownloads=1 the packages are downloaded one at a time" test "$(peak_downloads)" -eq 1

# The repository's own configuration sets a concurrency of one.
write_local_repository "max_parallel_downloads=1"
reset_local_packages
install_from_local_repository
check "premise: the repository's own max_parallel_downloads=1 applies without the option" \
  test "$(peak_downloads)" -eq 1
reset_local_packages
install_from_local_repository PARALLELDOWNLOADS=2
check "the packages install with parallelDownloads=2 beside the repository's own setting" exited_with 0
check "parallelDownloads=2 applies to the repository whose own configuration says one" \
  test "$(peak_downloads)" -eq 2
write_local_repository

reset_local_packages
install_from_local_repository PARALLELDOWNLOADS=10
check "parallelDownloads=10, above the image's limit of three downloads per mirror, succeeds" exited_with 0
check "with parallelDownloads=10 the downloads from the one mirror stay within the limit of three" \
  test "$(peak_downloads)" -eq 3
check "no bound was written to the dnf configuration" dnf_configuration_is "${configuration_before}"

kill "${server_pid}"

reportResults
