#!/usr/bin/env -S deno run --allow-read --allow-run=docker --allow-net=0.0.0.0
// Direct checks for installation controls. Uses disposable containers and this checkout's
// read-only feature; expected failures cannot be expressed by the scenario harness.
// Run without arguments for each supported image on the host architecture, or --image REF.
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";
import { fromFileUrl } from "jsr:@std/path@1.1.6";

const ID = "zypper-packages";
const MANAGER: string = "zypper";
const FEATURE = fromFileUrl(new URL(`../../src/${ID}`, import.meta.url));
const ARCH = Deno.build.arch === "aarch64" ? "arm64" : "amd64";
const compatibility = JSON.parse(Deno.readTextFileSync(new URL("./compatibility.json", import.meta.url)));
const args = parseArgs(Deno.args, { string: ["image", "only"], boolean: ["list"], collect: ["image"] });
const images: string[] = args.image.length ? args.image : compatibility.images
    .filter((entry: { arch?: string[] }) => (entry.arch ?? ["amd64"]).includes(ARCH))
    .map((entry: { image: string }) => entry.image);
if (!images.length) throw new Error(`no compatibility image supports ${ARCH}`);

type Result = { code: number; text: string };
type Controls = Record<string, string>;
async function docker(...args: string[]): Promise<Result> {
    const output = await new Deno.Command("docker", { args, stdout: "piped", stderr: "piped" }).output();
    return {
        code: output.code,
        text: new TextDecoder().decode(output.stdout) + new TextDecoder().decode(output.stderr),
    };
}
function assert(value: unknown, message: string): asserts value {
    if (!value) throw new Error(message);
}
class Container {
    constructor(readonly name: string) {}
    sh(script: string, ...args: string[]) {
        return docker("exec", this.name, "sh", "-c", script, "sh", ...args);
    }
    async setup(script: string, ...args: string[]) {
        const r = await this.sh(script, ...args);
        assert(r.code === 0, `setup failed: ${r.text}`);
        return r.text.trim();
    }
    install(packages: string, controls: Controls = {}) {
        return docker(
            "exec",
            "--env",
            `PACKAGES=${packages}`,
            ...Object.entries(controls)
                .flatMap(([key, value]) => ["--env", `${key.toUpperCase()}=${value}`]),
            this.name,
            "/feature/install.sh",
        );
    }
    async succeeds(packages: string, controls: Controls = {}) {
        const r = await this.install(packages, controls);
        assert(r.code === 0, `installation failed: ${r.text}`);
        return r;
    }
    async fails(packages: string, controls: Controls = {}, message?: string) {
        const r = await this.install(packages, controls);
        assert(r.code !== 0, `installation unexpectedly passed: ${r.text}`);
        if (message) assert(r.text.includes(message), `failure does not name ${message}: ${r.text}`);
        return r;
    }
    async installed(pkg: string) {
        const command = MANAGER === "apt"
            ? "dpkg-query -W -f='${db:Status-Status}' \"$1\" | grep -qx installed"
            : MANAGER === "apk"
            ? 'apk info -e "$1" >/dev/null'
            : MANAGER === "pacman"
            ? 'pacman -Q "$1" >/dev/null'
            : 'rpm -q "$1" >/dev/null';
        return (await this.sh(command, pkg)).code === 0;
    }
    metadata() {
        const command = MANAGER === "apt"
            ? 'find /var/lib/apt/lists -name "*_Packages*"'
            : MANAGER === "apk"
            ? 'for f in /var/cache/apk-packages/APKINDEX.*.tar.gz /var/cache/apk-packages/*.adb; do [ ! -f "$f" ] || echo "$f"; done'
            : MANAGER === "pacman"
            ? 'find /var/lib/pacman/sync -name "*.db"'
            : MANAGER === "zypper"
            ? 'for f in /var/cache/zypp/solv/*/solv; do [ ! -s "$f" ] || echo "$f"; done'
            : "find /var/cache/dnf /var/cache/libdnf5 -name repomd.xml 2>/dev/null; true";
        return this.setup(command);
    }
    async config() {
        const paths = MANAGER === "apt"
            ? "/etc/apt /usr/share/keyrings"
            : MANAGER === "apk"
            ? "/etc/apk/keys /etc/apk/repositories /etc/apk/repositories.d /etc/apk/apk.conf"
            : MANAGER === "pacman"
            ? "/etc/pacman.conf /etc/pacman.d/mirrorlist"
            : MANAGER === "zypper"
            ? "/etc/zypp"
            : "/etc/dnf /etc/yum.repos.d /etc/pki/rpm-gpg";
        if (MANAGER === "zypper") {
            return await this.setup(
                'for f in /etc/zypp/* /etc/zypp/repos.d/* /etc/zypp/services.d/* /etc/zypp/trusted.d/* /etc/zypp/trustedkeys.d/*; do [ ! -f "$f" ] || sha256sum "$f"; done | sort | sha256sum',
            );
        }
        return await this.setup(`find ${paths} -type f -exec sha256sum {} + 2>/dev/null | sort | sha256sum`);
    }
}
const packageName = MANAGER === "apk" || MANAGER === "pacman" ? "tree" : "bc";
const otherPackage = MANAGER === "apk" || MANAGER === "pacman" ? "file" : "file";
const tests: { name: string; run: (c: Container) => Promise<void>; network?: string }[] = [
    {
        name:
            "Invalid control fails before any change; Empty list ignores installation controls; Timeout boundaries are validated",
        async run(c) {
            const before = await c.config();
            await c.setup(
                'mkdir /tmp/stub; printf \'#!/bin/sh\\necho called >>/tmp/manager-called\\nexit 0\\n\' >"/tmp/stub/$1"; chmod +x "/tmp/stub/$1"',
                MANAGER === "apt" ? "apt-get" : MANAGER,
            );
            // The wrapper feature invocation has no opportunity to hide a native command.
            const invalid: Controls[] = [{ cleanup: "invalid" }, { cleanup: "" }];
            if (MANAGER !== "pacman") invalid.push({ refreshPolicy: "invalid" }, { refreshPolicy: "" });
            const boolean = MANAGER === "dnf"
                ? "installWeakDeps"
                : MANAGER === "apk"
                ? "upgradePackages"
                : MANAGER === "pacman"
                ? undefined
                : "installRecommends";
            if (boolean) invalid.push({ [boolean]: "yes" }, { [boolean]: "" });
            if (["apt", "apk", "dnf"].includes(MANAGER)) {
                for (
                    const value of [
                        "0",
                        "3601",
                        "01",
                        "-1",
                        "+1",
                        "1 ",
                        "1.5",
                        "１２",
                        "$(touch /tmp/pwned)",
                        "999999999999999999999999",
                    ]
                ) {
                    invalid.push({ networkTimeout: value });
                }
            }
            for (const options of invalid) {
                for (const packages of ["", packageName]) {
                    const result = await docker(
                        "exec",
                        "--env",
                        "PATH=/tmp/stub:/usr/sbin:/usr/bin:/sbin:/bin",
                        "--env",
                        `PACKAGES=${packages}`,
                        ...Object.entries(options).flatMap(([k, v]) => ["--env", `${k.toUpperCase()}=${v}`]),
                        c.name,
                        "/feature/install.sh",
                    );
                    assert(
                        result.code === 1 && result.text.includes(Object.keys(options)[0]),
                        `invalid controls did not fail clearly: ${result.text}`,
                    );
                }
            }
            for (const cleanup of ["all", "packages", "none"]) {
                await c.succeeds(" ,\t, ", { cleanup, path: "/tmp/stub:/usr/sbin:/usr/bin:/sbin:/bin" });
            }
            if (["apt", "apk", "dnf"].includes(MANAGER)) {
                for (const networkTimeout of ["", "1", "3600"]) await c.succeeds("", { networkTimeout });
            }
            assert(
                (await c.sh("test ! -e /tmp/manager-called && test ! -e /tmp/pwned")).code === 0,
                "invalid input called a manager or evaluated shell text",
            );
            assert(await c.config() === before, "invalid or empty input changed configuration");
        },
    },
    {
        name: "Missing cached metadata fails without refresh",
        async run(c) {
            if (MANAGER === "pacman") return;
            const before = await c.config();
            const result = await c.fails(packageName, { refreshPolicy: "never", cleanup: "packages" });
            assert(
                !/fetch https?:|Downloading|Retrieving repository/.test(result.text),
                `cache miss fetched metadata: ${result.text}`,
            );
            assert(!await c.installed(packageName), "cache miss installed a package");
            assert(await c.config() === before, "cache miss changed configuration");
        },
        network: "none",
    },
    {
        name:
            "Only package files are cleaned; Cached metadata is explicitly selected; Later controls apply to the second installation",
        async run(c) {
            // Leap's native service materializes repository definitions on its first use.
            if (MANAGER === "zypper") await c.setup("zypper --non-interactive --no-refresh repos >/dev/null");
            const before = await c.config();
            await c.setup("mkdir -p /var/cache/feature-unrelated; echo keep >/var/cache/feature-unrelated/sentinel");
            if (MANAGER === "apk") await c.setup("echo keep >/var/cache/apk/sentinel");
            await c.succeeds(packageName, { cleanup: "packages" });
            assert(await c.installed(packageName), "listed package is absent");
            assert(await c.metadata(), "packages cleanup removed metadata");
            await c.succeeds(
                packageName,
                MANAGER === "pacman" ? { cleanup: "none" } : { cleanup: "none", refreshPolicy: "never" },
            );
            assert(await c.metadata(), "none cleanup removed metadata");
            // A later default refresh must work after the earlier retained-cache choice.
            await c.succeeds(otherPackage, { cleanup: "all" });
            assert(
                await c.installed(packageName) && await c.installed(otherPackage),
                "second list lost installed packages",
            );
            assert(!await c.metadata(), "all cleanup retained metadata");
            assert(await c.config() === before, "control values persisted configuration");
            assert(
                await c.setup("cat /var/cache/feature-unrelated/sentinel") === "keep",
                "unrelated cache was removed",
            );
            if (MANAGER === "apk") {
                assert(await c.setup("cat /var/cache/apk/sentinel") === "keep", "native cache was changed");
            }
        },
    },
    {
        name: "Native timeout is inherited; Explicit timeout reaches network operations",
        async run(c) {
            if (!["apt", "apk", "dnf"].includes(MANAGER)) return;
            const binary = MANAGER === "apt" ? "apt-get" : MANAGER;
            await c.setup(
                `native=$(command -v "$1"); mkdir /tmp/bin
printf '#!/bin/sh\\nprintf "CALL" >>/tmp/native-args\\nfor arg do printf " [%%s]" "$arg" >>/tmp/native-args; done\\nprintf "\\\\n" >>/tmp/native-args\\nexec %s "$@"\\n' "$native" >"/tmp/bin/$1"
chmod +x "/tmp/bin/$1"`,
                binary,
            );
            for (const timeout of ["", "1"]) {
                await c.setup("rm -f /tmp/native-args");
                const r = await docker(
                    "exec",
                    "--env",
                    "PATH=/tmp/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                    "--env",
                    `PACKAGES=${packageName}`,
                    "--env",
                    `NETWORKTIMEOUT=${timeout}`,
                    c.name,
                    "/feature/install.sh",
                );
                assert(r.code === 0, `logged installation failed: ${r.text}`);
                const log = await c.setup("cat /tmp/native-args");
                const lines = log.split("\n").filter((line) => /\[(update|install|add)\]/.test(line));
                assert(lines.length > 0, "no network operations were logged");
                for (const line of lines) {
                    if (!timeout) assert(!/[Tt]imeout/.test(line), "empty timeout was overridden");
                    else {
                        const expected = MANAGER === "apt"
                            ? "Acquire::https::Timeout=1"
                            : MANAGER === "apk"
                            ? "[--timeout] [1]"
                            : "--setopt=*.timeout=1";
                        assert(line.includes(expected), `timeout did not reach network call: ${line}`);
                    }
                    assert(
                        !/retries|sslverify|allow-untrusted|no-check-certificate/.test(line),
                        "unrelated verification or retry option changed",
                    );
                }
            }
        },
    },
    {
        name: "Refresh is explicitly requested (unavailable additional repository)",
        async run(c) {
            if (MANAGER === "pacman") return;
            if (MANAGER === "apt") {
                await c.setup(
                    "echo 'deb http://127.0.0.1:9/ unavailable main' >/etc/apt/sources.list.d/unavailable.list",
                );
            } else if (MANAGER === "apk") {
                await c.setup("echo 'http://127.0.0.1:9/unavailable' >>/etc/apk/repositories");
            } else if (MANAGER === "dnf") {
                await c.setup(
                    "printf '[unavailable]\\nname=unavailable\\nbaseurl=http://127.0.0.1:9/\\nenabled=1\\nskip_if_unavailable=1\\ngpgcheck=1\\n' >/etc/yum.repos.d/unavailable.repo",
                );
            } else await c.setup("zypper --non-interactive addrepo http://127.0.0.1:9/ unavailable >/dev/null");
            await c.fails(packageName, {
                refreshPolicy: "always",
                ...(["apt", "apk", "dnf"].includes(MANAGER) ? { networkTimeout: "1" } : {}),
            });
            assert(!await c.installed(packageName), "failed strict refresh installed a package");
        },
    },
    {
        name: "Explicit timeout bounds a stalled local repository",
        network: "host",
        async run(c) {
            const listener = Deno.listen({ hostname: "0.0.0.0", port: 0 });
            const connections: Deno.Conn[] = [];
            const accepting = (async () => {
                try {
                    for await (const connection of listener) connections.push(connection);
                } catch (error) {
                    if (!(error instanceof Deno.errors.BadResource)) throw error;
                }
            })();
            const port = (listener.addr as Deno.NetAddr).port;
            try {
                if (MANAGER === "apt") {
                    await c.setup(
                        "rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*; printf 'deb http://127.0.0.1:%s/ unavailable main\\n' \"$1\" >/etc/apt/sources.list",
                        String(port),
                    );
                } else if (MANAGER === "apk") {
                    await c.setup(
                        "printf 'http://127.0.0.1:%s/unavailable\\n' \"$1\" >/etc/apk/repositories",
                        String(port),
                    );
                } else {
                    await c.setup(
                        "sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/*.repo; printf '[stall]\\nname=stall\\nbaseurl=http://127.0.0.1:%s/\\nenabled=1\\nskip_if_unavailable=0\\ngpgcheck=1\\nretries=1\\n' \"$1\" >/etc/yum.repos.d/stall.repo",
                        String(port),
                    );
                }
                const before = await c.config();
                const started = performance.now();
                await c.fails(packageName, { refreshPolicy: "always", networkTimeout: "1" });
                const elapsed = performance.now() - started;
                assert(connections.length > 0, "no request reached the stalled endpoint");
                assert(elapsed < 45000, `native timeout did not bound the stalled request (${elapsed} ms)`);
                assert(!await c.installed(packageName), "stalled refresh installed a package");
                assert(await c.config() === before, "timeout persisted configuration");
            } finally {
                listener.close();
                for (const connection of connections) connection.close();
                await accepting;
            }
        },
    },
    {
        name: "Baseline: refused entries fail before metadata or packages change",
        network: "none",
        async run(c) {
            const before = await c.setup("rpm -qa | sort | sha256sum");
            const refused = [
                "/tmp/bc.rpm",
                "https://example.invalid/bc",
                "bc.rpm",
                "--help",
                "bc file",
                "bc;echo bad",
                "b*",
                "évil",
            ];
            refused.push(
                ...(MANAGER === "dnf"
                    ? ["bc.RPM", "@core", "module:stream/profile", "bc>=1", "(bc)"]
                    : ["+bc", "!bc", "~bc", "pattern:base", "repo:bc", "bc=", "bc<=", "bc==1", "bc<1>2"]),
            );
            for (const entry of refused) await c.fails(`file,${entry}`, {}, entry);
            assert(!await c.metadata(), "a refused list loaded metadata");
            assert(await c.setup("rpm -qa | sort | sha256sum") === before, "a refused list changed installed packages");
        },
    },
    {
        name: "Baseline: unknown, wrong-case, unavailable version and architecture fail without partial installation",
        async run(c) {
            const before = await c.setup("rpm -qa | sort | sha256sum");
            const invalid = [
                "package-that-does-not-exist-123456",
                "Bc",
                "bc.s390x",
                MANAGER === "dnf" ? "bc-0.0.0-no-such-release" : "bc=0.0.0-no-such-release",
            ];
            if (MANAGER === "zypper") invalid.push("bc<0.0.0");
            for (const entry of invalid) {
                await c.fails(`file,${entry}`);
                assert(!await c.installed("file"), "a failing list partially installed file");
                assert(
                    await c.setup("rpm -qa | sort | sha256sum") === before,
                    "a failing list changed installed packages",
                );
            }
        },
    },
    {
        name: "Baseline: native pins, capability resolution, repeated lists and architecture qualifiers",
        async run(c) {
            let edition: string;
            if (MANAGER === "dnf") {
                const listing = await c.setup("dnf list --showduplicates file");
                edition = listing.split("\n").map((line) => line.trim().split(/\s+/))
                    .find((fields) => fields[0].startsWith("file."))?.[1] ?? "";
            } else {
                await c.setup("zypper --non-interactive refresh");
                const listing = await c.setup(
                    "zypper --xmlout --non-interactive --no-refresh search --details --match-exact file",
                );
                edition = listing.match(/<solvable[^>]*edition="([^"]+)"/)?.[1] ?? "";
            }
            assert(edition, "the repository offered no edition of file");
            const pin = MANAGER === "dnf" ? `file-${edition}` : `file=${edition}`;
            await c.succeeds(pin, { cleanup: "packages" });
            const installed = await c.setup('rpm -q --qf "%{VERSION}-%{RELEASE}" file');
            assert(edition.replace(/^\d+:/, "") === installed, `pin selected ${installed}, wanted ${edition}`);
            await c.succeeds("file", { cleanup: "packages" });
            assert(
                await c.setup('rpm -q --qf "%{VERSION}-%{RELEASE}" file') === installed,
                "same package changed from its current offered edition",
            );
            const arch = await c.setup("rpm --eval '%{_arch}'");
            await c.succeeds(`bc.${arch}`, { cleanup: "packages" });
            assert(await c.installed("file") && await c.installed("bc"), "different list lost earlier package");
            await c.succeeds(MANAGER === "dnf" ? "libz.so.1" : "awk");
            assert(
                (await c.sh(MANAGER === "dnf" ? "rpm -q --whatprovides libz.so.1" : "rpm -q gawk")).code === 0,
                "capability did not select a provider",
            );
            if (MANAGER === "zypper") {
                await c.succeeds("tree>=1");
                assert(await c.installed("tree"), "range did not select tree");
                await c.succeeds(`file-${edition}`);
            } else {
                const isDNF5 = (await c.setup("dnf --version")).includes("dnf5");
                if (isDNF5) {
                    await c.succeeds("dig");
                    assert(await c.installed("bind-utils"), "DNF5 did not resolve a program name");
                } else await c.fails("dig");
            }
        },
    },
    {
        name: "Baseline: conflict with coreutils fails without removal",
        async run(c) {
            assert(await c.installed("coreutils"), "the image lacks the conflict fixture coreutils");
            const before = await c.setup("rpm -qa | sort | sha256sum");
            await c.fails("coreutils-single");
            assert(await c.setup("rpm -qa | sort | sha256sum") === before, "conflict changed installed packages");
        },
    },
    {
        name: "Baseline: unverifiable signatures fail and do not import an untrusted key",
        async run(c) {
            await c.setup("keys=$(rpm -qa 'gpg-pubkey*'); [ -z \"$keys\" ] || rpm -e $keys");
            if (MANAGER === "dnf") {
                await c.setup(
                    "printf 'not a public key\\n' >/tmp/wrong-key; sed -i 's|^gpgkey=.*|gpgkey=file:///tmp/wrong-key|' /etc/yum.repos.d/*.repo",
                );
            }
            const before = await c.setup("rpm -qa | sort | sha256sum");
            await c.fails(packageName);
            assert(!await c.installed(packageName), "unverifiable repository/package installed a package");
            assert(
                await c.setup("rpm -qa | sort | sha256sum") === before,
                "failed verification changed the RPM database",
            );
        },
    },
    {
        name: "Baseline: a lower pin follows the native downgrade policy",
        async run(c) {
            if (MANAGER === "zypper") await c.setup("zypper --non-interactive refresh");
            let pkg = "";
            let older = "";
            for (const candidate of ["file", "bc", "libfuse3-3", "curl", "openssl-libs", "glibc"]) {
                const listing = MANAGER === "dnf"
                    ? await c.sh('dnf list --showduplicates "$1"', candidate)
                    : await c.sh(
                        'zypper --xmlout --non-interactive --no-refresh search --details --match-exact "$1"',
                        candidate,
                    );
                const editions = MANAGER === "dnf"
                    ? listing.text.split("\n").map((line) => line.trim().split(/\s+/))
                        .filter((fields) => fields[0]?.startsWith(`${candidate}.`)).map((fields) => fields[1])
                    : [...listing.text.matchAll(/<solvable[^>]*edition="([^"]+)"/g)].map((match) => match[1]);
                const unique = [...new Set(editions)].filter(Boolean);
                if (unique.length > 1) {
                    pkg = candidate;
                    older = await c.setup("printf '%s\\n' \"$@\" | sort -V | head -n 1", ...unique);
                    break;
                }
            }
            if (!pkg && MANAGER === "zypper") {
                const image = await c.setup("cat /etc/os-release");
                assert(image.includes("Tumbleweed"), "Leap has no package offered in two versions");
                throw new NotRun("Tumbleweed offers no two-version candidate (approved design exception)");
            }
            assert(pkg, "no package offered in two versions for the downgrade check");
            await c.succeeds(pkg);
            const before = await c.setup('rpm -q --qf "%{VERSION}-%{RELEASE}" "$1"', pkg);
            assert(before !== older.replace(/^\d+:/, ""), "unpinned install did not select a newer version");
            await c.succeeds(MANAGER === "dnf" ? `${pkg}-${older}` : `${pkg}=${older}`);
            const after = await c.setup('rpm -q --qf "%{VERSION}-%{RELEASE}" "$1"', pkg);
            assert(
                after === (MANAGER === "dnf" ? older.replace(/^\d+:/, "") : before),
                "lower pin did not follow the native policy",
            );
        },
    },
    {
        name: "Never validates raw caches, rebuilds parsed caches offline, and honors ZYPP_CONF",
        async run(c) {
            await c.setup(
                'printf "[main]\\ncachedir=/tmp/owned-zypp\\nmetadatadir=/tmp/owned-metadata\\n" >/tmp/custom-zypp.conf',
            );
            const controls = { zypp_conf: "/tmp/custom-zypp.conf", cleanup: "none" };
            await c.succeeds("bc", controls);
            const config = await c.config();
            const disconnected = await docker("network", "disconnect", "bridge", c.name);
            assert(disconnected.code === 0, disconnected.text);
            await c.setup("rm -rf /tmp/owned-zypp/solv");
            await c.succeeds("bc", { ...controls, refreshPolicy: "never" });
            await c.setup(
                'for f in /tmp/owned-metadata/*/repodata/repomd.xml; do printf "corrupt" >"$f"; done; rm -rf /tmp/owned-zypp/solv',
            );
            await c.fails("bc", { ...controls, refreshPolicy: "never" });
            assert(await c.config() === config, "repository configuration changed");
        },
    },
    {
        name: "Unsigned repository fails before installation",
        async run(c) {
            await c.setup("zypper --non-interactive refresh");
            await c.setup(
                'mkdir /tmp/unsigned; for d in /var/cache/zypp/raw/*; do [ ! -s "$d/repodata/repomd.xml" ] || { cp -R "$d/repodata" /tmp/unsigned/; break; }; done; rm -f /tmp/unsigned/repodata/repomd.xml.asc /tmp/unsigned/repodata/repomd.xml.key; zypper --non-interactive addrepo file:///tmp/unsigned unsigned',
            );
            const config = await c.config();
            const keys = await c.setup("rpm -qa 'gpg-pubkey*' | sort");
            await c.fails("bc");
            assert(!await c.installed("bc"), "package installed from unsigned metadata");
            assert(await c.setup("rpm -qa 'gpg-pubkey*' | sort") === keys, "trusted keys changed");
            assert(await c.config() === config, "repository configuration changed");
        },
    },
    {
        name: "Image without the manager accepts empty lists and fails clearly for nonempty lists",
        network: "none",
        async run(c) {
            const config = await c.config();
            await c.setup(
                'mkdir /tmp/no-manager; for cmd in sed tr; do ln -s "$(command -v "$cmd")" "/tmp/no-manager/$cmd"; done',
            );
            await c.succeeds("", { path: "/tmp/no-manager" });
            await c.fails("bc", { path: "/tmp/no-manager" }, "was not found");
            assert(await c.config() === config, "missing-manager invocation changed configuration");
        },
    },
    {
        name: "Recommendations are excluded by default and enabled on a later invocation",
        async run(c) {
            await c.succeeds("less", { cleanup: "none" });
            assert(!await c.installed("file"), "default installed a recommended package");
            await c.setup("zypper --non-interactive remove less");
            await c.succeeds("less", { installRecommends: "true", cleanup: "none" });
            assert(await c.installed("file"), "enabled recommendation was not selected");
            await c.succeeds("less", { installRecommends: "false" });
            assert(await c.installed("file"), "later false removed an installed recommendation");
        },
    },
];

