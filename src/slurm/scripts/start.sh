#!/usr/bin/env bash
# The slurm feature's start hook (postStartCommand). Runs at every container start, as the remote user, and re-runs
# itself as root through `sudo -n` when it is not root, passing the two variables through. In this order: imports the
# file named by DEVCONTAINER_SLURM_CONFIG_FILE over /etc/slurm/slurm.conf (never when the variable is unset or empty),
# aligns the SlurmctldHost and NodeName lines of a seeded slurm.conf (one whose first line is the feature's marker)
# with this container, decides the role from DEVCONTAINER_SLURM_FEATURE_MODE (auto, local, client), copies the
# Apptainer oci.conf template to /etc/slurm when the backend is configured and the file is absent, and starts, restarts,
# or stops munged, slurmctld, and slurmd with pid files under /run/slurm-feature. Exits non-zero on any failure.
set -euo pipefail

readonly CONFIG_DIR="/etc/slurm"
readonly CONFIG_FILE="/etc/slurm/slurm.conf"
readonly OCI_CONF="/etc/slurm/oci.conf"
readonly OCI_TEMPLATE="/usr/local/share/slurm/oci.conf"
readonly MARKER="# slurm-feature-seed: the slurm feature keeps the SlurmctldHost and NodeName lines of this file aligned with the container at every start; remove this line to take over the file."
readonly MUNGE_KEY="/etc/munge/munge.key"
readonly MUNGE_RUN_DIR="/run/munge"
readonly RUN_DIR="/run/slurm-feature"
readonly SLURMCTLD_PID_FILE="/run/slurm-feature/slurmctld.pid"
readonly SLURMD_PID_FILE="/run/slurm-feature/slurmd.pid"
readonly SLURMCTLD_LOG="/var/log/slurm/slurmctld.log"
readonly SLURMD_LOG="/var/log/slurm/slurmd.log"
readonly READY_TIMEOUT=90

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

source_file="${DEVCONTAINER_SLURM_CONFIG_FILE-}"
mode="${DEVCONTAINER_SLURM_FEATURE_MODE-}"
# The role the hook decided: local or client.
role=""
# Whether slurm.conf changed during this run, so running local daemons must restart.
config_changed=""

log() {
  printf 'slurm: %s\n' "$*"
}

fail() {
  printf 'slurm: error: %s\n' "$*" >&2
  exit 1
}

# Fails on a mode outside auto, local, and client before anything is changed; an unset or empty mode is auto.
validate_mode() {
  case "${mode}" in
    "" | auto) mode="auto" ;;
    local | client) ;;
    *) fail "DEVCONTAINER_SLURM_FEATURE_MODE is \"${mode}\"; use auto, local, or client" ;;
  esac
}

