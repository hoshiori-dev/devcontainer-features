#!/usr/bin/env bash
# Installs Slurm (the client commands, slurmctld, and slurmd) and MUNGE with the image's package manager: slurm-wlm and
# munge on Debian and Ubuntu, slurm, slurm-slurmctld, slurm-slurmd, and munge on Fedora, and the same from EPEL on a
# RHEL derivative, enabled through the distribution's epel-release package when it is not configured yet, with the EPEL
# key the package installs checked against its pinned full fingerprint. Creates the slurm system user when the packages
# do not, the state directories under /var/lib/slurm-feature, and the log directory /var/log/slurm; removes a MUNGE key
# a package generated; writes the seeded single-node /etc/slurm/slurm.conf and /etc/slurm/cgroup.conf; installs the
# start hook to /usr/local/share/slurm/start.sh; and, when the option apptainer decides so, the Apptainer backend
# template /usr/local/share/slurm/oci.conf. Runs as root at image build time; the option `apptainer` arrives as
# APPTAINER.
set -euo pipefail

readonly SHARE_DIR="/usr/local/share/slurm"
readonly START_HOOK="/usr/local/share/slurm/start.sh"
readonly OCI_TEMPLATE="/usr/local/share/slurm/oci.conf"
readonly CONFIG_DIR="/etc/slurm"
readonly CONFIG_FILE="/etc/slurm/slurm.conf"
readonly CGROUP_CONF="/etc/slurm/cgroup.conf"
readonly MUNGE_KEY="/etc/munge/munge.key"
readonly STATE_DIR="/var/lib/slurm-feature"
readonly LOG_DIR="/var/log/slurm"
readonly MARKER="# slurm-feature-seed: the slurm feature keeps the SlurmctldHost and NodeName lines of this file aligned with the container at every start; remove this line to take over the file."
readonly EPEL_KEY_DIR="/etc/pki/rpm-gpg"
readonly EPEL_RELEASE_PACKAGE="epel-release"
# The EPEL releases the feature trusts, each with the full fingerprint of its signing key.
readonly EPEL_FINGERPRINT_9="FF8AD1344597106ECE813B918A3872BF3228467C"
# The oldest Slurm whose oci.conf accepts IgnoreFileConfigJson, which lets a sandbox directory be the bundle.
readonly BACKEND_MIN_VERSION="23.02"
# The oldest Slurm whose slurmd runs without cgroup access (cgroup.conf CgroupPlugin=disabled).
readonly SLURM_MIN_VERSION="24.05"
readonly APT_LISTS_DIR="/var/lib/apt/lists"

export DEBIAN_FRONTEND=noninteractive

APPTAINER="${APPTAINER-auto}"

os_id=""
os_id_like=""
os_version_id=""
# The install path: apt, fedora, or rhel.
family=""
work_dir=""
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf 'slurm: %s\n' "$*"
}

fail() {
  printf 'slurm: error: %s\n' "$*" >&2
  exit 1
}

# Removes the temporary directory on every exit, success or failure.
cleanup() {
  if [[ -n "${work_dir}" && -d "${work_dir}" ]]; then
    if command -v gpgconf >/dev/null 2>&1; then
      GNUPGHOME="${work_dir}/gnupg" gpgconf --kill all >/dev/null 2>&1 || true
    fi
    rm --recursive --force "${work_dir}"
  fi
}

gpg_installed() {
  if command -v gpg >/dev/null 2>&1; then return 0; fi
  command -v gpg2 >/dev/null 2>&1
}

# Runs gpg, or gpg2 where only that name is installed, without prompts, in the temporary GnuPG home.
run_gpg() {
  if command -v gpg >/dev/null 2>&1; then
    GNUPGHOME="${work_dir}/gnupg" gpg --batch "$@"
  else
    GNUPGHOME="${work_dir}/gnupg" gpg2 --batch "$@"
  fi
}

apt_install() {
  apt-get install --yes --no-install-recommends "$@"
}

dnf_unattended() {
  dnf --assumeyes "$@"
}

validate_options() {
  if [[ ! "${APPTAINER}" =~ ^(auto|on|off)$ ]]; then
    fail "option apptainer is \"${APPTAINER}\"; use auto, on, or off"
  fi
  readonly APPTAINER
}

