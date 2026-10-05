
# NVIDIA Container Toolkit (nvidia-container-toolkit)

Installs the NVIDIA Container Toolkit from NVIDIA's signed package repository and registers the nvidia runtime with a Docker daemon in the dev container.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/nvidia-container-toolkit:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Toolkit release to install: 'latest' for the newest stable release, or an exact MAJOR.MINOR.PATCH release. Older releases have known vulnerabilities; see the notes. | string | latest |
| configureDocker | Register the nvidia runtime in /etc/docker/daemon.json when a Docker daemon (dockerd) is installed in the dev container; skipped when none is. | boolean | true |

## OS support

Supported images are listed in
[test/nvidia-container-toolkit/compatibility.json](../../test/nvidia-container-toolkit/compatibility.json). Ubuntu 24.04
is on NVIDIA's list of supported platforms; Debian 12, Fedora 44, and openSUSE Leap 16.0 are not, so support for them is
best effort. Other Debian-, Ubuntu-, Fedora-, RHEL-, openSUSE-, and SLES-based images with apt, dnf, or zypper are
attempted but not supported. Other distributions, such as Alpine Linux and Amazon Linux 2, and architectures other than
amd64 and arm64 fail the build. The full behavior is specified in
[openspec/specs/nvidia-container-toolkit/spec.md](../../openspec/specs/nvidia-container-toolkit/spec.md).

## What you provide

The feature installs the toolkit only. The host's GPU drivers, and giving the dev container itself access to the host's
GPUs, are up to you and your `devcontainer.json`; the feature installs no GPU driver or CUDA and adds no container
capability.

## Docker

With `configureDocker` enabled, the feature registers the `nvidia` runtime in `/etc/docker/daemon.json` when a Docker
daemon (`dockerd`) is installed in the dev container, such as by the
[docker-in-docker](https://github.com/devcontainers/features/tree/main/src/docker-in-docker) feature, which it installs
after. It does not make `nvidia` the default runtime: select it with `docker run --runtime=nvidia`. With only the Docker
CLI, as from docker-outside-of-docker, the step is skipped. The dev container runs privileged when you add
docker-in-docker, because that feature requires it; this feature does not.

## Security: older releases

Older NVIDIA Container Toolkit releases have known vulnerabilities, including container escapes, and every release in
NVIDIA's stable repository stays installable through `version`. The default, `latest`, installs the newest release. If
you pin an exact `version`, judging its risk is up to you. Known at the time of this feature's release:

| Fixed in | Vulnerabilities in earlier releases                                |
| -------- | ------------------------------------------------------------------ |
| 1.16.2   | CVE-2024-0132 (critical), CVE-2024-0133 (medium)                   |
| 1.17.3   | CVE-2024-0135 (high), CVE-2024-0136 (high), CVE-2024-0137 (medium) |
| 1.17.4   | CVE-2025-23359 (high)                                              |
| 1.17.8   | CVE-2025-23266 (critical), CVE-2025-23267 (high)                   |

This list is not maintained after release. NVIDIA's product security page, https://www.nvidia.com/en-us/security/, is
the authoritative and current source.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/nvidia-container-toolkit/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
