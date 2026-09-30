# Design

## Context

Research for this change, checked on 2026-09-30; see `proposal.md` for the motivation.

- **How the dev container CLI runs a feature entrypoint** (`devcontainers/cli`, `src/spec-node/singleContainer.ts`,
  `src/spec-node/imageMetadata.ts`): all entrypoints are joined by newlines into one `/bin/sh -c` script that first
  prints `Container started`, then runs them in metadata order (base image, then features in install order, then
  `devcontainer.json`), then `exec "$@"`. There is no `set -e`, so a failing entrypoint does not stop the container, and
  a hanging one delays the container's command. The script runs as the image's user unless `containerUser` is set;
  `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` and the plain distribution images run it as root. The CLI waits
  for Docker's start event, not for the entrypoints, before it runs lifecycle commands, so `postCreateCommand` and
  `postStartCommand` can begin while an entrypoint still runs. When a feature's lifecycle command fails, the CLI prints
  "Skipping any further user-provided commands" and runs none of the user's later hooks
  (`src/spec-common/injectHeadless.ts`). The `wslc` CLI variant drops `--cap-add`, `--privileged`, `--init`, and
  `--security-opt`.
- **Metadata merge**: the Features spec says `capAdd` is concatenated; the CLI takes a de-duplicated union. Docker's
  default capability set already includes `NET_RAW` (`moby/moby`, `oci/caps/defaults.go`).
- **Docker networking**: containers on a user-defined network resolve through the embedded DNS server at `127.0.0.11`
  (no IPv6 equivalent); containers on the default bridge get a copy of the host's `resolv.conf` (docker/docs,
  `engine/network/_index.md`). When that copy names only loopback resolvers, Docker substitutes `8.8.8.8` and `8.8.4.4`
  (`moby/moby`, `daemon/libnetwork/internal/resolvconf/resolvconf.go`) — this is what a nested Docker daemon does for
  its default-bridge containers once the dev container's `resolv.conf` points at a local resolver. Docker DNATs queries
  to `127.0.0.11:53` to a random port in its `nat` output chain, which runs before a filter-priority output chain, so
  only an interface match (`lo`) recognises them. `/etc/resolv.conf` is a bind mount Docker manages, so it can be
  rewritten in place but not replaced by a rename. Docker's iptables backend filters forwarded traffic in `DOCKER-USER`;
  its nftables backend (Docker 29, experimental) has no `DOCKER-USER` and tells users to add their own tables with their
  own base chains (`firewall-nftables.md`).
- **docker-in-docker** (`devcontainers/features`, `src/docker-in-docker`, 4.1.2): `privileged: true`, entrypoint
  `/usr/local/share/docker-init.sh`, which switches `iptables` alternatives between legacy and nft at start and starts
  `dockerd` in the background; it installs after `common-utils`. `common-utils` (2.7.0) declares no entrypoint. Current
  majors: docker-in-docker 4, common-utils 2.
- **Prior art** (`anthropics/claude-code`, `.devcontainer/`): `runArgs` add `NET_ADMIN` and `NET_RAW`;
  `postStartCommand: sudo /usr/local/bin/init-firewall.sh` with a sudoers line for that script; the script flushes the
  filter, nat, and mangle tables, restores Docker's DNS NAT rules, builds an ipset from GitHub meta `web`, `api`, `git`
  (through `aggregate`) and resolved domains, and self-checks that `example.com` fails and `api.github.com` succeeds. It
  leaves UDP 53 and TCP 22 open to any host, the host's /24 open both ways, and IPv6 unfiltered. Other published
  firewall features (`w3cj`, `blacktop`, `gus-costa`) use `postStartCommand` with `sudo`; `nshafer/egress-filter` uses a
  root entrypoint, a squid proxy, and `DOCKER-USER`, and its entrypoint always exits zero.
- **GitHub meta** (https://api.github.com/meta, 201,132 bytes, unauthenticated rate limit 60 requests per hour per IP,
  confirmed by its `x-ratelimit-limit` header): `web` 40, `api` 26, `git` 60 entries, each list with IPv6 ranges (for
  example `2a0a:a440::/29` in `git`); `web` includes `185.199.108.0/22`, where `raw.githubusercontent.com`,
  `objects.githubusercontent.com`, and `release-assets.githubusercontent.com` resolve, and `2606:50c0::/32`.
  `domains.website` lists `*.github.com` and `*.githubusercontent.com`.
- **dnsmasq `--nftset`** (dnsmasq manual): adds the addresses of every answer for the listed domains and their
  subdomains to existing nftables sets, `4#` or `6#` selecting the address family. dnsmasq keeps `CAP_NET_ADMIN` after
  dropping privileges when nftsets are configured (`src/dnsmasq.c`, dnsmasq 2.91 as packaged by Ubuntu). Fedora's
  `/etc/dnsmasq.conf` includes `/etc/dnsmasq.d`.
- **Kernel**: rules live in the host kernel. The WSL2 kernel `6.18.33.2-microsoft-standard-WSL2` has `nf_tables` with
  the `inet` family built in. GitHub-hosted runner kernels and Docker Desktop kernels were not checked; the first CI run
  on each architecture checks them.
