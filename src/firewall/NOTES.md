## A guardrail, not a security boundary

This feature makes unexpected egress, for example from an AI agent, fail as a refused connection instead of succeeding
silently. It is a guardrail, not a security boundary: it holds only for a remote user **without root, passwordless
`sudo`, or access to a Docker daemon**. The default users of common dev container images have passwordless `sudo`:
`vscode` in the Dev Containers base images can remove the rules with one command. Membership in the `docker` group is
equivalent to root, and a nested `--privileged` container or a `macvlan` network bypasses the rules.

**VS Code Server and extension downloads are refused** unless you add the `vscode` preset, for example
`"presets": "github,vscode"`.

Even for a remote user without those privileges:

- DNS lookups remain possible for every name, so data can leave the container through them.
- Other sites that share an allowed address or range are reachable too, such as other sites on an allowed CDN or in
  GitHub's ranges.
- With `defaultAction` `allow`, the feature refuses only what the denied entries name, and a process can avoid a denied
  name, for example by connecting to an address it did not look up, so use `deniedCidrs` for ranges that must stay out
  of reach.
- With `failureMode` `warn`, any process that can make a start fail removes the rules at that start.

## Before you enable it

- Everything no option allows is refused, including sibling Compose services, the Docker host, and package mirrors
  (`deb.debian.org`, `dl-cdn.alpinelinux.org`, Fedora mirrors): add them to `allowedDomains` or `allowedCidrs`.
- The default is `presets` `github` with `defaultAction` `deny`: the container reaches GitHub (web, API, Git, raw and
  release content) and nothing else beyond loopback and its DNS resolvers.
- With the default `failureMode` `closed`, a start whose rules cannot be applied in full keeps only loopback and DNS
  reachable, and the failing start check makes the dev container tool skip your later lifecycle commands (such as your
  own `postStartCommand` and `postAttachCommand`). Use `warn` for containers that must start anyway.

## What it adds to the container

| Metadata           | Value                                                                                            | Why                                                                             |
| ------------------ | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| `capAdd`           | `NET_ADMIN`                                                                                      | Loading the nftables rules at start; dnsmasq adding looked-up addresses to them |
| `entrypoint`       | `/usr/local/share/firewall/apply.sh`                                                             | Applies the rules as root at every start, before the container's command        |
| `postStartCommand` | `/usr/local/share/firewall/check.sh`                                                             | Checks, without privilege, that the rules are in force                          |
| `installsAfter`    | `ghcr.io/devcontainers/features/docker-in-docker`, `ghcr.io/devcontainers/features/common-utils` | Its entrypoint runs after docker-in-docker's                                    |

It installs `nftables`, a `dnsmasq` build with nftables set support (`dnsmasq-base` on Debian and Ubuntu,
`dnsmasq-dnssec-nftset` on Alpine, `dnsmasq` on Fedora), `curl`, `jq`, and `ca-certificates` from the image's configured
repositories. It adds no repository, no key, no sudoers entry, and no group membership; the remote user gains no
privilege and no command to change the rules.

## How it works

At every start the entrypoint, as root, replaces the feature's own nftables table `inet firewall` in one transaction and
touches no other table, so Docker's and docker-in-docker's rules stay as they are:

1. It writes the recorded DNS resolvers back into `/etc/resolv.conf` and loads a closed table: loopback, replies, IPv6
   neighbour discovery, and DNS to those resolvers.
2. With the `github` preset and `defaultAction` `deny`, it looks up `api.github.com` once, allows those addresses on TCP
   443 only, and fetches the GitHub ranges from `https://api.github.com/meta` (the `web`, `api`, and `git` lists; TLS
   only, since GitHub publishes no checksum or signature; at most two attempts of 20 seconds and 2 MiB). Every range
   must be a valid CIDR of at least /8 (IPv4) or /16 (IPv6) that does not contain `192.0.2.1`.
