# Tasks

## 1. Metadata and scaffold

- [x] 1.1 Replace the scaffold's `devcontainer-feature.json` with the option `apptainer`, the configuration volume
      mount, the `postStartCommand`, and `installsAfter` naming the apptainer feature; verify with `just validate`
- [x] 1.2 Write `test/slurm/compatibility.json` with the candidate images on amd64 and arm64; verify with
      `just validate`

## 2. Installer

- [x] 2.1 Write `install.sh`: platform detection, Slurm and MUNGE from the distribution (EPEL on a RHEL derivative with
      the pinned key), the `slurm` user and the feature-owned state directories, removal of a MUNGE key a package
      generated, the seeded `slurm.conf` with the marker line, the start hook installed to
      `/usr/local/share/slurm/start.sh`, and the Apptainer backend decision writing or removing the `oci.conf` template;
      verify with `shellcheck` and a run on one image of each family
- [x] 2.2 Write `scripts/start.sh`, the hook: re-exec as root through `sudo -n`, source import with validation and
      atomic replace, marker-governed alignment of the identity lines, mode decision with the `auto` rule, daemon
      management with pid files, readiness wait, `oci.conf` copy when absent; verify by running it twice in a container
      and checking one daemon of each kind
- [x] 2.3 Write `test/slurm/helpers.sh`, `test.sh` (packages, users, hook, seeded partition idle, `sbatch --wait`,
      `--test-only`, marker and hostname, key generated after the build, volume mounted, idempotent re-run, no backend
      template without Apptainer), and `duplicate.sh`; verify with `just test slurm`

## 3. Scenarios

- [x] 3.1 `test_source_and_modes` (debian:13): re-runs of the hook with the source variable (relative, absolute,
      changed, unchanged, missing, directory, the target itself), the marker removed, every mode, the `auto` rule on
      local, remote, mixed, and unresolvable entries; verify with
      `just test-scenarios slurm --scenario test_source_and_modes`
- [x] 3.2 `test_apptainer_backend` (debian:13 with the apptainer feature): `oci.conf` present, `srun
      --container`
      and `sbatch --container` in a sandbox, an existing `oci.conf` kept; verify with
      `just test-scenarios slurm --scenario test_apptainer_backend`
- [x] 3.3 `test_apptainer_off` (same pair, `apptainer` off): no template, no `oci.conf`; verify with
      `just test-scenarios slurm --scenario test_apptainer_off`
- [x] 3.4 `fail_backend_required` (debian:13): the installer with `apptainer` on fails naming what is missing, and with
      an invalid value names the accepted values; verify with
      `just test-scenarios slurm --scenario fail_backend_required`

## 4. Documentation

- [x] 4.1 Write `NOTES.md` with every statement the proposal's Acceptance lists; verify by reading it against that list
- [x] 4.2 Run `just docs`, and add the feature's row to `README.zh.md`; verify with `just docs-check`

## 5. Integration

- [x] 5.1 Run `just check`, `just test slurm`, and `just test-scenarios slurm`; record each Acceptance item and scenario
      with its result in the PR's Validation section, the manual runs included