- **Hosts the presets' sources list and the presets leave out**: https://code.claude.com/docs/en/network-config also
  names `claude.com`, `mcp-proxy.anthropic.com`, `storage.googleapis.com`, `bridge.claudeusercontent.com`, and two
  optional Datadog telemetry hosts; https://code.visualstudio.com/docs/setup/network also names
  `download.visualstudio.microsoft.com`, `*.vscode-unpkg.net`, `vscode-sync.trafficmanager.net`, and `vscode.dev`.
  `domains.website` of GitHub meta also lists `*.githubassets.com`, `*.github.io`, and `*.github.dev`.
- **Docker Hub blobs**: an anonymous blob request to `registry-1.docker.io` redirected to
  `production.cloudfront.docker.com`, a host Docker's allowlist page
  (https://docs.docker.com/desktop/enterprise/allow-list/) does not name; tests therefore pull no image (Goals: Test
  destinations).

Packages on the planned images, verified on 2026-09-30 for amd64 and arm64:

| Image                                               | nftables          | dnsmasq with nftset support                                                                   | Also installed                  |
| --------------------------------------------------- | ----------------- | --------------------------------------------------------------------------------------------- | ------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` | `1.0.9-1build1`   | `dnsmasq-base` `2.91-0ubuntu0.24.04.1` (`noble-updates`); `debian/rules` adds `-DHAVE_NFTSET` | `curl`, `jq`, `ca-certificates` |
| `debian:12`                                         | `1.0.6-2+deb12u2` | `dnsmasq-base` `2.90-4~deb12u2`; `debian/rules` adds `-DHAVE_NFTSET`                          | `curl`, `jq`, `ca-certificates` |
| `alpine:3.24`                                       | `1.1.6-r1`        | `dnsmasq-dnssec-nftset` `2.92_p2-r0`; plain `dnsmasq` lacks `HAVE_NFTSET` (`APKBUILD`)        | `curl`, `jq`, `ca-certificates` |
| `fedora:44`                                         | `1.1.6-2.fc44`    | `dnsmasq` `2.92rel2-9.fc44`; `dnsmasq.spec` adds `-DHAVE_NFTSET`                              | `curl`, `jq`, `ca-certificates` |

Sources: packages.debian.org, packages.ubuntu.com, pkgs.alpinelinux.org (v3.24, x86_64 and aarch64),
mdapi.fedoraproject.org (f44), and the packaging files on sources.debian.org, git.launchpad.net
(`ubuntu/noble-updates`), git.alpinelinux.org (`3.24-stable`), and src.fedoraproject.org (`f44`). These supersede the
earlier research brief, which had Ubuntu's `2.90-2ubuntu0.4` from an older `noble` pocket, Alpine 3.22, and Fedora 43,
and left Ubuntu's and Fedora's `HAVE_NFTSET` unverified. `alpine:3.24` is the current Alpine (same digest as `latest`)
and `fedora:44` the current Fedora (same digest as `latest`); both and `debian:12` publish amd64 and arm64 images
(docker-library `official-images`), and `base:ubuntu-24.04` publishes both (`docker buildx imagetools inspect`).

## Goals / Non-Goals

**Goals:**

- **One owned table, replaced atomically.** Every rule lives in one `inet` table named for the feature; each load
  deletes and recreates that table in a single `nft -f` transaction and touches no other table. Checked: the `rerun`
  scenario saves the ruleset without the feature's table, re-runs the start-time script as root, and compares; the
  `dind` scenario starts a nested container afterwards.
- **Never wider than configured after the first load.** The first rule set loaded at a start is the closed table:
  traffic through `lo`, ICMPv6 neighbour discovery, and DNS to the recorded resolvers. With the `github` preset,
  `api.github.com` is looked up once, through the recorded resolvers, only after the closed table is loaded; a closed
  table that adds exactly those addresses on TCP 443 replaces it; the fetch connects only to those addresses (the
  client's name resolution is pinned to them), so a second lookup cannot return an address the table lacks. The full
  table replaces the closed one in one transaction. dnsmasq starts only after the full table is loaded, because that
  load recreates the learned sets empty. No later step deletes the table except `failureMode` `warn` on failure.
  Checked: review of the script's order, and the `fetch-fails` scenario.
- **Chains.** Base chains: `output` and, with `filterForward`, `forward`, both at filter priority with policy drop and
  an explicit reject as their last rule; no `input` chain. Both accept, in this order: established and related
  connections; ICMPv6 types 133–136 (neighbour and router discovery) and 143 (MLDv2 reports); DNS (UDP and TCP 53) to
  the recorded resolvers; destinations in the configured, fetched, and learned sets; traffic to the nested bridges
  (`docker0`, `br-*`). `output` also accepts everything leaving through `lo`, which covers Docker's DNAT of
  `127.0.0.11`. Checked: the `rerun` scenario asserts the chain contents with `nft -j list table`; the `dind` scenario.
- **Bounded start.** The start-time script ends within 60 seconds even when the network is unreachable: the lookup of
  `api.github.com` is bounded at 5 seconds, the GitHub fetch at 20 seconds per attempt with at most two attempts (only
  after a connection error or timeout; an HTTP error status, including a rate-limit response, is not retried) and at 2
  MiB of response, and dnsmasq must answer within 5 seconds of its start. The check waits at most 90 seconds for the
  current start's record, longer than the script's bound, so a slow start that succeeds is never reported missing.
  Checked: review, and the `fetch-fails` scenario measures the script's run time.
- **Learned addresses in their own sets.** Addresses dnsmasq learns go to IPv4 and IPv6 sets separate from the interval
  sets of configured and fetched ranges, so a learned address inside a range never makes an insert fail. Checked: the
  `github-npm` scenario connects to `raw.githubusercontent.com`, which resolves inside a fetched `web` range.
- **Rejected, not dropped.** Refused outbound TCP connections get a TCP reset (connection refused), other protocols ICMP
  administratively prohibited, so they fail at once. The check accepts only a refused TCP connection to `192.0.2.1:443`
  within 3 seconds as proof; a timeout or an unreachable network means the firewall is not in force. Checked: `test.sh`
  times a refused connection (under one second).
- **Only root-owned inputs at start.** The start-time script reads only the configuration written by `install.sh` under
  `/usr/local/share/firewall/`, `/etc/resolv.conf`, its root-owned state directory, and the GitHub response; it sets its
  own `PATH` and ignores its environment. Every file it reads is owned by root and not writable by others. Checked:
  `test.sh` asserts owner and mode of each file, and the `rerun` scenario covers "Environment does not change the
  rules".
- **dnsmasq runs only from its own configuration.** It starts with a root-owned configuration file written at start (the
  allowed domains, the learned sets, and the recorded resolvers as upstream servers), reads neither the distribution's
  `/etc/dnsmasq.conf` nor a configuration directory nor `/etc/resolv.conf`, and listens on `127.0.0.1` only. It is not
  supervised. Checked: review, and the `rerun` scenario asserts its command line.
- **Resolvers recorded once per container.** The nameservers of `/etc/resolv.conf` are recorded in the state directory
  before the feature first rewrites the file. At every start the script first writes the recorded resolvers back into
  the file's `nameserver` lines, and names the local dnsmasq only once dnsmasq answers, so the file names dnsmasq only
  while it runs and a restart can resolve before dnsmasq starts. When the `nameserver` lines found at start name neither
  dnsmasq nor the recorded resolvers, Docker has regenerated the file and they are recorded anew. Only `nameserver`
  lines change, and the file is rewritten in place because it is a bind mount. Checked: the `rerun` scenario and a
  restart recorded in the PR's Validation section.
- **A record per start.** The start record carries the start time of the container's PID 1, which the unprivileged check
  can read from `/proc`; it is written atomically under `/run/firewall/` with mode `0644`. Checked: the `rerun` scenario
  covers "Stale record".
- **Validated options, twice.** `install.sh` validates every option value and fails the build; the start-time script
  validates the stored configuration again and treats an invalid one as a failure. Checked: a failing build cannot be a
  scenario, so the PR's Validation section records `devcontainer build` runs with an unknown preset, a malformed CIDR, a
  CIDR with host bits set, `0.0.0.0/0`, and a wildcard domain.
- **Idempotent install.** `install.sh` overwrites its configuration and scripts, installs packages only when missing,
  and adds no line to any shared file. Checked: `duplicate.sh` installs with non-default options (without the `github`
  preset), then defaults, and asserts that the defaults are in effect.
- **Distribution packages only.** No URL is fetched at build time; packages come from the image's configured
  repositories with the package manager's default verification. Checked: review of `install.sh` against the URL
  inventory below.
- **Test destinations.** Tests connect only to hosts in the URL inventory: `github.com`, `api.github.com`, and
  `raw.githubusercontent.com` as allowed hosts, `registry.npmjs.org` as allowed with the `npm` preset and as the host
  outside the allowlist otherwise. Addresses that the rules refuse inside the container (`192.0.2.1`, `8.8.8.8` on port
  53) are never reached. Nested containers run an image imported from the dev container's own filesystem, so no test
  pulls from a registry. Checked: review of the test scripts against the inventory.
- **GitHub fetches in tests stay within the rate limit.** Only a start with the `github` preset fetches. Each
  compatibility job starts two containers with the defaults (`test.sh` and the final install of `duplicate.sh`) and so
  fetches twice; the scenario job fetches at most six times, because scenarios that do not test GitHub behaviour select
  other presets; a full local run (`just test firewall` on one architecture and `just test-scenarios firewall`) fetches
  at most 14 times from one address, so four full runs fit in GitHub's hourly limit. A rate-limited start fails with the
  reason in the check's output, so a red job names its cause; a re-run after the limit resets is the remedy. Tests carry
  no token. Checked: the scenario list below; the first CI run.

**Non-Goals:**

- A security boundary: root or `sudo` in the container can delete the table; DNS lookups can carry data; allowed CDN and
  GitHub ranges carry other tenants' content; the agent can edit `.devcontainer/` for the next build.
- Restricting a remote user who has privilege. The guardrail assumes a remote user without root, passwordless `sudo`, or
  access to a Docker daemon. The `vscode` user of `base:ubuntu-24.04` has passwordless `sudo`, so there the rules are
  removable by default; with docker-in-docker, membership in the `docker` group is root-equivalent, and a nested
  `--privileged` container or a `macvlan` network on the dev container's interface bypasses the rules. `NOTES.md` states
  this first.
- Inbound filtering, host firewalling, and filtering traffic between the container and bridges that exist only inside it
  (a nested Docker's `docker0` and `br-*`).
- Filtering by DNS name (every name resolves), by TLS SNI, or through an HTTP proxy.
- A command for the remote user to re-apply or loosen the rules; a restart re-applies them.
- Restarting dnsmasq after it exits; lookups then fail until the next start (spec, Requirement: Failure mode).
- Support for `--network=host`, where the rules would land in the host's network namespace (see Open Questions).
- An `iptables` fallback for kernels without `nf_tables`. If a CI runner's kernel lacks it, the PR stops and the
  maintainer decides between dropping that architecture from `compatibility.json` and a fallback.
- Claims about GitHub Codespaces, which was not checked.

## Decisions

- **Apply from the feature entrypoint as root** (maintainer decision). The entrypoint runs before the container's
  command in every start, needs no grant, and the remote user cannot call it. Rejected: `postStartCommand` with a
  sudoers entry (prior art), which gives the agent a root command, runs later, and misses starts outside the CLI;
  build-time rules, which do not survive because each container run gets a new network namespace.
- **`capAdd: ["NET_ADMIN"]` only** (maintainer decision). Loading nftables rules needs it; rejections are generated by
  the kernel, and Docker grants `NET_RAW` by default anyway. Rejected: `NET_RAW` (prior art), which widens nothing the
  feature uses; `privileged`.
- **nftables with an own `inet` table.** One table covers IPv4 and IPv6, interval sets replace `ipset` and `aggregate`
  (absent on Alpine), and a drop in any base chain is final whatever Docker's tables say, so nothing else is flushed.
  Rejected: `iptables` with `ipset`, which conflicts with docker-in-docker switching the `iptables` alternative at start
  and needs separate IPv4 and IPv6 rules; flushing the filter tables (prior art), which destroys Docker's rules;
  `DOCKER-USER`, which Docker's nftables backend does not have.
- **Domains through dnsmasq `--nftset`.** A local dnsmasq forwards to the recorded resolvers and adds the addresses of
  every answer for an allowed domain to the learned sets, so CDN rotation and subdomains work. Packages: `dnsmasq-base`
  on Debian and Ubuntu (no service scripts), `dnsmasq-dnssec-nftset` on Alpine, `dnsmasq` on Fedora. Rejected: resolving
  the domains once at start (addresses rotate within minutes on CDNs); an HTTP(S) proxy such as squid (much larger, and
  only tools that honor proxy variables are covered).
- **Closed table, then fetch, then full table** (maintainer decision). The GitHub ranges are fetched under the closed
  table and validated before the full table is built. Rejected: fetching before any rule is loaded, which leaves egress
  open during the fetch; loading the full table without the ranges and adding them later, which makes "applied" mean two
  different rule sets.
- **GitHub ranges from `web`, `api`, `git`.** They cover the web UI, the REST API, and Git over HTTPS and SSH. Rejected:
  `actions`, `codespaces`, and `copilot`, which are large cloud-provider ranges; `packages` (GHCR), left to
  `allowedDomains`.
- **DNS only to the recorded resolvers and `127.0.0.11`** (maintainer decision). Rejected: port 53 to any address (prior
  art), which lets any process pick an arbitrary resolver.
- **Failure modes.** `closed` keeps the closed table (without `api.github.com`) and makes the check fail; `warn` deletes
  the table and makes the check warn. `closed` keeps DNS to the recorded resolvers: it is the table every start already
  runs under, so a failure adds no third rule set, and DNS is equally reachable in the applied state, so a failed start
  opens nothing for DNS tunnelling that an applied one closes. Rejected: `warn` keeping a partial table, which is
  neither the configured policy nor unrestricted and is hard to reason about; `closed` as loopback only (the research
  brief's wording), which would need its own table and leaves the failed container unable to resolve names for
  diagnosis.
- **Start check probes a documentation address.** The unprivileged check connects to `192.0.2.1` (TEST-NET-1) on port
  443 and expects an immediate refusal, which only the firewall's reset produces; without the firewall the attempt times
  out or finds no route, and no real host is contacted either way. `allowedCidrs` therefore rejects ranges containing
  that address. The check cannot list the ruleset because it runs without `NET_ADMIN`. Rejected: probing `example.com`
  (prior art), a real third party that a user may allowlist; also probing an allowed host, which would fail container
  start on transient network errors.
- **Nested Docker.** With `filterForward`, forwarded traffic meets the same sets; output to `docker0` and `br-*` is
  accepted because anything leaving those bridges for the outside is forwarded and filtered, and forwarding into those
  bridges is accepted so published ports of nested containers and traffic between nested networks work. Nested
  containers on a user-defined network resolve through the nested daemon's embedded DNS, which forwards to the dev
  container's dnsmasq.
- **`installsAfter` docker-in-docker and common-utils** (maintainer decision). Entrypoint order follows install order,
  so `docker-init.sh` (which switches `iptables` alternatives and starts `dockerd`) has run before the firewall loads.
  `common-utils` declares no entrypoint; ordering after it is install order only, so the feature installs its packages
  after common-utils has created the remote user and upgraded packages (`upgradePackages`), and the "No sudoers entry"
  test sees common-utils' final sudoers and groups. Neither is a functional dependency, so no `dependsOn`. References
  use the full GHCR refs without a tag.
- **Option shape** (maintainer decision). Types and defaults, owned by `devcontainer-feature.json` once it exists:

  | Option           | Type                                 | Default    |
  | ---------------- | ------------------------------------ | ---------- |
  | `presets`        | string, comma-separated, `proposals` | `"github"` |
  | `allowedDomains` | string, comma-separated              | `""`       |
  | `allowedCidrs`   | string, comma-separated              | `""`       |
  | `failureMode`    | enum `closed`, `warn`                | `"closed"` |
  | `filterForward`  | boolean                              | `true`     |

  Rejected: one boolean per preset (`w3cj`), which turns every new preset into a new option.
- **POSIX `sh`.** Alpine ships no bash, so `install.sh` and the start-time scripts use `#!/bin/sh` with `set -eu`.
- **`test/canary.json` stays empty.** Canaries should be fast and stable (`testing.md`); this feature depends on
  `api.github.com` and its rate limit, so it would make infrastructure changes flaky. The first stable feature without
  network dependencies becomes the canary.

