# Spec Delta

## Purpose

Installs Slurm and MUNGE from the image's distribution and runs, at every container start, either a real single-node
Slurm cluster (`slurmctld`, `slurmd`, `munged`) inside the dev container or only the client side against an external
cluster, with the Slurm configuration directory persisted in a named volume and optionally imported from a file the
developer names.

Upstream sources:

- Home and source: https://github.com/SchedMD/slurm
- Documentation: https://slurm.schedmd.com/
- Quick Start Administrator Guide: https://slurm.schedmd.com/quickstart_admin.html
- slurm.conf reference: https://slurm.schedmd.com/slurm.conf.html
- slurmd reference: https://slurm.schedmd.com/slurmd.html
- Authentication: https://slurm.schedmd.com/authentication.html
- MUNGE: https://github.com/dun/munge
- Dev Container Features reference: https://containers.dev/implementors/features/

## ADDED Requirements

### Requirement: Supported images

The feature SHALL install on the distributions and architectures listed in `test/slurm/compatibility.json`. On a
distribution whose `/etc/os-release` identifies none of the supported families, the install SHALL fail before changing
the image, with a message naming the detected distribution. On an architecture where the distribution lacks a required
package, the install SHALL fail with the package manager's error.

#### Scenario: Supported image

- **WHEN** the feature is installed on an image listed in `test/slurm/compatibility.json`
- **THEN** the build succeeds, `sbatch`, `squeue`, `sinfo`, `srun`, `scontrol`, `slurmctld`, `slurmd`, and `munged` are
  present, the `slurm` and `munge` system users exist, and the start-time script the feature declares exists and is
  executable

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on an image whose distribution is not supported
- **THEN** the build fails with a message naming the detected distribution and installs nothing

### Requirement: Packages from the distribution

The feature SHALL install the Slurm client commands, `slurmctld`, `slurmd`, and MUNGE from the distribution's packages
at the version it ships, with the package manager's signature verification in effect: from the repositories configured
in the image on Debian, Ubuntu, and Fedora, and from EPEL on a RHEL derivative (Requirement: EPEL on RHEL derivatives).
It SHALL NOT download anything else at build time.

#### Scenario: Distribution version installed

- **WHEN** the feature has been installed on a Debian, Ubuntu, or Fedora image
- **THEN** `sinfo --version` reports the version of the distribution's Slurm client package, and the image's repository
  and signing key configuration is unchanged

#### Scenario: Package verification fails

- **WHEN** the package manager rejects a package or repository signature during the install
- **THEN** the build fails and the feature does not retry with verification disabled

### Requirement: EPEL on RHEL derivatives

On a RHEL derivative, the feature SHALL install Slurm from EPEL. When no EPEL repository is configured, it SHALL install
the distribution's `epel-release` package from the repositories configured in the image and SHALL verify the key that
package delivers as Requirement: EPEL signing key states before any EPEL package is installed; when that package is
unavailable, the install SHALL fail naming EPEL before changing the image.

#### Scenario: EPEL enabled on a RHEL derivative

- **WHEN** the feature is installed on a RHEL-derivative image of the compatibility list without EPEL configured
- **THEN** EPEL is configured from the distribution's `epel-release` package, `sinfo --version` reports the version EPEL
  ships for that release, and the `epel` repository has package signature checking on

#### Scenario: EPEL already configured

- **WHEN** the feature is installed on a RHEL-derivative image where EPEL is already configured
- **THEN** the install adds no repository and installs Slurm from the configured EPEL

#### Scenario: EPEL unavailable

- **WHEN** the feature is installed on a RHEL-derivative image where neither EPEL nor an `epel-release` package is
  available
- **THEN** the build fails with a message naming EPEL, and the image is unchanged

### Requirement: EPEL signing key

When the feature enables EPEL, it SHALL trust it only when the key file the `epel-release` package installs for that
release holds exactly one primary key whose full fingerprint equals the pinned one: EPEL 9,
`FF8AD1344597106ECE813B918A3872BF3228467C`. A release without a pinned fingerprint SHALL fail the install naming the
release. The feature SHALL NOT import a key from any other source.

#### Scenario: Key matches

- **WHEN** the `epel-release` package installs the EPEL 9 key with the pinned fingerprint
- **THEN** the install continues and EPEL packages are verified by the package manager with that key

#### Scenario: Key mismatch