# Sets os_id, os_id_like, os_version_id, and family; fails on an unsupported distribution before anything changes.
detect_platform() {
  local distributions distribution
  [[ -r /etc/os-release ]] \
    || fail "cannot read /etc/os-release to detect the distribution; use a Debian, Ubuntu, Fedora, or RHEL-derivative" \
      "image"
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  os_id_like="$(. /etc/os-release && printf '%s\n' "${ID_LIKE:-}")"
  # shellcheck source=/dev/null
  os_version_id="$(. /etc/os-release && printf '%s\n' "${VERSION_ID:-}")"
  case "${os_id}" in
    debian | ubuntu) family="apt" ;;
    fedora) family="fedora" ;;
    rhel | centos | almalinux | rocky) family="rhel" ;;
  esac
  if [[ -z "${family}" ]]; then
    read -ra distributions <<<"${os_id_like}"
    for distribution in "${distributions[@]}"; do
      case "${distribution}" in
        debian | ubuntu) family="apt" ;;
        rhel | centos) family="rhel" ;;
        *) continue ;;
      esac
      break
    done
  fi
  case "${family}" in
    apt)
      if ! command -v apt-get >/dev/null 2>&1; then family=""; fi
      ;;
    fedora | rhel)
      if ! command -v dnf >/dev/null 2>&1; then family=""; fi
      ;;
  esac
  if [[ -z "${family}" ]]; then
    fail "unsupported distribution \"${os_id:-unknown}\" (ID_LIKE \"${os_id_like}\"); use a Debian or Ubuntu image" \
      "with apt, or a Fedora or RHEL-derivative image with dnf"
  fi
}

# Fails unless the key file $1 holds exactly one primary key, a public key with the fingerprint $2; $3 names it.
verify_key_file() {
  local key_file="$1"
  local expected="$2"
  local name="$3"
  local records primaries first kind fingerprint
  if [[ ! -d "${work_dir}/gnupg" ]]; then mkdir --mode 0700 "${work_dir}/gnupg"; fi
  records="$(run_gpg --show-keys --with-colons "${key_file}" 2>/dev/null)" \
    || fail "${key_file} holds no readable OpenPGP key (expected ${name} with fingerprint ${expected})"
  # A pub or sec record is a primary key; the first fpr after it is that key's. grep prints 0 and exits 1 on no line.
  primaries="$(grep --count --extended-regexp '^(pub|sec):' <<<"${records}" || true)"
  first="$(
    awk -F: '$1 == "pub" || $1 == "sec" { kind = $1; next } kind && $1 == "fpr" { print kind, $10; exit }' \
      <<<"${records}"
  )"
  kind="${first%% *}"
  fingerprint="${first#* }"
  if ((primaries != 1)) || [[ "${kind}" != pub || "${fingerprint}" != "${expected}" ]]; then
    fail "${key_file} is not ${name}: expected exactly one primary key, a public key with fingerprint ${expected}," \
      "found ${primaries} primary key(s), public or secret, the first (${kind:-none}) with fingerprint" \
      "\"${fingerprint:-none}\"; check that nothing replaced the key"
  fi
  log "verified ${name} ${expected}"
}

# RHEL derivative: enables EPEL through the distribution's epel-release package when no EPEL repository is configured,
# with GnuPG in the same transaction for the key check, and verifies the key the package installs.
enable_epel() {
  local major expected key_file repositories
  local packages=()
  repositories="$(dnf repolist --enabled 2>/dev/null)" \
    || fail "cannot list the enabled repositories with dnf repolist; check dnf's messages above"
  if awk '$1 == "epel" { found = 1 } END { exit !found }' <<<"${repositories}"; then
    log "EPEL is already configured in the image: installing from it as it is"
    return
  fi
  major="${os_version_id%%.*}"
  case "${major}" in
    9) expected="${EPEL_FINGERPRINT_9}" ;;
    *)
      fail "no pinned EPEL signing key for release ${major:-unknown} (VERSION_ID \"${os_version_id}\"); this" \
        "feature trusts EPEL 9 only"
      ;;
  esac
  key_file="${EPEL_KEY_DIR}/RPM-GPG-KEY-EPEL-${major}"
  packages=("${EPEL_RELEASE_PACKAGE}")
  if ! gpg_installed; then packages+=(gnupg2); fi
  log "installing ${packages[*]} from the image's repositories to enable EPEL ${major}"
  dnf_unattended install "${packages[@]}" \
    || fail "cannot install ${packages[*]} from the image's repositories, which this feature needs to enable EPEL;" \
      "use an image whose repositories offer them, or configure EPEL in the image first"
  [[ -r "${key_file}" ]] \
    || fail "${EPEL_RELEASE_PACKAGE} installed no key at ${key_file}; this feature trusts only that file, checked" \
      "against fingerprint ${expected}"
  verify_key_file "${key_file}" "${expected}" "the EPEL ${major} signing key"
}