# Fails, before the re-run as root, when the source file exists but the invoking user cannot read it: root reads
# any file, so the check must happen here.
check_source_readable() {
  local resolved
  [[ -n "${source_file}" ]] || return 0
  if [[ "${source_file}" == /* ]]; then resolved="${source_file}"; else resolved="${PWD}/${source_file}"; fi
  # -r alone: a file under a directory the user cannot traverse must not be read by root either.
  if [[ ! -r "${resolved}" ]]; then
    fail "DEVCONTAINER_SLURM_CONFIG_FILE names \"${source_file}\" (${resolved}), which the remote user cannot read or" \
      "which does not exist; ${CONFIG_FILE} is unchanged"
  fi
}

# Re-runs this script as root when it is not root, with the two variables and the working directory kept.
become_root() {
  if (($(id --user) == 0)); then return; fi
  command -v sudo >/dev/null 2>&1 \
    || fail "the start hook needs root and sudo is not installed; give the remote user passwordless sudo"
  if ! sudo --non-interactive true 2>/dev/null; then
    fail "the start hook needs root and the remote user cannot run sudo without a password; give the remote user" \
      "passwordless sudo"
  fi
  exec sudo --non-interactive env "DEVCONTAINER_SLURM_CONFIG_FILE=${source_file}" "DEVCONTAINER_SLURM_FEATURE_MODE=${mode}" \
    "$(realpath "${BASH_SOURCE[0]}")"
}

# Replaces CONFIG_FILE with the content of the file $1 atomically: a temporary file in the same directory, moved over
# the target once complete, so the previous complete file stays until then.
replace_config() {
  local temp
  temp="$(mktemp "${CONFIG_DIR}/.slurm.conf.XXXXXXXXXX")"
  if ! cat "$1" >"${temp}"; then
    rm --force "${temp}"
    fail "cannot copy $1 into ${CONFIG_DIR}; ${CONFIG_FILE} is unchanged"
  fi
  chmod 0644 "${temp}"
  chown root:root "${temp}"
  mv --force "${temp}" "${CONFIG_FILE}"
  config_changed="yes"
}

# Imports the source file when DEVCONTAINER_SLURM_CONFIG_FILE is set and not empty; fails before touching anything
# when the source is invalid.
import_source() {
  local resolved
  if [[ -z "${source_file}" ]]; then
    log "DEVCONTAINER_SLURM_CONFIG_FILE is unset or empty: ${CONFIG_FILE} is kept as it is"
    return
  fi
  if [[ "${source_file}" == /* ]]; then
    resolved="${source_file}"
  else
    resolved="${PWD}/${source_file}"
  fi
  [[ -e "${resolved}" ]] \
    || fail "DEVCONTAINER_SLURM_CONFIG_FILE names \"${source_file}\" (${resolved}), which does not exist; ${CONFIG_FILE}" \
      "is unchanged"
  [[ -f "${resolved}" ]] \
    || fail "DEVCONTAINER_SLURM_CONFIG_FILE names \"${source_file}\" (${resolved}), which is not a regular file;" \
      "${CONFIG_FILE} is unchanged"
  [[ -r "${resolved}" ]] \
    || fail "DEVCONTAINER_SLURM_CONFIG_FILE names \"${source_file}\" (${resolved}), which cannot be read; ${CONFIG_FILE}" \
      "is unchanged"
  if [[ -e "${CONFIG_FILE}" && "$(realpath "${resolved}")" == "$(realpath "${CONFIG_FILE}")" ]]; then
    log "DEVCONTAINER_SLURM_CONFIG_FILE names ${CONFIG_FILE} itself: nothing to copy"
    return
  fi
  if [[ -e "${CONFIG_FILE}" ]] && cmp --silent "${resolved}" "${CONFIG_FILE}"; then
    log "${resolved} equals ${CONFIG_FILE}: nothing to copy"
    return
  fi
  log "copying ${resolved} to ${CONFIG_FILE}"
  replace_config "${resolved}"
}

# Prints the node line slurmd reports for this container, with State=UNKNOWN.
node_line() {
  local line
  # slurmd may log warnings before the node line; only the NodeName line counts.
  line="$(slurmd -C 2>/dev/null | grep --max-count 1 '^NodeName=' || true)"
  [[ -n "${line}" ]] \
    || fail "slurmd -C reported no node line; run it by hand to see why, and check ${CONFIG_FILE}"
  printf '%s State=UNKNOWN\n' "${line}"
}

# Keeps the identity lines of a seeded slurm.conf aligned with this container: while its first line is the marker,
# SlurmctldHost and NodeName are rewritten from the hostname and slurmd -C; every other byte is kept.
align_seed() {
  local first host node temp
  [[ -f "${CONFIG_FILE}" ]] || fail "${CONFIG_FILE} does not exist; delete the configuration volume to reseed it"
  first="$(head --lines 1 "${CONFIG_FILE}")"
  if [[ "${first}" != "${MARKER}" ]]; then
    log "${CONFIG_FILE} does not start with the feature's marker line: it is yours, left untouched"
    return
  fi
  host="$(uname --nodename)"
  node="$(node_line)"
  temp="$(mktemp "${CONFIG_DIR}/.slurm.conf.XXXXXXXXXX")"
  awk -v host="${host}" -v node="${node}" '
    /^SlurmctldHost=/ { print "SlurmctldHost=" host; next }
    /^NodeName=/ { print node; next }
    { print }' "${CONFIG_FILE}" >"${temp}"
  if cmp --silent "${temp}" "${CONFIG_FILE}"; then
    rm --force "${temp}"
    return
  fi
  log "aligning the seeded ${CONFIG_FILE} with this container (${host})"
  chmod 0644 "${temp}"
  chown root:root "${temp}"
  mv --force "${temp}" "${CONFIG_FILE}"
  config_changed="yes"
}

# Prints the SlurmctldHost entries of slurm.conf, one per line, as "host" or "host(address)".
controller_entries() {
  awk -F= '/^[Ss]lurmctld[Hh]ost=/ { sub(/[ \t#].*/, "", $2); print $2 }' "${CONFIG_FILE}"
}

