# Spec Delta

## Purpose

Installs the libvirt client tools from the image's distribution and prepares the dev container to manage the virtual
machines of the host's libvirt daemon: `qemu:///system` is the default connection, and at every container start the
remote user is given access to the host's libvirt socket when the developer has mounted the host's `/run/libvirt` into
the container.

Upstream sources:

- Home: https://libvirt.org/
- Documentation: https://libvirt.org/docs.html
- Connection URIs: https://libvirt.org/uri.html
- Daemons and their sockets: https://libvirt.org/daemons.html
- virsh reference: https://libvirt.org/manpages/virsh.html
- virt-install: https://virt-manager.org/
- Dev Container Features reference: https://containers.dev/implementors/features/

## ADDED Requirements

### Requirement: Supported images

The feature SHALL install on the distributions and architectures listed in
`test/libvirt-outside-of-docker/compatibility.json`. On a distribution whose `/etc/os-release` identifies none of the
supported families, the install SHALL fail before changing the image, with a message naming the detected distribution.
The feature SHALL NOT check the architecture itself; on an architecture where the distribution lacks a required package,
the install SHALL fail with the package manager's error.

#### Scenario: Supported image

- **WHEN** the feature is installed on an image listed in `test/libvirt-outside-of-docker/compatibility.json`
- **THEN** the build succeeds, `virsh` is on `PATH` for every user, and the scripts the feature declares as its
  entrypoint and its `postStartCommand` exist and are executable

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on an image whose distribution is not supported
- **THEN** the build fails with a message naming the detected distribution and installs nothing

### Requirement: Packages from the image's repositories only

The feature SHALL install the libvirt client (`virsh`) and the packages its options select only from the package
repositories already configured in the image, at the versions they ship, with the package manager's signature
verification in effect. It SHALL NOT add a package repository or a signing key, SHALL NOT download anything else at
build time, and SHALL NOT install a libvirt daemon or a QEMU system emulator.

#### Scenario: Client only

- **WHEN** the feature has been installed with default options
- **THEN** `virsh --version` reports the version of the distribution's libvirt client package, no libvirt daemon and no
  QEMU system emulator is installed, and the image's repository and signing key configuration is unchanged

#### Scenario: Package verification fails

- **WHEN** the package manager rejects a package or repository signature during the install
- **THEN** the build fails and the feature does not retry with verification disabled

### Requirement: Option virtInstall

The feature SHALL accept the option `virtInstall` as declared here: `true` installs the distribution's `virt-install`
package, which also provides `virt-clone` and `virt-xml`, and `false` does not install it.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `true`    |

#### Scenario: Omitted virtInstall

- **WHEN** the feature is installed without `virtInstall`
- **THEN** `virt-install --version` succeeds

#### Scenario: virtInstall disabled

- **WHEN** the feature is installed with `virtInstall` `false` on an image that does not hold `virt-install`
- **THEN** `virsh` is installed and `virt-install` is not

### Requirement: Option qemuImg

The feature SHALL accept the option `qemuImg` as declared here: `true` installs the distribution's package that provides
`qemu-img`, and `false` does not install it.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `false`   |

#### Scenario: Omitted qemuImg

- **WHEN** the feature is installed without `qemuImg` on an image that does not hold `qemu-img`
- **THEN** `qemu-img` is not installed

#### Scenario: qemuImg enabled

- **WHEN** the feature is installed with `qemuImg` `true`
- **THEN** `qemu-img --version` succeeds

### Requirement: Host socket mounted by the developer

The feature SHALL NOT declare a mount. The host's libvirt sockets reach the container only through a bind mount of the
host's `/run/libvirt` at `/run/libvirt` that the developer adds to `devcontainer.json`; `NOTES.md` SHALL give that
mount, read-only. A container built with the feature SHALL start whether or not the mount is present.

#### Scenario: No mount

- **WHEN** a container is built with the feature and without the mount
- **THEN** the container starts, and the start check reports that no host socket is mounted (Requirement: Start check)

#### Scenario: Read-only mount

- **WHEN** the host runs a libvirt system daemon and the developer mounts the host's `/run/libvirt` read-only at
  `/run/libvirt`
- **THEN** `virsh list --all`, run by a user who may open the socket, lists the host's virtual machines

### Requirement: Default connection

The feature SHALL set the container environment variable `LIBVIRT_DEFAULT_URI` to `qemu:///system`, so that every user's
libvirt client tools connect to the system daemon behind `/run/libvirt` instead of a per-user session daemon. It SHALL
NOT write a libvirt client configuration file. A value the developer sets for the variable in `remoteEnv` of
`devcontainer.json` replaces the feature's for the remote user's processes, and `NOTES.md` SHALL say so.

#### Scenario: Remote user's default connection

