# Spec Delta

## MODIFIED Requirements

### Requirement: Option allowedDomains

The feature SHALL accept comma-separated DNS names, case-insensitively, ignoring surrounding whitespace and empty
entries. Each SHALL be a valid DNS name; the feature SHALL fail installation and name any invalid entry, including
wildcard label `*.example`. Valid entries SHALL allow subdomains as Allowed domains specifies.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted allowedDomains

- **WHEN** the feature is installed without `allowedDomains`
- **THEN** no domain is allowed beyond those of the selected presets

### Requirement: Option allowedCidrs

The feature SHALL accept comma-separated IPv4/IPv6 addresses or CIDRs, ignoring whitespace and empty entries. Each SHALL
allow its range or single address on every protocol and port. The feature SHALL fail installation and name any invalid
address, host bits outside a prefix, or range containing start-check probe `192.0.2.1`.

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

The feature SHALL accept comma-separated DNS names, case-insensitively, ignoring surrounding whitespace and empty
entries. Each SHALL be a valid DNS name; the feature SHALL fail installation and name any invalid entry, including
wildcard label `*.example`. Valid entries SHALL deny subdomains as Denied domains specifies.

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

The feature SHALL accept comma-separated IPv4/IPv6 addresses or CIDRs, ignoring whitespace and empty entries. Each SHALL
deny its range or single address on every protocol and port. The feature SHALL fail installation and name any invalid
address or host bits outside a prefix.

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

### Requirement: Option filterForward

When enabled, the feature SHALL apply the same outbound rules, including DNS restrictions, to forwarded traffic such as
nested-container traffic, subject to Forwarded traffic exceptions. When disabled, it SHALL NOT filter forwarded traffic.

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

The root entrypoint SHALL apply firewall rules before the container command on every start and SHALL replace prior
feature rules with those for build-time options. Repeated starts of the same image SHALL yield the same rules except for
resolver-learned addresses, fetched GitHub ranges, and resolvers rerecorded after Docker regenerates resolv.conf. The
dev container tool MAY run lifecycle commands while the entrypoint runs; firewall rules SHALL apply only after first
load.

#### Scenario: First start

- **WHEN** a container built with the feature starts
- **THEN** the firewall is in force before the container's command runs and the start is recorded as applied

#### Scenario: Restart re-applies the same rules

- **WHEN** a container with the feature is stopped and started again
- **THEN** the firewall is applied again with the same rules and the same checks pass as after the first start

### Requirement: Outbound default deny

Once active, the firewall SHALL refuse every outbound IPv4/IPv6 connection not allowed by Rule precedence. With
defaultAction=deny, it SHALL allow loopback, permitted resolver DNS, allowed destinations not refused by a more-specific
denial, and reply traffic; IPv6 neighbor discovery SHALL remain possible. A refused connection SHALL fail immediately
with an error. The feature SHALL NOT filter inbound connections.

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

Each allowedDomains entry SHALL allow its exact name and all subdomains on every protocol and port at resolver-returned
addresses, from lookup until next start. The feature SHALL follow changed addresses. Addresses not learned through the
container resolver SHALL remain refused unless another option allows them. NOTES.md SHALL warn that top-level/shared
suffixes permit nearly any destination.

#### Scenario: Subdomain of an allowed domain

- **WHEN** `presets` is empty, `allowedDomains` contains `githubusercontent.com`, and a process connects to
  `raw.githubusercontent.com`
- **THEN** the connection succeeds

#### Scenario: Address not obtained through the resolver

- **WHEN** a process connects to an address that the container's resolver has not returned for an allowed name since the
  start, and no other option allows it
- **THEN** the connection is refused

### Requirement: Denied domains

Each deniedDomains entry SHALL refuse its exact name and all subdomains at resolver-returned addresses from lookup until
next start, while names SHALL still resolve. The longer allowed/denied domain SHALL win; equal names SHALL be denied.
Directly reached addresses SHALL not be refused by deniedDomains unless another rule matches; other names resolving to a
refused address SHALL also be refused.

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

For outbound and filtered forwarded traffic, the feature SHALL apply rules in order: allow replies, loopback, IPv6
neighbor discovery, allowed resolver DNS and Forwarded traffic exceptions; refuse other DNS; refuse `192.0.2.1`; then
use the longest matching prefix among CIDRs, preset ranges, and resolver-learned domain addresses, allowing or refusing
as that entry says and refusing an equal-length allow/deny tie; otherwise apply defaultAction.

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

