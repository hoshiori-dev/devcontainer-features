# Proposal

Implements [#148](https://github.com/hoshiori-dev/devcontainer-features/issues/148).

## Why

A developer who writes `.sbatch` scripts has no way to check them without a cluster: `#SBATCH` lines are comments to
Bash, so `bash job.sbatch` proves nothing, and a hand-written mock reproduces Slurm's parsing and scheduling badly. A
real single-node Slurm inside the dev container checks submission, directives, resource requests, queueing, and
execution with Slurm itself, and the same installation serves as the client of an external cluster once the developer
brings that cluster's `slurm.conf`.

## What Changes

- A new feature `slurm` installs the distribution's Slurm packages and MUNGE on the Debian, Ubuntu, Fedora, and
  RHEL-derivative (AlmaLinux, Rocky Linux) images of its compatibility list, and seeds a minimal single-node
  `slurm.conf` that runs without cgroup isolation (`proctrack/linuxproc`, `task/none`). Debian, Ubuntu, and Fedora carry
  Slurm in their own repositories; a RHEL derivative carries it in EPEL, which the feature enables through the
  distribution's own `epel-release` package when it is not configured yet, checking the EPEL signing key against a
  fingerprint the spec pins.
- The Slurm configuration directory `/etc/slurm` is a named volume (`slurm-config-${devcontainerId}`) declared by the
  feature, so a configuration survives rebuilds of the same dev container; an empty volume is seeded from the image, a
  non-empty one is kept as it is, including after a feature upgrade.
- A `postStartCommand` of the feature runs at every start: it imports the file named by the container environment
  variable `DEVCONTAINER_SLURM_CONFIG_FILE` over the volume's `slurm.conf` when the variable is set, never touches the
  volume when it is unset or empty, then runs or stops the local daemons according to `DEVCONTAINER_SLURM_FEATURE_MODE`
  (`auto`, `local`, `client`, default `auto`). It assumes passwordless `sudo` for the remote user and fails with a
  non-zero status instead of degrading.
- The seeded configuration stays valid when Docker gives a recreated container another hostname: while the seeded file
  still carries the feature's marker line, each start aligns its controller-host and node lines with the container's
  hostname and resources and changes nothing else; a file without the marker is never changed by the feature.
- `local` mode runs `munged`, `slurmctld`, and `slurmd` in the container, generating the MUNGE key at the first start
  rather than in the image; `client` mode runs no controller or compute daemon; `auto` picks one of the two from the
  configuration's `SlurmctldHost` entries and fails when they do not all point at this container or all away from it.
  The feature never sends a reconfiguration to a controller it has not identified as local.
- Only the configuration directory is persisted. Scheduler state, the compute spool, logs, and the MUNGE key stay in the
  container's writable layer with no promise to survive recreation.
- The feature has one option, `apptainer` (`auto`, `on`, `off`; default `auto`), which configures Apptainer from the
  `apptainer` feature as the container backend of the local Slurm through an `oci.conf`, so `srun --container` and
  `sbatch --container` run a job step inside an Apptainer sandbox: `auto` configures it when Apptainer is in the image
  at build time and the image's Slurm is 23.02 or newer, `on` requires both and fails the build otherwise, `off` never
  configures it. The feature orders itself after the `apptainer` feature with `installsAfter` and does not depend on it,
  because a client-only Slurm needs no runtime. The two environment variables remain the runtime interface. Directed by
  the maintainer on 2026-10-15 ([#150](https://github.com/hoshiori-dev/devcontainer-features/issues/150)).
- The repository's root `README.md` lists the feature under "Features".

## Capabilities

### New Capabilities

- `slurm`: installing Slurm and MUNGE from the distribution, the seeded single-node configuration and its volume, the
  configuration source variable, the daemon mode variable, the start hook and its daemon management, persistence scope,
  container metadata, repeated installation, and failure behavior.

### Modified Capabilities

None.

## Impact

- Feature ids touched: `slurm`, new at version `1.0.0`. No other feature changes, so no other bump.
- Files: `src/slurm/` (`devcontainer-feature.json`, `install.sh`, the start-time scripts it installs, `NOTES.md`,
  generated `README.md`), `test/slurm/` (`test.sh`, `duplicate.sh`, `scenarios.json` and its scripts,
  `compatibility.json`), and `openspec/specs/slurm/spec.md` at archive; the root `README.md` and `README.zh.md` gain the
  feature's row.
- Container metadata: one `mounts` entry (the configuration volume) and one `postStartCommand`; no `privileged`,
  `capAdd`, `securityOpt`, `entrypoint`, `init`, or `containerEnv`. The volume, the start hook, and the `oci.conf` the
  backend option writes are the security-sensitive surface the package gate reviews.
- Dependencies: no `dependsOn`; `installsAfter` names `ghcr.io/hoshiori-dev/devcontainer-features/apptainer`, whose
  change (`add-apptainer-feature`) lands first.
- Downloads: none beyond the image's package repositories and, on a RHEL derivative, EPEL. EPEL is the one repository
  the feature adds; its key arrives in the distribution's `epel-release` package and is checked against the pinned
  fingerprint before use.
- CI: the new feature's jobs on each compatibility image and architecture, plus one job per scenario. Scenario runs
  leave named configuration volumes on the Docker daemon that runs them (design.md, Risks).
- `test/canary.json` does not change.

## Acceptance

**Becomes true:**

- On every image of `test/slurm/compatibility.json`, the scenarios of "Supported images", "Packages from the
  distribution", "Seeded single-node configuration", "Configuration directory in a named volume", "Local state outside
  the volume", "Local mode", "Start hook", "Container metadata", and "Installing twice" pass in the feature's
  autogenerated, duplicate, or scenario tests: a fresh container with neither variable set runs a local single-node
  Slurm in which `sinfo` lists the seeded partition and `sbatch --wait` runs a job to completion.
- The scenarios of "Option apptainer", "Backend decision", and "Apptainer container backend" pass in scenario tests on
  one image that installs the `apptainer` feature with this one and on one that does not, except "Slurm too old", which
  is verified by a manual run on an image whose Slurm predates 23.02, recorded in the PR's Validation section.
- The scenarios of "Configuration source file", "Daemon mode", "Automatic mode detection", "Client mode", and "No
  reconfiguration of a remote controller" pass in scenario tests on at least one image, through the container
  environment of the scenario or through re-runs of the start hook inside the container with the variables set, as
  `test/firewall` re-runs its start-time scripts.
- The scenarios of "EPEL on RHEL derivatives" pass in the autogenerated test on every RHEL-derivative image of the
  compatibility list, and "EPEL already configured" and "EPEL unavailable" in scenario tests on one such image.
- The scenarios CI cannot run are each verified by a manual run recorded in the PR's Validation section: "Seeded
  configuration follows the container" across a container recreation with another hostname, "Key mismatch" of "EPEL
  signing key", "Rebuild keeps the volume", "Feature upgrade keeps the volume", "Volume recreated", "Source cleared
  later" across a recreation, and "Read-only source" through a read-only bind mount.
- `src/slurm/NOTES.md` states, for human readers: that the feature installs real Slurm and is not a simulator; the two
  variables, that a relative source path resolves against the workspace root in the container and an absolute one inside
  the container, that the source is copied and never written to or linked, that an invalid source fails the start hook
  without changing the existing configuration and does not stop the container; that the volume holds the whole
  configuration directory while the source variable imports one `slurm.conf` and companion files are the user's; that
  the volume lives on one Docker host and that deleting it discards the configuration; that clearing the source variable
  does not restore the default configuration and how to reset the volume; that the default local mode validates
  submission, scheduling, and single-node execution without cgroup, GPU, or multi-node guarantees; that an imported
  remote configuration still needs network access, a compatible Slurm version, and the cluster's authentication key;
  that only the configuration is persisted; that the Slurm version is the distribution's, from EPEL on a RHEL
  derivative, and which version each image of the compatibility list gets; that the variables go in `containerEnv` and
  take effect on recreation, and that `"waitFor": "postStartCommand"` makes tools wait for Slurm; that the start hook
  needs passwordless `sudo`; that the feature keeps the seeded configuration's identity lines aligned until the marker
  line is removed; that `client` mode runs no controller or compute daemon but may still need the cluster's
  authentication service; and what the `apptainer` option configures, that it needs the `apptainer` feature and Slurm
  23.02 or newer, how a sandbox directory is built and passed to `--container`, and that an `oci.conf` already in the
  volume is kept.
- `just check` passes, including `just validate` for the new feature's metadata, version `1.0.0`, and compatibility
  list, and `just docs` leaves the generated `src/slurm/README.md` unchanged.
- The root `README.md` and `README.zh.md` each have one row for `slurm` under their features list, linking to
  `src/slurm/` with a one-sentence description.
- `just test slurm` and `just test-scenarios slurm` pass locally.

**Stays true:**

- The feature requests no `privileged`, `capAdd`, `securityOpt`, `entrypoint`, `init`, or `containerEnv`, declares no
  `dependsOn`, names only the `apptainer` feature in `installsAfter`, adds no package repository other than EPEL on a
  RHEL derivative, trusts, for the EPEL it enables, no signing key the image's own repositories did not deliver or the
  spec does not pin, and downloads nothing itself.
- The image carries no MUNGE key, including on distributions whose `munge` package generates one at install, and no
  Slurm daemon starts at image build time.
- A file named by `DEVCONTAINER_SLURM_CONFIG_FILE` is never written to, linked, or given a temporary file beside it, and
  an existing `slurm.conf` in the volume is never deleted, truncated, or replaced with a partial copy.
- With the source variable unset or empty, no start overwrites the volume's `slurm.conf` with the seeded default or with
  any other content, apart from the marker-governed identity lines of the seeded file.
- No start sends `scontrol reconfigure`, a restart, or any other change to a controller the feature has not identified
  as running in this container.
- No other feature's files, version, or tests change.