### Security review surface

- **Downloads at build:** none. Packages come from the image's configured repositories, verified by apt, apk, or dnf
  signatures; the feature adds no repository and no key.
- **Fetch at start:** `https://api.github.com/meta`, only with the `github` preset: TLS verified against the image's CA
  bundle, bounded time and size, connection pinned to the addresses in the closed table, every entry parsed as an IPv4
  or IPv6 CIDR before use, whole response rejected on any invalid entry. It is data, never executed.
- **Keys:** none.
- **Metadata:**

| Field                                                         | Value                                                                                            | Justification                                                                            |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| `capAdd`                                                      | `NET_ADMIN`                                                                                      | Loading nftables rules; nothing else                                                     |
| `entrypoint`                                                  | `/usr/local/share/firewall/apply.sh`                                                             | Runs as root at every start before the container's command; reads only root-owned inputs |
| `postStartCommand`                                            | `/usr/local/share/firewall/check.sh`                                                             | Unprivileged check; fails loudly in `closed` mode                                        |
| `installsAfter`                                               | `ghcr.io/devcontainers/features/docker-in-docker`, `ghcr.io/devcontainers/features/common-utils` | Entrypoint and install order only                                                        |
| `dependsOn`                                                   | none                                                                                             | No feature is required                                                                   |
| `mounts`, `containerEnv`, `privileged`, `init`, `securityOpt` | none                                                                                             | Not needed                                                                               |