class NotRun extends Error {}
let skipped = 0;
let failed = 0;
let ran = 0;
for (const image of images) {
    for (
        const test of tests.filter((t) =>
            (!args.only || t.name.includes(args.only)) &&
            !(MANAGER === "pacman" &&
                /^Missing cached|^Refresh is explicitly|^Native timeout|^Explicit timeout/.test(t.name)) &&
            !(MANAGER === "zypper" && /^Native timeout|^Explicit timeout/.test(t.name))
        )
    ) {
        if (args.list) {
            console.log(`${image}  ${test.name}`);
            ran++;
            continue;
        }
        const name = `${ID}-controls-${crypto.randomUUID().slice(0, 8)}`;
        try {
            const start = await docker(
                "run",
                "--detach",
                "--rm",
                "--name",
                name,
                "--network",
                test.network ?? "bridge",
                "--volume",
                `${FEATURE}:/feature:ro`,
                "--entrypoint",
                "sleep",
                image,
                "86400",
            );
            assert(start.code === 0, start.text);
            await test.run(new Container(name));
            console.log(`PASS  ${image}  ${test.name}`);
        } catch (e) {
            if (e instanceof NotRun) {
                skipped++;
                console.log(`NOT RUN  ${image}  ${test.name}: ${e.message}`);
                continue;
            }
            failed++;
            console.log(`FAIL  ${image}  ${test.name}\n${e instanceof Error ? e.message : e}`);
        } finally {
            if (!args.list) await docker("rm", "--force", name);
            ran++;
        }
    }
}
assert(ran > 0, "no check matched the selected images and scenarios");
console.log(`${ran - failed - skipped} passed, ${failed} failed, ${skipped} not run (${ran} checks)`);
if (failed) Deno.exit(1);