- **WHEN** the key file holds a key with another fingerprint, or more than one primary key
- **THEN** the build fails naming the fingerprint found, and no EPEL package is installed

#### Scenario: Unpinned release

- **WHEN** the feature is installed on a RHEL derivative without EPEL configured whose EPEL release has no pinned
  fingerprint
- **THEN** the build fails naming the release, and no EPEL package is installed

### Requirement: Seeded single-node configuration

The install SHALL write `/etc/slurm/slurm.conf` describing a single-node cluster that this container runs on its own:
one node, one default partition, `AuthType=auth/munge`, `ProctrackType=proctrack/linuxproc`, `TaskPlugin=task/none`,
state and spool directories outside `/etc/slurm`, and a first line that marks the file as the feature's seed. It SHALL
NOT start a daemon or create a MUNGE key at build time.

#### Scenario: Fresh container with defaults

- **WHEN** a container built with the feature starts for the first time with neither variable of this feature set
- **THEN** `sinfo` lists the seeded partition with its one node idle, and `sbatch --wait` on a script that prints the
  hostname completes with the job's output in the container

#### Scenario: Test-only submission

- **WHEN** `sbatch --test-only` is run in that container with a script requesting resources the node has
- **THEN** Slurm reports when the job would start, and no job is queued

#### Scenario: Marker line present

- **WHEN** the seeded `slurm.conf` is read in a fresh container
- **THEN** its first line is the feature's marker comment, which says that the feature keeps the controller-host and
  node lines of this file aligned with the container and that removing the line stops it

### Requirement: Seeded configuration follows the container

At every start, while the volume's `slurm.conf` begins with the feature's marker line, the start hook SHALL set its
`SlurmctldHost` line and its `NodeName` line to the container's current hostname and the resources `slurmd -C` reports,
changing no other line. A `slurm.conf` that does not begin with the marker line SHALL NOT be changed by the feature in
any way except through Requirement: Configuration source file.

#### Scenario: Recreated with another hostname

- **WHEN** the container is removed and created again from the same image with the same volume and a different hostname,
  with the marker line still in place
- **THEN** the local cluster starts, `sinfo` lists the node idle under the new hostname, and every line of `slurm.conf`
  other than `SlurmctldHost` and `NodeName` is unchanged

#### Scenario: Marker removed

- **WHEN** the developer removes the marker line and edits `slurm.conf` in the volume, then the container starts
- **THEN** the file is byte-identical after the start, whatever the hostname

### Requirement: Configuration directory in a named volume

The feature SHALL declare one mount: the named volume `slurm-config-${devcontainerId}` at `/etc/slurm`. An empty volume
SHALL receive the image's `/etc/slurm` content at the first mount; a non-empty volume SHALL keep its content across
stops, rebuilds, and feature upgrades, and the feature SHALL never replace it with the seeded default.

#### Scenario: Rebuild keeps the volume

- **WHEN** `slurm.conf` in the volume has been edited, and the dev container is rebuilt without the source variable
- **THEN** the edited file is in place after the rebuild

#### Scenario: Feature upgrade keeps the volume

- **WHEN** a newer version of the feature with a different seed is built against an existing non-empty volume
- **THEN** the volume's `slurm.conf` is unchanged by the build and the start

#### Scenario: Volume recreated

- **WHEN** the volume is deleted and the container is created again
- **THEN** the volume holds the image's seed, and nothing of the deleted volume

### Requirement: Local state outside the volume

The feature SHALL keep the controller state directory, the compute spool directory, the daemons' logs, and the MUNGE key
outside `/etc/slurm`, in the container's writable layer, and SHALL NOT declare a volume for them. The MUNGE key SHALL be
generated at the first start that needs it, never at image build; a key the `munge` package generated at install SHALL
be removed by the install.

#### Scenario: Image carries no key

- **WHEN** the image built with the feature is inspected before any container start, on any image of the compatibility
  list, including one whose `munge` package generates a key at install
- **THEN** no MUNGE key file exists in it

#### Scenario: Key generated at first start

- **WHEN** a container starts in local mode for the first time
- **THEN** a MUNGE key readable only by the MUNGE user exists, and a second start reuses it

### Requirement: Configuration source file