- **Idempotency:** Goals "Idempotent install" and "One owned table, replaced atomically"; Requirement: Installing twice.
- **Failure behavior:** Requirement: Failure mode and Requirement: Start check; an unsupported distribution fails the
  build (Requirement: Supported images).

### Supported images

Planned `test/firewall/compatibility.json`, each on `amd64` and `arm64`:

| Image                                               | `remoteUser` | Why                                                         |
| --------------------------------------------------- | ------------ | ----------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` | `vscode`     | The usual dev container base; tests the check without root  |
| `debian:12`                                         | (none)       | Plain Debian; the scenarios' image, where tests run as root |
| `alpine:3.24`                                       | (none)       | musl, BusyBox, and the `dnsmasq-dnssec-nftset` subpackage   |
| `fedora:44`                                         | (none)       | dnf-based distributions                                     |

Architecture does not change the rules, which live in the host kernel; the second architecture covers packaging.

### Test coverage

The harness cannot stop and start a container, reach it from outside, pass a build that must fail, or use IPv6 (Docker
on the runners has none by default), and a failing `postStartCommand` fails the container's start. Scenarios therefore
start with a configuration that succeeds and then, as root, re-run the start-time script under the condition to test.
Planned scenarios, all on `debian:12` (amd64) where the test runs as root: `domains` (`presets` empty, `allowedDomains`
`githubusercontent.com`), `cidrs` (`presets` empty, `allowedCidrs` `185.199.108.0/22,2606:50c0::/32`), `github-npm`,
`rerun` (defaults), `fetch-fails` (defaults), `warn` (`failureMode` `warn`), `dind` (with docker-in-docker), and
`dind-no-forward` (with docker-in-docker, `filterForward` false, `presets` `npm`). `rerun` re-runs the script once,
after stopping dnsmasq, deleting the feature's table, leaving `resolv.conf` naming dnsmasq, adding a table of its own,
and setting variables named like the options. A "Validation" entry is a run recorded in the PR's Validation section.

| Scenario of the spec                                        | Covered by                                                                                                              |
| ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Supported image                                             | `test.sh` on every image                                                                                                |
| Unsupported distribution                                    | Validation: `devcontainer build` on an image of an unsupported distribution                                             |
| Package verification fails                                  | Validation: `devcontainer build` from a Dockerfile that removes the image's archive keys                                |
| No repository added                                         | Review of `install.sh`; `test.sh` asserts no repository or key file names the feature                                   |
| Unknown preset, Malformed CIDR, CIDR that cannot be applied | Validation: `devcontainer build` runs (Goals: Validated options, twice)                                                 |
| First start                                                 | `test.sh` (record of the current start is `applied`); ordering by review of the entrypoint                              |
| Restart re-applies the same rules                           | `rerun`; Validation: `docker restart`, then the check as the remote user                                                |
| Allowed domain is reachable, GitHub preset                  | `test.sh` (`github.com`, `api.github.com`)                                                                              |
| Unlisted domain is refused                                  | `test.sh` (`registry.npmjs.org`)                                                                                        |
| IPv6 default deny                                           | `rerun` asserts the IPv6 rules and the reject in the ruleset; Validation: a container on an IPv6-enabled Docker network |
| Inbound connection still answered                           | Validation: a published port reached from the host; `rerun` asserts that the table has no `input` chain                 |
| Subdomain of an allowed domain, No preset                   | `domains`                                                                                                               |
| Address not obtained through the resolver                   | `domains` (a literal address of `github.com`)                                                                           |
| IPv4 and IPv6 ranges                                        | `cidrs` (IPv4 by connection, IPv6 by ruleset); Validation: IPv6 on an IPv6-enabled Docker network                       |
| Presets combine                                             | `github-npm`                                                                                                            |
| Ranges loaded                                               | `test.sh` (learned sets flushed as root, then a literal `github.com` address)                                           |
| Fetch fails                                                 | `fetch-fails` (a table of its own drops traffic to `api.github.com`, script re-run)                                     |
| GitHub preset not selected                                  | `domains` (the record names no fetch)                                                                                   |
| Other DNS server refused                                    | `test.sh` (TCP to `8.8.8.8` port 53 is refused at once)                                                                 |
| Unlisted name still resolves                                | `test.sh` (`registry.npmjs.org` resolves and is refused)                                                                |
| Nested container filtered, user-defined network             | `dind`                                                                                                                  |
| Forward filtering disabled                                  | `dind-no-forward`                                                                                                       |
| Closed on failure, Failure with closed mode                 | `fetch-fails` (check exits non-zero)                                                                                    |
| Warn on failure, Failure with warn mode                     | `warn`                                                                                                                  |
| Rules cannot be loaded                                      | `fetch-fails` (table deleted, script re-run under `setpriv` without `CAP_NET_ADMIN`)                                    |
| Firewall in force                                           | `test.sh` (the check as the remote user)                                                                                |
| Stale record                                                | `rerun` (record's start time set to an earlier one, check run)                                                          |
| Remote user reads the record                                | `test.sh` on `base:ubuntu-24.04` as `vscode`                                                                            |
| No sudoers entry                                            | `test.sh`                                                                                                               |
| Environment does not change the rules                       | `rerun`                                                                                                                 |
| Other rules untouched                                       | `rerun`                                                                                                                 |
| With docker-in-docker                                       | `dind`                                                                                                                  |
| Metadata of a built container                               | `test.sh` (bounding set is Docker's default plus `NET_ADMIN`)                                                           |
| Root removes the firewall                                   | `rerun` (`registry.npmjs.org` reachable after the table is deleted, before the re-run)                                  |
| Different options the second time                           | `duplicate.sh`                                                                                                          |
| Same options twice                                          | Validation: `install.sh` run twice with the same options in a plain container of each image                             |

## URL inventory

The feature configures no package repository: `install.sh` uses the repositories preconfigured in each image, through
its package manager, and fetches no URL itself. At start, it fetches one URL. Every other entry below is a destination
the presets allow and the feature never contacts itself, or an ordering reference; "test" in the When column marks the
hosts the tests connect to (Goals: Test destinations). Verified column: a read-only `curl -sSIL` (or name resolution) on
2026-09-30; HTTP status and observed final host.

| URL / template                                    | Purpose                                                   | When                                 | Integrity / authenticity                                         | Official source evidence                                                                                                                             | Verified                                                                                             |
| ------------------------------------------------- | --------------------------------------------------------- | ------------------------------------ | ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `https://api.github.com/meta`                     | GitHub `web`, `api`, `git` ranges for the `github` preset | start (fetched); test                | TLS against the image's CA bundle; every entry validated as CIDR | https://docs.github.com/en/rest/meta/meta, https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-githubs-ip-addresses | 2026-09-30: 200, final host `api.github.com`, JSON 201,132 bytes                                     |
| `github.com` (and subdomains)                     | `github` preset                                           | start (allowed only); test           | TLS of the client                                                | `domains.website` of https://api.github.com/meta lists `*.github.com`                                                                                | 2026-09-30: 200, final host `github.com`                                                             |
| `githubusercontent.com` (subdomains)              | `github` preset                                           | start (allowed only); test           | TLS of the client                                                | `domains.website` of https://api.github.com/meta lists `*.githubusercontent.com`                                                                     | 2026-09-30: apex has no address; `raw.githubusercontent.com` 200, redirects to `github.com`          |
| `registry.npmjs.org`                              | `npm` preset                                              | start (allowed only); test           | TLS of the client                                                | https://docs.npmjs.com/cli/v11/using-npm/config (`registry` default)                                                                                 | 2026-09-30: 200, final host `registry.npmjs.org`                                                     |
| `pypi.org`                                        | `pypi` preset                                             | start (allowed only)                 | TLS of the client                                                | https://docs.pypi.org/api/                                                                                                                           | 2026-09-30: 200, final host `pypi.org`                                                               |
| `files.pythonhosted.org`                          | `pypi` preset                                             | start (allowed only)                 | TLS of the client                                                | https://docs.pypi.org/api/ (file host)                                                                                                               | 2026-09-30: 404 at `/`, final host `files.pythonhosted.org`                                          |
| `api.anthropic.com`                               | `anthropic` preset                                        | start (allowed only)                 | TLS of the client                                                | https://code.claude.com/docs/en/network-config                                                                                                       | 2026-09-30: 404 at `/`, final host `api.anthropic.com`                                               |
| `claude.ai`                                       | `anthropic` preset                                        | start (allowed only)                 | TLS of the client                                                | https://code.claude.com/docs/en/network-config                                                                                                       | 2026-09-30: 403 at `/`, final host `claude.ai`                                                       |
| `platform.claude.com`                             | `anthropic` preset                                        | start (allowed only)                 | TLS of the client                                                | https://code.claude.com/docs/en/network-config                                                                                                       | 2026-09-30: 200, final host `platform.claude.com`                                                    |
| `update.code.visualstudio.com`                    | `vscode` preset                                           | start (allowed only)                 | TLS of the client                                                | https://code.visualstudio.com/docs/setup/network                                                                                                     | 2026-09-30: 200; `/latest/server-linux-x64/stable` redirects to `vscode.download.prss.microsoft.com` |
| `vscode.download.prss.microsoft.com`              | `vscode` preset (redirect target of the update server)    | start (allowed only)                 | TLS of the client                                                | https://code.visualstudio.com/docs/setup/network                                                                                                     | 2026-09-30: 403 at `/`, final host `vscode.download.prss.microsoft.com`                              |
| `vscode-cdn.net` (subdomains)                     | `vscode` preset                                           | start (allowed only)                 | TLS of the client                                                | https://code.visualstudio.com/docs/setup/network (`*.vscode-cdn.net`)                                                                                | 2026-09-30: apex has no address; `main.vscode-cdn.net` 400, final host unchanged                     |
| `marketplace.visualstudio.com`                    | `vscode` preset                                           | start (allowed only)                 | TLS of the client                                                | https://code.visualstudio.com/docs/setup/network                                                                                                     | 2026-09-30: 404 at `/`, final host `marketplace.visualstudio.com`                                    |
| `gallery.vsassets.io` (subdomains)                | `vscode` preset                                           | start (allowed only)                 | TLS of the client                                                | https://code.visualstudio.com/docs/setup/network (`*.gallery.vsassets.io`)                                                                           | 2026-09-30: apex has no address; `ms-python.gallery.vsassets.io` 404, final host unchanged           |
| `gallerycdn.vsassets.io` (subdomains)             | `vscode` preset                                           | start (allowed only)                 | TLS of the client                                                | https://code.visualstudio.com/docs/setup/network (`*.gallerycdn.vsassets.io`)                                                                        | 2026-09-30: apex has no address; `ms-python.gallerycdn.vsassets.io` 403, final host unchanged        |
| `192.0.2.1:443`                                   | Start check's refusal probe                               | start (never reached)                | Not applicable: reserved documentation address                   | https://www.rfc-editor.org/rfc/rfc5737                                                                                                               | 2026-09-30: RFC 200 (final `www.rfc-editor.org/info/rfc5737/`)                                       |
| `ghcr.io/devcontainers/features/docker-in-docker` | `installsAfter` ordering; `dind` scenarios                | build (only if the user installs it) | OCI digest, resolved by the dev container CLI                    | https://github.com/devcontainers/features/tree/main/src/docker-in-docker                                                                             | 2026-09-30: GHCR manifest `latest` 200; major tags 1–4                                               |
| `ghcr.io/devcontainers/features/common-utils`     | `installsAfter` ordering                                  | build (only if the user installs it) | OCI digest, resolved by the dev container CLI                    | https://github.com/devcontainers/features/tree/main/src/common-utils                                                                                 | 2026-09-30: GHCR manifest `latest` 200; major tags 1–2                                               |