# Installs the Slurm packages and MUNGE, with the tools the start hook needs that minimal images lack: procps (pgrep)
# and util-linux (runuser), from the image's repositories.
install_packages() {
  case "${family}" in
    apt)
      log "installing slurm-wlm, munge, procps, and util-linux from the image's repositories"
      apt-get update || fail "cannot refresh the image's package lists; check the network and apt-get's messages above"
      apt_install slurm-wlm munge procps util-linux \
        || fail "cannot install slurm-wlm and munge; check the network and apt-get's messages above"
      ;;
    fedora)
      log "installing slurm, slurm-slurmctld, slurm-slurmd, munge, procps-ng, and util-linux from the image's" \
        "repositories"
      dnf_unattended install slurm slurm-slurmctld slurm-slurmd munge procps-ng util-linux \
        || fail "cannot install the Slurm packages and munge; check the network and dnf's messages above"
      ;;
    rhel)
      enable_epel
      log "installing slurm, slurm-slurmctld, slurm-slurmd, and munge from EPEL, procps-ng and util-linux from the" \
        "image's repositories"
      dnf_unattended install slurm slurm-slurmctld slurm-slurmd munge procps-ng util-linux \
        || fail "cannot install the Slurm packages and munge; check dnf's messages above, the network, and that no" \
          "EPEL repository the image configured is disabled"
      ;;
  esac
}

# Creates the slurm user when the packages did not, the state and log directories with the owners the daemons need,
# and removes a MUNGE key a package generated at install: the key is generated at the first start instead.
prepare_system() {
  if ! getent passwd slurm >/dev/null; then
    log "creating the slurm system user"
    useradd --system --shell /usr/sbin/nologin --home-dir /nonexistent --no-create-home slurm
  fi
  getent passwd munge >/dev/null || fail "the munge package created no munge user; check the package's messages above"
  mkdir --parents "${STATE_DIR}/slurmctld" "${STATE_DIR}/slurmd" "${LOG_DIR}" /var/log/munge /var/lib/munge
  chown slurm:slurm "${STATE_DIR}/slurmctld" "${LOG_DIR}"
  chmod 0755 "${STATE_DIR}/slurmctld" "${STATE_DIR}/slurmd" "${LOG_DIR}"
  chown munge:munge /var/log/munge /var/lib/munge
  chmod 0700 /var/log/munge /var/lib/munge
  if [[ -e "${MUNGE_KEY}" ]]; then
    log "removing the MUNGE key the munge package generated; the start hook generates one at the first start"
    rm --force "${MUNGE_KEY}"
  fi
}

# Writes the seeded single-node configuration: the marker as line one, placeholders for the identity lines the start
# hook aligns, and no cgroup plugin, which the container lacks the privileges for.
write_seed() {
  mkdir --parents "${CONFIG_DIR}"
  log "writing the seeded single-node configuration to ${CONFIG_FILE}"
  cat >"${CONFIG_FILE}" <<EOF
${MARKER}
ClusterName=devcontainer
SlurmctldHost=localhost
SlurmUser=slurm
AuthType=auth/munge
CredType=cred/munge
ProctrackType=proctrack/linuxproc
TaskPlugin=task/none
JobAcctGatherType=jobacct_gather/none
MpiDefault=none
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core
ReturnToService=2
StateSaveLocation=${STATE_DIR}/slurmctld
SlurmdSpoolDir=${STATE_DIR}/slurmd
SlurmctldPidFile=/run/slurm-feature/slurmctld.pid
SlurmdPidFile=/run/slurm-feature/slurmd.pid
SlurmctldLogFile=${LOG_DIR}/slurmctld.log
SlurmdLogFile=${LOG_DIR}/slurmd.log
NodeName=localhost CPUs=1 RealMemory=1 State=UNKNOWN
PartitionName=devcontainer Nodes=ALL Default=YES MaxTime=INFINITE State=UP
EOF
  chmod 0644 "${CONFIG_FILE}"
  log "writing ${CGROUP_CONF} with the cgroup plugin disabled"
  printf 'CgroupPlugin=disabled\n' >"${CGROUP_CONF}"
  chmod 0644 "${CGROUP_CONF}"
}