# Prints this container's hostname and addresses, one per line: loopback, the hostname, the addresses /etc/hosts and the
# tools present give for it.
local_identities() {
  local host
  host="$(uname --nodename)"
  printf '%s\n' "${host}" "${host%%.*}" localhost 127.0.0.1 ::1
  # Docker writes the container's address next to its hostname in /etc/hosts, which getent reads on every image;
  # hostname and ip are not installed everywhere.
  getent ahosts "${host}" 2>/dev/null | awk '{ print $1 }'
  if command -v hostname >/dev/null 2>&1; then hostname --all-ip-addresses 2>/dev/null | tr ' ' '\n'; fi
  if command -v ip >/dev/null 2>&1; then
    ip -oneline address show 2>/dev/null | awk '{ sub(/\/.*/, "", $4); print $4 }'
  fi
}

# Whether the SlurmctldHost entry $1 points at this container: its address part, or its name resolved with getent,
# matches one of the local identities. Prints "local", "remote", or "unresolved".
classify_entry() {
  local entry="$1"
  local name address candidates identities candidate
  name="${entry%%(*}"
  address=""
  if [[ "${entry}" == *"("*")" ]]; then
    address="${entry#*(}"
    address="${address%)}"
  fi
  identities="$(local_identities)"
  if [[ -n "${address}" ]]; then
    candidates="${address}"
  else
    candidates="${name}"
  fi
  if ! grep --quiet --line-regexp --fixed-strings "${name}" <<<"${identities}"; then
    # A name that is not ours resolves to addresses; none means unresolved.
    if [[ -z "${address}" ]]; then
      candidates="$(getent ahosts "${name}" 2>/dev/null | awk '{ print $1 }' | sort --unique)"
      [[ -n "${candidates}" ]] || { echo unresolved; return; }
    fi
  else
    echo local
    return
  fi
  while read -r candidate; do
    [[ -n "${candidate}" ]] || continue
    if grep --quiet --line-regexp --fixed-strings "${candidate}" <<<"${identities}" || [[ "${candidate}" == 127.* ]]; then
      echo local
      return
    fi
  done <<<"${candidates}"
  echo remote
}

