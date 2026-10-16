## What it installs

Real Apptainer, in its **unprivileged, non-setuid** form: the `apptainer` package, never `apptainer-suid`. Everything
that needs the setuid helper is out of reach in a container anyway: the container has no `CAP_SYS_ADMIN`, so even root
cannot mount, and `--fakeroot` fails because the user-namespace mapping helpers cannot write the mapping. What works is
what an unprivileged user can do with user namespaces: build and run sandbox directories, pull and run SIF images,
`apptainer shell`, `exec`, `run`, and `build` into a sandbox or a SIF.

The installed version is whatever each source currently ships; the feature has no `version` option. On Debian and Ubuntu
images without `/etc/localtime` (the plain `ubuntu` images) the feature also installs `tzdata`, because Apptainer binds
that file into every container.

| Image                | Source                                                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Fedora               | The image's own repositories                                                                                                    |
| AlmaLinux 9, Rocky 9 | EPEL 9, enabled through the distribution's `epel-release` package when the image has not configured it, key fingerprint checked |
| Ubuntu               | The project's PPA (`ppa:apptainer/ppa`), key fingerprint checked, written as a `signed-by` source                               |
| Debian               | The `.deb` of the newest GitHub release, amd64 only; upstream publishes no checksum or signature, so TLS alone protects it      |

Supported images are listed in [test/apptainer/compatibility.json](../../test/apptainer/compatibility.json). The full
behavior is specified in [openspec/specs/apptainer/spec.md](../../openspec/specs/apptainer/spec.md).

## What it adds to the container

| Metadata      | Value                                       | Why                                                                                                                                    |
| ------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `securityOpt` | `seccomp=unconfined`, `apparmor=unconfined` | Docker's default seccomp profile forbids unprivileged user namespaces, and its AppArmor profile forbids mounting; Apptainer needs both |

These settings relax the container's isolation for every process in it, not only Apptainer. Add the feature only to dev
containers whose other software you trust with that.

## What the host must allow

- **Unprivileged user namespaces.** Most distributions allow them (`user.max_user_namespaces` above zero; on Debian also
  `kernel.unprivileged_userns_clone=1`).
- **Ubuntu 24.04 and newer hosts** restrict them to confined programs. The container runs unconfined, so set
  `kernel.apparmor_restrict_unprivileged_userns=0` on the host, as Apptainer's admin guide says for unprivileged
  installs; otherwise every `apptainer exec` fails with Apptainer's message about user namespaces.
- **`/dev/fuse` for SIF images.** Mounting a SIF needs the FUSE device, which a feature cannot add. Either pass it in
  your `devcontainer.json`:

  ```json
  { "runArgs": ["--device=/dev/fuse"] }
  ```

  or run SIF images with `--unsquash`, which extracts them to a temporary sandbox first. That extraction mounts a procfs
  inside a user namespace, which some Docker hosts refuse (GitHub-hosted runners do: "can't mount proc filesystem to
  /proc: operation not permitted"); sandbox directories (`apptainer build --sandbox mydir docker://...`) work everywhere
  user namespaces do and need nothing else.

## With the slurm feature

When this collection's [`slurm`](../slurm/README.md) feature is installed in the same container, it finds Apptainer and
configures it as the container backend of its local Slurm: `srun --container <sandbox dir>` and
`sbatch --container <sandbox dir>` run the job step inside the sandbox. See that feature's notes for the option that
controls it.