install_hook() {
  mkdir --parents "${SHARE_DIR}"
  log "installing the start hook to ${START_HOOK}"
  install --mode 0755 "${script_dir}/scripts/start.sh" "${START_HOOK}"
}

# With apptainer on, fails before anything changes when Apptainer is not on PATH; the version floor, which needs the
# packages, follows later.
check_backend_preconditions() {
  if [[ "${APPTAINER}" == on ]] && ! command -v apptainer >/dev/null 2>&1; then
    fail "apptainer is on, but the backend needs: Apptainer on PATH (install the apptainer feature first)"
  fi
}

# Prints the installed Slurm version as MAJOR.MINOR, from sinfo --version ("slurm 23.11.4").
slurm_version() {
  local output
  output="$(sinfo --version)" || fail "sinfo --version failed after the install; check the package's messages above"
  [[ "${output}" =~ ^slurm(-wlm)?\ ([0-9]+\.[0-9]+) ]] || fail "sinfo --version printed \"${output}\", not a version"
  printf '%s\n' "${BASH_REMATCH[2]}"
}

# Prints the older of the two versions $1 and $2.
older_version() {
  printf '%s\n%s\n' "$1" "$2" | sort --version-sort | head --lines 1
}

# Fails when the installed Slurm is older than the oldest release whose slurmd runs in an unprivileged container.
check_slurm_version() {
  local version
  version="$(slurm_version)"
  if [[ "$(older_version "${SLURM_MIN_VERSION}" "${version}")" != "${SLURM_MIN_VERSION}" ]]; then
    fail "the image's Slurm is ${version}, and this feature needs ${SLURM_MIN_VERSION} or newer: older slurmd" \
      "cannot start without a writable cgroup file system, which an unprivileged container lacks; use an image" \
      "listed in test/slurm/compatibility.json"
  fi
  log "the image's Slurm is ${version}"
}

# Decides the Apptainer backend from the option, Apptainer on PATH, and the Slurm version; writes or removes the
# oci.conf template accordingly.
decide_backend() {
  local version oldest
  local missing=()
  if [[ "${APPTAINER}" == off ]]; then
    log "apptainer is off: no container backend is configured"
    rm --force "${OCI_TEMPLATE}"
    return
  fi
  version="$(slurm_version)"
  if ! command -v apptainer >/dev/null 2>&1; then
    missing+=("Apptainer on PATH (install the apptainer feature first)")
  fi
  oldest="$(older_version "${BACKEND_MIN_VERSION}" "${version}")"
  if [[ "${oldest}" != "${BACKEND_MIN_VERSION}" ]]; then
    missing+=("Slurm ${BACKEND_MIN_VERSION} or newer (the image has ${version})")
  fi
  if ((${#missing[@]} > 0)); then
    if [[ "${APPTAINER}" == on ]]; then
      fail "apptainer is on, but the backend needs: ${missing[*]}"
    fi
    log "apptainer is auto and the backend is not configured; it needs: ${missing[*]}"
    rm --force "${OCI_TEMPLATE}"
    return
  fi
  log "configuring Apptainer as the container backend: writing ${OCI_TEMPLATE}"
  cat >"${OCI_TEMPLATE}" <<EOF
# Written by the slurm feature: runs each container step with Apptainer on the bundle path (a sandbox directory).
IgnoreFileConfigJson=true
EnvExclude="^(SLURM_CONF|SLURM_CONF_SERVER)="
RunTimeEnvExclude="^(SLURM_CONF|SLURM_CONF_SERVER)="
RunTimeRun="apptainer exec --bind ${STATE_DIR}/slurmd %b %@"
RunTimeKill="kill -s SIGTERM %p"
RunTimeDelete="kill -s SIGKILL %p"
EOF
  chmod 0644 "${OCI_TEMPLATE}"
}

clean_caches() {
  case "${family}" in
    apt)
      apt-get clean
      rm --recursive --force "${APT_LISTS_DIR:?}"/*
      ;;
    fedora | rhel) dnf clean all ;;
  esac
}

main() {
  validate_options
  detect_platform
  log "installing on ${os_id} ${os_version_id} through the ${family} path"
  trap cleanup EXIT
  work_dir="$(mktemp --directory /tmp/slurm-install.XXXXXXXXXX)"
  check_backend_preconditions
  install_packages
  prepare_system
  write_seed
  install_hook
  check_slurm_version
  decide_backend
  clean_caches
  log "done"
}

main "$@"
