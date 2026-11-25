## What it does

Installs [Incus](https://linuxcontainers.org/incus/) from the
[Zabbly package repository](https://github.com/zabbly/incus), which Incus's installation guide names for Debian and
Ubuntu, and starts the Incus daemon at every container start, so you run **system containers inside the dev container**,
and virtual machines with the option `vm`.

The full behavior is specified in [openspec/specs/incus/spec.md](../../openspec/specs/incus/spec.md).

```sh
incus launch images:debian/13 demo
incus exec demo -- bash
incus list
```

## Security

- **The container is privileged.** Instances need writable cgroups, system paths Docker masks, and a bridge with packet
  filter rules; virtual machines need `/dev/kvm`, and loop-backed storage pools need loop devices; a feature cannot
  request single devices. A privileged container can take over its host.
- **Membership in the `incus-admin` group amounts to root in the container and on its host.** The feature adds the
  remote user to that group, whose members control a daemon that runs as root.
- **The image gains a package repository outside its distribution**: `pkgs.zabbly.com`, signed by a key the feature
  accepts only by its fingerprint. Later `apt-get upgrade` runs in the image follow that repository's channel.

Use this feature only for dev containers whose users you would trust with root on the host.

## Channels and the host's kernel

`channel` selects where Incus comes from: `stable` (the default) is upstream's current feature release and moves about
once a month; `lts-7.0` and `lts-6.0` are the long-term support series. The repository keeps only the newest builds of a
channel, so an exact version cannot be chosen.

- **The host's kernel must meet the requirement of the installed series.** Instances share the kernel of the machine
  that runs Docker. Incus's [requirements](https://linuxcontainers.org/incus/docs/main/requirements/) name the minimum
  for the current release; on an older host, choose `lts-6.0`, whose requirement is lower.
- **A volume written by a newer Incus cannot be opened by an older one.** Changing to an older channel needs a new
  volume: delete `incus-data-${devcontainerId}`, which deletes the instances with it.

## What happens at every start

- The container runs with an init process as its first process (the feature sets `init`). The daemon leaves ended helper
  processes to the container's first process, and a container command such as `sleep infinity` would never collect them.
- The feature's entrypoint, `/usr/local/share/incus-feature/start.sh`, starts `incusd` with the group `incus-admin` for
  its socket and waits at most 60 seconds until it answers. The daemon's log is `/var/log/incus/incusd.log`.
- With `initialize` `minimal` (the default), a daemon that holds no storage pool and no managed network gets Incus's own
  minimal initialization, `incus admin init --minimal`: a storage pool of the `dir` driver inside the volume, the NAT
  bridge `incusbr0`, and the `default` profile's disk and network devices. A daemon that holds either is left as it is.
- The outcome is recorded in `/run/incus-feature/status`: the result, the reason of a failure, and what was done about
  the initialization.
- The feature's `postStartCommand`, `/usr/local/share/incus-feature/check.sh`, reads that record, connects as the remote
  user, and fails with the reason when the daemon does not run.

The daemon is not supervised. If it stops, run `sudo /usr/local/share/incus-feature/start.sh`: it starts the daemon when
it does not run, never stops it, and changes nothing when it answers.

## Your own initialization

For anything beyond the minimal setup (another storage driver, several networks, profiles, projects, an API address),
set `initialize` to `none` and apply a [preseed](https://linuxcontainers.org/incus/docs/main/howto/initialize/) from a
lifecycle command, where the file and the command are visible in your repository:

```jsonc
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/incus:1": { "initialize": "none" }
  },
  "postCreateCommand": "/usr/local/share/incus-feature/check.sh && incus admin init --preseed < .devcontainer/incus.yaml"
}
```

```yaml
# .devcontainer/incus.yaml
networks:
  - name: devbr0
    type: bridge
    config:
      ipv4.address: 10.77.0.1/24
      ipv4.nat: "true"
      ipv6.address: none
storage_pools:
  - name: data
    driver: dir
profiles:
  - name: default
    devices:
      root:
        path: /
        pool: data
        type: disk
      eth0:
        name: eth0
        network: devbr0
        type: nic
```

A dev container tool may run lifecycle commands while the entrypoint is still starting the daemon, so the command first
runs the feature's start check, which waits for the daemon. `postCreateCommand` runs again when the container is created
again, against the daemon the volume already holds; Incus applies an unchanged preseed again without error.

## What persists

One named volume per dev container survives a rebuild: `incus-data-${devcontainerId}`, mounted at `/var/lib/incus`. It
holds the daemon's database, storage pools of the `dir` driver, images, and instances. Deleting the volume deletes them.

## Limits

- **Instance limits through cgroups are not applied.** `limits.memory`, `limits.cpu`, and the other limits Incus
  enforces through cgroups have no effect or are refused: inside the container the daemon's cgroup holds processes and
  cannot delegate controllers to its instances. Instances start and run without them.
- **Stopping the container ends every running instance at once**, as a power cut would: a feature has no hook that runs
  before the container stops. Stop instances first (`incus stop --all`).
- **A Docker daemon in the same container cuts instances off the network.** Docker sets the packet filter's forwarding
  policy to drop. Incus documents the remedy under
  [Prevent connectivity issues with Incus and Docker](https://linuxcontainers.org/incus/docs/main/howto/network_bridge_firewalld/).
- **`init` cannot be switched off from `devcontainer.json`**: a dev container tool turns it on when any feature asks for
  it. An image whose own command must be the container's first process, such as systemd, does not work with this
  feature.
- Virtual machines (`vm` `true`) run only where the host exposes `/dev/kvm` to the container.
- `incus launch` and `incus init` read an instance configuration from standard input when it is not a terminal; in a
  script, add `</dev/null`.

## OS support

See [test/incus/compatibility.json](../../test/incus/compatibility.json). The Zabbly repository serves the Debian and
Ubuntu releases its README lists, on amd64 and arm64; the build fails on any other release.
