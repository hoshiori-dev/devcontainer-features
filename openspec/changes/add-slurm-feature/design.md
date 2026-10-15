# Design

## Context

See proposal.md for motivation and acceptance; the behavior is in `specs/slurm/spec.md`. The interface below was settled
before the issue: the two variable names, the volume, the copy-not-link rule, and the persistence scope are decisions,
not proposals. Facts checked on 2026-10-15, needed only for this change:

- **Packages.** Debian and Ubuntu ship `slurm-wlm`, which depends on `slurmctld`, `slurmd`, and `slurm-client` at one
  version; `slurmd` depends on `munge`. Versions: Debian 12 `22.05.8`, Debian 13 `24.11.5`, Ubuntu 22.04 `21.08.5`,
  Ubuntu 24.04 `23.11.4`, each on amd64 and arm64. The packages create the `slurm` and `munge` system users, ship
  systemd units only, and read `/etc/slurm/slurm.conf`. Fedora packages Slurm too, but the first version targets the
  Debian family only, so one package layout is proven before a second is added.
- **Slurm.** `AuthType=auth/munge` is the default and needs `munged` on every host that authenticates, with one shared
  `munge.key`; `auth/slurm` exists from 23.11 and is absent on Ubuntu 22.04. `ProctrackType=proctrack/linuxproc` and
  `TaskPlugin=task/none` run without cgroup access. `RealMemory` defaults to 1 MiB; a node whose configured CPUs exceed
  the actual count goes down, so the seed cannot guess resources at build time. `slurmd -C` prints the node line with
  the actual CPUs and memory. `SlurmctldHost=<name>(<address>)` takes an optional address; with several entries the
  first is primary. `slurmctld` refuses to run on a host whose name matches no `SlurmctldHost` entry, and `slurmd` looks
  its own hostname up among the `NodeName`/`NodeHostname` lines. Changing `AuthType` or a listening port needs a daemon
  restart; most other changes take `scontrol reconfigure` or a restart.
- **Dev Containers.** A Feature may declare `mounts` with `${devcontainerId}`, which is unique per dev container on a
  Docker host and stable across its rebuilds; a Feature's lifecycle commands run before the user's, in feature order; a
  failing `postStartCommand` makes the tool skip the later lifecycle commands but does not stop the container; the
  default `waitFor` is `updateContentCommand`. `devcontainer features test` creates the test container with `up`, so
  feature mounts and lifecycle commands apply in tests, as `test/firewall` relies on.
- **Docker.** An empty named volume mounted over a directory that holds files in the image receives those files; a
  non-empty volume obscures the image's directory; `volume-nocopy` would disable the seeding, so it is not used.

## Goals / Non-Goals

**Goals:**

- The seed is complete for one node whatever the host: the install writes it with the marker as line one,
  `SlurmctldHost`, `NodeName`, and `PartitionName` lines, `StateSaveLocation` and `SlurmdSpoolDir` under
  `/var/lib/slurm`, logs under `/var/log/slurm`, `SelectType=select/cons_tres` with `SelectTypeParameters=CR_Core`,
  `ReturnToService=2`, and `SlurmUser=slurm` — checked by `test.sh` asserting those lines on every compatibility image.
- Identity lines are aligned, never guessed: at each start, while line one is the marker, the hook rewrites exactly the
  `SlurmctldHost` and `NodeName` lines from the hostname and `slurmd -C`, with an in-place edit that keeps every other
  byte — checked by a scenario that edits other lines, re-runs the hook, and diffs the file; the hostname change itself
  is a manual run recorded in the PR.
- The hook runs the same way from the tool and from a shell: it sets its own `PATH`, runs its tools by absolute path,
  takes its inputs only from the two variables and the volume, and decides the mode before it touches a daemon — checked
  by the re-run scenarios.
- Daemon management is explicit and bounded: `munged`, `slurmctld`, and `slurmd` are started directly (no systemd), as
  the users the packages intend (`munged` as `munge`, `slurmctld` as `slurm`, `slurmd` as root), each with a pid file
  under `/run` the hook owns; a running daemon is recognized by its pid file and a live process of the expected command,
  a stale pid file is removed, and a restart is a stop of the hook's own processes followed by a start — checked by the
  "Repeated start", "Configuration changed", and "Client mode after local daemons" scenarios counting processes and
  comparing pids.
