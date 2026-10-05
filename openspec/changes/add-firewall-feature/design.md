# Design

## Context

Research for this change, checked on 2026-09-30; see `proposal.md` for the motivation.

- **How the dev container CLI runs a feature entrypoint** (`devcontainers/cli`, `src/spec-node/singleContainer.ts`,
  `src/spec-node/imageMetadata.ts`): all entrypoints are joined by newlines into one `/bin/sh -c` script that first
  prints `Container started`, then runs them in metadata order (base image, then features in install order, then
  `devcontainer.json`), then `exec "$@"`. There is no `set -e`, so a failing entrypoint does not stop the container, and
  a hanging one delays the container's command. The script runs as the image's user unless `containerUser` is set;
  `mcr.microsoft.com/devcontainers/base:ubuntu24.04` and the plain distribution images run it as root. The CLI waits for
  Docker's start event, not for the entrypoints, before it runs lifecycle commands, so `postCreateCommand` and
  `postStartCommand` can begin while an entrypoint still runs. When a feature's lifecycle command fails, the CLI prints
  "Skipping any further user-provided commands" and runs none of the user's later hooks
  (`src/spec-common/injectHeadless.ts`). The `wslc` CLI variant drops `--cap-add`, `--privileged`, `--init`, and
  `--security-opt`.
- **Metadata merge**: the Features spec says `capAdd` is concatenated; the CLI takes a de-duplicated union. Docker's
  default capability set already includes `NET_RAW` (`moby/moby`, `daemon/pkg/oci/caps/defaults.go`).
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
  majors: docker-in-docker 4, common-utils 2. When `/etc/resolv.conf` names `internal.cloudapp.net`, as on Azure hosts,
  and its option `azureDnsAutoDetection` is `true` (the default), `docker-init.sh` starts `dockerd` with
  `--dns 168.63.129.16`.
- **Nested containers' lookups** (observed on an Azure host on 2026-10-01: `debian:12`, nested Docker 29.8.1, `presets`
  `npm`, `allowedCidrs` `185.199.108.0/22`, `filterForward` omitted). With docker-in-docker's defaults, `dockerd` runs
  with `--dns 168.63.129.16`, which is also the dev container's recorded resolver: a user-defined network's embedded DNS
  forwards to it and the default bridge's `resolv.conf` names it, so on both networks names resolve and dnsmasq learns
  nothing. `registry.npmjs.org` is refused until the dev container itself looks it up, `github.com` is refused, and
  `185.199.109.133` is reachable; after a re-run of the start-time script with the `github` preset, `github.com` is
  reachable through the fetched ranges. With `azureDnsAutoDetection` `false`, `dockerd` runs without `--dns`: a
  user-defined network's embedded DNS forwards to the dev container's `127.0.0.1`, dnsmasq learns the addresses, and
  `registry.npmjs.org` is reachable (3 of 3 runs of the start-time script); default-bridge containers get `8.8.8.8` and
  `8.8.4.4`, where no name resolves and `185.199.109.133` is still reachable. Denied names follow the same lookups (same
  host and day, one container per configuration, `presets` empty). With docker-in-docker's defaults, `defaultAction`
  `allow`, and `deniedDomains` `registry.npmjs.org`, a nested container on either network reaches `registry.npmjs.org`
  (HTTP 200) while the denied set stays empty and the dev container itself is refused; after the dev container's own
  lookup the nested container is refused too (2 of 2). With `allowedCidrs` `185.199.108.0/22` and `deniedDomains`
  `raw.githubusercontent.com`, a nested container on either network reaches `raw.githubusercontent.com` (HTTP 301) and
  is refused `github.com`. With `defaultAction` `allow` and `deniedCidrs` `185.199.108.0/22`, it is refused
  `185.199.109.133` and reaches `github.com`. With `azureDnsAutoDetection` `false`, `defaultAction` `allow`, and
  `deniedDomains` `registry.npmjs.org`, a nested container on a user-defined network is refused `registry.npmjs.org` on
  its first request and reaches `github.com`; on the default bridge no name resolves. A host other than Azure was not
  observed: that `dockerd` runs without `--dns` there follows from `docker-init.sh`.
- **Prior art** (`anthropics/claude-code`, `.devcontainer/`): `runArgs` add `NET_ADMIN` and `NET_RAW`;
  `postStartCommand: sudo /usr/local/bin/init-firewall.sh` with a sudoers line for that script; the script flushes the
  filter, nat, and mangle tables, restores Docker's DNS NAT rules, builds an ipset from GitHub meta `web`, `api`, `git`
  (through `aggregate`) and resolved domains, and self-checks that `example.com` fails and `api.github.com` succeeds. It
  leaves UDP 53 and TCP 22 open to any host, the host's /24 open both ways, and IPv6 unfiltered. Other published
  firewall features (`w3cj`, `blacktop`, `gus-costa`) use `postStartCommand` with `sudo`; `src/egress-filter` in
  `nshafer/devcontainer-features` uses a root entrypoint, a squid proxy, and `DOCKER-USER`, and its entrypoint always
  exits zero.
- **GitHub meta** (https://api.github.com/meta, 201,132 bytes, unauthenticated rate limit 60 requests per hour per IP,
  confirmed by its `x-ratelimit-limit` header): `web` 40, `api` 26, `git` 60 entries, each list with IPv6 ranges (for
  example `2a0a:a440::/29` in `git`); `web` includes `185.199.108.0/22`, where `raw.githubusercontent.com`,
  `objects.githubusercontent.com`, and `release-assets.githubusercontent.com` resolve, and `2606:50c0::/32`.
  `domains.website` lists `*.github.com` and `*.githubusercontent.com`. The shortest prefixes across the three lists are
  /20 for IPv4 and /29 for IPv6 (checked 2026-09-30, 80 distinct entries). GitHub Pages sites (`pages.github.io`,
  185.199.108.153 to 185.199.111.153) resolve inside `185.199.108.0/22`.
