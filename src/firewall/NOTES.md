## A guardrail, not a security boundary

This feature makes unexpected egress, for example from an AI agent, fail as a refused connection instead of succeeding
silently. It does not stop a process that tries to get around it. It holds only for a remote user **without root,
passwordless `sudo`, or access to a Docker daemon**, and the default users of common dev container images have
passwordless `sudo`: `vscode` in the Dev Containers base images can remove the rules with one command. It does not stop
a process that:

- has root or passwordless `sudo` inside the container, or can use a Docker daemon, including through membership in the
  `docker` group (a nested `--privileged` container or a `macvlan` network bypasses the rules);
- tunnels data through DNS lookups, which stay possible for every name;
- reaches other services that share an allowed address or range, such as other sites on an allowed CDN or GitHub's
  ranges;
- reaches a denied host through an address it did not look up through the container's resolver, through a name that is
  not denied, or through a protocol that carries names inside allowed traffic (DNS over HTTPS);
- reaches a denied range through a name of an allowed domain that resolves into it (DNS rebinding);
- makes a start fail on purpose while `failureMode` is `warn`, for example by exhausting GitHub's API rate limit or by
  binding `127.0.0.1:53` first: that start removes the rules;
- exploits the resolver (dnsmasq), which keeps the capability to change the rules;
- forges the start check's output through the dynamic loader of the remote user's environment (`LD_PRELOAD`);
- changes the dev container configuration in the workspace for the next build.

With `defaultAction` `allow`, the feature refuses only what the denied entries name: use `deniedCidrs` for ranges that
must stay out of reach, since `deniedDomains` refuses only the addresses learned from lookups of denied names.

## Before you enable it

- **VS Code Server and extension downloads are refused** unless you add the `vscode` preset (for example
  `"presets": "github,vscode"`). Everything no option allows is refused, including sibling Compose services, the Docker
  host, and package mirrors (`deb.debian.org`, `dl-cdn.alpinelinux.org`, Fedora mirrors): add them to `allowedDomains`
  or `allowedCidrs`.
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
  reachable**. `domains.website` of GitHub's meta endpoint also lists `*.githubassets.com` and `*.github.dev`, which the
  preset leaves out; the `actions`, `codespaces`, `copilot`, and `packages` (GHCR) ranges are left out too.
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
- Nested containers (docker-in-docker): with `filterForward` `true`, their traffic meets the same rules. Use
  user-defined networks (`docker network create`): their embedded DNS forwards to the feature's resolver, while
  containers on the default bridge get `8.8.8.8` as resolver, which is refused. Traffic between the container and its
  nested networks is always allowed.

## Limits and failures

- The dev container tool may run lifecycle commands while the entrypoint is still running; the rules are in force for
  them only once the entrypoint loads its first table, which is its first action. The start check waits for the record.
- GitHub allows 60 unauthenticated requests per hour per IP address. A start that is rate-limited fails with that reason
  in the start check's output; a start after the limit resets fetches again.
- If dnsmasq exits after a successful start, name lookups fail until the next start; the recorded result stays.
- When no rule can be loaded at all (no `NET_ADMIN`, for example with a runtime that drops `capAdd`, an entrypoint that
  does not run as root, or a kernel without nftables), outbound traffic is unrestricted and the start check reports it.
- `--network=host` is not supported: the rules would land in the host's network namespace.
- A failed start writes its reason to the container log and to `/run/firewall/status`. A restart applies the rules
  again.

## OS support

See [test/firewall/compatibility.json](../../test/firewall/compatibility.json).