- Readiness is waited for, with a bound: after starting the local daemons the hook waits until `scontrol ping` answers
  and the node is not down, and fails naming the daemons' log files when the bound passes — checked by the default
  scenario timing the first `sinfo`.
- `auto` is decided from resolved addresses: every `SlurmctldHost` entry's address part, or its name through
  `getent hosts`, is compared with the container's hostname, `127.0.0.0/8`, `::1`, and the addresses of its interfaces;
  one unresolvable or mixed entry fails — checked by scenarios with a seeded file, a file naming an unresolvable host, a
  file naming an address of another network, and a file with mixed entries.
- Copy atomicity: the temporary file is created with `mktemp` in `/etc/slurm`, filled, given the mode and owner of the
  target, and moved over it with `mv`; comparison is `cmp` before any write; failure before `mv` removes the temporary
  file and leaves the target — checked by the source scenarios comparing checksums before and after, and by a run with a
  source that stops being readable mid-way (manual, recorded in the PR).
- `client` mode never starts `slurmctld` or `slurmd`, and no code path issues `scontrol reconfigure` except the local
  restart path, which is a signal to the hook's own `slurmctld` pid — checked by review of the script and by the "Client
  mode" scenario.
- Every failure exits non-zero with one message naming the input and the reason; `sudo -n` is used for every privileged
  step so a missing sudoers entry fails at once — checked by the "No passwordless sudo" re-run with a user without sudo.

**Non-Goals:**

- Everything the proposal places out of scope; `NOTES.md` tells users what the local mode does not prove.
- Managing `gres.conf`, `cgroup.conf`, `topology.conf`, `Include` targets, `slurmdbd`, or configless mode.
- Providing or distributing a MUNGE key for a remote cluster; the developer mounts it at `/etc/munge/munge.key`.
- Stopping the daemons at container stop, or recovering jobs after a restart.
- A diagnostics command; the daemon logs under `/var/log/slurm` and `scontrol show config` are the diagnostics.
- Fedora, openSUSE, Alpine, and Slurm built from source.

## Options

The feature has no options: the two runtime variables are not build options because they must change without a rebuild
of the image, and `${devcontainerId}` cannot vary by option.

- **Rejected option shapes.** A `version` option — rejected for the first version, the feature installs the
  distribution's package and must not claim a release it cannot install (the issue's out-of-scope list); it can be added
  later as a MINOR change. A `mode` build option mirroring `DEVCONTAINER_SLURM_FEATURE_MODE` — rejected, two sources for
  one role would need a precedence rule and a rebuild to change. A `configFile` build option — rejected for the same
  reason, and the file is a runtime input.

## Decisions

- **Distribution packages, not upstream builds.** Slurm publishes source only; building it in every image would add
  minutes and a toolchain, and the distribution's package is signed and verified by the package manager. The cost is a
  different Slurm version per image, which the proposal accepts and `NOTES.md` states. Alternative: a GHCR image of
  Slurm — rejected, the collection installs into the user's image.
- **Marker-governed identity lines, not a hostname-independent seed.** Docker assigns a recreated container a new
  hostname, `slurmctld` refuses to run where its hostname matches no `SlurmctldHost`, and `slurmd` needs its hostname
  among the node lines, so a seed written at build time cannot stay valid without a start-time step. Rewriting only
  while the marker is line one keeps the rule explicit and auditable: the user who removes the marker owns the file.
  Alternative: names that need no rewrite (`SlurmctldHost=localhost`, `NodeName=localhost`, `slurmd -N localhost`) —
  rejected unless the proof of concept shows both daemons accept them on every target version, because `slurmd -N` is
  documented for multiple-slurmd builds and `slurmctld` checks its own hostname; if they do, the rewrite becomes a no-op
  and the marker stays as the contract. Alternative: rewriting at the first start only — rejected, the second recreation
  would break the cluster.
- **Resources from `slurmd -C` at start, never from the build host.** The build sees the build host's CPUs and memory,
  not the container's; a seed that overstates them marks the node down. The node line comes from `slurmd -C`, which
  reports what the container sees, with `State=UNKNOWN` kept.
- **No cgroup plugins by default.** `proctrack/linuxproc` and `task/none` need no cgroup delegation and no privileges;
  the price is weaker process tracking, which the proposal accepts for a development cluster.
