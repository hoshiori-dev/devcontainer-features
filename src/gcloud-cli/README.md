
# Google Cloud CLI (gcloud-cli)

Installs the Google Cloud CLI (gcloud, bq, gsutil, and optional components) from Google's signed APT/DNF repositories with archive fallback, and preserves private ~/.config/gcloud state in a project volume.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/gcloud-cli:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Google Cloud CLI release to install ('latest' or an exact MAJOR.MINOR.PATCH version) | string | latest |
| components | Comma-separated Google Cloud CLI component IDs to install alongside the base CLI | string | - |

## Installation routes and version retention

`gcloud-cli` installs `gcloud`, `bq`, and `gsutil` on the default `PATH` for every user without modifying shell startup
files. Both `install.sh` and the creation-time state initializer use Bash (`#!/usr/bin/env bash`), so minimal images
without `bash` (such as stock Alpine Linux) are unsupported.

- **Debian and Ubuntu (`apt-get`)**: installs `google-cloud-cli` (and mapped component packages) from Google's signed
  APT repository (`https://packages.cloud.google.com/apt`), verifying the repository signing key against pinned
  fingerprint `35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3`. Python byte-compilation is skipped during package install
  (`CLOUDSDK_SKIP_PY_COMPILATION=1`) for fast container builds.
- **Fedora and RHEL derivatives (`dnf`)**: installs from Google's `cloud-sdk-el10` RPM repository, verifying the v10
  signing key against pinned fingerprint `C5F744A098136F40C370E8493156C631B64936F9`. Every RPM package is
  signature-checked (`gpgcheck=1`) against that local key; `repo_gpgcheck=0` follows Google's EL10 configuration because
  the repository metadata signature uses a 2048-bit key rejected by EL10 and Fedora 44 crypto policies.
- **Other Linux distributions (`x86_64` / `aarch64`, e.g. openSUSE Leap, Arch Linux)**: emits a warning naming the
  distribution and falls back to Google's official Linux tar.gz archive (`dl.google.com` for `latest`,
  `storage.googleapis.com/cloud-sdk-release` for pinned versions) installed under `/usr/local/share/google-cloud-sdk`
  with commands linked into `/usr/local/bin`. Because Google publishes no detached signature or standalone checksum file
  alongside the Linux tar.gz archives, fallback archive and `gcloud components install` downloads rely on HTTPS/TLS.

Google's APT and RPM repositories retain package versions published within the last 365 days. Pinning an older
`MAJOR.MINOR.PATCH` version on APT or DNF fails if that release has aged out of the 365-day window.

## Options and components

- **`version`** (default `"latest"`): accepts `"latest"` or an exact `MAJOR.MINOR.PATCH` release (without a leading
  `v`), such as `"593.0.0"`.
- **`components`** (default `""`): comma-separated Google Cloud CLI component IDs, such as
  `"kubectl,gke-gcloud-auth-plugin"`.
  - `alpha`, `beta`, and `preview` are already bundled in `google-cloud-cli` on APT/DNF and installed via
    `gcloud components install` on the archive fallback route.
  - `kubectl` maps to the `kubectl` package on APT/DNF.
  - `bigtable`, `cloud-datastore-emulator`/`gcd-emulator`, `cloud-firestore-emulator`, and `cloud-spanner-emulator` map
    to their upstream `google-cloud-cli-*-emulator` packages; other component IDs `<id>` map to `google-cloud-cli-<id>`
    on APT/DNF and `<id>` on the archive fallback route.

Installing the feature a second time updates or downgrades `gcloud` and installed components to the later `version`,
preserves existing state mappings, and leaves no duplicate repository definitions.

## Project state and persistence

The named volume `gcloud-cli-${devcontainerId}` is mounted at `/var/lib/gcloud-cli`. Your remote user's
`~/.config/gcloud` directory is linked to `/var/lib/gcloud-cli/config`, keeping `CLOUDSDK_CONFIG` unset and leaving all
other entries under `~/.config` local to the container.

The creation hook `/usr/local/share/gcloud-cli-feature/initialize` runs once per container creation (`onCreateCommand`)
to verify the mount, private permissions (`0700` on `/var/lib/gcloud-cli` and `config`; `0600` on known credential
files), and remote-user write access without running a full-tree scan or `sudo` on healthy volumes. If the container is
recreated with a different numeric UID, noninteractive `sudo` repairs ownership strictly inside `/var/lib/gcloud-cli`
without following symlinks out of it.

- **Existing `~/.config/gcloud` or `CLOUDSDK_CONFIG`**: if `~/.config/gcloud` already exists as a real file, directory,
  dangling link, or link elsewhere—or if `CLOUDSDK_CONFIG` is set to another directory—initialization fails clearly
  while preserving your existing data. Back up and migrate it explicitly rather than expecting automatic import.
- **Changing user, home, or mounts later**: recreate the container or rerun
  `/usr/local/share/gcloud-cli-feature/initialize` as the remote user.
- **Inspecting or migrating the project volume**:

  ```sh
  docker inspect CONTAINER_ID --format '{{range .Mounts}}{{if eq .Destination "/var/lib/gcloud-cli"}}{{.Name}}{{end}}{{end}}'
  ```

## Authentication and credentials

The feature configures no authentication during image build and never copies host credentials. After the container
starts, sign in via `gcloud init`, `gcloud auth login --no-launch-browser` (or `--cred-file=...`), or
`gcloud auth application-default login`.

- **Retained in `/var/lib/gcloud-cli/config`**: active configurations (`configurations/`), CLI credential stores
  (`credentials.db`, `access_tokens.db`, `legacy_credentials/`), and Application Default Credentials
  (`application_default_credentials.json`).
- **Consumer-managed stores**: external credential files referenced by `GOOGLE_APPLICATION_CREDENTIALS`, workload
  identity credential files outside `~/.config/gcloud`, and host Secret Service keyrings are not mapped or provisioned
  by this feature.
- **File retention vs. live login**: retaining credential files across container rebuilds keeps local CLI state intact,
  but tokens can still expire or be revoked by Google Cloud IAM. Automated tests validate file persistence, mounts, and
  permissions with synthetic fixtures only.

## Optional editor integration

If you use VS Code with Google Cloud Code (`GoogleCloudTools.cloudcode`), you can add `"GoogleCloudTools.cloudcode"` to
your project's `customizations.vscode.extensions` manually; this feature does not install IDE extensions automatically.

## Checking persistence locally

Contributors can run `test/gcloud-cli/manual/state_persistence.sh IMAGE` against a built dev container image for
`vscode` to verify unattended non-networked configuration and synthetic credential persistence across container
recreation and project isolation.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/gcloud-cli/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