Each preset SHALL allow its named domains as Allowed domains does, plus its listed ranges. The `github` preset SHALL
include github.com and githubusercontent.com, plus GitHub web ranges only under defaultAction=deny; all Pages addresses
SHALL then be reachable although github.io is not listed. NOTES.md SHALL name the hosts each preset source lists and
leaves out, and SHALL explain GitHub Pages reachability.

#### Scenario: GitHub preset

- **WHEN** `presets` contains `github`
- **THEN** HTTPS connections to `github.com` and `api.github.com` succeed and a connection to a host outside every
  allowed set is refused

#### Scenario: No preset

- **WHEN** `presets` is empty and `allowedDomains` names one domain
- **THEN** only that domain, loopback, and the DNS resolvers are reachable

### Requirement: GitHub ranges

For `presets=github` with defaultAction=deny, each start SHALL fetch and validate GitHub web/api/git IPv4 and IPv6
ranges from https://api.github.com/meta. Before ranges load, the feature SHALL allow beyond loopback and resolver DNS
only HTTPS to addresses returned by one api.github.com resolver lookup, and SHALL connect only to those addresses.

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

Beyond loopback, DNS SHALL reach only resolvers in Docker-generated `/etc/resolv.conf`; Docker 127.0.0.11 and the
feature resolver SHALL be allowed over loopback. Other DNS SHALL be refused regardless of rules. Names SHALL still
resolve through Docker, including denied names; user-defined networks SHALL resolve only names Docker answers. NOTES.md
SHALL state this limit; search/options lines SHALL stay intact.

#### Scenario: Other DNS server refused

- **WHEN** a process sends a DNS query to a public resolver that `/etc/resolv.conf` did not name
- **THEN** the query is refused

#### Scenario: Unlisted name still resolves

- **WHEN** a process looks up a name that no option allows
- **THEN** the lookup returns its addresses and a connection to them is refused

### Requirement: Forwarded traffic

Regardless of filterForward, the feature SHALL allow traffic to networks only inside the container, traffic forwarded
into them, and replies to allowed forwarded connections. The feature SHALL NOT guarantee name-based allow/deny for
nested-container traffic when its lookups bypass the container resolver. NOTES.md SHALL explain both exceptions, their
cause, and a user remedy.

#### Scenario: Nested container reaches an allowed range

- **WHEN** `filterForward` is enabled and a nested container connects to an address inside a range that `allowedCidrs`
  lists
- **THEN** the connection succeeds

### Requirement: Failure mode

A start SHALL fail if rules cannot fully apply, GitHub fetch fails, or the domain resolver cannot start (including
address/port collision). If no rule loads (missing NET_ADMIN, non-root entrypoint, or missing nftables), outbound SHALL
remain unrestricted. A non-root entrypoint SHALL write no record; start check SHALL detect this and NOTES.md SHALL
require root. A resolver dying after success SHALL NOT change record/rules; lookups SHALL fail until restart.

#### Scenario: Rules cannot be loaded

- **WHEN** the container runs without `NET_ADMIN` or the entrypoint does not run as root
- **THEN** outbound traffic is not restricted; a start that runs as root is recorded as not applied, and a start under
  an entrypoint that does not run as root writes no record, so the start check reports it from the missing record

#### Scenario: Resolver port taken

- **WHEN** `failureMode` is `closed` and another process holds the resolver's address and port when a start launches the
  resolver
- **THEN** the start is recorded as failed, only loopback and the DNS resolvers are reachable, and `/etc/resolv.conf`
  names the container's own resolvers

### Requirement: Start check

The unprivileged postStartCommand SHALL wait a bounded time for this start’s record, treat an earlier record as missing,
and verify `192.0.2.1` is blocked without Internet traffic. It SHALL set its own PATH, run without inherited
environment, and call tools by absolute path. For missing/failed/not-applied starts it SHALL print the reason; closed
SHALL exit nonzero, while warn SHALL exit zero after a stderr warning.

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

### Requirement: Guardrail, not a security boundary

The feature SHALL be documented as a guardrail, not a security boundary, and SHALL NOT claim protection against
root/passwordless sudo, Docker access, DNS tunneling, shared allowed addresses, resolver-bypassing access to denied
hosts, un-denied names, or names inside allowed protocols such as DNS over HTTPS. NOTES.md SHALL state these limits and
that common users such as vscode may have passwordless sudo; with defaultAction=allow only denied entries are refused.

#### Scenario: Root removes the firewall