- **WHEN** the remote user runs `virsh uri` in a container whose mount reaches a running host daemon
- **THEN** it prints `qemu:///system`

#### Scenario: Developer's own URI

- **WHEN** `devcontainer.json` sets `LIBVIRT_DEFAULT_URI` in `remoteEnv` to another URI
- **THEN** the remote user's `virsh` connects to that URI

### Requirement: Socket group alignment at every start

On every start of the container the feature's entrypoint SHALL, when it runs as root and the remote user recorded at
build time is not root, look at the first of `/run/libvirt/virtqemud-sock` and `/run/libvirt/libvirt-sock` that is a
socket, the order in which the libvirt client prefers them, and make the remote user a member of a group that has the
socket's GID (Requirement: Group for the socket). It SHALL then hand over to the container's command, whatever the
outcome.

#### Scenario: Processes of the remote user can open the socket

- **WHEN** the mounted socket is group-writable, not world-writable, and its GID is not 0
- **THEN** after the start the processes the dev container tool starts for the remote user can open the socket

#### Scenario: Both sockets mounted

- **WHEN** the mount holds both `virtqemud-sock` and `libvirt-sock`, with different groups or modes
- **THEN** the group is aligned with `virtqemud-sock`, the socket `virsh --connect qemu:///system` opens

#### Scenario: Root remote user

- **WHEN** the remote user is root
- **THEN** no group is created or changed

#### Scenario: Entrypoint not run as root

- **WHEN** the container's user is not root
- **THEN** the entrypoint changes no group and the container's command runs

### Requirement: Group for the socket

When a group of the container already has the socket's GID, the entrypoint SHALL add the remote user to that group.
Otherwise it SHALL give a group named `libvirt-host` the socket's GID, creating the group when it does not exist, and
add the remote user to it. It SHALL never change the GID of any other group.

#### Scenario: Unused GID

- **WHEN** the socket's GID belongs to no group of the container
- **THEN** after the start a group `libvirt-host` has that GID and the remote user is a member

#### Scenario: GID of an existing group

- **WHEN** the socket's GID belongs to a group of the container
- **THEN** the remote user is a member of that group, and no group is created or renumbered

#### Scenario: Host GID changed

- **WHEN** a container that created `libvirt-host` at an earlier start is started with a socket of another unused GID
- **THEN** `libvirt-host` has the new GID and the remote user is a member

### Requirement: Membership in an existing group is accepted

