# Spec Delta

## Purpose

Installs nftables and dnsmasq from the image's distribution together with a start-time firewall that restricts a dev
container's outbound and forwarded traffic to an allowlist of presets, domains, and CIDRs, checked by an unprivileged
start check. It is a guardrail that surfaces unexpected egress, for example from an AI agent, not a security boundary.

Upstream sources:

- nftables wiki: https://wiki.nftables.org/wiki-nftables/index.php/Main_Page
- dnsmasq documentation: https://thekelleys.org.uk/dnsmasq/doc.html
- GitHub IPs: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-githubs-ip-addresses
- Docker packet filtering and firewalls: https://docs.docker.com/engine/network/packet-filtering-firewalls/
- Dev Container Features reference: https://containers.dev/implementors/features/

## ADDED Requirements

### Requirement: Supported images

The feature SHALL install on the distributions and architectures listed in `test/firewall/compatibility.json`. On a
distribution whose `/etc/os-release` identifies none of the supported distribution families, the install SHALL fail
before changing the image, with a message that names the detected distribution. The feature SHALL NOT check the
architecture itself; on an architecture where the distribution lacks a required package, the install SHALL fail with the
package manager's error.

#### Scenario: Supported image

- **WHEN** the feature is installed on an image listed in `test/firewall/compatibility.json`
- **THEN** the build succeeds and the firewall's start-time scripts and packages are present

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on an image whose distribution is not supported
- **THEN** the build fails with a message naming the detected distribution and installs nothing

### Requirement: Packages from the image's repositories only

The feature SHALL install its packages, among them nftables and a dnsmasq build with nftables set support, only from the
package repositories already configured in the image, with the package manager's signature verification in effect. It
SHALL NOT add a package repository or signing key, and SHALL NOT download anything else at build time.

#### Scenario: Package verification fails

- **WHEN** the package manager rejects a package or repository signature during the install
- **THEN** the build fails and the feature does not retry with verification disabled

#### Scenario: No repository added

- **WHEN** the feature has been installed
- **THEN** the image's package repository and signing key configuration is unchanged

### Requirement: Option validation at build time

The install SHALL reject, with a message naming the offending value:

- a `presets` entry that is not a known preset;
- an `allowedDomains` entry that is not a valid DNS name, including an entry with a wildcard label such as `*.example`
  (subdomains are always included);
- an `allowedCidrs` entry that is not a valid IPv4 or IPv6 address or CIDR, that has bits set outside its prefix length,
  or whose range contains `192.0.2.1`, the address the start check probes (Requirement: Start check).

Entries in these options are separated by commas; surrounding whitespace and empty entries are ignored.

#### Scenario: Unknown preset

- **WHEN** `presets` contains a name that is not a known preset
- **THEN** the build fails with a message naming that entry

#### Scenario: Malformed CIDR

- **WHEN** `allowedCidrs` contains an entry that is neither an IPv4 nor an IPv6 address or CIDR
- **THEN** the build fails with a message naming that entry

#### Scenario: CIDR that cannot be applied as written

- **WHEN** `allowedCidrs` contains an entry with host bits set, or an entry such as `0.0.0.0/0` that contains
  `192.0.2.1`
- **THEN** the build fails with a message naming that entry

### Requirement: Firewall applied at every start

The feature SHALL apply the firewall on every start of the container, as root, through the feature's entrypoint, before
the container's command runs. Each start SHALL replace everything the feature applied before with the rules for the
options the image was built with, so every start of the same image yields the same rules apart from addresses learned
through the resolver, the GitHub ranges fetched at that start, and resolvers re-recorded after Docker regenerated
`/etc/resolv.conf`. The dev container tool may run lifecycle commands while the entrypoint is still running; the
firewall is in force for them only from the moment the entrypoint loads its first rules.

#### Scenario: First start

- **WHEN** a container built with the feature starts
- **THEN** the firewall is in force before the container's command runs and the start is recorded as applied

#### Scenario: Restart re-applies the same rules

- **WHEN** a container with the feature is stopped and started again
- **THEN** the firewall is applied again with the same allowlist and the same checks pass as after the first start

### Requirement: Outbound default deny