- **dnsmasq `--nftset`** (dnsmasq manual): adds the addresses of every answer for the listed domains and their
  subdomains to existing nftables sets, `4#` or `6#` selecting the address family. dnsmasq keeps `CAP_NET_ADMIN` after
  dropping privileges when nftsets are configured (`src/dnsmasq.c`, dnsmasq 2.91 as packaged by Ubuntu). Fedora's
  `/etc/dnsmasq.conf` includes `/etc/dnsmasq.d`. Of the `--nftset` entries whose domain matches a reply's question name,
  dnsmasq applies only the one with the longest domain, the later one on a tie (`domain_find_sets` in `src/forward.c`,
  read in Debian's packaging repository at 2.89 and in the upstream mirror `imp/dnsmasq` as of 2026-03); the manual
  states that rule for `--server` and `--address` only. The packages create a `dnsmasq` system user
  (`debian/dnsmasq-base.postinst`, Alpine's `dnsmasq.pre-install`, Fedora's `dnsmasq-systemd-sysusers.conf`).
- **Kernel**: rules live in the host kernel. The WSL2 kernel `6.18.33.2-microsoft-standard-WSL2` has `nf_tables` with
  the `inet` family built in. GitHub-hosted runner kernels and Docker Desktop kernels were not checked; the first CI run
  on each architecture checks them.
- **Hosts the presets' sources list and the presets leave out** (re-read 2026-09-30):
  https://code.claude.com/docs/en/network-config also names `claude.com`, `mcp-proxy.anthropic.com`,
  `downloads.claude.ai`, `storage.googleapis.com`, `bridge.claudeusercontent.com`, `*.frame.claudeusercontent.com`,
  `formulae.brew.sh` (Homebrew installs only), `code.claude.com`, and, as optional, `*-review.googlesource.com` and two
  Datadog telemetry hosts; it also names `github.com`, `raw.githubusercontent.com`, and `registry.npmjs.org`, which the
  `github` and `npm` presets cover. https://code.visualstudio.com/docs/setup/network also names `code.visualstudio.com`,
  `go.microsoft.com`, `rink.hockeyapp.net`, `vsmarketplacebadges.dev`, `download.visualstudio.microsoft.com`,
  `vscode-sync.trafficmanager.net`, `vscode-sync-insiders.trafficmanager.net`, `vscode.dev`, `*.vscode-unpkg.net`, and
  `default.exp-tas.com`, and `raw.githubusercontent.com`, which the `github` preset covers. `domains.website` of GitHub
  meta also lists `*.githubassets.com`, `*.github.io`, and `*.github.dev`; `*.github.io` is reachable anyway by address
  through the `web` range.
- **Docker Hub blobs**: an anonymous blob request to `registry-1.docker.io` redirected to
  `production.cloudfront.docker.com`, which Docker's allowlist page
  (https://docs.docker.com/desktop/enterprise/allow-list/) lists next to `registry-1.docker.io` for pulls and pushes. A
  pull therefore needs two hosts outside the URL inventory, one of them a CDN; tests pull no image (Goals: Test
  destinations).
- **Requirements added after the package was approved at commit `01d7e82`** (the knowledge base on `main` on
  2026-10-05): `.agents/knowledge/shell-style.md`, `.agents/knowledge/review-guidance.md`, the sections "Developer trust
  and readability" and "User documentation" of `.agents/knowledge/feature-authoring.md`, and "Test intent and
  readability", the POSIX stand-in `test/<id>/checks.sh`, and `scenarioArchitectures` in `.agents/knowledge/testing.md`.
  The scripts under `src/firewall/` and `test/firewall/` and `src/firewall/NOTES.md` were written before them: on
  2026-10-05, plain `shellcheck` reported nothing on the branch's scripts, and
  `shellcheck -o require-variable-braces,require-double-brackets` reported 391 findings (284 in the four shipped
  scripts, 107 in the test scripts). Where this design names the shell style guide, or says what a comment in a script
  marks, it describes the scripts as sections 5 to 8 of `tasks.md` leave them.

Packages on the planned images, verified on 2026-09-30 for amd64 and arm64:

| Image                                              | nftables          | dnsmasq with nftset support                                                                   | Also installed                  |
| -------------------------------------------------- | ----------------- | --------------------------------------------------------------------------------------------- | ------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | `1.0.9-1build1`   | `dnsmasq-base` `2.91-0ubuntu0.24.04.1` (`noble-updates`); `debian/rules` adds `-DHAVE_NFTSET` | `curl`, `jq`, `ca-certificates` |
| `debian:12`                                        | `1.0.6-2+deb12u2` | `dnsmasq-base` `2.90-4~deb12u2`; `debian/rules` adds `-DHAVE_NFTSET`                          | `curl`, `jq`, `ca-certificates` |
| `alpine:3.24`                                      | `1.1.6-r1`        | `dnsmasq-dnssec-nftset` `2.92_p2-r0`; plain `dnsmasq` lacks `HAVE_NFTSET` (`APKBUILD`)        | `curl`, `jq`, `ca-certificates` |
| `fedora:44`                                        | `1.1.6-2.fc44`    | `dnsmasq` `2.92rel2-9.fc44`; `dnsmasq.spec` adds `-DHAVE_NFTSET`                              | `curl`, `jq`, `ca-certificates` |

Sources: packages.debian.org, packages.ubuntu.com, pkgs.alpinelinux.org (v3.24, x86_64 and aarch64),
mdapi.fedoraproject.org (f44), and the packaging files on sources.debian.org, git.launchpad.net
(`ubuntu/noble-updates`), git.alpinelinux.org (`3.24-stable`), and src.fedoraproject.org (`f44`). These supersede the
earlier research brief, which had Ubuntu's `2.90-2ubuntu0.4` from an older `noble` pocket, Alpine 3.22, and Fedora 43,
and left Ubuntu's and Fedora's `HAVE_NFTSET` unverified. `alpine:3.24` is the current Alpine (same digest as `latest`)
and `fedora:44` the current Fedora (same digest as `latest`); both and `debian:12` publish amd64 and arm64 images
(docker-library `official-images`), and `base:ubuntu24.04` publishes both (`docker buildx imagetools inspect`).

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
  load recreates the learned sets empty. With `defaultAction` `allow`, nothing is fetched and the full table replaces
  the closed one directly. No later step deletes the table except `failureMode` `warn` on failure; with `closed`, a
  failure after the full load, such as dnsmasq failing to start, replaces the full table with the closed one (without
  `api.github.com`) in one transaction. Checked: review of the script's order, and the `fetch_fails` scenario.
- **Chains.** Base chains: `output` and, with `filterForward`, `forward`, both at filter priority with policy drop; no
  `input` chain. Both run, in this order: accept established and related connections; accept ICMPv6 types 133–136
  (neighbour and router discovery) only with hop limit 255 and 143 (MLDv2 reports) only with hop limit 1, the values RFC
  4861 and RFC 3810 require, so none of them can leave the link; accept DNS (UDP and TCP 53) to the recorded resolvers
  and reject all other DNS; accept traffic to the nested bridges (`docker0`, `br-*`); reject `192.0.2.1`; then one rule
  pair per prefix length, from /32 and /128 down to /0, the reject rule for that length's denied entries before the
  accept rule for its allowed ones, each matching an anonymous set of those entries (deduplicated, since GitHub's lists
  repeat ranges), with the learned sets in the /32 and /128 pairs; last, an accept or a reject by `defaultAction`.
  `output` first accepts everything leaving through `lo`, which covers Docker's DNAT of `127.0.0.11`. Ordering by prefix
  length yields the longest match without computing range differences, and a same-length tie refuses. Checked: the
  `rerun` scenario asserts the chain contents with `nft -j list table`; the `denied_cidrs`, `denied_domains`, and `dind`
  scenarios.
- **Bounded start.** The start-time script ends within 60 seconds even when the network is unreachable: the lookup of
  `api.github.com` is bounded at 5 seconds, the GitHub fetch at 20 seconds per attempt with at most two attempts (only
  after a connection error or timeout; an HTTP error status, including a rate-limit response, is not retried) and at 2
  MiB of response, and dnsmasq must answer within 5 seconds of its start. The check waits at most 90 seconds for the
  current start's record, longer than the script's bound, so a slow start that succeeds is never reported missing.
  Checked: review, and the `fetch_fails` scenario measures the script's run time.
- **Learned addresses in their own sets.** Addresses dnsmasq learns go to four named sets (allowed and denied, IPv4 and
  IPv6), separate from the configured and fetched ranges, so a learned address inside a range never makes an insert
  fail. Each domain entry gets one `--nftset` line naming only its own verdict's sets, so dnsmasq's longest match
  (Context) decides between an allowed domain and a denied one; a name in both lists gets only the denied line. Checked:
  the `github_npm` scenario connects to `raw.githubusercontent.com`, which resolves inside a fetched `web` range; the
  `denied_domains` and `denied_in_range` scenarios.
- **Rejected, not dropped.** Refused outbound TCP connections get a TCP reset (connection refused), other protocols ICMP
  administratively prohibited, so they fail at once. The check accepts only a refused TCP connection to `192.0.2.1:443`
  within 3 seconds as proof; a timeout or an unreachable network means the firewall is not in force. Checked: `test.sh`
  times a refused connection (under one second).
- **Only root-owned inputs at start.** The start-time script reads only the configuration written by `install.sh` under
  `/usr/local/share/firewall/`, `/etc/resolv.conf`, its root-owned state directory, and the GitHub response; it sets its
  own `PATH` and ignores its environment. Every file it reads is owned by root and not writable by others. Checked:
  `test.sh` asserts owner and mode of each file, and the `rerun` scenario covers "Environment does not change the
  rules".
- **The check ignores its environment.** The check re-executes itself under `env -i` with a fixed `PATH` before doing
  anything else, calls every tool by absolute path, and reads no file the remote user can write. In `check.sh` and in
  `apply.sh`, which clears its environment the same way, the re-execution is the script's first lines, before `set -eu`,
  the constants, and the functions: a deliberate deviation from the layout `.agents/knowledge/shell-style.md`
  (Skeletons) gives an executable script, so that no line of the script, the sourcing of the library included, runs
  under the inherited environment; a comment above the re-execution gives this reason. The first process still starts
  under the environment the dev container tool probed, so a dynamic-loader variable such as `LD_PRELOAD` acts before the
  re-execution (Risks). Checked: the `rerun` scenario runs the check with a `PATH` that shadows its tools and with `ENV`
  and `BASH_ENV` set.
- **dnsmasq runs only from its own configuration.** It starts with a root-owned configuration file written at start (the
  allowed domains, the learned sets, and the recorded resolvers as upstream servers), reads neither the distribution's
  `/etc/dnsmasq.conf` nor a configuration directory nor `/etc/resolv.conf`, and listens on `127.0.0.1` only, with
  `--bind-interfaces`, so a port another process already holds makes it exit with an error; the start then fails before
  `/etc/resolv.conf` names it. It runs as the `dnsmasq` user its package creates (Context) and keeps only
  `CAP_NET_ADMIN`, to add to the sets. It is not supervised. Checked: review; the `rerun` scenario asserts its command
  line; `test.sh` asserts its user; the `fetch_fails` scenario takes the port first.
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
  CIDR with host bits set, `0.0.0.0/0` in `allowedCidrs`, a wildcard domain, `*` alone in `allowedDomains`, and a
  malformed entry, one with host bits set, and a wildcard domain in `deniedCidrs` and `deniedDomains`. The same
  validator checks each fetched GitHub range, with the minimum prefixes of Decisions; `test.sh` runs it against fixture
  responses.
- **Option values reach the generated files only in validated form.** The start-time script writes two files that
  another program then reads: the ruleset for `nft -f` (One owned table, replaced atomically) and dnsmasq's
  configuration (dnsmasq runs only from its own configuration). No option value is written to either as given: a CIDR
  entry is written as the validator prints it again from the numbers it parsed, a domain entry in lower case and only
  after each of its labels matched the validator's pattern for a DNS label, and `presets`, `defaultAction`, and
  `filterForward` only select fixed text; the stored options are validated again at every start before either file is
  written. This is the one deliberate deviation from the rule of `.agents/knowledge/shell-style.md` (Options are data)
  that an option value never reaches a script the feature generates: the single-transaction load and dnsmasq's own
  configuration file each need a generated file, and the validated forms cannot carry a directive of either format. A
  comment above each of the two generators gives this reason. Checked: review of the validator and the two generators.
- **The entrypoint always exits zero.** `apply.sh` ends with status 0 whether the start is applied, failed, or not
  applied: the result reaches the user through the start record and the start check (Requirement: Failure mode,
  Requirement: Start check), never through the entrypoint's status, so a tool that stops at a failing entrypoint still
  runs the container's command. The script therefore defines no `fail` that exits 1, which
  `.agents/knowledge/shell-style.md` (Logging and failure) asks of every executable shipped script. Its failed-start
  handler has a name of its own, so no function called `fail` means something else, and a comment at the handler marks
  the deviation with this reason; `log` writes to standard output, as the guide says. Checked: review of every exit of
  the script.
- **Idempotent install.** `install.sh` overwrites its configuration and scripts, installs packages only when missing,
  and adds no line to any shared file. Checked: `duplicate.sh` installs with non-default options (without the `github`
  preset, with `defaultAction` `allow` and denied entries), then defaults, and asserts that the defaults are in effect.
- **Distribution packages only.** No URL is fetched at build time; packages come from the image's configured
  repositories with the package manager's default verification. Checked: review of `install.sh` against the URL
  inventory below.
- **Test destinations.** Tests connect only to hosts in the URL inventory: `github.com`, `api.github.com`, and
  `raw.githubusercontent.com` as allowed hosts, `registry.npmjs.org` as allowed with the `npm` preset, as denied with
  `deniedDomains`, and as the host no entry names otherwise. Connections to a literal address use one of
  `raw.githubusercontent.com`'s (`185.199.108.133` to `185.199.111.133`) with that name as the TLS server name.
  Addresses that the rules refuse inside the container (`192.0.2.1`, `8.8.8.8` on port 53) are never reached. Nested
  containers run an image imported from the dev container's own filesystem, so no test pulls from a registry. Checked:
  review of the test scripts against the inventory.
- **GitHub fetches in tests stay within the rate limit.** Only a start with the `github` preset and `defaultAction`
  `deny` fetches. Each compatibility job starts two containers with the defaults (`test.sh` and the final install of
  `duplicate.sh`) and so fetches twice; the scenario job fetches at most seven times, because scenarios that do not test
  GitHub behaviour select other presets or `defaultAction` `allow`; a full local run (`just test firewall` on one
  architecture and `just test-scenarios firewall`) fetches at most 15 times from one address, so four full runs fit in
  GitHub's hourly limit. A rate-limited start fails with the reason in the check's output, so a red job names its cause;
  a re-run after the limit resets is the remedy. Tests carry no token. Checked: the scenario list below; the first CI
  run.
- **Scripts follow the shell style guide.** Every `*.sh` under `src/firewall/` and `test/firewall/` follows
  `.agents/knowledge/shell-style.md` as written. The only deliberate deviations are the ones this design names, each
  marked in the script by a comment that gives its reason: option values in the two generated files, the entrypoint's
  exit status, and the re-execution under `env -i` (the Goals above that state them), and the labels of the checks that
  verify a Goal (Test coverage). Two more kinds are marked the same way: each `# shellcheck disable` a script keeps for
  one line, which the guide counts as a deviation, and the labels of the three checks that assert a test's premise, for
  as long as Open Questions 13 stands as written. Checked:
  `shellcheck -o require-variable-braces,require-double-brackets` reports nothing on those files, and a review against
  the guide, rule by rule.

**Non-Goals:**

- A security boundary: root or `sudo` in the container can delete the table; DNS lookups can carry data; allowed CDN and
  GitHub ranges carry other tenants' content; the agent can edit `.devcontainer/` for the next build.
- Restricting a remote user who has privilege. The guardrail assumes a remote user without root, passwordless `sudo`, or
  access to a Docker daemon. The `vscode` user of `base:ubuntu24.04` has passwordless `sudo`, so there the rules are
  removable by default; with docker-in-docker, membership in the `docker` group is root-equivalent, and a nested
  `--privileged` container or a `macvlan` network on the dev container's interface bypasses the rules. `NOTES.md` states
  this first.
- Inbound filtering, host firewalling, and filtering traffic between the container and bridges that exist only inside it
  (a nested Docker's `docker0` and `br-*`).
- A nested container reaching an allowed domain (maintainer decision of 2026-10-01) or, from the same cause, being
  refused a denied one (Open Questions): the feature protects the dev container's own traffic, and nested Docker is an
  exception `NOTES.md` records (Decisions: Nested Docker).
- Filtering by DNS name (every name resolves), by TLS SNI, or through an HTTP proxy.
- A denylist that holds against a process avoiding the container's resolver: `deniedDomains` refuses only addresses
  learned from lookups of denied names, so literal addresses, DNS over HTTPS, and names that are not denied pass it
  where `defaultAction` is `allow`.
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
  every answer for an allowed or denied domain to that verdict's learned sets, so CDN rotation and subdomains work.
  Packages: `dnsmasq-base` on Debian and Ubuntu (no service scripts), `dnsmasq-dnssec-nftset` on Alpine, `dnsmasq` on
  Fedora. Rejected: resolving the domains once at start (addresses rotate within minutes on CDNs); an HTTP(S) proxy such
  as squid (much larger, and only tools that honor proxy variables are covered).
- **Closed table, then fetch, then full table** (maintainer decision). The GitHub ranges are fetched under the closed
  table and validated before the full table is built. Rejected: fetching before any rule is loaded, which leaves egress
  open during the fetch; loading the full table without the ranges and adding them later, which makes "applied" mean two
  different rule sets.
- **An explicit `defaultAction`** (maintainer decision). One option decides what no entry matches, so the mode is
  visible in the configuration, the start record, and the check's summary, and a later mode is a new `enum` value.
  Rejected: `*` in `allowedDomains` as the switch, which hides a mode inside a list, makes one domain entry open literal
  addresses too, and needs an exception to the domain validation.
- **The longest match decides, a tie refuses** (maintainer decision). The same rule as a routing table, applied to
  allowed and denied CIDRs, preset ranges, and learned addresses (each a single address), and to overlapping allowed and
  denied domains through dnsmasq. Rejected: denied always winning, which cannot open one address inside a denied range,
  such as a Compose service inside a DMZ; allowed always winning, which cannot carve an address out of an allowed range.
- **Denied domains through learned sets.** A denied name resolves, and its addresses are refused, so it fails as a
  refused connection like every other refusal. Rejected: an NXDOMAIN answer (dnsmasq `--address=/name/`), which makes a
  denied name look like a typo and contradicts "every name resolves"; resolving denied names once at start (addresses
  rotate on CDNs).
- **No GitHub fetch with `defaultAction` `allow`.** The fetched ranges only allow, and with `allow` they would matter
  only against a shorter denied entry; the preset's domains still take part. Rejected: fetching anyway, which spends the
  rate limit and can fail a start for rules that change nothing in the usual case.
- **GitHub ranges from `web`, `api`, `git`.** They cover the web UI, the REST API, and Git over HTTPS and SSH. Rejected:
  `actions`, `codespaces`, and `copilot`, which are large cloud-provider ranges; `packages` (GHCR), left to
  `allowedDomains`.
- **DNS only to the recorded resolvers and `127.0.0.11`** (maintainer decision), under both default actions and whatever
  the allowed entries say, so asking another resolver cannot sidestep dnsmasq's learned sets. Rejected: port 53 to any
  address (prior art), which lets any process pick an arbitrary resolver.
- **Failure modes.** `closed` leaves the closed table (without `api.github.com`) and makes the check fail: it keeps the
  table when the failure comes before the full load and reloads it when the failure comes after; `warn` deletes the
  table and makes the check warn. `closed` keeps DNS to the recorded resolvers: it is the table every start already runs
  under, so a failure adds no third rule set, and DNS is equally reachable in the applied state, so a failed start opens
  nothing for DNS tunnelling that an applied one closes. Rejected: `warn` keeping a partial table, which is neither the
  configured policy nor unrestricted and is hard to reason about; `closed` as loopback only (the research brief's
  wording), which would need its own table and leaves the failed container unable to resolve names for diagnosis.
- **Minimum prefix for fetched ranges: /8 for IPv4, /16 for IPv6.** Fetched entries pass the `allowedCidrs` checks and
  these minimums, far above GitHub's /20 and /29 (Context), so a wrong or subverted response cannot open a wide range
  unnoticed; with `192.0.2.1` always refused, the check would no longer notice one. Rejected: syntax only (the audit on
  this PR); a bound close to today's prefixes, which fails starts on a legitimate change for little gain.
- **No warning for broad `allowedDomains` entries.** `NOTES.md` explains that an entry allows every name under it.
  Rejected: a warning for single-label entries, which are also Compose service names; a public suffix list, which the
  feature would have to download or ship.
- **Start check probes a documentation address.** The unprivileged check connects to `192.0.2.1` (TEST-NET-1) on port
  443 and expects an immediate refusal, which only the firewall's reset produces; without the firewall the attempt times
  out or finds no route, and no real host is contacted either way. The table rejects that address before any allowed
  entry, so the probe proves the rules under both default actions, and `allowedCidrs` rejects ranges containing it
  because such an entry could not take effect as written. The check cannot list the ruleset because it runs without
  `NET_ADMIN`. Rejected: probing `example.com` (prior art), a real third party that a user may allowlist; also probing
  an allowed host, which would fail container start on transient network errors.
- **Nested Docker: filtered, with no guarantee for allowed or denied domains** (maintainer decision of 2026-10-01 for
  allowed domains; denied domains follow from the same cause, see Open Questions). With `filterForward`, forwarded
  traffic meets the same rules; output to `docker0` and `br-*` is accepted because anything leaving those bridges for
  the outside is forwarded and filtered, and forwarding into those bridges is accepted so published ports of nested
  containers and traffic between nested networks work. From a nested container, what the entries state by address holds:
  an address inside `allowedCidrs` or a preset's ranges is reachable, one inside `deniedCidrs` is refused, and, with
  `defaultAction` `deny`, a destination no entry allows is refused. A domain is allowed or denied only at the addresses
  dnsmasq has learned, so only when the nested container's lookup passes through the dev container's dnsmasq; a nested
  daemon started with its own DNS servers, as docker-in-docker does on Azure hosts (Context), sends lookups past it.
  Under such a daemon an allowed domain is refused (fail closed), and a denied domain is reached wherever
  `defaultAction` `allow` or an allowed range lets its address through (fail open), each until the dev container's own
  lookup has taught dnsmasq the address. The feature protects the dev container's own traffic and `NOTES.md` records
  nested Docker as an exception; `filterForward` and its default stay as they are. Rejected for now: handling nested
  lookups in the feature, which the maintainer judged complex.
- **`installsAfter` docker-in-docker and common-utils** (maintainer decision). Entrypoint order follows install order,
  so `docker-init.sh` (which switches `iptables` alternatives and starts `dockerd`) has run before the firewall loads.
  `common-utils` declares no entrypoint; ordering after it is install order only, so the feature installs its packages
  after common-utils has created the remote user and upgraded packages (`upgradePackages`), and the "No sudoers entry"
  test sees common-utils' final sudoers and groups. Neither is a functional dependency, so no `dependsOn`. References
  use the full GHCR refs without a tag.
- **Option shape.** Names, types, and defaults are maintainer decisions. Every option is new; the delta spec's Option
  requirements are normative and win where this table differs:

  | Option           | Type    | Default    | Enum or proposals                                                  | Meaning                                                                                                                                                 |
  | ---------------- | ------- | ---------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | `defaultAction`  | string  | `"deny"`   | enum `"deny"`, `"allow"`                                           | What happens to traffic no allowed or denied entry matches                                                                                              |
  | `presets`        | string  | `"github"` | proposals `"github"`, `"npm"`, `"pypi"`, `"anthropic"`, `"vscode"` | Comma-separated named destination sets to allow                                                                                                         |
  | `allowedDomains` | string  | `""`       | none                                                               | Comma-separated domains to allow, each with every subdomain                                                                                             |
  | `allowedCidrs`   | string  | `""`       | none                                                               | Comma-separated IPv4 or IPv6 addresses or CIDRs to allow                                                                                                |
  | `deniedDomains`  | string  | `""`       | none                                                               | Comma-separated domains to refuse, each with every subdomain                                                                                            |
  | `deniedCidrs`    | string  | `""`       | none                                                               | Comma-separated IPv4 or IPv6 addresses or CIDRs to refuse                                                                                               |
  | `failureMode`    | string  | `"closed"` | enum `"closed"`, `"warn"`                                          | When the rules cannot be applied in full: closed keeps only loopback and DNS reachable and fails the start check; warn removes the rules and only warns |
  | `filterForward`  | boolean | `true`     | none                                                               | Apply the rules to traffic the container forwards, such as that of nested containers                                                                    |

  Defaults: `defaultAction` is `"deny"`, so the feature is an allowlist unless a user opts out, which is what surfaces
  unexpected egress. `presets` is `"github"` by the maintainer's decision (Open Questions 2). `allowedDomains` and
  `allowedCidrs` are empty, so nothing beyond the presets is allowed unless named; `deniedDomains` and `deniedCidrs` are
  empty, so nothing the allowed entries name is refused unless named. `failureMode` is `"closed"` so a start that cannot
  apply the rules stays restricted and fails loudly, which is what surfaces a firewall that is not in force; `warn` is
  for containers that must start anyway (Risks). `filterForward` is `true` so nested containers' traffic is filtered by
  default, as the proposal states, instead of leaving a nested Docker daemon as an unfiltered way out. Rejected: one
  boolean per preset (`w3cj`), which turns every new preset into a new option.
- **POSIX `sh`.** Alpine ships no bash, so `install.sh` and the start-time scripts use `#!/bin/sh` with `set -eu`, as
  `.agents/knowledge/shell-style.md` (Choosing bash or POSIX sh) requires of a feature whose compatibility list holds
  such an image; the library `scripts/common.sh` is POSIX `sh` too. `test.sh` and `duplicate.sh` run on every
  compatibility image, so they are POSIX `sh` with the stand-in `test/firewall/checks.sh`; the scenario scripts run only
  on `debian:12` and are bash with `dev-container-features-test-lib` (Decisions of 2026-10-05).
- **Shell style.** The scripts follow `.agents/knowledge/shell-style.md` (Goals: Scripts follow the shell style guide);
  this entry holds only what the guide leaves open for this feature.
  - Files: three executables, because each runs at another time and as another user (`install.sh` at build time,
    `apply.sh` as the entrypoint, `check.sh` as the unprivileged `postStartCommand`), and one library,
    `scripts/common.sh`, so the build and every start validate with one copy of the rules (Goals: Validated options,
    twice). `install.sh` sources it next to itself, `apply.sh` sources the root-owned copy under
    `/usr/local/share/firewall/`, and `check.sh` sources nothing.
  - Lists: an option's list is split on commas only. Whitespace around an entry, line breaks included, is ignored, and
    each entry is matched as a whole, so a line break inside an entry fails it, as the Option requirements'
    comma-separated lists state. The validator on the branch also splits on line breaks, so it accepts `github` and
    `npm` on two lines as two presets; `tasks.md` corrects it.
  - Package managers: each update or install command of apt, apk, and dnf ends in the guide's `|| fail` and keeps its
    own output, so the build still fails with the package manager's error (Requirement: Supported images), followed by
    the feature's own line.
  - Known failure modes handled, each under a comment naming it: a connection error or timeout of the GitHub fetch (one
    more attempt, Goals: Bounded start) and a `sleep` that takes no fractional seconds. The EXIT trap of `apply.sh` is
    Requirement: Failure mode applied to any stop of the script, not a recovery from an unknown error.

### Security review surface

- **Downloads at build:** none. Packages come from the image's configured repositories, verified by apt, apk, or dnf
  signatures (the package-manager download rule in `feature-authoring.md`); the feature adds no repository and no key.
- **Fetch at start:** `https://api.github.com/meta`, only with the `github` preset and `defaultAction` `deny`. GitHub
  publishes no checksum or signature for it, so under the direct-download rule in `feature-authoring.md` it relies on
  TLS alone, verified against the image's CA bundle, and the spec states this (Requirement: GitHub ranges). Bounded time
  and size, connection pinned to the addresses in the closed table, every entry parsed as an IPv4 or IPv6 CIDR before
  use, whole response rejected on any invalid entry. It is data, never executed.
- **Long-running process:** dnsmasq parses DNS answers from the network and keeps `CAP_NET_ADMIN` to add learned
  addresses to the sets. It runs as the `dnsmasq` user, listens on `127.0.0.1` only, and reads only its root-owned
  configuration; a flaw in it that an answer can exploit could change or flush the rules, which the spec states as a
  guardrail limit (Requirement: Guardrail, not a security boundary).
- **Keys:** none.
- **Options:** no option value is executed, sourced, or used as a path, URL, or command name. `defaultAction`,
  `failureMode`, and `filterForward` are matched against their whole value, and a `presets` entry only selects a fixed
  set (Requirement: Presets). Every list entry is validated at build and again at start (Goals: Validated options,
  twice). Option values are written to the root-owned options file, the start record, and the build and container logs;
  beyond those, only the validator's canonical form of a CIDR entry reaches the nftables ruleset and only that of a
  domain entry reaches the dnsmasq configuration, the one place where an option value reaches an interpreter other than
  as an argument (Goals: Option values reach the generated files only in validated form). No option changes the
  container metadata, a user, a group, or a file mode. Every value that loosens the guardrail is a named option visible
  in `devcontainer.json`: `defaultAction` `allow`, `failureMode` `warn`, `filterForward` `false`, and broad
  `allowedDomains` or `allowedCidrs` entries. The start record, readable by every user of the container, holds the
  option values and the recorded resolvers and no credential.
- **Metadata:**

| Field                                                         | Value                                                                                            | Justification                                                                            |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| `capAdd`                                                      | `NET_ADMIN`                                                                                      | Loading nftables rules at start; dnsmasq adding learned addresses to the sets            |
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

| Image                                              | `remoteUser` | Why                                                         |
| -------------------------------------------------- | ------------ | ----------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | `vscode`     | The usual dev container base; tests the check without root  |
| `debian:12`                                        | (none)       | Plain Debian; the scenarios' image, where tests run as root |
| `alpine:3.24`                                      | (none)       | musl, BusyBox, and the `dnsmasq-dnssec-nftset` subpackage   |
| `fedora:44`                                        | (none)       | dnf-based distributions                                     |

Architecture does not change the rules, which live in the host kernel; the second architecture covers packaging.

### Test coverage

The harness cannot stop and start a container, reach it from outside, pass a build that must fail, or use IPv6 (Docker
on the runners has none by default), and a failing `postStartCommand` fails the container's start. Scenarios therefore
start with a configuration that succeeds and then, as root, re-run the start-time script under the condition to test.
Planned scenarios, all on `debian:12` (amd64) where the test runs as root: `domains` (`presets` empty, `allowedDomains`
`githubusercontent.com`), `cidrs` (`presets` empty, `allowedCidrs` `185.199.108.0/22,2606:50c0::/32`, `deniedCidrs`
`185.199.108.133/32`), `github_npm`, `rerun` (defaults), `fetch_fails` (defaults), `warn` (`failureMode` `warn`), `dind`
(with docker-in-docker, `presets` `npm`, `allowedCidrs` `185.199.108.0/22`), `dind_no_forward` (with docker-in-docker,
`filterForward` false, `presets` `npm`), `allow_all` (`defaultAction` `allow`, `deniedCidrs`
`10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16,100.64.0.0/10,fc00::/7,fe80::/10`), `denied_cidrs`
(`defaultAction` `allow`, `presets` empty, `allowedCidrs` `185.199.109.133/32,185.199.110.0/24`, `deniedCidrs`
`185.199.108.0/22,185.199.110.0/24`), `denied_domains` (`defaultAction` `allow`, `presets` empty, `allowedDomains`
`raw.githubusercontent.com`, `deniedDomains` `githubusercontent.com,registry.npmjs.org`, `deniedCidrs`
`185.199.108.0/22`), and `denied_in_range` (`deniedDomains` `raw.githubusercontent.com`). `rerun` re-runs the script
once, after stopping dnsmasq, deleting the feature's table, leaving `resolv.conf` naming dnsmasq, adding a table of its
own, and setting variables named like the options, then runs the check with a `PATH` that shadows its tools and with
`ENV` and `BASH_ENV` set. `fetch_fails` also re-runs the script after an unprivileged process binds `127.0.0.1:53`. A
"Validation" entry is a run recorded in the PR's Validation section.

Some checks verify a Goal that no spec scenario states: that `/etc/resolv.conf` names the local resolver after an
applied start and that the recorded resolvers are the record's (Resolvers recorded once per container), the resolver's
command line and configuration (dnsmasq runs only from its own configuration), the order of the rules (Chains), the
60-second bound (Bounded start), the learned sets (Learned addresses in their own sets), and the table still in place
beside a nested container (One owned table, replaced atomically). Each keeps its place, is labelled in the words of its
Goal, and is marked in the script by a comment naming that Goal: a deviation from the rule of
`.agents/knowledge/shell-style.md` (Tests) that a label uses the words of the spec, made because the delta spec states
behavior and these are invariants of the approach.

| Scenario of the spec                                                                                                                        | Covered by                                                                                                                                    |
| ------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Supported image                                                                                                                             | `test.sh` on every image                                                                                                                      |
| Unsupported distribution                                                                                                                    | Validation: `devcontainer build` on an image of an unsupported distribution                                                                   |
| Package verification fails                                                                                                                  | Validation: `devcontainer build` from a Dockerfile that removes the image's archive keys                                                      |
| No repository added                                                                                                                         | Review of `install.sh`; `test.sh` asserts no repository or key file names the feature                                                         |
| Unknown preset, Malformed CIDR, CIDR that cannot be applied as written, Malformed denied domain, Malformed denied CIDR                      | Validation: `devcontainer build` runs (Goals: Validated options, twice)                                                                       |
| First start                                                                                                                                 | `test.sh` (record of the current start is `applied`); ordering by review of the entrypoint                                                    |
| Restart re-applies the same rules                                                                                                           | `rerun`; Validation: `docker restart`, then the check as the remote user                                                                      |
| Allowed domain is reachable, GitHub preset, Omitted presets                                                                                 | `test.sh` (`github.com`, `api.github.com`)                                                                                                    |
| Unlisted domain is refused, Omitted defaultAction, Omitted allowedDomains, Omitted allowedCidrs, Omitted deniedDomains, Omitted deniedCidrs | `test.sh` (`registry.npmjs.org`; the ruleset holds no denied entry)                                                                           |
| IPv6 default deny                                                                                                                           | `rerun` asserts the IPv6 rules and the reject in the ruleset; Validation: a container on an IPv6-enabled Docker network                       |
| Inbound connection still answered                                                                                                           | Validation: a published port reached from the host; `rerun` asserts that the table has no `input` chain                                       |
| Subdomain of an allowed domain, No preset                                                                                                   | `domains`                                                                                                                                     |
| Address not obtained through the resolver                                                                                                   | `domains` (a literal address of `github.com`)                                                                                                 |
| IPv4 and IPv6 ranges                                                                                                                        | `cidrs` (IPv4 by connection, IPv6 by ruleset); Validation: IPv6 on an IPv6-enabled Docker network                                             |
| Denied range inside an allowed range                                                                                                        | `cidrs` (`185.199.108.133` refused, `185.199.109.133` reachable)                                                                              |
| Presets combine                                                                                                                             | `github_npm`                                                                                                                                  |
| Ranges loaded                                                                                                                               | `test.sh` (learned sets flushed as root, then a literal `github.com` address)                                                                 |
| Fetch fails                                                                                                                                 | `fetch_fails` (a table of its own drops traffic to `api.github.com`, script re-run)                                                           |
| Implausible range                                                                                                                           | `test.sh` (the range validator against fixture responses)                                                                                     |
| GitHub preset not selected                                                                                                                  | `domains` (the record names no fetch)                                                                                                         |
| Unlisted traffic already let through                                                                                                        | `allow_all` (the record names no fetch)                                                                                                       |
| Other DNS server refused                                                                                                                    | `test.sh` and `allow_all` (TCP to `8.8.8.8` port 53 is refused at once)                                                                       |
| Unlisted name still resolves                                                                                                                | `test.sh` (`registry.npmjs.org` resolves and is refused)                                                                                      |
| Nested container filtered, Nested container reaches an allowed range, Omitted filterForward                                                 | `dind` (`github.com` refused, `185.199.109.133` reachable)                                                                                    |
| Forwarded traffic not filtered                                                                                                              | `dind_no_forward`                                                                                                                             |
| Omitted failureMode, Failed start leaves only the resolvers, Failure reported as an error                                                   | `fetch_fails` (check exits non-zero)                                                                                                          |
| Failed start removes the rules, Failure reported as a warning                                                                               | `warn`                                                                                                                                        |
| Unlisted destination let through                                                                                                            | `allow_all` (`registry.npmjs.org`), `denied_cidrs` and `denied_domains` (`github.com`)                                                        |
| Denied range under open egress                                                                                                              | `denied_cidrs` (`185.199.108.133` refused, `github.com` reachable); `allow_all` asserts the private ranges' rejects in the ruleset            |
| Allowed address inside a denied range                                                                                                       | `denied_cidrs` (`185.199.109.133` reachable, `185.199.111.133` refused)                                                                       |
| Same range allowed and denied                                                                                                               | `denied_cidrs` (`185.199.110.133` refused)                                                                                                    |
| Resolvers inside a denied range                                                                                                             | Validation: a container whose `deniedCidrs` contains its recorded resolver                                                                    |
| Allowed name inside a denied range, Allowed subdomain of a denied domain                                                                    | `denied_domains` (`raw.githubusercontent.com`)                                                                                                |
| Denied domain refused                                                                                                                       | `denied_domains` (`registry.npmjs.org` resolves and is refused)                                                                               |
| Denied subdomain of an allowed domain, Denied name inside an allowed range                                                                  | `denied_in_range` (`raw.githubusercontent.com` refused, `github.com` reachable)                                                               |
| Rules cannot be loaded                                                                                                                      | `fetch_fails` (table deleted, script re-run under `setpriv` without `CAP_NET_ADMIN`)                                                          |
| Resolver port taken                                                                                                                         | `fetch_fails` (port held by an unprivileged process, script re-run: failed record, closed table, `resolv.conf` naming the recorded resolvers) |
| Firewall in force                                                                                                                           | `test.sh` (the check as the remote user)                                                                                                      |
| Stale record                                                                                                                                | `rerun` (record's start time set to an earlier one, check run)                                                                                |
| Changed environment                                                                                                                         | `rerun` (the check with a shadowing `PATH`, `ENV`, and `BASH_ENV`)                                                                            |
| Resolver user                                                                                                                               | `test.sh` (dnsmasq's process runs as `dnsmasq`)                                                                                               |
| Remote user reads the record                                                                                                                | `test.sh` on `base:ubuntu24.04` as `vscode`                                                                                                   |
| No sudoers entry                                                                                                                            | `test.sh`                                                                                                                                     |
| Environment does not change the rules                                                                                                       | `rerun`                                                                                                                                       |
| Other rules untouched                                                                                                                       | `rerun`                                                                                                                                       |
| With docker-in-docker                                                                                                                       | `dind`                                                                                                                                        |
| Metadata of a built container                                                                                                               | `test.sh` (bounding set is Docker's default plus `NET_ADMIN`)                                                                                 |
| Root removes the firewall                                                                                                                   | `rerun` (`registry.npmjs.org` reachable after the table is deleted, before the re-run)                                                        |
| Different options the second time                                                                                                           | `duplicate.sh`                                                                                                                                |
| Same options twice                                                                                                                          | Validation: `install.sh` run twice with the same options in a plain container of each image                                                   |

### Decisions of 2026-10-05

The maintainer decided these points in conversation on 2026-10-05, when the package was revised for the requirements
added to the knowledge base after its approval (Context). The answers settle these points and nothing else: the revised
package returns to the package gate.

- **Option values in the generated ruleset and resolver configuration.** The approach stays and is recorded as the one
  deliberate deviation from the guide's rule that an option value never reaches a script the feature generates, with the
  validation bound that makes it safe and a reason comment above each generator (Goals: Option values reach the
  generated files only in validated form); the implementation does not change and no test is added. Rejected: passing
  every entry as a command argument, which gives up the single-transaction load.
- **A failed start in `apply.sh`.** The entrypoint keeps exit status 0 in every case; the failed-start handler gets a
  name of its own, so no function called `fail` carries other semantics, and the deviation is commented, as the uv
  restyle did for `repair_volume.sh` (Goals: The entrypoint always exits zero). Rejected: exiting 1 through the guide's
  `fail` with an EXIT trap.
- **The re-execution under `env -i`.** It stays as the first lines of `apply.sh` and `check.sh`, a marked deviation from
  the skeleton's layout (Goals: The check ignores its environment). Rejected: making it the first step of `main`.
- **Dialect of the tests.** `test.sh` and `duplicate.sh`, which run on Alpine, are POSIX `sh` with
  `test/firewall/checks.sh`; the twelve scenario scripts, which run only on `debian:12`, are bash with
  `dev-container-features-test-lib` (Decisions: POSIX `sh`). Rejected: every test script POSIX.
- **Checks of a Goal that no spec scenario states.** They stay, each labelled in the words of the Goal it checks and
  marked in the script as a deviation with that reason (Test coverage). Rejected: adding those behaviors to the delta
  spec; dropping the checks.
- **Letter case of domain entries.** Requirement: Option allowedDomains and Requirement: Option deniedDomains say that
  upper and lower case are equivalent; the implementation does not change. Rejected: rejecting upper-case entries;
  leaving the spec silent.
- **Acceptance and the shell style guide.** The proposal's Becomes true gains the item that states the check of Goals:
  Scripts follow the shell style guide, as the restyle proposals carry it. Rejected: leaving that check to this design
  and the tasks alone.
- **Coverage table.** It uses the delta spec's scenario name "CIDR that cannot be applied as written". Rejected: leaving
  the table as it was.
- **`NOTES.md` and the guardrail limits.** The proposal's Acceptance item names what Requirement: Guardrail, not a
  security boundary says `NOTES.md` SHALL state, the nested Docker exception, and the metadata the feature adds;
  `NOTES.md` is trimmed to that and keeps every statement other approved text binds to the documentation. Rejected:
  keeping the full list of ways around the rules in `NOTES.md`.

## Optional improvements offered, not adopted

The audit of 2026-10-05 offered this with the decision on option values in the generated files; the maintainer did not
adopt it (Decisions of 2026-10-05), and it stays out of this change.

- **A check in `test.sh` that runs the validator against values with quotes, braces, semicolons, and line breaks.** Pro:
  the bound on the two generated files would have a test of its own. Con: one more check of an invariant no spec
  scenario states, for a bound that the review of the validator covers and that the existing checks of malformed entries
  already exercise.

## URL inventory

The feature configures no package repository: `install.sh` uses the repositories preconfigured in each image, through
its package manager, and fetches no URL itself. At start, it fetches one URL. Every other entry below is a destination
the presets allow and the feature never contacts itself, or an ordering reference; "test" in the When column marks the
hosts the tests connect to (Goals: Test destinations). Verified column: a read-only `curl -sSIL` (or name resolution) on
2026-09-30; HTTP status and observed final host.

| URL / template                                    | Purpose                                                   | When                                              | Integrity / authenticity                                         | Official source evidence                                                                                                                             | Verified                                                                                             |
| ------------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `https://api.github.com/meta`                     | GitHub `web`, `api`, `git` ranges for the `github` preset | start (fetched with `defaultAction` `deny`); test | TLS against the image's CA bundle; every entry validated as CIDR | https://docs.github.com/en/rest/meta/meta, https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-githubs-ip-addresses | 2026-09-30: 200, final host `api.github.com`, JSON 201,132 bytes                                     |
| `github.com` (and subdomains)                     | `github` preset                                           | start (allowed only); test                        | TLS of the client                                                | `domains.website` of https://api.github.com/meta lists `*.github.com`                                                                                | 2026-09-30: 200, final host `github.com`                                                             |
| `githubusercontent.com` (subdomains)              | `github` preset                                           | start (allowed only); test                        | TLS of the client                                                | `domains.website` of https://api.github.com/meta lists `*.githubusercontent.com`                                                                     | 2026-09-30: apex has no address; `raw.githubusercontent.com` 200, redirects to `github.com`          |
| `registry.npmjs.org`                              | `npm` preset                                              | start (allowed only); test                        | TLS of the client                                                | https://docs.npmjs.com/cli/v11/using-npm/config (`registry` default)                                                                                 | 2026-09-30: 200, final host `registry.npmjs.org`                                                     |
| `pypi.org`                                        | `pypi` preset                                             | start (allowed only)                              | TLS of the client                                                | https://docs.pypi.org/api/                                                                                                                           | 2026-09-30: 200, final host `pypi.org`                                                               |
| `files.pythonhosted.org`                          | `pypi` preset                                             | start (allowed only)                              | TLS of the client                                                | https://docs.pypi.org/api/ (file host)                                                                                                               | 2026-09-30: 404 at `/`, final host `files.pythonhosted.org`                                          |
| `api.anthropic.com`                               | `anthropic` preset                                        | start (allowed only)                              | TLS of the client                                                | https://code.claude.com/docs/en/network-config                                                                                                       | 2026-09-30: 404 at `/`, final host `api.anthropic.com`                                               |
| `claude.ai`                                       | `anthropic` preset                                        | start (allowed only)                              | TLS of the client                                                | https://code.claude.com/docs/en/network-config                                                                                                       | 2026-09-30: 403 at `/`, final host `claude.ai`                                                       |
| `platform.claude.com`                             | `anthropic` preset                                        | start (allowed only)                              | TLS of the client                                                | https://code.claude.com/docs/en/network-config                                                                                                       | 2026-09-30: 200, final host `platform.claude.com`                                                    |
| `update.code.visualstudio.com`                    | `vscode` preset                                           | start (allowed only)                              | TLS of the client                                                | https://code.visualstudio.com/docs/setup/network                                                                                                     | 2026-09-30: 200; `/latest/server-linux-x64/stable` redirects to `vscode.download.prss.microsoft.com` |
| `vscode.download.prss.microsoft.com`              | `vscode` preset (redirect target of the update server)    | start (allowed only)                              | TLS of the client                                                | https://code.visualstudio.com/docs/setup/network                                                                                                     | 2026-09-30: 403 at `/`, final host `vscode.download.prss.microsoft.com`                              |
| `vscode-cdn.net` (subdomains)                     | `vscode` preset                                           | start (allowed only)                              | TLS of the client                                                | https://code.visualstudio.com/docs/setup/network (`*.vscode-cdn.net`)                                                                                | 2026-09-30: apex has no address; `main.vscode-cdn.net` 400, final host unchanged                     |
| `marketplace.visualstudio.com`                    | `vscode` preset                                           | start (allowed only)                              | TLS of the client                                                | https://code.visualstudio.com/docs/setup/network                                                                                                     | 2026-09-30: 404 at `/`, final host `marketplace.visualstudio.com`                                    |
| `gallery.vsassets.io` (subdomains)                | `vscode` preset                                           | start (allowed only)                              | TLS of the client                                                | https://code.visualstudio.com/docs/setup/network (`*.gallery.vsassets.io`)                                                                           | 2026-09-30: apex has no address; `ms-python.gallery.vsassets.io` 404, final host unchanged           |
| `gallerycdn.vsassets.io` (subdomains)             | `vscode` preset                                           | start (allowed only)                              | TLS of the client                                                | https://code.visualstudio.com/docs/setup/network (`*.gallerycdn.vsassets.io`)                                                                        | 2026-09-30: apex has no address; `ms-python.gallerycdn.vsassets.io` 403, final host unchanged        |
| `192.0.2.1:443`                                   | Start check's refusal probe                               | start (never reached)                             | Not applicable: reserved documentation address                   | https://www.rfc-editor.org/rfc/rfc5737                                                                                                               | 2026-09-30: RFC 200 (final `www.rfc-editor.org/info/rfc5737/`)                                       |
| `ghcr.io/devcontainers/features/docker-in-docker` | `installsAfter` ordering; `dind` scenarios                | build (only if the user installs it)              | OCI digest, resolved by the dev container CLI                    | https://github.com/devcontainers/features/tree/main/src/docker-in-docker                                                                             | 2026-09-30: GHCR manifest `latest` 200; major tags 1–4                                               |
| `ghcr.io/devcontainers/features/common-utils`     | `installsAfter` ordering                                  | build (only if the user installs it)              | OCI digest, resolved by the dev container CLI                    | https://github.com/devcontainers/features/tree/main/src/common-utils                                                                                 | 2026-09-30: GHCR manifest `latest` 200; major tags 1–2                                               |

## Risks / Trade-offs

- [Lifecycle commands can start before the first rule loads, because the CLI does not wait for entrypoints] → The closed
  table is the script's first action, the check waits for the current start's record, and `NOTES.md` states the window.
- [GitHub's unauthenticated rate limit (60 per hour per IP) or an outage fails the fetch, and `closed` then leaves the
  container offline] → The check names the reason; CI keeps its fetches within the limit (Goals); see Open Questions for
  a fallback to the last validated ranges.
- [The remote user of the usual base image has passwordless `sudo`] → Non-Goals; `NOTES.md` states it first.
- [Sibling Compose services and the Docker host are refused unless allowed] → `NOTES.md` shows allowing a service name
  through `allowedDomains` (resolved by Docker's embedded DNS through dnsmasq) or its subnet through `allowedCidrs`; a
  hand run recorded in the PR's Validation section proves the service-name path, because the harness cannot start a
  sibling container (Test coverage), or `NOTES.md` drops it. See Open Questions.
- [A nested container is refused an allowed domain when its lookups do not pass through dnsmasq: under a nested daemon
  with its own DNS servers (docker-in-docker's `azureDnsAutoDetection` on Azure hosts), and on the default bridge, whose
  containers otherwise get `8.8.8.8`, which is refused] → Not guaranteed (Decisions: Nested Docker); `NOTES.md` states
  the exception and the two remedies observed to work (Context): `allowedCidrs`, and `azureDnsAutoDetection` `false`
  with a user-defined network. The `dind` scenario asserts only a refusal and an allowed range.
- [A nested container reaches a denied domain when its lookups do not pass through dnsmasq, wherever `defaultAction`
  `allow` or an allowed range lets the address through: the denylist fails open for nested containers under a nested
  daemon with its own DNS servers] → Not guaranteed (Decisions: Nested Docker; Open Questions); `NOTES.md` states it
  with the two remedies observed to work (Context): `deniedCidrs`, and `azureDnsAutoDetection` `false` with a
  user-defined network. No scenario asserts it.
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
- [An unprivileged process can make the next start fail on purpose, by exhausting GitHub's rate limit or by binding
  `127.0.0.1:53` before dnsmasq, and with `failureMode` `warn` that start removes the rules] → `closed`, the default,
  turns it into a denial of service; `NOTES.md` states it where it introduces `warn`; Open Questions 3 would blunt the
  rate-limit path.
- [A process that controls the remote user's login environment can forge the check's output through the dynamic loader
  before the check re-executes itself] → The spec names it as a guardrail limit; the start record stays root-written.
- [A process that receives queries meant for dnsmasq can answer lookups] → It cannot add addresses to the sets, so it
  can mislead or fail lookups but not widen egress.
- [With `defaultAction` `allow`, the feature refuses only what the denied entries name, and a process can avoid a denied
  name through a literal address, DNS over HTTPS, or a name that is not denied] → Non-Goals; `NOTES.md` states it where
  it introduces `defaultAction`, and recommends `deniedCidrs` for ranges that must stay out of reach.
- [Denying a name refuses every name that shares its addresses, and addresses it once had stay refused until the next
  start] → Documented in `NOTES.md`; a narrower name or `deniedCidrs` is the remedy.
- [A name of an allowed domain that an outsider controls can resolve into a denied range (DNS rebinding) and open that
  address, since a learned address is more specific than any range] → `NOTES.md` recommends `allowedCidrs`, not
  `allowedDomains`, for openings into a denied range.
- [dnsmasq's longest match between `--nftset` entries is in its code, not its manual] → Context records the code read;
  the `denied_domains` and `denied_in_range` scenarios check it on the packaged dnsmasq.

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
   applied with stale ranges." The fallback would also blunt a rate limit exhausted on purpose (Risks).
4. **Sibling Compose services.** As written: no automatic allowance for the container's own subnets (it would also open
   the Docker host's gateway address); `NOTES.md` documents `allowedDomains` with service names and `allowedCidrs`.
5. **Lifetime of learned addresses.** As written: until the next start (Requirement: Allowed domains; dnsmasq passes no
   TTL to the set). Alternative: element timeouts, which change that requirement.
6. **`--network=host`.** As written: documented as unsupported, without detection (Non-Goals), since no reliable
   in-container test distinguishes the host's network namespace. Alternative: refuse when a `docker0` interface exists
   at start, which misfires with docker-in-docker.
7. **Alpine tag.** As written: `alpine:3.24`, the current release, pinned so a new Alpine release does not change the
   tested image unannounced. Alternative: `alpine:latest`.
8. **Denied domains and nested containers.** As written: not guaranteed, like allowed domains, and documented in
   `NOTES.md` (Requirement: Forwarded traffic). The maintainer's decision of 2026-10-01 to record nested Docker as an
   exception was taken for allowed domains, which fail closed; the same cause makes `deniedDomains` fail open for nested
   containers (Context), which was found afterwards. Alternative: treat nested lookups in the feature, which that
   decision set aside as complex.

Questions 9 to 13 were raised on 2026-10-05, by requirements the knowledge base gained after the questions above were
answered (Context). Each names the rule that raises it. No text of the proposal or the delta spec depends on them; the
first answer of each is what sections 5 and 6 of `tasks.md` are written to.

9. **What `check` in `checks.sh` does after a failed check.** `.agents/knowledge/shell-style.md` (Choosing bash or POSIX
   sh) asks a POSIX test for a stand-in "with the same `check` / `reportResults` interface" and leaves the status of a
   failed check open. As written: `check` records the failure and returns 1, as the stand-in on the branch and the CLI's
   library do, so under `set -e` a POSIX test and a bash scenario both stop at their first failed check; the uv restyle
   chose this for a feature with tests in both dialects. Alternative: record the failure and go on, as
   `test/glab/checks.sh` and the stand-in that `just new-feature --posix` generates do, which changes
   `test/firewall/checks.sh` (tasks 6.1) and gives `test.sh` and `duplicate.sh` other semantics than the scenario
   scripts. Recommended: as written.
10. **Where the assertions both dialects use live.** `.agents/knowledge/testing.md` (Layout) names `test/<id>/checks.sh`
    as the file a POSIX test sources, and `.agents/knowledge/shell-style.md` (Tests) lets a shared helper file hold only
    assertions several scripts use; neither says what a bash scenario sources beside the CLI's library. As written: one
    POSIX file, `test/firewall/checks.sh`, holds the stand-in and the shared assertions with the helpers they call.
    `test.sh` and `duplicate.sh` source it alone, the scenario scripts source it after the library, and it defines
    `check` and `reportResults` only when the library has not, under a comment giving that reason: the file on the
    branch, renamed and reduced to assertions. Alternatives: the stand-in alone in `checks.sh` and the shared assertions
    in a second POSIX file every test sources, which adds a file and a source line to `test.sh` and `duplicate.sh`; or
    no shared file for the scenario scripts, each repeating the assertions it uses as the uv restyle did, which repeats
    about fifteen short functions across twelve scripts. Either changes tasks 6.1 to 6.3 and 6.5 and nothing under
    `src/firewall/`. Recommended: as written.
11. **`/var/lib/apt/lists` as a named constant.** `.agents/knowledge/shell-style.md` (Options are data) asks for a
    readonly constant for "every path the feature creates or modifies outside a temporary directory", and `install.sh`
    empties that directory after `apt-get install`. As written: `install.sh` names it, the rule read literally, as the
    glab and hf-cli restyles did. Alternative: leave it unnamed as a path the package manager owns, as the uv restyle
    did, which changes tasks 5.1 only. Recommended: as written.
12. **Log lines for start-time steps that neither change the image nor use the network.**
    `.agents/knowledge/shell-style.md` (Logging and failure) asks for one line "for every step that changes the image or
    uses the network". At a start nothing changes the image, and only the lookup of `api.github.com` and the fetch use
    the network. As written: `apply.sh` logs one line for the lookup and one for the fetch, each naming its source,
    beside what it logs on the branch (a retry, a failed start, the result); the table loads, the rewrites of
    `/etc/resolv.conf`, and the resolver's start get no line of their own, the reading on which the uv restyle left its
    repair of a runtime volume without one. Alternative: one line for each of those steps too, which changes tasks 5.3
    and adds up to six lines to the container log of every start. Recommended: as written.
13. **Checks that assert a test's premise.** `.agents/knowledge/shell-style.md` (Tests) says a check's label states one
    behavior in the words of the spec. `duplicate.sh` checks that "the first install used other options", and the
    `rerun` scenario checks, before its re-run, that "resolv.conf still names the stopped resolver" and that "a table of
    the test's own exists"; none of the three is a behavior of the feature. As written: all three stay checks, as they
    are on the branch, each labelled as the premise it asserts and marked in the script as a deviation with that reason,
    as the checks of a Goal are (Decisions of 2026-10-05), and `duplicate.sh` compares the harness's values with
    literals. Alternative: preconditions that stop the script with a message and are no longer checks, which changes
    tasks 6.3 and 6.5, removes three check lines, and takes the premise checks out of the deviations that Goals: Scripts
    follow the shell style guide lists. The glab restyle decided this for its `duplicate.sh` and rejected keeping such
    checks under labels the spec does not state, and on 2026-10-05 the maintainer chose the precondition for the same
    point in the changes `add-hf-mount-feature` and `add-openspec-feature`; that answer was not given for this change,
    so it is not written in. With `check` returning 1 (question 9), a failed premise stops the script under either
    answer. Recommended: the alternative, so that the three changes treat a test's premise alike. Setup steps the branch
    wraps in `check` (holding the resolver's port, importing the nested image) assert nothing and become plain commands
    under the same rule; this question is about the three assertions only.

Questions 14 and 15 were raised on 2026-10-05 by hand runs against the scripts as sections 5 to 8 of `tasks.md` leave
them; tasks 3.8 and 3.1 had recorded both as open. Each names the requirement at stake. No text of the proposal or the
delta spec is changed for them; the first answer of each is what `NOTES.md` states.

14. **DNS servers configured for a dev container on a user-defined network.** Requirement: DNS only to the container's
    resolvers says that DNS traffic to an address `/etc/resolv.conf` does not name is refused, and that every name still
    resolves. On a user-defined network, Docker's `/etc/resolv.conf` names only `127.0.0.11`. When DNS servers are
    configured for the container (`docker run --dns`, `dns:` in a Compose file) or for the daemon, the embedded resolver
    forwards to them from the container's own network namespace, so the rules refuse those queries and the two sentences
    cannot both hold. Observed on `debian:12` with `--dns 8.8.8.8` and `presets` `npm`: the start is applied and the
    check passes, `registry.npmjs.org` does not resolve, and a sibling container's name, which Docker answers itself,
    does; a rule added by hand that accepts DNS to `8.8.8.8` makes every name resolve. Without configured servers Docker
    forwards from the host's namespace, and on the default bridge `/etc/resolv.conf` names the configured servers, so
    every name resolves in both. As written: a documented limitation of the supported network configurations. `NOTES.md`
    says not to configure DNS servers for a dev container on a user-defined network and what works instead; the rules
    and the resolver handling stay as they are. Alternative: extend the resolver handling to the servers Docker forwards
    to, which the generated `/etc/resolv.conf` names only in a comment (`# ExtServers: [8.8.8.8]`). The start-time
    script would read that comment and accept DNS to those addresses. This widens "the resolvers named in
    `/etc/resolv.conf`" in the requirement and adds a scenario to it, depends on the form of that comment, and lets a
    process in the container query those servers directly, past the sets dnsmasq fills. Recommended: as written.
15. **A start under an entrypoint that does not run as root.** Requirement: Failure mode, Scenario: Rules cannot be
    loaded, says that such a start "is recorded as not applied", and Requirement: Start record readable by the remote
    user says that each start writes a record. The record lives in `/run/firewall/`, which root alone can write (Goals:
    A record per start), and it has to stay unwritable for the remote user, who may be the entrypoint's user. So such a
    start writes no record. Observed on `debian:12`: `apply.sh` run as uid 65534 logs one line and ends with status 0,
    no `/run/firewall` exists, outbound traffic is unrestricted, and the check ends after its 90 seconds with one error
    line that names the missing record, and with a non-zero status under `failureMode` `closed`. Requirement: Start
    check holds, since it names a missing record beside a failed and a not-applied one. As written: a documented
    limitation. `NOTES.md` says that the entrypoint has to run as root, that otherwise no rule is loaded and no record
    written, what the check then reports, and to keep the container's user at root and name the unprivileged user with
    `remoteUser`. The scenario's "recorded as not applied" holds for a start without `NET_ADMIN`; for a start without
    root, the check reports the start as not applied from the missing record. Alternative: change what the delta spec
    states, so that the scenario and the record requirement say a start without root leaves no record and the check
    reports it; or give such a start a place to record, which the entrypoint's user, and so possibly the remote user,
    could then write, against Requirement: Start record readable by the remote user. Recommended: as written, with the
    scenario's wording corrected when the delta spec is next revised.