## Risks / Trade-offs

- [Lifecycle commands can start before the first rule loads, because the CLI does not wait for entrypoints] → The closed
  table is the script's first action, the check waits for the current start's record, and `NOTES.md` states the window.
- [GitHub's unauthenticated rate limit (60 per hour per IP) or an outage fails the fetch, and `closed` then leaves the
  container offline] → The check names the reason; CI keeps its fetches within the limit (Goals); see Open Questions for
  a fallback to the last validated ranges.
- [The remote user of the usual base image has passwordless `sudo`] → Non-Goals; `NOTES.md` states it first.
- [Sibling Compose services and the Docker host are refused unless allowed] → `NOTES.md` shows allowing a service name
  through `allowedDomains` (resolved by Docker's embedded DNS through dnsmasq) or its subnet through `allowedCidrs`; a
  scenario proves the service-name path or `NOTES.md` drops it. See Open Questions.
- [Nested containers on the default bridge get `8.8.8.8` as resolver, which is refused] → `NOTES.md` recommends
  user-defined networks, whose embedded DNS forwards to the dev container's dnsmasq; the `dind` scenario uses one.
- [VS Code Server and extension downloads inside the container are refused without the `vscode` preset] → `NOTES.md`
  says so first.
- [The `anthropic` and `vscode` presets cover only part of what their sources list] → `NOTES.md` names the left-out
  hosts (Context) so users can add them through `allowedDomains`; see Open Questions.
- [Allowing a CDN-hosted domain allows other sites sharing its addresses, and learned addresses stay allowed until the
  next start] → Documented as a guardrail limit; element timeouts are an Open Question.
- [dnsmasq exits after start, and every lookup fails until the next start] → Documented in `NOTES.md`; the check runs
  only once per start and does not see it.
- [A kernel without `nf_tables`, a runtime that drops `capAdd` (`wslc`), or a non-root container user prevents loading]
  → Egress is then unrestricted in both modes (spec); the check fails in `closed` mode and warns in `warn` mode.
- [A failing check skips the user's later lifecycle commands] → Intended in `closed` mode, stated in `NOTES.md`; `warn`
  avoids it.
- [Docker keeps the rewritten `resolv.conf` across restarts, so a network change leaves stale recorded resolvers] → The
  recorded resolvers are re-recorded whenever Docker has regenerated the file; otherwise a rebuild resets them.
- [The fetched ranges change between starts] → Intended: each start uses the current list (spec, Requirement: Firewall
  applied at every start).

## Open Questions

The package as written implements the first answer of each question, so a maintainer's approval accepts it; a different
answer changes the named part before approval.

1. **Preset catalogue for 1.0.0.** As written: `github`, `npm`, `pypi`, `anthropic` (API and sign-in only), and `vscode`
   (VS Code Server and Marketplace downloads only), with `NOTES.md` naming the hosts their sources list and the presets
   leave out; distribution mirrors (`deb.debian.org`, `dl-cdn.alpinelinux.org`, Fedora mirrors) stay with
   `allowedDomains`, since Fedora's mirror list is not a fixed host set. Alternative: widen `anthropic` or `vscode` to
   the hosts in Context, which changes Requirement: Presets and adds inventory rows. Adding a preset later is a MINOR
   bump.
2. **Default presets.** Decided by the maintainer: `github`. `NOTES.md` puts the `vscode` preset in its first lines.
3. **Fallback when the GitHub fetch fails.** As written: none; a failed fetch fails the start. Alternative: keep the
   last validated ranges in the root-owned state directory and use them when a later fetch fails; the first start still
   fails without them, and CI gains nothing because every test container is new. It would add to Requirement: GitHub
   ranges: "Scenario: Fetch fails with earlier ranges — **WHEN** `presets` contains `github`, the fetch fails, and an
   earlier start of the same container loaded ranges — **THEN** those ranges are allowed and the start is recorded as
   applied with stale ranges."
4. **Sibling Compose services.** As written: no automatic allowance for the container's own subnets (it would also open
   the Docker host's gateway address); `NOTES.md` documents `allowedDomains` with service names and `allowedCidrs`.
5. **Lifetime of learned addresses.** As written: until the next start (Requirement: Allowed domains; dnsmasq passes no
   TTL to the set). Alternative: element timeouts, which change that requirement.
6. **`--network=host`.** As written: documented as unsupported, without detection (Non-Goals), since no reliable
   in-container test distinguishes the host's network namespace. Alternative: refuse when a `docker0` interface exists
   at start, which misfires with docker-in-docker.
7. **Root `README.md` and `test/canary.json`.** As written: neither changes (proposal, Stays true); the canary stays
   empty for the reason in Decisions. The root `README.md` still says "No features have been published yet." and goes
   stale once `firewall` is released. Alternative: list `firewall` in the README's Features section in this change.
8. **Alpine tag.** As written: `alpine:3.24`, the current release, pinned so a new Alpine release does not change the
   tested image unannounced. Alternative: `alpine:latest`.