When the container environment variable `DEVCONTAINER_SLURM_CONFIG_FILE` is set and not empty, the start hook SHALL copy
the file it names over the volume's `slurm.conf` before anything else, and SHALL treat it as authoritative at every
start. When the variable is unset or empty, the hook SHALL NOT change the volume's `slurm.conf`. The variable SHALL NOT
be read from Slurm's own `SLURM_CONF`.

#### Scenario: Omitted source

- **WHEN** the variable is unset or empty and the volume's `slurm.conf` was edited
- **THEN** the start leaves the file as edited, apart from Requirement: Seeded configuration follows the container

#### Scenario: Relative source path

- **WHEN** the variable holds a relative path
- **THEN** it is resolved against the workspace folder inside the container, and that file's content becomes the
  volume's `slurm.conf`

#### Scenario: Absolute source path

- **WHEN** the variable holds an absolute path
- **THEN** it is resolved in the container's file system, not the host's, and that file's content becomes the volume's
  `slurm.conf`

#### Scenario: Changed source

- **WHEN** the source file's content differs from the volume's `slurm.conf` at a start
- **THEN** after the start the volume's `slurm.conf` is byte-identical to the source

#### Scenario: Source cleared later

- **WHEN** a source was imported at an earlier start, and the container is recreated with the variable unset
- **THEN** the volume's `slurm.conf` keeps the imported content; the seeded default is not restored

### Requirement: Source file validation

Before the volume is touched, the start hook SHALL check that the resolved source exists, is a regular file, is
readable, and is not the volume's `slurm.conf` itself; on any failure it SHALL exit non-zero with a message naming the
given path and the reason, leaving the volume's `slurm.conf` byte-identical and the daemons as they were. It SHALL
handle paths with spaces and non-ASCII characters.

#### Scenario: Missing source

- **WHEN** the variable names a path that does not exist, or names a directory
- **THEN** the hook fails naming the path and the reason, and the volume's `slurm.conf` and the running daemons are
  unchanged

#### Scenario: Unreadable source

- **WHEN** the variable names a file the hook cannot read
- **THEN** the hook fails naming the path and the reason, and the volume's `slurm.conf` is unchanged

#### Scenario: Source is the target

- **WHEN** the variable names `/etc/slurm/slurm.conf` or a link to it
- **THEN** the hook does not copy the file onto itself, and the file is unchanged

### Requirement: Source copy safety

The start hook SHALL copy the source one way: it SHALL NOT write to, link to, or create a temporary file beside the
source, and it SHALL replace the volume's `slurm.conf` atomically through a temporary file in the same directory, so the
previous complete file stays in place until the new one is complete. When the source content equals the volume's
`slurm.conf`, the hook SHALL NOT write the file or restart a daemon for it.

#### Scenario: Read-only source

- **WHEN** the variable names a file on a read-only bind mount
- **THEN** the copy succeeds, the source's content, permissions, and modification time are unchanged, and no file was
  created beside it

#### Scenario: Unchanged source

- **WHEN** the source content equals the volume's `slurm.conf` at a start
- **THEN** the file's modification time is unchanged and, in local mode, the daemons keep their process ids

### Requirement: Daemon mode

The container environment variable `DEVCONTAINER_SLURM_FEATURE_MODE` SHALL select the start hook's role: `local` runs
the local cluster, `client` runs no local controller or compute daemon, `auto` (the default when unset or empty) chooses
between them as Requirement: Automatic mode detection states. Any other value SHALL fail the hook, naming the accepted
values, before anything is changed.

#### Scenario: Omitted mode

- **WHEN** the variable is unset or empty
- **THEN** the hook behaves as with `auto`

#### Scenario: Invalid mode

- **WHEN** the variable holds a value other than `auto`, `local`, or `client`
- **THEN** the hook exits non-zero naming the accepted values, and neither the configuration nor the daemons change

### Requirement: Local mode

In `local` mode the start hook SHALL run `munged`, `slurmctld`, and `slurmd` in the container, one of each, with the
volume's `slurm.conf`. When that file's `SlurmctldHost` entries do not all name this container, the hook SHALL fail
without starting a daemon. When the configuration changed since the daemons started, the hook SHALL restart the local
daemons; otherwise it SHALL leave them running.

#### Scenario: Local mode with a local configuration

- **WHEN** the mode is `local` and `slurm.conf` names this container as its only controller
- **THEN** one `munged`, one `slurmctld`, and one `slurmd` run, and `sinfo` lists the configured partition