3. It loads the full table, starts dnsmasq as the `dnsmasq` user on `127.0.0.1`, and points `/etc/resolv.conf` at it.
   dnsmasq forwards to the recorded resolvers and adds the addresses of every answer for an allowed or denied domain to
   that verdict's set, so CDN rotation and subdomains are followed.

Where allowed and denied entries overlap, the longest prefix decides (a looked-up address counts as a single address)
and a tie refuses; what no entry matches follows `defaultAction`. DNS to any server other than the recorded resolvers is
refused whatever the options say, and every name still resolves. Refused TCP connections get a reset, other protocols an
ICMP error, so they fail at once. Inbound connections are not filtered. The script ends within 60 seconds even when the
network is down.

The start record **`/run/firewall/status`** (readable, not writable, by every user) names the result (`applied`,
`failed`, or `not-applied`), its reason, the time, and the options in effect. The start check waits at most 90 seconds
for the current start's record and connects to `192.0.2.1:443`, which the rules always refuse, so it contacts no host on
the Internet.

## Options in detail

- A domain entry allows (or denies) the name and **every name under it**, on every port: a top-level domain or a shared
  suffix, such as a dynamic DNS provider's domain, allows nearly any destination. Wildcards (`*.example.com`) are
  rejected because subdomains are always included.
- A name is reachable at the addresses the container's resolver returned for it, from that lookup until the next start;
  an address never looked up for an allowed name stays refused unless a CIDR allows it.
- Denying a name refuses every other name that shares its addresses, until the next start; a narrower name or
  `deniedCidrs` is the remedy. To open an address inside a denied range, prefer `allowedCidrs` over `allowedDomains`: a
  name of an allowed domain that someone else controls can resolve into the denied range.
- `allowedCidrs` rejects ranges that contain `192.0.2.1`, the address the start check probes, such as `0.0.0.0/0`; use
  `defaultAction` `allow` instead.
- The `github` preset allows `github.com`, `githubusercontent.com`, and GitHub's `web`, `api`, and `git` ranges. The
  `web` ranges hold the addresses of GitHub Pages, so **every GitHub Pages site, custom domains included, is
  reachable**. `domains.website` of GitHub's meta endpoint also lists `*.githubassets.com`, `*.github.io`, and
  `*.github.dev`, which the preset leaves out as domains; `*.github.io` is reachable anyway by address through the `web`
  ranges. The `actions`, `codespaces`, `copilot`, and `packages` (GHCR) ranges are left out too.
- The `npm` preset allows `registry.npmjs.org`; `pypi` allows `pypi.org` and `files.pythonhosted.org`.
- The `anthropic` preset (`api.anthropic.com`, `claude.ai`, `platform.claude.com`) covers the API and sign-in only. Its
  source, https://code.claude.com/docs/en/network-config, also lists `claude.com`, `mcp-proxy.anthropic.com`,
  `downloads.claude.ai`, `storage.googleapis.com`, `bridge.claudeusercontent.com`, `*.frame.claudeusercontent.com`,
  `formulae.brew.sh` (Homebrew installs only), `code.claude.com`, and, as optional, `*-review.googlesource.com` and two
  Datadog telemetry hosts.
- The `vscode` preset (`update.code.visualstudio.com`, `vscode.download.prss.microsoft.com`, `vscode-cdn.net`,
  `marketplace.visualstudio.com`, `gallery.vsassets.io`, `gallerycdn.vsassets.io`) covers VS Code Server and Marketplace
  downloads only. Its source, https://code.visualstudio.com/docs/setup/network, also lists `code.visualstudio.com`,
  `go.microsoft.com`, `rink.hockeyapp.net`, `vsmarketplacebadges.dev`, `download.visualstudio.microsoft.com`,
  `vscode-sync.trafficmanager.net`, `vscode-sync-insiders.trafficmanager.net`, `vscode.dev`, `*.vscode-unpkg.net`, and
  `default.exp-tas.com`.
