#!/usr/bin/env bash
# Scenario "test_source_and_modes": re-runs the start hook with the two variables, as a container start with that
# containerEnv would run it: the source file (relative to the working directory, absolute, unchanged, changed, missing,
# a directory, the target itself), the marker removed, every mode, and the auto rule on local, remote, mixed, and
# unresolvable controller entries. Each case stands for the spec scenario named in its label.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

work="$(mktemp -d)"
host="$(uname -n)"
as_root cp "${SLURM_CONFIG}" "${work}/seed.conf"

# Prints the sha256 of the volume's slurm.conf.
config_sum() {
  sha256sum "${SLURM_CONFIG}" | cut -d' ' -f1
}

# A local configuration with the marker removed and a comment the hook must keep. ClusterName stays: slurmctld refuses
# a saved state written under another name.
sed "1d" "${work}/seed.conf" >"${work}/local.conf"
printf '# kept by the user\n' >>"${work}/local.conf"
# A remote configuration: a controller that resolves to an address of another network.
sed "s/^SlurmctldHost=.*/SlurmctldHost=controller.example(192.0.2.10)/" "${work}/local.conf" >"${work}/remote.conf"
# A mixed configuration: this container and a remote controller.
sed "s/^SlurmctldHost=.*/SlurmctldHost=${host}\nSlurmctldHost=controller.example(192.0.2.10)/" "${work}/local.conf" >"${work}/mixed.conf"
# An unresolvable configuration.
sed "s/^SlurmctldHost=.*/SlurmctldHost=no-such-host.invalid/" "${work}/local.conf" >"${work}/unresolved.conf"
mkdir -p "${work}/dir"

check "the local cluster is ready before the cases" node_idle
pids="$(daemon_pids)"

# Relative source path: resolved against the working directory
cd "${work}"
check "Relative source path: a relative source is copied over slurm.conf" hook "local.conf" ""
check "the copied file is byte-identical to the source" cmp "${SLURM_CONFIG}" "${work}/local.conf"
check "Configuration changed: the local daemons were restarted with the new file" test "$(daemon_pids)" != "${pids}"
check "the cluster is ready again" node_idle
pids="$(daemon_pids)"

# Unchanged source: no write, no restart
before="$(stat -c '%Y' "${SLURM_CONFIG}")"
check "Unchanged source: a source equal to slurm.conf exits zero" hook "${work}/local.conf" ""
check "the file's modification time is unchanged" test "$(stat -c '%Y' "${SLURM_CONFIG}")" = "${before}"
check "the daemons keep their process ids" test "$(daemon_pids)" = "${pids}"

# Marker removed: the file is not realigned
check "Marker removed: a file without the marker is byte-identical after a start" \
  bash -c "s=\$(sha256sum ${SLURM_CONFIG}); ${SLURM_HOOK} >/dev/null && test \"\$(sha256sum ${SLURM_CONFIG})\" = \"\$s\""
check "the user's comment survived" grep -qx '# kept by the user' "${SLURM_CONFIG}"

# Missing source, directory, unreadable: failure before anything changes
sum="$(config_sum)"
check "Missing source: a missing file fails naming the path" bash -c "out=\$(hook ${work}/absent.conf '' || true); grep -q 'absent.conf.*does not exist' <<<\"\$out\""
check "slurm.conf is unchanged after the missing source" test "$(config_sum)" = "${sum}"
check "Missing source: a directory fails naming the path" bash -c "out=\$(hook ${work}/dir '' || true); grep -q 'not a regular file' <<<\"\$out\""
check "the daemons are unchanged after the invalid sources" test "$(daemon_pids)" = "${pids}"
# Root reads any file, so the unreadable case holds only for a remote user without root.
if (($(id -u) != 0)); then
  chmod 000 "${work}/remote.conf"
  check "Unreadable source: an unreadable file fails naming the path" bash -c "out=\$(hook ${work}/remote.conf '' || true); grep -q 'cannot be read' <<<\"\$out\""
  chmod 644 "${work}/remote.conf"
else
  echo "Unreadable source: skipped, the remote user is root and reads any file" >&2
fi
check "Source is the target: naming slurm.conf itself changes nothing" bash -c "out=\$(hook ${SLURM_CONFIG} ''); grep -q 'itself' <<<\"\$out\""
check "slurm.conf is still unchanged" test "$(config_sum)" = "${sum}"

# Invalid mode
check "Invalid mode: a value outside auto, local, client fails naming them" bash -c "out=\$(hook '' bogus || true); grep -q 'use auto, local, or client' <<<\"\$out\""
check "the daemons are unchanged after the invalid mode" test "$(daemon_pids)" = "${pids}"

# Client mode stops the local daemons; a remote source goes to client under auto
check "Client mode: the local daemons are stopped" bash -c "hook '' client >/dev/null && no_local_daemons"
check "Auto with a remote configuration: a remote controller gives the client role" \
  bash -c "out=\$(hook ${work}/remote.conf ''); grep -q 'role client' <<<\"\$out\" && no_local_daemons"
check "No reconfiguration of a remote controller: the hook logs no reconfigure" \
  bash -c "out=\$(hook ${work}/remote.conf ''); ! grep -qi reconfigure <<<\"\$out\""
check "Local mode with a remote configuration: local fails naming the controller entry" \
  bash -c "out=\$(hook ${work}/remote.conf local || true); grep -q 'controller.example' <<<\"\$out\" && no_local_daemons"
check "Auto undecidable: mixed entries fail naming them" \
  bash -c "out=\$(hook ${work}/mixed.conf '' || true); grep -q 'cannot tell' <<<\"\$out\" && no_local_daemons"
check "Auto undecidable: an unresolvable entry fails naming it" \
  bash -c "out=\$(hook ${work}/unresolved.conf '' || true); grep -q 'unresolved 1' <<<\"\$out\" && no_local_daemons"

# Back to a local configuration under auto
check "Auto with a local configuration: the local role starts the daemons again" \
  bash -c "out=\$(hook ${work}/local.conf ''); grep -q 'role local' <<<\"\$out\" && node_idle && one_of_each_daemon"
check "Omitted mode: unset behaves as auto" bash -c "out=\$(hook ${work}/local.conf ''); grep -q 'mode auto' <<<\"\$out\""
check "Client mode after local daemons: client stops them again" bash -c "hook '' client >/dev/null && no_local_daemons"
check "Local mode with a local configuration" bash -c "out=\$(hook '' local); grep -q 'role local' <<<\"\$out\" && node_idle"

# Source cleared: the imported file stays
check "Omitted source: with the variable empty the imported file is kept" \
  bash -c "hook '' '' >/dev/null && cmp ${SLURM_CONFIG} ${work}/local.conf"

# Restore the seed for later runs of this container.
as_root cp "${work}/seed.conf" "${SLURM_CONFIG}"
rm -rf "${work}"
reportResults