#### Scenario: Local mode with a remote configuration

- **WHEN** the mode is `local` and `slurm.conf` names a controller that is not this container
- **THEN** the hook exits non-zero naming the controller entry, and no `slurmctld` or `slurmd` is started

#### Scenario: Repeated start

- **WHEN** the hook runs again in a container whose local daemons run with an unchanged configuration
- **THEN** the hook exits zero, still exactly one of each daemon runs, and their process ids are unchanged

#### Scenario: Configuration changed

- **WHEN** the hook runs after the volume's `slurm.conf` changed while the local daemons were running
- **THEN** the daemons run again with the new configuration, and `scontrol show config` reflects it

### Requirement: Client mode

In `client` mode the start hook SHALL NOT start `slurmctld` or `slurmd`, and SHALL stop them when a previous start left
them running. It SHALL run `munged` when a MUNGE key is present and the configuration uses MUNGE, and otherwise say that
the cluster's authentication must be provided. The Slurm commands SHALL use the volume's `slurm.conf` as it is.

#### Scenario: Client mode

- **WHEN** the mode is `client`
- **THEN** no `slurmctld` or `slurmd` runs after the start, and `scontrol show config` reads the volume's `slurm.conf`

#### Scenario: Client mode after local daemons

- **WHEN** the hook runs with `client` in a container where an earlier start left local daemons running
- **THEN** those daemons are stopped and the hook exits zero

#### Scenario: Unreachable controller

- **WHEN** the mode is `client` and the configured controller cannot be reached
- **THEN** the hook exits zero after the copy and daemon steps, and `sinfo` reports Slurm's own connection error; the
  hook does not start a local cluster instead

### Requirement: Automatic mode detection

In `auto` mode the hook SHALL read every `SlurmctldHost` entry of the volume's `slurm.conf`; it SHALL act as `local`
when each entry's host name or address resolves to this container's hostname, a loopback address, or an address of one
of its interfaces, as `client` when none does, and SHALL fail without changing a daemon when some do and some do not,
when an entry cannot be resolved, or when the file has no entry. `ClusterName` SHALL NOT take part.

#### Scenario: Auto with a local configuration

- **WHEN** the mode is `auto` and every `SlurmctldHost` entry points at this container
- **THEN** the hook behaves as `local`

#### Scenario: Auto with a remote configuration

- **WHEN** the mode is `auto` and no `SlurmctldHost` entry points at this container
- **THEN** the hook behaves as `client`

#### Scenario: Auto undecidable

- **WHEN** the mode is `auto` and the entries are mixed, one cannot be resolved, or none exists
- **THEN** the hook exits non-zero naming the entries, and no daemon is started or stopped

### Requirement: No reconfiguration of a remote controller

The start hook SHALL send `scontrol reconfigure`, a restart, or any other change only to a `slurmctld` running in this
container that it started; it SHALL NOT send one to any other controller, whatever the mode.

#### Scenario: Remote configuration imported

- **WHEN** the source variable imports a configuration naming a remote controller and the hook runs in `client` or
  `auto`
- **THEN** the hook issues no `scontrol reconfigure` and no request other than the Slurm commands the developer runs

### Requirement: Start hook

The feature SHALL declare one `postStartCommand`, a script in the image that runs as the remote user and does its
privileged steps through `sudo -n`, in this order: resolve and import the source, decide the mode, then start, restart,
or stop the local daemons. It SHALL exit non-zero on any failure, and SHALL be safe to run any number of times in the
same container.

#### Scenario: Remote user with passwordless sudo

- **WHEN** the container's remote user is not root and has passwordless `sudo`
- **THEN** the hook completes the copy and the daemon management and exits zero

#### Scenario: No passwordless sudo

- **WHEN** the remote user cannot run `sudo` without a password
- **THEN** the hook exits non-zero with a message saying so, without waiting for input

#### Scenario: Hook run by hand

- **WHEN** the developer runs the hook's script again from a shell
- **THEN** the result equals a container start with the same environment

### Requirement: Container metadata

The feature SHALL declare exactly one mount (Requirement: Configuration directory in a named volume) and one
`postStartCommand`, and SHALL NOT request `privileged`, `capAdd`, `securityOpt`, `entrypoint`, `init`, or
`containerEnv`. It SHALL declare no `dependsOn`, and `installsAfter` SHALL name exactly
`ghcr.io/hoshiori-dev/devcontainer-features/apptainer`, so Apptainer, when the user installs it, is present when this
feature's install runs.