Once the firewall is in force, the container SHALL refuse every outbound connection, IPv4 and IPv6, except traffic
through the loopback interface, DNS traffic to the resolvers allowed by Requirement: DNS only to the container's
resolvers, traffic to a destination allowed by `presets`, `allowedDomains`, or `allowedCidrs`, and reply traffic of
connections the container accepted or opened through these exceptions. IPv6 neighbour discovery SHALL stay possible, so
an allowed IPv6 destination is reachable. A refused connection SHALL fail immediately with an error rather than time
out. Inbound connections to the container SHALL NOT be filtered by the feature.

#### Scenario: Allowed domain is reachable

- **WHEN** a process in the container connects to a host whose name is allowed by `presets` or `allowedDomains`
- **THEN** the connection succeeds

#### Scenario: Unlisted domain is refused

- **WHEN** a process in the container connects to a host that no option allows
- **THEN** the connection fails immediately with an error

#### Scenario: IPv6 default deny

- **WHEN** a process in the container connects over IPv6 to an address that no option allows
- **THEN** the connection fails immediately with an error

#### Scenario: Inbound connection still answered

- **WHEN** a client outside the container connects to a port the container publishes or forwards
- **THEN** the container's replies on that connection are delivered

### Requirement: Allowed domains

Each `allowedDomains` entry SHALL allow the name itself and every subdomain of it, on every protocol and port. A name
SHALL become reachable at the addresses the container's resolver returns for it, from the time of that lookup until the
next start of the container, so addresses that change between lookups are followed. An address the container did not
obtain through its resolver SHALL stay refused unless another option allows it.

#### Scenario: Subdomain of an allowed domain

- **WHEN** `presets` is empty, `allowedDomains` contains `githubusercontent.com`, and a process connects to
  `raw.githubusercontent.com`
- **THEN** the connection succeeds

#### Scenario: Address not obtained through the resolver

- **WHEN** a process connects to an address that the container's resolver has not returned for an allowed name since the
  start, and no other option allows it
- **THEN** the connection is refused

### Requirement: Allowed CIDRs

Each `allowedCidrs` entry SHALL allow every address in that IPv4 or IPv6 range, or that single address, on every
protocol and port.

#### Scenario: IPv4 and IPv6 ranges

- **WHEN** `allowedCidrs` lists one IPv4 and one IPv6 range
- **THEN** connections to addresses in either range are allowed and addresses outside both stay refused

### Requirement: Presets

`presets` SHALL select named destination sets, each allowing the domains listed here the way `allowedDomains` allows
them, plus the ranges named for it. Each set follows the source named with it:

- `github`: `github.com`, `githubusercontent.com`, and the IPv4 and IPv6 ranges of Requirement: GitHub ranges. Source:
  the `domains.website` list of the endpoint named in Requirement: GitHub ranges.
- `npm`: `registry.npmjs.org`. Source: the `registry` default in https://docs.npmjs.com/cli/v11/using-npm/config
- `pypi`: `pypi.org`, `files.pythonhosted.org`. Source: https://docs.pypi.org/api/
- `anthropic`: `api.anthropic.com`, `claude.ai`, `platform.claude.com`, which cover the API and sign-in only. Source:
  https://code.claude.com/docs/en/network-config
- `vscode`: `update.code.visualstudio.com`, `vscode.download.prss.microsoft.com`, `vscode-cdn.net`,
  `marketplace.visualstudio.com`, `gallery.vsassets.io`, `gallerycdn.vsassets.io`, which cover VS Code Server and
  Marketplace downloads only. Source: https://code.visualstudio.com/docs/setup/network

`NOTES.md` SHALL name the hosts that a preset's source lists and the preset leaves out. Several presets SHALL combine as
the union of their destinations; an empty `presets` SHALL select none.

#### Scenario: GitHub preset

- **WHEN** `presets` contains `github`
- **THEN** HTTPS connections to `github.com` and `api.github.com` succeed and a connection to a host outside every
  allowed set is refused

#### Scenario: Presets combine

- **WHEN** `presets` contains `github` and `npm`
- **THEN** both `api.github.com` and `registry.npmjs.org` are reachable

#### Scenario: No preset

- **WHEN** `presets` is empty and `allowedDomains` names one domain
- **THEN** only that domain, loopback, and the DNS resolvers are reachable

### Requirement: GitHub ranges