- **Daemons started directly, with pid files owned by the hook.** The images have no systemd, and `init: true` is not a
  service manager; direct starts with `-D`-less daemonization and pid files under `/run/slurm-feature/` are what the
  hook can inspect and stop. Alternative: `init: true` — rejected, it adds a reaper but no control and widens the
  container's metadata. Alternative: `entrypoint` — rejected, the copy and the mode need the workspace and the
  variables, and `postStartCommand` already runs after both exist; the firewall feature uses an entrypoint because its
  rules must precede every process, which Slurm's daemons need not.
- **Restart, not `scontrol reconfigure`, after a local configuration change.** A restart covers every kind of change
  (`AuthType`, ports, node lines) with one path; running jobs are lost, which the persistence scope already declines to
  promise. `scontrol reconfigure` stays unused so no path can reach a remote controller by mistake.
- **MUNGE key at the first local start.** A key in the image would be shared by every container built from it; one
  generated at first start, `0400` and owned by `munge`, is private to the container and not persisted, as decided. In
  `client` mode the hook starts `munged` only when a key exists, so a user-mounted cluster key works and the absence of
  one is reported rather than papered over with a random key.
- **One volume, mounted at `/etc/slurm`.** The packages read that path, so no `SLURM_CONF` override is needed and
  daemons and commands agree on the file. The whole directory is in the volume so companion files the user adds persist
  too. Alternative: a volume at another path and `SLURM_CONF` set through `containerEnv` — rejected, it adds metadata
  and a variable users would confuse with the feature's.
- **Relative source paths resolve against the workspace folder.** The hook reads it from the working directory the tool
  gives a `postStartCommand`, which is the workspace folder; when run by hand from elsewhere, the developer passes an
  absolute path or runs it from the workspace, as `NOTES.md` says.
- **Validation of the source is structural only.** The hook checks existence, type, readability, and identity with the
  target; it does not parse `slurm.conf`, because the daemons are the only correct parser and a remote cluster's file
  may use directives the local version lacks. A broken file reaches the daemons, which fail and are reported.

## Risks / Trade-offs

- [The proof of concept finds that `slurmctld` or `slurmd` on one target version rejects the aligned identity lines or
  needs a different node line] → the proof of concept runs first on every target image; the spec's contract is the
  outcome (the cluster starts after recreation, nothing else changes), so the mechanism can move within the design
  without a spec change, and an image that cannot be made to work leaves the compatibility list before approval of the
  implementation.
- [`${devcontainerId}` is not expanded by every tool in feature `mounts`] → the devcontainer CLI, which the tests and
  Codespaces use, expands it; the proof of concept checks it in `devcontainer features test`; a tool that does not would
  mount a literal name, shared between dev containers, which `NOTES.md` would then state.
- [Scenario runs leave a named volume per test container on the daemon that runs them] → CI runners are ephemeral;
  locally, `NOTES.md` and the test folder's comments give `docker volume ls --filter name=slurm-config-` and
  `docker volume rm`; a `just test-clean` extension is a separate harness change.
- [A user's `remoteUser` without passwordless `sudo`] → the hook fails at once with the reason; the proposal states the
  assumption and the limitation is in `NOTES.md`.
- [The first `sinfo` runs before the daemons are ready when the tool does not wait for `postStartCommand`] → `NOTES.md`
  documents `"waitFor": "postStartCommand"`; the hook itself waits for readiness, so a tool that waits sees a ready
  cluster.
- [`slurmd -C` under a CPU quota reports every host CPU] → accepted; the local mode promises no isolation, and the
  seed's `CR_Core` only shapes scheduling.
- [Ubuntu 22.04 ships Slurm 21.08, two major versions behind] → kept in the candidate list for the proof of concept;
  dropped from `compatibility.json` before implementation if the hook needs a feature it lacks.
- [Daemons keep running after the hook fails later in the same start] → the hook orders the source import and the mode
  decision before any daemon step, so a failed import or an invalid mode leaves the daemons as they were, which the spec
  states.

## Open Questions

- Whether `getent hosts` resolves the container's own hostname on every target image, or the hook must also read
  `/etc/hostname` — a mechanism detail the proof of concept settles.
- Whether `slurmd` on Debian 12 needs `/sys/fs/cgroup` readable even with no cgroup plugin configured — settled by the
  proof of concept; it changes no requirement.
