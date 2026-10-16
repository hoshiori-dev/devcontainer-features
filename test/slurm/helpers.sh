# shellcheck shell=bash
# Assertions shared by the slurm tests. Sourced by test.sh, duplicate.sh, and the scenario scripts after
# dev-container-features-test-lib; each function returns non-zero on failure and says why on stderr.

readonly SLURM_CONFIG="/etc/slurm/slurm.conf"
readonly SLURM_OCI_CONF="/etc/slurm/oci.conf"
readonly SLURM_OCI_TEMPLATE="/usr/local/share/slurm/oci.conf"
readonly SLURM_HOOK="/usr/local/share/slurm/start.sh"
readonly SLURM_MARKER="# slurm-feature-seed: the slurm feature keeps the SlurmctldHost and NodeName lines of this file aligned with the container at every start; remove this line to take over the file."
readonly SLURM_CTLD_PID_FILE="/run/slurm-feature/slurmctld.pid"
readonly SLURM_D_PID_FILE="/run/slurm-feature/slurmd.pid"

# Runs a command as root: the tests run as the image's remote user, which may be a sudoer.
as_root() {
  local uid
  uid="$(id -u)"
  if ((uid == 0)); then
    "$@"
  else
    sudo "$@"
  fi
}

# Runs the start hook as the remote user with the two variables as given: hook <config file value> <mode value>.
# Prints the hook's output and returns its status.
hook() {
  env DEVCONTAINER_SLURM_CONFIG_FILE="$1" DEVCONTAINER_SLURM_FEATURE_MODE="$2" "${SLURM_HOOK}" 2>&1
}

# Waits until sinfo reports the node idle, at most 60 seconds.
node_idle() {
  local state
  for _ in $(seq 1 60); do
    # sinfo pads its columns; the trailing spaces are dropped.
    state="$(sinfo --noheader --format '%T' 2>/dev/null | tr -d ' ' || true)"
    if [[ "${state}" == idle ]]; then return 0; fi
    sleep 1
  done
  printf '%s\n' "the node is '${state}', not idle" >&2
  return 1
}

# sinfo lists the seeded partition with one node.
seeded_partition_listed() {
  local line
  line="$(sinfo --noheader --format '%P %D' 2>&1)" || return
  [[ "$(awk '{ print $1, $2 }' <<<"${line}")" == 'devcontainer* 1' ]]
}

# sbatch --wait runs a script printing the hostname to completion, with the output in the working directory.
batch_job_completes() {
  local dir out
  dir="$(mktemp -d)"
  # uname, not hostname: Fedora images ship no hostname command.
  (cd "${dir}" && sbatch --wait --output=job.out --wrap 'uname -n') >/dev/null || return
  # The output file may land a moment after --wait returns.
  for _ in $(seq 1 10); do
    [[ -s "${dir}/job.out" ]] && break
    sleep 0.5
  done
  out="$(<"${dir}/job.out")"
  rm -rf "${dir}"
  [[ "${out}" == "$(uname -n)" ]]
}

# sbatch --test-only reports when the job would start and queues nothing.
test_only_queues_nothing() {
  local before after output
  before="$(squeue --noheader | wc -l)"
  output="$(sbatch --test-only --wrap 'hostname' 2>&1)" || return
  after="$(squeue --noheader | wc -l)"
  grep -q 'to start at' <<<"${output}" && [[ "${before}" == "${after}" ]]
}

marker_is_first_line() {
  [[ "$(head -n 1 "${SLURM_CONFIG}")" == "${SLURM_MARKER}" ]]
}

# SlurmctldHost and NodeName name this container's hostname.
identity_lines_aligned() {
  local host
  host="$(uname -n)"
  grep -qx "SlurmctldHost=${host}" "${SLURM_CONFIG}" && grep -q "^NodeName=${host} " "${SLURM_CONFIG}"
}

# The MUNGE key exists, is readable only by munge, and is newer than the hook the build installed.
munge_key_from_first_start() {
  local mode
  as_root test -f /etc/munge/munge.key || return
  mode="$(as_root stat -c '%U %a' /etc/munge/munge.key)"
  [[ "${mode}" == "munge 400" ]] && as_root test /etc/munge/munge.key -nt "${SLURM_HOOK}"
}

# /etc/slurm is a mount (the configuration volume).
config_dir_is_mount() {
  grep -q ' /etc/slurm ' /proc/self/mounts
}

# Prints the pids of slurmctld and slurmd from their pid files.
daemon_pids() {
  as_root cat "${SLURM_CTLD_PID_FILE}" "${SLURM_D_PID_FILE}" | tr '\n' ' '
}

one_of_each_daemon() {
  local ctld d munged
  ctld="$(pgrep -cx slurmctld)" || return
  d="$(pgrep -cx slurmd)" || return
  munged="$(pgrep -cx munged)" || return
  if [[ "${ctld}" != 1 || "${d}" != 1 || "${munged}" != 1 ]]; then
    printf '%s\n' "slurmctld ${ctld}, slurmd ${d}, munged ${munged}" >&2
    return 1
  fi
}

no_local_daemons() {
  ! pgrep -x slurmctld >/dev/null && ! pgrep -x slurmd >/dev/null
}

# Neither the backend template nor oci.conf exists.
no_backend_files() {
  [[ ! -e "${SLURM_OCI_TEMPLATE}" && ! -e "${SLURM_OCI_CONF}" ]]
}

# The template exists and oci.conf in the volume equals it.
backend_files_present() {
  [[ -f "${SLURM_OCI_TEMPLATE}" ]] && cmp -s "${SLURM_OCI_TEMPLATE}" "${SLURM_OCI_CONF}"
}

# The checks that run inside `bash -c` strings call these functions, so they are exported.
export -f hook node_idle one_of_each_daemon no_local_daemons seeded_partition_listed
export SLURM_HOOK SLURM_CONFIG SLURM_OCI_CONF
