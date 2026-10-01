# Spec Delta

## Purpose

Installs nftables and dnsmasq from the image's distribution together with a start-time firewall that restricts a dev
container's outbound and forwarded traffic to an allowlist of presets, domains, and CIDRs, or, with its default action
set to allow, keeps that traffic from a denylist of domains and CIDRs, checked by an unprivileged start check. It is a
guardrail that surfaces unexpected egress, for example from an AI agent, not a security boundary.

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

### Requirement: Option defaultAction

The feature SHALL accept the option `defaultAction` as declared here, which decides the outbound and filtered forwarded
traffic that no allowed or denied entry matches (Requirement: Rule precedence): with `deny`, that traffic is refused,
and with `allow`, it is let through.

| Field   | Value              |
| ------- | ------------------ |
| Type    | `string`           |
| Default | `"deny"`           |
| Enum    | `["deny","allow"]` |

#### Scenario: Omitted defaultAction

- **WHEN** the feature is installed without `defaultAction` and a process connects to a host that no option names
- **THEN** the connection fails immediately with an error

#### Scenario: Unlisted destination let through

- **WHEN** `defaultAction` is `allow` and a process connects to a host that no option names
- **THEN** the connection succeeds

### Requirement: Option presets

The feature SHALL accept the option `presets` as declared here: comma-separated names of the destination sets of
Requirement: Presets, ignoring surrounding whitespace and empty entries, combined as the union of their destinations,
with an empty list selecting none and an entry that is not a known preset failing the install with a message naming it.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"github"` |

#### Scenario: Omitted presets

- **WHEN** the feature is installed without `presets`
- **THEN** the `github` preset is selected and no other

#### Scenario: Unknown preset

- **WHEN** `presets` contains a name that is not a known preset
- **THEN** the build fails with a message naming that entry

#### Scenario: Presets combine

- **WHEN** `presets` contains `github` and `npm`
- **THEN** both `api.github.com` and `registry.npmjs.org` are reachable

### Requirement: Option allowedDomains

The feature SHALL accept the option `allowedDomains` as declared here: comma-separated DNS names, ignoring surrounding
whitespace and empty entries, each allowed as Requirement: Allowed domains states, with an entry that is not a valid DNS
name, including an entry with a wildcard label such as `*.example` (subdomains are always included), failing the install
with a message naming it.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted allowedDomains

- **WHEN** the feature is installed without `allowedDomains`
- **THEN** no domain is allowed beyond those of the selected presets

### Requirement: Option allowedCidrs

The feature SHALL accept the option `allowedCidrs` as declared here: comma-separated IPv4 or IPv6 addresses or CIDRs,
ignoring surrounding whitespace and empty entries, each allowing every address in that range, or that single address, on
every protocol and port, with an entry that is not a valid IPv4 or IPv6 address or CIDR, that has bits set outside its
prefix length, or whose range contains `192.0.2.1`, the address the start check probes (Requirement: Start check),
failing the install with a message naming it.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted allowedCidrs

- **WHEN** the feature is installed without `allowedCidrs`
- **THEN** no address range is allowed beyond those of the selected presets

#### Scenario: IPv4 and IPv6 ranges

- **WHEN** `allowedCidrs` lists one IPv4 and one IPv6 range
- **THEN** connections to addresses in either range are allowed and addresses outside both stay refused

#### Scenario: Malformed CIDR

- **WHEN** `allowedCidrs` contains an entry that is neither an IPv4 nor an IPv6 address or CIDR
- **THEN** the build fails with a message naming that entry

#### Scenario: CIDR that cannot be applied as written

- **WHEN** `allowedCidrs` contains an entry with host bits set, or an entry such as `0.0.0.0/0` that contains
  `192.0.2.1`
- **THEN** the build fails with a message naming that entry

### Requirement: Option deniedDomains

The feature SHALL accept the option `deniedDomains` as declared here: comma-separated DNS names, ignoring surrounding
whitespace and empty entries, each denied as Requirement: Denied domains states, with an entry that is not a valid DNS
name, including an entry with a wildcard label such as `*.example` (subdomains are always included), failing the install
with a message naming it.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted deniedDomains

- **WHEN** the feature is installed without `deniedDomains`
- **THEN** no domain is refused beyond what the other options refuse

#### Scenario: Malformed denied domain

- **WHEN** `deniedDomains` contains an entry that is not a valid DNS name
- **THEN** the build fails with a message naming that entry

### Requirement: Option deniedCidrs

The feature SHALL accept the option `deniedCidrs` as declared here: comma-separated IPv4 or IPv6 addresses or CIDRs,
ignoring surrounding whitespace and empty entries, each refusing every address in that range, or that single address, on
every protocol and port as Requirement: Rule precedence states, with an entry that is not a valid IPv4 or IPv6 address
or CIDR, or that has bits set outside its prefix length, failing the install with a message naming it.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted deniedCidrs

- **WHEN** the feature is installed without `deniedCidrs`
- **THEN** no address range is refused beyond what the other options refuse

#### Scenario: Denied range under open egress

- **WHEN** `defaultAction` is `allow` and `deniedCidrs` lists a range
- **THEN** a connection to an address in that range fails immediately with an error and a connection to a host outside
  it succeeds

#### Scenario: Malformed denied CIDR

- **WHEN** `deniedCidrs` contains an entry that is not a valid IPv4 or IPv6 address or CIDR, or has host bits set
- **THEN** the build fails with a message naming that entry

### Requirement: Option failureMode

The feature SHALL accept the option `failureMode` as declared here, which decides what a failed start (Requirement:
Failure mode) leaves in place: with `closed`, only loopback and the DNS resolvers stay reachable, and with `warn`, every
rule the feature applied is removed, leaving outbound traffic unrestricted by the feature.

| Field   | Value               |
| ------- | ------------------- |
| Type    | `string`            |
| Default | `"closed"`          |
| Enum    | `["closed","warn"]` |

#### Scenario: Omitted failureMode

- **WHEN** the feature is installed without `failureMode` and a start fails after the rules could be loaded
- **THEN** only loopback and the DNS resolvers are reachable and the start is recorded as failed

#### Scenario: Failed start leaves only the resolvers

- **WHEN** `failureMode` is `closed` and a start fails after the rules could be loaded
- **THEN** only loopback and the DNS resolvers are reachable and the start is recorded as failed

#### Scenario: Failed start removes the rules

- **WHEN** `failureMode` is `warn` and a start fails
- **THEN** the feature leaves no rule in place and the start is recorded as failed with its reason

### Requirement: Option filterForward

The feature SHALL accept the option `filterForward` as declared here: when it is enabled, traffic that the container
forwards, such as traffic of containers nested in it, is subject to the same rules as its own outbound traffic,
including the DNS restriction, and when it is disabled, the feature does not filter forwarded traffic.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `true`    |

#### Scenario: Omitted filterForward

- **WHEN** the feature is installed without `filterForward` and a container nested inside connects to a host no option
  allows
- **THEN** the connection is refused

#### Scenario: Nested container filtered

- **WHEN** `filterForward` is enabled and a container nested inside connects to a host no option allows
- **THEN** the connection is refused

#### Scenario: Forwarded traffic not filtered

- **WHEN** `filterForward` is disabled and a nested container connects to a host no option allows
- **THEN** the feature does not refuse it

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
- **THEN** the firewall is applied again with the same rules and the same checks pass as after the first start

### Requirement: Outbound default deny

Once the firewall is in force, the container SHALL refuse every outbound connection, IPv4 and IPv6, that Requirement:
Rule precedence refuses. With `defaultAction` `deny`, that is every connection except traffic through the loopback
interface, DNS traffic to the resolvers allowed by Requirement: DNS only to the container's resolvers, traffic to a
destination allowed by `presets`, `allowedDomains`, or `allowedCidrs` and not refused by a denied entry at least as
specific, and reply traffic of connections the container accepted or opened through these exceptions. IPv6 neighbour
discovery SHALL stay possible, so an allowed IPv6 destination is reachable. A refused connection SHALL fail immediately
with an error rather than time out. Inbound connections to the container SHALL NOT be filtered by the feature.

#### Scenario: Allowed domain is reachable

- **WHEN** a process in the container connects to a host whose name is allowed by `presets` or `allowedDomains`
- **THEN** the connection succeeds

#### Scenario: Unlisted domain is refused

- **WHEN** `defaultAction` is `deny` and a process in the container connects to a host that no option allows
- **THEN** the connection fails immediately with an error

#### Scenario: IPv6 default deny

- **WHEN** `defaultAction` is `deny` and a process in the container connects over IPv6 to an address that no option
  allows
- **THEN** the connection fails immediately with an error

#### Scenario: Inbound connection still answered

- **WHEN** a client outside the container connects to a port the container publishes or forwards
- **THEN** the container's replies on that connection are delivered

### Requirement: Allowed domains

Each `allowedDomains` entry SHALL allow the name itself and every subdomain of it, on every protocol and port. A name
SHALL become reachable at the addresses the container's resolver returns for it, from the time of that lookup until the
next start of the container, so addresses that change between lookups are followed, unless Requirement: Rule precedence
refuses them. An address the container did not obtain through its resolver SHALL stay refused unless another option
allows it. `NOTES.md` SHALL state that an entry allows every name under it, so a top-level domain or a shared suffix,
such as a dynamic DNS provider's domain, allows nearly any destination.

#### Scenario: Subdomain of an allowed domain

- **WHEN** `presets` is empty, `allowedDomains` contains `githubusercontent.com`, and a process connects to
  `raw.githubusercontent.com`
- **THEN** the connection succeeds

#### Scenario: Address not obtained through the resolver

- **WHEN** a process connects to an address that the container's resolver has not returned for an allowed name since the
  start, and no other option allows it
- **THEN** the connection is refused

### Requirement: Denied domains

Each `deniedDomains` entry SHALL deny the name itself and every subdomain of it, on every protocol and port. The
addresses the container's resolver returns for a denied name SHALL be refused from the time of that lookup until the
next start of the container, and the name SHALL still resolve. A name matched by both an allowed domain (from `presets`
or `allowedDomains`) and a denied one SHALL follow the longer of the two entries, and the denied one when both are the
same name. An address that the container reaches without a lookup of a denied name through its resolver is not refused
by `deniedDomains`, and every other name that shares a refused address is refused with it.

#### Scenario: Denied domain refused

- **WHEN** `deniedDomains` contains a name and a process looks it up and connects to it
- **THEN** the lookup returns its addresses and the connection fails immediately with an error

#### Scenario: Allowed subdomain of a denied domain

- **WHEN** `deniedDomains` contains `githubusercontent.com`, `allowedDomains` contains `raw.githubusercontent.com`, and
  a process connects to `raw.githubusercontent.com`
- **THEN** the connection succeeds

#### Scenario: Denied subdomain of an allowed domain

- **WHEN** an allowed domain contains a subdomain that `deniedDomains` lists and a process connects to that subdomain
- **THEN** the connection is refused

#### Scenario: Denied name inside an allowed range

- **WHEN** `presets` contains `github`, `deniedDomains` contains `raw.githubusercontent.com`, and a process connects to
  `raw.githubusercontent.com`
- **THEN** the connection is refused although its addresses lie in a GitHub range

### Requirement: Rule precedence

The feature SHALL decide each outbound connection, and each forwarded one it filters, in this order:

1. Reply traffic of accepted connections, traffic through the loopback interface, IPv6 neighbour discovery, DNS traffic
   to the resolvers of Requirement: DNS only to the container's resolvers, and traffic of Requirement: Forwarded traffic
   are allowed, whatever the denied entries say; other DNS traffic is refused.
2. Traffic to `192.0.2.1`, the address the start check probes (Requirement: Start check), is refused.
3. Among the entries that contain the destination address (`allowedCidrs`, `deniedCidrs`, the ranges of the selected
   presets, and the addresses learned through allowed and denied domains, each learned address counting as a single
   address), the one with the longest prefix decides: an allowed entry lets the traffic through and a denied one refuses
   it. Between an allowed and a denied entry of the same prefix length, the traffic is refused.
4. Traffic that no entry contains is decided by `defaultAction`.

#### Scenario: Allowed address inside a denied range

- **WHEN** `deniedCidrs` lists a range and `allowedCidrs` lists an address inside it
- **THEN** connections to that address succeed and connections to other addresses of the range fail immediately with an
  error

#### Scenario: Denied range inside an allowed range

- **WHEN** `allowedCidrs` lists a range and `deniedCidrs` lists a smaller range inside it
- **THEN** connections to the smaller range fail immediately with an error and connections to the rest of the range
  succeed

#### Scenario: Same range allowed and denied

- **WHEN** `allowedCidrs` and `deniedCidrs` list the same range
- **THEN** connections to that range fail immediately with an error

#### Scenario: Resolvers inside a denied range

- **WHEN** `deniedCidrs` lists a range that contains the container's resolvers
- **THEN** names still resolve and other connections to that range are refused

#### Scenario: Allowed name inside a denied range

- **WHEN** `deniedCidrs` lists a range and a name of an allowed domain resolves to an address inside it
- **THEN** a connection to that name succeeds

### Requirement: Presets

`presets` SHALL select named destination sets, each allowing the domains listed here the way `allowedDomains` allows
them, plus the ranges named for it. Each set follows the source named with it:

- `github`: `github.com`, `githubusercontent.com`, and, with `defaultAction` `deny`, the IPv4 and IPv6 ranges of
  Requirement: GitHub ranges. Source: the `domains.website` list of the endpoint named in Requirement: GitHub ranges.
  Its `web` ranges hold the addresses of GitHub Pages, so every Pages site, custom domains included, is reachable by
  address although `github.io` is not among its domains.
- `npm`: `registry.npmjs.org`. Source: the `registry` default in https://docs.npmjs.com/cli/v11/using-npm/config
- `pypi`: `pypi.org`, `files.pythonhosted.org`. Source: https://docs.pypi.org/api/
- `anthropic`: `api.anthropic.com`, `claude.ai`, `platform.claude.com`, which cover the API and sign-in only. Source:
  https://code.claude.com/docs/en/network-config
- `vscode`: `update.code.visualstudio.com`, `vscode.download.prss.microsoft.com`, `vscode-cdn.net`,
  `marketplace.visualstudio.com`, `gallery.vsassets.io`, `gallerycdn.vsassets.io`, which cover VS Code Server and
  Marketplace downloads only. Source: https://code.visualstudio.com/docs/setup/network

`NOTES.md` SHALL name the hosts that a preset's source lists and the preset leaves out, and SHALL state that the
`github` preset makes every GitHub Pages site reachable.

#### Scenario: GitHub preset

- **WHEN** `presets` contains `github`
- **THEN** HTTPS connections to `github.com` and `api.github.com` succeed and a connection to a host outside every
  allowed set is refused

#### Scenario: No preset

- **WHEN** `presets` is empty and `allowedDomains` names one domain
- **THEN** only that domain, loopback, and the DNS resolvers are reachable

### Requirement: GitHub ranges

When `presets` contains `github` and `defaultAction` is `deny`, each start SHALL fetch https://api.github.com/meta over
HTTPS, with a bounded time and response size. GitHub publishes no checksum or signature for this response, so the fetch
SHALL rely on TLS alone, verified against the image's CA certificates, and SHALL NOT disable or weaken that
verification. The start SHALL allow every IPv4 and IPv6 range in the response's `web`, `api`, and `git` lists. Every
entry of those lists SHALL be validated as an `allowedCidrs` entry is (Requirement: Option allowedCidrs) and SHALL have
a prefix of at least /8 for IPv4 and at least /16 for IPv6; an entry that fails either check, an error status, a
timeout, or a malformed response SHALL make the whole fetch a failure handled by Requirement: Failure mode, and a
response that reports GitHub's rate limit SHALL be recorded with that reason. Until the ranges are loaded, the only
destinations reachable beyond loopback and the DNS resolvers SHALL be the addresses that one lookup of `api.github.com`
through those resolvers returned at that start, on the HTTPS port, and the fetch SHALL connect only to those addresses.

#### Scenario: Ranges loaded

- **WHEN** `presets` contains `github` and the fetch succeeds
- **THEN** an address inside a `git` range is reachable without a DNS lookup of a GitHub name

#### Scenario: Fetch fails

- **WHEN** `presets` contains `github` and the fetch times out or returns an invalid range
- **THEN** no range from that response is allowed and the start is handled as a failure

#### Scenario: Implausible range

- **WHEN** `presets` contains `github` and the response lists a range with host bits set, a range shorter than the
  minimum prefix, or a range that contains `192.0.2.1`
- **THEN** no range from that response is allowed and the start is handled as a failure

#### Scenario: GitHub preset not selected

- **WHEN** `presets` does not contain `github`
- **THEN** the start fetches nothing

#### Scenario: Unlisted traffic already let through

- **WHEN** `presets` contains `github` and `defaultAction` is `allow`
- **THEN** the start fetches nothing

### Requirement: DNS only to the container's resolvers

The container SHALL be able to send DNS queries beyond the loopback interface only to the resolvers named in
`/etc/resolv.conf` as Docker last generated it (Requirement: Firewall applied at every start); queries to Docker's
embedded resolver `127.0.0.11` and to the feature's local resolver travel through the loopback interface and stay
allowed. DNS traffic to any other address SHALL be refused, whatever `defaultAction` and the allowed entries say. Every
name SHALL still resolve, including names that no option allows and denied names, since only connections are filtered.
The feature SHALL keep the `search` and `options` lines of `/etc/resolv.conf` intact.

#### Scenario: Other DNS server refused

- **WHEN** a process sends a DNS query to a public resolver that `/etc/resolv.conf` did not name
- **THEN** the query is refused

#### Scenario: Unlisted name still resolves

- **WHEN** a process looks up a name that no option allows
- **THEN** the lookup returns its addresses and a connection to them is refused

### Requirement: Forwarded traffic

Whatever `filterForward` is, traffic from the container to networks that exist only inside it, such as the bridges of a
nested Docker daemon, traffic forwarded into those networks, and reply traffic of forwarded connections that were
allowed SHALL be allowed, whatever the denied entries say; which forwarded traffic the rules filter is stated in
Requirement: Option filterForward. The feature does not guarantee that a nested container reaches a destination allowed
only by name: an allowed name is reachable at the addresses the container's resolver returned for it (Requirement:
Allowed domains), and a nested Docker daemon configured with its own DNS servers sends its containers' lookups to those
servers instead. `NOTES.md` SHALL state this exception, its cause, and what a user can do.

#### Scenario: Nested container reaches an allowed range

- **WHEN** `filterForward` is enabled and a nested container connects to an address inside a range that `allowedCidrs`
  lists
- **THEN** the connection succeeds

### Requirement: Failure mode

A start SHALL be a failure when the rules for the configured options cannot be applied in full: the rules cannot be
loaded, the GitHub ranges fetch fails, or the resolver that learns allowed and denied domains cannot start, including
when another process already holds its address and port. A resolver that cannot start SHALL leave `/etc/resolv.conf`
naming the container's own resolvers, never the process that holds the port. What a failed start leaves in place is
stated in Requirement: Option failureMode; in both modes the start SHALL be recorded as failed with its reason. When no
rule can be loaded at all (the container lacks `NET_ADMIN`, the entrypoint does not run as root, or the kernel lacks
nftables support), outbound traffic stays unrestricted in both modes. A resolver that exits after a successful start
SHALL NOT change the recorded result or the rules; name lookups then fail until the next start.

#### Scenario: Rules cannot be loaded

- **WHEN** the container runs without `NET_ADMIN` or the entrypoint does not run as root
- **THEN** outbound traffic is not restricted and the start is recorded as not applied

#### Scenario: Resolver port taken

- **WHEN** `failureMode` is `closed` and another process holds the resolver's address and port when a start launches the
  resolver
- **THEN** the start is recorded as failed, only loopback and the DNS resolvers are reachable, and `/etc/resolv.conf`
  names the container's own resolvers

### Requirement: Start check

The feature SHALL run, as its `postStartCommand` and without privilege, a check that waits a bounded time for the record
of the current start, treats a record left from an earlier start as missing, and verifies that `192.0.2.1`, which the
rules refuse whatever the options say (Requirement: Rule precedence), is refused. The check SHALL send no traffic to any
host on the Internet. It SHALL set its own `PATH`, SHALL run without the environment variables it inherits, and SHALL
call its tools by absolute path, so a changed `PATH`, `ENV`, or `BASH_ENV` of the remote user does not change its
result. On a failed, missing, or not-applied start it SHALL print the reason; with `failureMode` `closed` it SHALL exit
non-zero, and with `warn` it SHALL exit zero after a warning on standard error.

#### Scenario: Firewall in force

- **WHEN** the current start was applied and the probe address is refused
- **THEN** the check exits zero and prints a one-line summary

#### Scenario: Failure reported as an error

- **WHEN** `failureMode` is `closed` and the current start failed or was not applied
- **THEN** the check prints the reason and exits non-zero, so the dev container tool reports the failure

#### Scenario: Failure reported as a warning

- **WHEN** `failureMode` is `warn` and the current start failed or was not applied
- **THEN** the check prints a warning with the reason on standard error and exits zero

#### Scenario: Stale record

- **WHEN** the only start record present belongs to an earlier start of the container
- **THEN** the check treats the current start as not applied

#### Scenario: Changed environment

- **WHEN** the check runs with a `PATH` whose first directory holds programs named like the tools it uses, and with
  `ENV` and `BASH_ENV` set
- **THEN** its result and exit status are those of a run in a clean environment

### Requirement: Start record readable by the remote user

Each start SHALL write a record of its result (applied, failed, or not applied), its reason, its time, and the options
in effect to a file whose path `NOTES.md` documents, readable and not writable by the remote user.

#### Scenario: Remote user reads the record

- **WHEN** the remote user reads the start record
- **THEN** it names the result and the options in effect, and writing to it is denied

### Requirement: Resolver runs unprivileged

The resolver that learns allowed and denied domains SHALL run as an unprivileged user other than root and the remote
user, keeping only the capability it needs to add addresses to the feature's sets.

#### Scenario: Resolver user

- **WHEN** the firewall is in force
- **THEN** the resolver's process runs as neither root nor the remote user

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
- **THEN** the nested Docker daemon starts and runs a nested container

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
range, that reaches a denied host through an address it did not look up through the container's resolver, through a name
that is not denied, or through a protocol that carries names inside allowed traffic (such as DNS over HTTPS), that
reaches a denied range through a name of an allowed domain that resolves into it, that makes a start fail on purpose
while `failureMode` is `warn` (for example by exhausting GitHub's rate limit), that exploits the resolver, which keeps
the capability to change the rules, that forges the start check's output through the dynamic loader of the remote user's
environment, or that changes the dev container configuration in the workspace for the next build. `NOTES.md` SHALL state
that the guardrail holds only for a remote user without root, passwordless `sudo`, or access to a Docker daemon, that
the default users of common dev container images, such as `vscode` in the Dev Containers base images, have passwordless
`sudo`, and that with `defaultAction` `allow` the feature refuses only what the denied entries name, and that with
`failureMode` `warn` any process that can make a start fail removes the rules at that start.

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
