## What it installs

Real Slurm, not a simulator: the distribution's `slurmctld`, `slurmd`, the client commands, and MUNGE. Every start of
the container runs a **single-node cluster inside the dev container** (controller, compute daemon, and MUNGE all in this
container), so `#SBATCH` directives, resource requests, queueing, and execution are checked by Slurm itself. With your
own `slurm.conf` it is instead the client of an external cluster.

The installed Slurm is the distribution's package, so the version differs per image; supported images are listed in
[test/slurm/compatibility.json](../../test/slurm/compatibility.json). Images whose Slurm is older than 24.05 (Debian 12,
Ubuntu 22.04 and 24.04, EPEL 9) are not supported: their `slurmd` cannot start without a writable cgroup file system,
which an unprivileged container lacks. The full behavior is specified in
[openspec/specs/slurm/spec.md](../../openspec/specs/slurm/spec.md).

## Configuration

`/etc/slurm` is a **named volume** (`slurm-config-${devcontainerId}`), so your configuration survives rebuilds of the
same dev container. The volume lives on one Docker host; deleting it discards the configuration, and a fresh volume is
seeded from the image's default configuration.

The seed starts with a marker line. **While that line is the first line**, every start rewrites the `SlurmctldHost` and
`NodeName` lines to this container's hostname and resources, because Docker gives a recreated container another
hostname; every other line is yours and is kept. Remove the marker line to take over the file completely.

Two container environment variables, set in `containerEnv` (they take effect when the container is recreated):

| Variable                          | Meaning                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `DEVCONTAINER_SLURM_CONFIG_FILE`  | One file copied over `/etc/slurm/slurm.conf` at every start. A relative path resolves against the workspace folder inside the container, an absolute path inside the container (mount a host file first). The file is copied, never written to or linked; a read-only bind mount works. A missing, unreadable, or non-regular file fails the start hook and leaves the existing configuration unchanged. Unset or empty: the volume's file is never overwritten, and clearing the variable does not restore the default. |
| `DEVCONTAINER_SLURM_FEATURE_MODE` | `auto` (default), `local`, or `client`. `local` runs the daemons and fails when `SlurmctldHost` names another machine; `client` runs no controller or compute daemon; `auto` reads the `SlurmctldHost` entries and fails rather than guess when they are mixed or unresolvable.                                                                                                                                                                                                                                          |

Only `slurm.conf` is imported. The seed also writes `cgroup.conf` with `CgroupPlugin=disabled`, which the local mode
needs; other companion files (`gres.conf`, `Include` targets) are yours to put in the volume. Only the configuration
directory is persisted: scheduler state, running jobs, logs (`/var/log/slurm`), and the MUNGE key, generated at the
first start, are not guaranteed to survive recreation. The feature never sends `scontrol reconfigure` or any other
change to a controller it has not identified as this container.

Connecting to a remote cluster still needs network access, a compatible Slurm version, and the cluster's MUNGE key at
`/etc/munge/munge.key` (mount it yourself); a copied configuration alone grants nothing.

## Start hook

The feature's `postStartCommand`, `/usr/local/share/slurm/start.sh`, does the copy and the daemon management. It needs
**passwordless `sudo`** for the remote user (the default users of the Dev Containers base images have it) and exits
non-zero on any failure, which makes the dev container tool skip your later lifecycle commands but does not stop the
container. To have tools wait for Slurm before connecting, set `"waitFor": "postStartCommand"` in your
`devcontainer.json`. Running the hook again by hand gives the same result as a start.

The default local mode uses `proctrack/linuxproc`, `task/none`, and no cgroup plugin: it checks submission, scheduling,
and single-node execution, not CPU, memory, or GPU isolation, multi-node scheduling, or production policies.

## Apptainer backend

With the [apptainer](../apptainer/README.md) feature installed first and the option `apptainer` at `auto` (the default)
or `on`, the feature writes an `oci.conf` so `srun --container <sandbox dir>` and `sbatch --container <sandbox dir>` run
the job step inside an Apptainer sandbox directory (`apptainer build --sandbox mydir docker://...`). The template is
copied into the volume only when `/etc/slurm/oci.conf` is absent; an existing file is kept. The backend needs Slurm
23.02 or newer; `on` fails the build when Apptainer or that version is missing, `auto` logs why it skipped, `off` never
configures it.

| Metadata           | Value                                                   | Why                                               |
| ------------------ | ------------------------------------------------------- | ------------------------------------------------- |
| `mounts`           | volume `slurm-config-${devcontainerId}` at `/etc/slurm` | The configuration survives rebuilds               |
| `postStartCommand` | `/usr/local/share/slurm/start.sh`                       | Copies the source and manages the daemons         |
| `installsAfter`    | `ghcr.io/hoshiori-dev/devcontainer-features/apptainer`  | Apptainer, when you install it, is found at build |