# Decides the role from the mode and, for auto, from the SlurmctldHost entries; fails on an invalid mode, on a local
# configuration that names another controller, and on entries that are mixed, unresolved, or absent.
decide_role() {
  local entries entry verdict locals=0 remotes=0 unresolved=0
  [[ -f "${CONFIG_FILE}" ]] || fail "${CONFIG_FILE} does not exist; delete the configuration volume to reseed it"
  entries="$(controller_entries)"
  while read -r entry; do
    [[ -n "${entry}" ]] || continue
    verdict="$(classify_entry "${entry}")"
    case "${verdict}" in
      local) locals=$((locals + 1)) ;;
      remote) remotes=$((remotes + 1)) ;;
      *) unresolved=$((unresolved + 1)) ;;
    esac
  done <<<"${entries}"
  case "${mode}" in
    client) role="client" ;;
    local)
      if ((remotes > 0 || unresolved > 0 || locals == 0)); then
        fail "mode local, but the SlurmctldHost entries of ${CONFIG_FILE} do not all name this container:" \
          "$(tr '\n' ' ' <<<"${entries}"); the local daemons are not started"
      fi
      role="local"
      ;;
    auto)
      if ((locals > 0 && remotes == 0 && unresolved == 0)); then
        role="local"
      elif ((remotes > 0 && locals == 0 && unresolved == 0)); then
        role="client"
      else
        fail "mode auto cannot tell whether the SlurmctldHost entries of ${CONFIG_FILE} name this container:" \
          "$(tr '\n' ' ' <<<"${entries:-none}") (local ${locals}, remote ${remotes}, unresolved ${unresolved});" \
          "set DEVCONTAINER_SLURM_FEATURE_MODE to local or client; no daemon was changed"
      fi
      ;;
  esac
  log "mode ${mode}: role ${role}"
}

# Prints the pid in the file $1 when a process of the command name $2 runs under it; prints nothing otherwise and
# removes a stale file.
running_pid() {
  local pid comm
  [[ -f "$1" ]] || return 0
  pid="$(tr --delete '[:space:]' <"$1")"
  if [[ "${pid}" =~ ^[0-9]+$ ]] && [[ -r "/proc/${pid}/comm" ]]; then
    comm="$(<"/proc/${pid}/comm")"
    if [[ "${comm}" == "$2" ]]; then
      printf '%s\n' "${pid}"
      return 0
    fi
  fi
  rm --force "$1"
}

# Stops the process in the pid file $1 named $2 and waits for it to exit.
stop_daemon() {
  local pid
  pid="$(running_pid "$1" "$2")"
  [[ -n "${pid}" ]] || return 0
  log "stopping $2 (pid ${pid})"
  kill "${pid}" 2>/dev/null || true
  for _ in $(seq 1 30); do
    [[ -d "/proc/${pid}" ]] || break
    sleep 0.5
  done
  if [[ -d "/proc/${pid}" ]]; then kill -9 "${pid}" 2>/dev/null || true; fi
  rm --force "$1"
}

# Whether slurm.conf uses MUNGE for authentication (the default when AuthType is absent).
uses_munge() {
  local auth
  auth="$(awk -F= '/^[Aa]uth[Tt]ype=/ { sub(/[ \t#].*/, "", $2); print $2 }' "${CONFIG_FILE}" | tail --lines 1)"
  [[ -z "${auth}" || "${auth}" == auth/munge ]]
}

# Generates the MUNGE key when none exists (local role) and runs munged when a key exists and it is not running.
ensure_munged() {
  if [[ -L "${MUNGE_KEY}" ]]; then
    fail "${MUNGE_KEY} is a symbolic link; the feature writes the key only to a regular file there"
  fi
  if [[ ! -e "${MUNGE_KEY}" ]]; then
    if [[ "${role}" != local ]]; then
      log "no MUNGE key at ${MUNGE_KEY}: provide the cluster's key there for client access that uses MUNGE"
      return
    fi
    log "generating the MUNGE key at ${MUNGE_KEY}"
    (umask 077 && head --bytes 1024 /dev/urandom >"${MUNGE_KEY}")
    chown munge:munge "${MUNGE_KEY}"
    chmod 0400 "${MUNGE_KEY}"
  fi
  if [[ ! -d "${MUNGE_RUN_DIR}" ]]; then
    mkdir --parents "${MUNGE_RUN_DIR}"
    chown munge:munge "${MUNGE_RUN_DIR}"
  fi
  if pgrep --exact munged >/dev/null 2>&1; then return; fi
  log "starting munged"
  runuser --user munge -- munged || fail "munged did not start; check /var/log/munge/munged.log"
}