- **WHEN** a process with root in the container deletes the feature's rules
- **THEN** outbound traffic is unrestricted until the next start re-applies them

## ADDED Requirements

### Requirement: Preset source hosts and omissions are documented

The `npm` preset SHALL allow `registry.npmjs.org` (source: https://docs.npmjs.com/cli/v11/using-npm/config, `registry`
default); `pypi` SHALL allow `pypi.org` and `files.pythonhosted.org` (source: https://docs.pypi.org/api/).

#### Scenario: Package registry presets

- **WHEN** `presets` contains `npm` or `pypi`
- **THEN** the named registry hosts are allowed according to the preset list

### Requirement: GitHub preset domains use the documented source

The `github` preset SHALL allow `github.com` and `githubusercontent.com` as domains from the `domains.website` list of
https://api.github.com/meta. Its GitHub Pages `web` ranges allow every Pages site, including custom domains by address;
`github.io` itself is not among the preset domains.

#### Scenario: GitHub Pages are reachable by address

- **WHEN** `presets` includes `github`, `defaultAction=deny`, and GitHub ranges loaded successfully
- **THEN** Pages destinations in the `web` ranges are allowed even though `github.io` is not listed as a domain

### Requirement: Anthropic preset scope is documented

The `anthropic` preset SHALL allow `api.anthropic.com`, `claude.ai`, and `platform.claude.com` for API and sign-in only,
from https://code.claude.com/docs/en/network-config; NOTES.md SHALL document these hosts and omitted destinations.

#### Scenario: Anthropic preset hosts

- **WHEN** `presets` contains `anthropic`
- **THEN** its three listed hosts are allowed and its documented scope remains API and sign-in only

### Requirement: VS Code preset scope is documented

The `vscode` preset SHALL allow `update.code.visualstudio.com`, `vscode.download.prss.microsoft.com`, `vscode-cdn.net`,
`marketplace.visualstudio.com`, `gallery.vsassets.io`, and `gallerycdn.vsassets.io` for VS Code Server and Marketplace
downloads only, from https://code.visualstudio.com/docs/setup/network. NOTES.md SHALL document these hosts and
omissions.

#### Scenario: VS Code preset hosts

- **WHEN** `presets` contains `vscode`
- **THEN** the listed Server and Marketplace download hosts are allowed

### Requirement: GitHub metadata fetch relies on TLS

For github ranges, the feature SHALL fetch https://api.github.com/meta over HTTPS with bounded time and response size,
and verify TLS against image CA certificates; it SHALL NOT disable or weaken verification. Since GitHub publishes no
checksum or signature, trust relies on TLS alone.

#### Scenario: GitHub range metadata uses verified HTTPS

- **WHEN** `presets=github` and `defaultAction=deny`
- **THEN** the feature fetches the endpoint over verified HTTPS within the configured bounds

### Requirement: GitHub ranges are validated and applied as a whole

Every web/api/git IPv4/IPv6 range SHALL pass allowedCidrs validation and have IPv4 prefix /8 or longer and IPv6 /16 or
longer. The feature SHALL allow each validated range. An error status, timeout, malformed response, invalid range, or
rate limit SHALL fail the whole fetch/start and record the reason; partial ranges SHALL NOT load.

#### Scenario: Invalid GitHub metadata fails as a whole

- **WHEN** the metadata response has an invalid range, malformed body, error status, timeout, or reports the rate limit
- **THEN** no range from that response is allowed and start failure records the cause

### Requirement: Failed start records include the reason

For either failureMode, the feature SHALL record each failed start and its reason. If the resolver cannot start, it
SHALL leave `/etc/resolv.conf` naming container resolvers, never the process that owns the port. A resolver that exits
after successful start SHALL NOT change recorded status or loaded rules.

#### Scenario: Resolver port is already occupied

- **WHEN** another process holds the resolver address and port at start
- **THEN** the start is recorded as failed with the cause and resolv.conf still names container resolvers

### Requirement: Guardrail documentation includes indirect bypasses

NOTES.md SHALL state that allowed-domain addresses inside denied ranges may remain reachable, a process can
intentionally fail a warn-mode start (including by exhausting GitHub's rate limit) and thereby remove rules, the
resolver retains rule-changing capability, and a remote user's dynamic loader can forge start-check output. It SHALL
also state that changing workspace devcontainer configuration affects later builds and that any process causing start
failure in warn mode removes the rules.

#### Scenario: Guardrail limitations are documented

- **WHEN** a user reads the feature notes
- **THEN** these indirect bypasses and failure behaviors are described
