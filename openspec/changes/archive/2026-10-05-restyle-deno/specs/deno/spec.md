# Spec Delta

## MODIFIED Requirements

### Requirement: Shared location for global tools

The feature SHALL set `DENO_INSTALL_ROOT` to `/usr/local/share/deno` in the container environment and SHALL put
`/usr/local/share/deno/bin` on `PATH` there, so that executables created with `deno install --global` land in that
directory and run by name in every shell. `/usr/local/share/deno/bin` SHALL come after the image's own `PATH` entries.
Because a login shell's startup files may reset `PATH` (Debian's `/etc/profile` does), the feature SHALL also append the
directory to `PATH` in login shells through a file of its own under `/etc/profile.d/`, adding it only when it is not
already there. When the remote user exists at build time and is not root, the feature SHALL make `/usr/local/share/deno`
and `/usr/local/share/deno/bin` writable by that user without elevated privileges, also after the Dev Container CLI
changes that user's UID or GID to match the host; otherwise it SHALL leave them owned by root.

For a non-root remote user, an existing `deno` group SHALL be reused only when it has no supplementary members other
than that user and is not any account's primary group. A conflict SHALL fail before package installation or downloads,
with a message naming the conflicting account, without changing group membership or the tools directories.

For a non-root remote user, the feature SHALL require `groupadd` only when the `deno` group does not exist yet, and
`usermod` only when that user is not yet a member of the `deno` group. When a command it requires is missing, the
feature SHALL fail before package installation or downloads, with a message naming the missing command, without changing
group membership or the tools directories.

#### Scenario: Existing group belongs to another account

- **WHEN** a non-root remote user exists and another account is a supplementary member of `deno` or uses its GID as its
  primary group
- **THEN** installation fails before package installation or downloads, names the conflicting account, and leaves group
  membership and the tools directories unchanged

#### Scenario: Remote user has deno as its primary group

- **WHEN** a non-root remote user exists and uses the existing `deno` group's GID as its primary group
- **THEN** installation fails before package installation or downloads, explains the primary-group conflict, and leaves
  group membership and the tools directories unchanged

#### Scenario: Existing group is reserved for the feature

- **WHEN** an existing `deno` group is no account's primary group and has no supplementary members other than the
  non-root remote user
- **THEN** installation succeeds, including when that group is empty, and the user retains tools access after UID/GID
  remapping and a reinstall

#### Scenario: Group command missing

- **WHEN** a non-root remote user exists, and the image lacks `groupadd` while no `deno` group exists, or lacks
  `usermod` while that user is not a member of the `deno` group
- **THEN** installation fails before package installation or downloads, names the missing command, and leaves group
  membership and the tools directories unchanged

#### Scenario: Group prepared in the image

- **WHEN** a non-root remote user is already the only supplementary member of a `deno` group that is no account's
  primary group, and the image lacks both `groupadd` and `usermod`
- **THEN** installation succeeds and that user installs a global tool with `deno install --global` without elevated
  privileges

#### Scenario: Non-root remote user installs a global tool

- **WHEN** the remote user is a non-root user that exists at build time and runs `deno install --global` on a local
  script
- **THEN** the command succeeds without elevated privileges, the executable appears in `/usr/local/share/deno/bin`, and
  it runs by name from a new shell

#### Scenario: Remote user's UID changed after the build

- **WHEN** the remote user is a non-root user that exists at build time, and its UID and GID are changed after the
  build, as the Dev Container CLI's `updateRemoteUserUID` does to match the host
- **THEN** that user still installs a global tool with `deno install --global` without elevated privileges, and the tool
  runs by name from a new shell

#### Scenario: Login shell runs a global tool

- **WHEN** a global tool is installed with `deno install --global` and a login shell (`bash -l`) is started as the
  remote user, on an image whose `/etc/profile` resets `PATH`
- **THEN** the tool runs by name in that login shell, and `/usr/local/share/deno/bin` appears in its `PATH` once, after
  the image's own entries

#### Scenario: Root or absent remote user

- **WHEN** the remote user is root, or does not exist when the feature is installed
- **THEN** the installation succeeds and `/usr/local/share/deno` is owned by root