When `presets` contains `github`, each start SHALL fetch https://api.github.com/meta over HTTPS, with a bounded time and
response size. GitHub publishes no checksum or signature for this response, so the fetch SHALL rely on TLS alone,
verified against the image's CA certificates, and SHALL NOT disable or weaken that verification. The start SHALL allow
every IPv4 and IPv6 range in the response's `web`, `api`, and `git` lists. Every entry of those lists SHALL be validated
as an IPv4 or IPv6 CIDR; an invalid entry, an error status, a timeout, or a malformed response SHALL make the whole
fetch a failure handled by Requirement: Failure mode, and a response that reports GitHub's rate limit SHALL be recorded
with that reason. Until the ranges are loaded, the only destinations reachable beyond loopback and the DNS resolvers
SHALL be the addresses that one lookup of `api.github.com` through those resolvers returned at that start, on the HTTPS
port, and the fetch SHALL connect only to those addresses.

#### Scenario: Ranges loaded

- **WHEN** `presets` contains `github` and the fetch succeeds
- **THEN** an address inside a `git` range is reachable without a DNS lookup of a GitHub name

#### Scenario: Fetch fails

- **WHEN** `presets` contains `github` and the fetch times out or returns an invalid range
- **THEN** no range from that response is allowed and the start is handled as a failure

#### Scenario: GitHub preset not selected

- **WHEN** `presets` does not contain `github`
- **THEN** the start fetches nothing

### Requirement: DNS only to the container's resolvers

The container SHALL be able to send DNS queries beyond the loopback interface only to the resolvers named in
`/etc/resolv.conf` before the feature first changed it; queries to Docker's embedded resolver `127.0.0.11` and to the
feature's local resolver travel through the loopback interface and stay allowed. DNS traffic to any other address SHALL
be refused. Names outside the allowlist SHALL still resolve, since only connections are filtered. The feature SHALL keep
the `search` and `options` lines of `/etc/resolv.conf` intact.

#### Scenario: Other DNS server refused

- **WHEN** a process sends a DNS query to a public resolver that `/etc/resolv.conf` did not name
- **THEN** the query is refused

#### Scenario: Unlisted name still resolves

- **WHEN** a process looks up a name that no option allows
- **THEN** the lookup returns its addresses and a connection to them is refused

### Requirement: Forwarded traffic

When `filterForward` is enabled, traffic that the container forwards, such as traffic of containers nested in it, SHALL
be subject to the same allowlist as its own outbound traffic, including the DNS restriction. When it is disabled, the
feature SHALL NOT filter forwarded traffic. In both cases, traffic from the container to networks that exist only inside
it, such as the bridges of a nested Docker daemon, traffic forwarded into those networks, and reply traffic of forwarded
connections that were allowed SHALL be allowed.

#### Scenario: Nested container filtered

- **WHEN** `filterForward` is enabled and a container nested inside connects to a host no option allows
- **THEN** the connection is refused

#### Scenario: Nested container on a user-defined network reaches an allowed domain

- **WHEN** `filterForward` is enabled and a nested container on a user-defined network connects to an allowed domain
- **THEN** the connection succeeds

#### Scenario: Forward filtering disabled

- **WHEN** `filterForward` is disabled and a nested container connects to a host no option allows
- **THEN** the feature does not refuse it

### Requirement: Failure mode

A start SHALL be a failure when the rules for the configured options cannot be applied in full: the rules cannot be
loaded, the GitHub ranges fetch fails, or the resolver that learns allowed domains cannot start. With `failureMode`
`closed`, a failed start SHALL leave only loopback and the DNS resolvers reachable. With `failureMode` `warn`, a failed
start SHALL remove every rule the feature applied, leaving outbound traffic unrestricted by the feature. In both modes
the start SHALL be recorded as failed with its reason. When no rule can be loaded at all (the container lacks
`NET_ADMIN`, the entrypoint does not run as root, or the kernel lacks nftables support), outbound traffic stays
unrestricted in both modes. A resolver that exits after a successful start SHALL NOT change the recorded result or the
rules; name lookups then fail until the next start.

#### Scenario: Closed on failure

- **WHEN** `failureMode` is `closed` and a start fails after the rules could be loaded
- **THEN** only loopback and the DNS resolvers are reachable and the start is recorded as failed

#### Scenario: Warn on failure

- **WHEN** `failureMode` is `warn` and a start fails
- **THEN** the feature leaves no rule in place and the start is recorded as failed with its reason

#### Scenario: Rules cannot be loaded

- **WHEN** the container runs without `NET_ADMIN` or the entrypoint does not run as root
- **THEN** outbound traffic is not restricted and the start is recorded as not applied

### Requirement: Start check