# Starts slurmctld and slurmd when they are not running, restarting them first when the configuration changed.
ensure_local_daemons() {
  local ctld_pid d_pid
  mkdir --parents "${RUN_DIR}"
  chown slurm:slurm "${RUN_DIR}"
  # A slurm.conf edited by hand since the daemons started counts as changed too.
  if [[ -z "${config_changed}" && -f "${SLURMCTLD_PID_FILE}" && "${CONFIG_FILE}" -nt "${SLURMCTLD_PID_FILE}" ]]; then
    log "${CONFIG_FILE} changed after the daemons started: restarting them"
    config_changed="yes"
  fi
  if [[ -n "${config_changed}" ]]; then
    stop_daemon "${SLURMD_PID_FILE}" slurmd
    stop_daemon "${SLURMCTLD_PID_FILE}" slurmctld
  fi
  ctld_pid="$(running_pid "${SLURMCTLD_PID_FILE}" slurmctld)"
  if [[ -z "${ctld_pid}" ]]; then
    log "starting slurmctld"
    runuser --user slurm -- slurmctld || fail "slurmctld did not start; check ${SLURMCTLD_LOG}"
  fi
  d_pid="$(running_pid "${SLURMD_PID_FILE}" slurmd)"
  if [[ -z "${d_pid}" ]]; then
    log "starting slurmd"
    slurmd || fail "slurmd did not start; check ${SLURMD_LOG}"
  fi
}

# Waits until the controller answers and the node is not down, within READY_TIMEOUT seconds.
wait_ready() {
  local state
  for _ in $(seq 1 "${READY_TIMEOUT}"); do
    # sinfo pads its column; a trailing * marks a node that does not respond yet.
    state="$(sinfo --noheader --format '%T' 2>/dev/null | tr --delete ' ' || true)"
    # Every line (one per partition and node state) must be settled; a trailing * marks a node not responding yet.
    if scontrol ping 2>/dev/null | grep --quiet ' is UP' && [[ -n "${state}" ]] \
      && ! grep --quiet --invert-match --extended-regexp '^(idle|allocated|mixed)$' <<<"${state}"; then
      log "ready: the local cluster answers and its node is ${state}"
      return
    fi
    sleep 1
  done
  fail "the local cluster is not ready after ${READY_TIMEOUT} seconds (node state \"${state:-none}\"); check" \
    "${SLURMCTLD_LOG} and ${SLURMD_LOG}"
}

# Copies the Apptainer oci.conf template into the configuration directory when the backend is configured and the file
# is absent; an existing file is kept.
ensure_oci_conf() {
  if [[ ! -f "${OCI_TEMPLATE}" ]]; then
    # The volume keeps the file (it is the user's), so a backend turned off after it was configured stays in force.
    if [[ -e "${OCI_CONF}" ]]; then
      log "warning: ${OCI_CONF} exists in the volume although this image configures no container backend; remove" \
        "the file to stop running container steps through it"
    fi
    return 0
  fi
  if [[ -e "${OCI_CONF}" ]]; then return; fi
  log "copying the Apptainer backend configuration to ${OCI_CONF}"
  install --mode 0644 "${OCI_TEMPLATE}" "${OCI_CONF}"
}

main() {
  validate_mode
  check_source_readable
  become_root
  import_source
  align_seed
  decide_role
  ensure_oci_conf
  case "${role}" in
    local)
      ensure_munged
      ensure_local_daemons
      wait_ready
      ;;
    client)
      stop_daemon "${SLURMD_PID_FILE}" slurmd
      stop_daemon "${SLURMCTLD_PID_FILE}" slurmctld
      if uses_munge; then
        ensure_munged
      else
        log "the configuration does not use auth/munge: munged is not started"
      fi
      log "client role: no local controller or compute daemon runs; the Slurm commands use ${CONFIG_FILE}"
      ;;
  esac
}

main "$@"