#### Scenario: Metadata of a built container

- **WHEN** a container is built with only this feature
- **THEN** it is not privileged, has no added capability, and has one named volume mounted at `/etc/slurm`

### Requirement: Option apptainer

The feature SHALL accept the option `apptainer` as declared here; Requirement: Backend decision states what each value
does.

| Field   | Value                 |
| ------- | --------------------- |
| Type    | `string`              |
| Default | `"auto"`              |
| Enum    | `["auto","off","on"]` |

#### Scenario: Omitted apptainer

- **WHEN** the feature is installed without `apptainer` in an image where the `apptainer` feature was installed first
  and the Slurm is 23.02 or newer
- **THEN** the backend is configured, as with `on`

#### Scenario: Omitted apptainer without Apptainer

- **WHEN** the feature is installed without `apptainer` in an image without Apptainer
- **THEN** the build succeeds, the build log says the backend is not configured and why, and no `oci.conf` is written

#### Scenario: Backend required

- **WHEN** the feature is installed with `apptainer` set to `on` in an image without Apptainer, or whose Slurm predates
  23.02
- **THEN** the build fails naming what is missing

#### Scenario: Backend disabled

- **WHEN** the feature is installed with `apptainer` set to `off` in an image where Apptainer is present
- **THEN** no `oci.conf` is written and `srun --container` reports that no container runtime is configured

#### Scenario: Invalid apptainer

- **WHEN** the feature is installed with `apptainer` set to a value that is not `auto`, `on`, or `off`
- **THEN** the install fails with a message naming the accepted values, and nothing is installed

### Requirement: Backend decision

The install SHALL decide the Apptainer container backend from `apptainer` at build time: `auto` configures it when
`apptainer` is on `PATH` and the image's Slurm is 23.02 or newer, and otherwise logs why not; `on` fails the build
naming what is missing when either is absent; `off` never configures it and removes a template an earlier install left.
The decision SHALL be recorded in the image as the presence or absence of the backend template.

#### Scenario: Backend decided

- **WHEN** the feature is installed with `apptainer` set to `on` in an image where Apptainer and a Slurm of 23.02 or
  newer are present
- **THEN** the build succeeds and the backend template exists in the image

### Requirement: Apptainer container backend

When the backend is configured, the install SHALL keep a template `oci.conf` outside `/etc/slurm` that runs each
container step with `apptainer exec` on the bundle path, and the start hook SHALL copy it to `/etc/slurm/oci.conf` when
that file is absent and SHALL never overwrite an existing one. A sandbox directory named by `--container` SHALL then run
the step inside the container as the submitting user, without privileges.

#### Scenario: Job step in a sandbox

- **WHEN** an unprivileged user builds a sandbox with `apptainer build --sandbox` from a small OCI image and runs
  `srun --container <sandbox> cat /etc/os-release` in local mode
- **THEN** the output names the sandbox image's distribution, not the dev container's

#### Scenario: Batch job in a sandbox

- **WHEN** the user submits `sbatch --wait --container <sandbox>` with a script that prints `/etc/os-release`
- **THEN** the job completes and its output names the sandbox image's distribution

#### Scenario: Existing oci.conf kept

- **WHEN** the volume already holds an `oci.conf` and the container starts with the backend configured
- **THEN** the file is byte-identical after the start

#### Scenario: Slurm too old

- **WHEN** the backend is requested with `auto` on an image whose Slurm predates 23.02
- **THEN** the build succeeds without an `oci.conf`, and the build log names the installed and the required version

### Requirement: Installing twice

Installing the feature a second time on the same image SHALL succeed and leave the same result as one install with the
second run's `apptainer` value: the packages installed once, the seed rewritten with the same content, the start-time
script replaced, and the backend template written or removed according to that value.

#### Scenario: Second install

- **WHEN** the feature is installed twice on the same image
- **THEN** the build succeeds, and after a start one `munged`, one `slurmctld`, and one `slurmd` run

#### Scenario: Different apptainer value the second time

- **WHEN** the feature is installed with `apptainer` set to `off` and then to `on` in an image with Apptainer
- **THEN** the backend template exists after the second install, and the reverse order leaves none