The feature SHALL run, as its `postStartCommand` and without privilege, a check that waits a bounded time for the record
of the current start, treats a record left from an earlier start as missing, and verifies that a destination outside the
allowlist is refused. The check SHALL send no traffic to any host on the Internet. On a failed, missing, or not-applied
start it SHALL print the reason; with `failureMode` `closed` it SHALL exit non-zero, and with `warn` it SHALL exit zero
after a warning on standard error.

#### Scenario: Firewall in force

- **WHEN** the current start was applied and a destination outside the allowlist is refused
- **THEN** the check exits zero and prints a one-line summary

#### Scenario: Failure with closed mode

- **WHEN** `failureMode` is `closed` and the current start failed or was not applied
- **THEN** the check prints the reason and exits non-zero, so the dev container tool reports the failure

#### Scenario: Failure with warn mode

- **WHEN** `failureMode` is `warn` and the current start failed or was not applied
- **THEN** the check prints a warning with the reason on standard error and exits zero

#### Scenario: Stale record

- **WHEN** the only start record present belongs to an earlier start of the container
- **THEN** the check treats the current start as not applied

### Requirement: Start record readable by the remote user

Each start SHALL write a record of its result (applied, failed, or not applied), its reason, its time, and the options
in effect to a file whose path `NOTES.md` documents, readable and not writable by the remote user.

#### Scenario: Remote user reads the record

- **WHEN** the remote user reads the start record
- **THEN** it names the result and the options in effect, and writing to it is denied

### Requirement: No privilege for the remote user

The feature SHALL NOT grant the remote user any privilege: no sudoers entry, no group membership, and no command that
re-applies or removes the firewall. The firewall applied at start SHALL take its configuration only from root-owned
files written at build time and SHALL NOT read files or environment variables the remote user can change.

#### Scenario: No sudoers entry

- **WHEN** the feature has been installed
- **THEN** no sudoers file or group membership was added for the remote user

#### Scenario: Environment does not change the rules

- **WHEN** the container's environment sets a variable with the name of an option
- **THEN** the rules applied at start are those of the options the image was built with

### Requirement: Coexistence with other rules

The feature SHALL add and replace only its own nftables table and SHALL NOT flush, delete, or change any other table,
chain, or rule, including Docker's and those of the docker-in-docker feature. It SHALL be installed after
`ghcr.io/devcontainers/features/docker-in-docker` and `ghcr.io/devcontainers/features/common-utils` when either is
installed in the same container, so its entrypoint runs after docker-in-docker's.

#### Scenario: Other rules untouched

- **WHEN** the firewall is applied in a container that already holds other nftables or iptables rules
- **THEN** those rules are unchanged

#### Scenario: With docker-in-docker

- **WHEN** the feature is installed together with docker-in-docker
- **THEN** the nested Docker daemon starts, and a nested container can reach an allowed domain

### Requirement: Container metadata

The feature SHALL request the `NET_ADMIN` capability and no other added capability, SHALL NOT request privileged mode,
mounts, or container environment variables, and SHALL declare no `dependsOn`.

#### Scenario: Metadata of a built container

- **WHEN** a container is built with only this feature
- **THEN** its added capabilities are exactly `NET_ADMIN` and it is not privileged

### Requirement: Guardrail, not a security boundary

The feature SHALL be documented as a guardrail and not a security boundary, and it SHALL NOT claim to stop a process
that has root or passwordless `sudo` inside the container, that can use a Docker daemon (including through membership in
the `docker` group), that tunnels data through DNS lookups, that reaches other services sharing an allowed address or
range, or that changes the dev container configuration in the workspace for the next build. `NOTES.md` SHALL state that
the guardrail holds only for a remote user without root, passwordless `sudo`, or access to a Docker daemon, and that the
default users of common dev container images, such as `vscode` in the Dev Containers base images, have passwordless
`sudo`.

#### Scenario: Root removes the firewall

- **WHEN** a process with root in the container deletes the feature's rules
- **THEN** outbound traffic is unrestricted until the next start re-applies them

### Requirement: Installing twice

Installing the feature a second time SHALL succeed. With the same options, the image SHALL end up as after one install.
With different options, the options of the later install SHALL be the only ones in effect from the next start on.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same options
- **THEN** the build succeeds and the firewall applied at start is the same as after one install

#### Scenario: Different options the second time

- **WHEN** the feature is installed with some options and then again with different options
- **THEN** the build succeeds and at start only the second install's options are in effect