Adding the remote user to a group of the container that happens to have the socket's GID also gives the user what that
group grants inside the container. The feature SHALL accept this and SHALL name the group in its start record: the
developer chose to give the remote user the host's libvirt daemon, which reaches further than any group of the container
(Requirement: Control of the host's daemon).

#### Scenario: Record names the group

- **WHEN** the remote user was added to an existing group of the container
- **THEN** the start record names that group and its GID

### Requirement: Sockets left to the host's authorization

The entrypoint SHALL change no group when neither path is a socket, when the socket's mode lets every user write to it,
or when the socket's group is GID 0. The remote user SHALL never be added to the root group. In the last two cases the
host decides by other means than the socket's group who may connect.

#### Scenario: No socket

- **WHEN** nothing is mounted at `/run/libvirt`
- **THEN** the remote user's groups are unchanged

#### Scenario: World-writable socket

- **WHEN** the mounted socket's mode lets every user write to it
- **THEN** the remote user's groups are unchanged

#### Scenario: Socket of the root group

- **WHEN** the mounted socket is owned by GID 0 and is not world-writable
- **THEN** the remote user's groups are unchanged and the start record says the socket's group is root

### Requirement: Start record

Each start whose entrypoint runs as root SHALL record what the group alignment did and why in a file `NOTES.md` names,
readable and not writable by the remote user. An entrypoint that does not run as root records nothing.

#### Scenario: Remote user reads the record

- **WHEN** the remote user reads the start record
- **THEN** it names the socket examined, its GID, and what was done, and writing to it is denied

### Requirement: Host directory left unchanged

The feature SHALL NOT create, remove, rename, re-own, or change the mode of anything under `/run/libvirt`, at build time
or at start, whether or not it is a mount.

#### Scenario: Writable mount

- **WHEN** the developer mounts the host's `/run/libvirt` without `readonly` and the container starts
- **THEN** every entry under the host's `/run/libvirt` has the owner, group, and mode it had before

### Requirement: Start check

The feature SHALL run, as its `postStartCommand` and as the remote user, a check that waits a bounded time for the
current start's record and then reports on the connection (Requirement: Start check result). It SHALL NOT wait when that
record is absent and the container's first process is not root's, since no record can come. The check SHALL be safe to
run any number of times and SHALL change nothing.

#### Scenario: Run by hand

- **WHEN** the developer runs the check's script again from a shell
- **THEN** it reports the same as at the start, and no group, file, or record has changed

#### Scenario: Group added while the check was starting

- **WHEN** the entrypoint adds the remote user to the socket's group after the check's process has started
- **THEN** the check connects with that group, as a process started later has it, and says so in its summary

### Requirement: Start check result

When neither `/run/libvirt/virtqemud-sock` nor `/run/libvirt/libvirt-sock` is a socket, the check SHALL print that no
host socket is mounted, name the mount `NOTES.md` gives, and exit zero. When one is a socket, it SHALL run
`virsh --connect qemu:///system version`: on success it SHALL print a one-line summary and exit zero, and on failure it
SHALL print the command's error and the start record and exit non-zero.

#### Scenario: Connected

- **WHEN** the mount reaches a running host daemon whose socket the remote user may open
- **THEN** the check prints a summary naming the daemon's libvirt version and exits zero

#### Scenario: No socket

- **WHEN** the container has no mount at `/run/libvirt`
- **THEN** the check prints that no host socket is mounted and how to add the mount, and exits zero

#### Scenario: Refused

- **WHEN** a socket is mounted and the host's daemon refuses the remote user
- **THEN** the check prints the error and the start record and exits non-zero, so the dev container tool reports the
  failure

### Requirement: Control of the host's daemon

The developer's mount gives the remote user control of the host's libvirt system daemon, which amounts to root on the
host: the daemon attaches any host file or device to a virtual machine on request, and a read-only mount does not narrow
this. The feature SHALL accept this risk, since managing the host's virtual machines is its purpose and the mount is
visible in `devcontainer.json`, and `NOTES.md` SHALL state it.

#### Scenario: Notes state the reach of the mount

- **WHEN** a developer reads the feature's `NOTES.md`
- **THEN** it says that the mount gives the container control of the host's libvirt daemon, that this amounts to root on
  the host, and that the read-only flag does not limit it

### Requirement: Not together with libvirt-in-docker

The install SHALL fail, before changing the image, with a message naming both features, when the image already holds the
`libvirt-in-docker` feature.

#### Scenario: Installed after libvirt-in-docker

- **WHEN** the feature is installed on an image on which `libvirt-in-docker` was installed
- **THEN** the build fails with a message naming both features and saying they are alternatives

### Requirement: Container metadata

The feature SHALL declare one `containerEnv` variable (Requirement: Default connection), one entrypoint (Requirement:
Socket group alignment at every start), and one `postStartCommand` (Requirement: Start check). It SHALL NOT request
`privileged`, `capAdd`, `securityOpt`, `mounts`, or `init`, and SHALL declare no `dependsOn` and no `installsAfter`.

#### Scenario: Metadata of a built container

- **WHEN** a container is built with only this feature
- **THEN** it is not privileged, has no added capability, and has no mount the feature declared

### Requirement: Installing twice

Installing the feature a second time SHALL succeed. With the same options, the image SHALL end up as after one install.
With different options, a package an earlier install added SHALL stay, a package the later install selects SHALL be
added, and the remote user the later install recorded SHALL be the one the entrypoint serves.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same options
- **THEN** the build succeeds and the installed tools and the start behavior are those of one install

#### Scenario: Different options the second time

- **WHEN** the feature is installed with `virtInstall` `false` and `qemuImg` `true`, and then with default options
- **THEN** the build succeeds and `virsh`, `virt-install`, and `qemu-img` are all installed

### Requirement: Documented limits

`NOTES.md` SHALL state that paths in a virtual machine's definition, disk images among them, are paths on the host; that
only the host's system daemon (`qemu:///system`) is reached, not a user's session daemon; that graphical consoles listen
on the host and are not reachable through the mount, while `virsh console` is; and that the group alignment happens at
container start only.

#### Scenario: Notes list the limits

- **WHEN** a developer reads the feature's `NOTES.md`
- **THEN** each statement of this requirement is present

### Requirement: Documented host requirements

`NOTES.md` SHALL state that the host must be Linux with a Docker daemon that runs as root beside the libvirt daemon,
which excludes Docker Desktop, rootless Docker, and Podman; that the numeric user ID of the container's user must belong
to a user of the host, whom the host's daemon looks up and, where polkit authorizes the socket, decides by; and that a
host that confines containers with SELinux needs that confinement lifted for the socket by the developer.

#### Scenario: Notes list the host requirements

- **WHEN** a developer reads the feature's `NOTES.md`
- **THEN** each statement of this requirement is present

#### Scenario: User ID unknown to the host

- **WHEN** the socket's group admits the remote user and the host has no user with the remote user's numeric ID
- **THEN** the host's daemon refuses the connection and the start check exits non-zero with the daemon's error