- Sibling Compose services: allow a service by its name in `allowedDomains` (Docker's embedded DNS answers it through
  the feature's resolver) or its subnet in `allowedCidrs`. The container's own subnets are not allowed automatically,
  since that would also open the Docker host's gateway address.

## Nested containers (docker-in-docker)

The feature protects the dev container's own outbound traffic. Containers nested in it are an exception: the rules apply
to them too, but **a nested container is not guaranteed to reach an allowed domain, nor to be refused a denied one**.

- With `filterForward` `true`, what the options state by address holds for a nested container: it reaches the addresses
  inside `allowedCidrs` and inside the `github` preset's ranges, is refused those inside `deniedCidrs`, and, with
  `defaultAction` `deny`, is refused every destination no option allows. Traffic between the container and its nested
  networks is always allowed.
- What the options state by name holds only for lookups the feature's resolver answers: a domain is allowed or denied at
  the addresses that resolver returned for it, and it sees only lookups made through the dev container's
  `/etc/resolv.conf`. A nested Docker daemon configured with its own DNS servers sends its containers' lookups
  elsewhere. The known case is docker-in-docker on an Azure host: its `azureDnsAutoDetection` option (default `true`)
  starts the daemon with `--dns 168.63.129.16`. A nested container then resolves an allowed name but is refused the
  connection, and it **reaches a denied name** wherever `defaultAction` `allow` or an allowed range, such as the
  `github` preset's, lets the address through. A lookup of the name by the dev container itself changes this only for
  the addresses that lookup returned.
- A nested daemon without DNS servers of its own, which is docker-in-docker's default away from Azure hosts, gives the
  containers on its default bridge (`docker run` without `--network`) `8.8.8.8` and `8.8.4.4` as resolvers, which are
  refused, so no name resolves there. Its containers on a user-defined network (`docker network create`) look names up
  through the feature's resolver, so allowed and denied domains hold for them.
- What you can do today: state by address what nested containers need and what they must not reach, in `allowedCidrs`
  and `deniedCidrs`; or set docker-in-docker's `azureDnsAutoDetection` to `false` and run nested containers on a
  user-defined network.

## Limits and failures

- The dev container tool may run lifecycle commands while the entrypoint is still running; the rules are in force for
  them only once the entrypoint loads its first table, which is its first action. The start check waits for the record.
- GitHub allows 60 unauthenticated requests per hour per IP address. A start that is rate-limited fails with that reason
  in the start check's output; a start after the limit resets fetches again.
- If dnsmasq exits after a successful start, name lookups fail until the next start; the recorded result stays.
- When no rule can be loaded at all (no `NET_ADMIN`, for example with a runtime that drops `capAdd`, an entrypoint that
  does not run as root, or a kernel without nftables), outbound traffic is unrestricted and the start check reports it.
- The entrypoint has to run as root. If the container's user is not root (`containerUser`, or the image's `USER`), the
  entrypoint loads no rule and cannot write the start record either, so the start check waits its 90 seconds and then
  reports that the record is missing. Leave the container's user at root and name the unprivileged user with
  `remoteUser`.
- Do not configure DNS servers for a dev container on a user-defined Docker network, which is what Docker Compose
  creates: not with `docker run --dns`, not with `dns:` in a Compose file, and not with a Docker daemon started with
  `--dns`. Docker's embedded resolver then forwards lookups from inside the container to those servers, and the rules
  refuse them like any DNS server that `/etc/resolv.conf` does not name. Only the names Docker answers itself, those of
  other containers and services, still resolve, although the start check passes. Without configured DNS servers every
  name resolves, and so it does on the default bridge network, where `/etc/resolv.conf` names the configured servers.
- `--network=host` is not supported: the rules would land in the host's network namespace.
- A failed start writes its reason to the container log and to `/run/firewall/status`. A restart applies the rules
  again.

## OS support

See [test/firewall/compatibility.json](../../test/firewall/compatibility.json).
