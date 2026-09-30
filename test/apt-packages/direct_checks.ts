#!/usr/bin/env -S deno run --allow-read --allow-run=docker
// Direct checks for apt-packages: the spec scenarios a scenario test cannot assert — expected
// failures, two installs in one container, prepared or offline containers (design.md of the change
// that added the feature, decision "Direct checks for what a scenario cannot assert", and its Test
// plan). Runs src/apt-packages/install.sh from this checkout, mounted read-only, as root in a
// throwaway container per check, and asserts the exit status, the message, and the image state.
// CI does not run it; paste its output into the PR's Validation section.
//
//   test/apt-packages/direct_checks.ts [--image <ref>]... [--only <text>] [--list]
//
// Without --image it checks every image test/apt-packages/compatibility.json lists for this
// machine's architecture, plus alpine:3.22 for the image without apt-get. --only keeps the checks
// whose scenario contains <text>; --list prints the checks without running anything. Needs docker
// and network access to the images' repositories; a check that needs no network runs offline.
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";
import { fromFileUrl } from "jsr:@std/path@1.1.6";

const FEATURE_DIR = fromFileUrl(new URL("../../src/apt-packages", import.meta.url));
const COMPATIBILITY = fromFileUrl(new URL("./compatibility.json", import.meta.url));
const HOST_ARCH = Deno.build.arch === "aarch64" ? "arm64" : "amd64";

/** Outside the compatibility list: an image without apt-get (Docker Hub official image). */
const NO_APT_IMAGE = "alpine:3.22";

type Network = "bridge" | "none";

interface Result {
    code: number;
    /** stdout and stderr, in that order. */
    out: string;
}

async function docker(args: string[]): Promise<Result> {
    const output = await new Deno.Command("docker", { args, stdout: "piped", stderr: "piped" }).output();
    const decoder = new TextDecoder();
    return { code: output.code, out: decoder.decode(output.stdout) + decoder.decode(output.stderr) };
}

/** POSIX sh helpers prepended to every script run in a container. */
const HELPERS = `
installed() { [ "$(dpkg-query -W -f='\${Status}' "$1" 2>/dev/null)" = "install ok installed" ]; }
`;

const live = new Set<string>();

class Container {
    private constructor(readonly name: string, readonly image: string) {}

    static async start(image: string, network: Network): Promise<Container> {
        const name = `apt-packages-direct-${crypto.randomUUID().slice(0, 8)}`;
        live.add(name);
        const started = await docker([
            "run",
            "--detach",
            "--rm",
            "--name",
            name,
            "--network",
            network,
            "--user",
            "root",
            "--volume",
            `${FEATURE_DIR}:/feature:ro`,
            "--entrypoint",
            "sleep",
            image,
            "86400",
        ]);
        if (started.code !== 0) {
            live.delete(name);
            throw new Error(`docker run ${image} failed: ${started.out.trim()}`);
        }
        return new Container(name, image);
    }

    /** Runs a POSIX sh script in the container. */
    sh(script: string): Promise<Result> {
        return docker(["exec", this.name, "sh", "-c", HELPERS + script]);
    }

    /** Runs a script that must succeed and returns its trimmed output. */
    async text(script: string): Promise<string> {
        const result = await this.sh(script);
        if (result.code !== 0) throw new Error(`setup failed (exit ${result.code}): ${script}\n${result.out.trim()}`);
        return result.out.trim();
    }

    /** Runs the feature the way the CLI does, as root; `packages` undefined leaves PACKAGES unset. */
    install(packages?: string): Promise<Result> {
        const env = packages === undefined ? [] : ["--env", `PACKAGES=${packages}`];
        return docker(["exec", ...env, this.name, "/feature/install.sh"]);
    }

    async installed(pkg: string): Promise<boolean> {
        return (await this.sh(`installed '${pkg}'`)).code === 0;
    }

    version(pkg: string): Promise<string> {
        return this.text(`dpkg-query -W -f='\${Version}' '${pkg}'`);
    }

    /** Number of package index files in /var/lib/apt/lists. */
    async indexCount(): Promise<number> {
        return Number(await this.text("ls /var/lib/apt/lists | grep -c '_Packages' || true"));
    }

    dpkgStatus(): Promise<string> {
        return this.text("sha256sum /var/lib/dpkg/status");
    }

    async disconnect(): Promise<void> {
        const result = await docker(["network", "disconnect", "bridge", this.name]);
        if (result.code !== 0) throw new Error(`docker network disconnect failed: ${result.out.trim()}`);
    }

    async remove(): Promise<void> {
        await docker(["rm", "--force", this.name]);
        live.delete(this.name);
    }
}

class Asserter {
    readonly failures: string[] = [];

    ok(condition: boolean, message: string): void {
        if (!condition) this.failures.push(message);
    }

    /** `expected` is an exit status, or "nonzero" for any failure. */
    exit(result: Result, expected: number | "nonzero", what: string): void {
        const passed = expected === "nonzero" ? result.code !== 0 : result.code === expected;
        this.ok(passed, `${what}: expected exit ${expected}, got ${result.code}; output:\n${indent(result.out)}`);
    }

    says(result: Result, text: string, what: string): void {
        this.ok(result.out.includes(text), `${what}: output does not contain ${JSON.stringify(text)}`);
    }
}

function indent(text: string): string {
    const lines = text.trim().split("\n");
    const shown = lines.length > 25 ? ["…", ...lines.slice(-25)] : lines;
    return shown.map((line) => `      ${line}`).join("\n");
}

interface Check {
    /** The spec scenario(s) the check covers. */
    scenario: string;
    /** "apt": every compatibility image; "no-apt": the image without apt-get. */
    on: "apt" | "no-apt";
    network: Network;
    run(c: Container, t: Asserter): Promise<void>;
}

/** Package lists that are valid but must leave the image untouched. */
const EMPTY_LISTS = ["", " , ,\t, ", ","];

/**
 * A package the repositories offer in two versions and that is not installed, whose older version installs cleanly
 * (simulated), chosen at run time so that no fixed version goes stale. Leaves a package index in the container.
 */
async function twoVersionPackage(c: Container): Promise<{ pkg: string; older: string; candidate: string }> {
    const found = await c.sh(`
set -e
apt-get update -qq --error-on=any >/dev/null
preferred="unzip rsync less nano zip xxd patch sqlite3 libxml2-utils wget curl openssh-client tzdata"
generic=$(/usr/lib/apt/apt-helper cat-file /var/lib/apt/lists/*-security_*_Packages* \\
  /var/lib/apt/lists/*-updates_*_Packages* 2>/dev/null | sed -n 's/^Package: //p' | head -n 300) || generic=
for p in $preferred $generic; do
  installed "$p" && continue
  candidate=$(apt-cache policy "$p" | sed -n 's/^  Candidate: //p')
  [ -n "$candidate" ] && [ "$candidate" != "(none)" ] || continue
  for v in $(apt-cache madison "$p" | grep ' Packages$' | awk -F'|' '{gsub(/ /, "", $2); print $2}' | sort -u); do
    dpkg --compare-versions "$v" lt "$candidate" || continue
    if apt-get -s -qq install --no-install-recommends -o APT::Cmd::Pattern-Only=true -- "$p=$v" >/dev/null 2>&1; then
      echo "$p $v $candidate"
      exit 0
    fi
  done
done
exit 3
`);
    if (found.code !== 0) {
        throw new Error(
            "no package that is not installed is offered in two versions whose older one installs; the check " +
                `cannot pick a version to pin on ${c.image} (exit ${found.code}):\n${indent(found.out)}`,
        );
    }
    const [pkg, older, candidate] = found.out.trim().split("\n").pop()!.split(" ");
    return { pkg, older, candidate };
}

/** Each refusal runs with a valid entry beside it, so a validation gap would install something. */
async function refuses(c: Container, t: Asserter, entries: string[]): Promise<void> {
    const status = await c.dpkgStatus();
    for (const entry of entries) {
        const what = `entry ${JSON.stringify(entry)}`;
        const result = await c.install(`file,${entry}`);
        t.exit(result, 1, what);
        t.says(result, entry, what);
        t.ok((await c.indexCount()) === 0, `${what}: a package index was fetched`);
        t.ok((await c.dpkgStatus()) === status, `${what}: dpkg's status file changed`);
        t.ok((await c.sh("test ! -e /tmp/pwned")).code === 0, `${what}: a command in the entry ran`);
    }
}

const CHECKS: Check[] = [
    {
        scenario: "Omitted packages",
        on: "apt",
        network: "none",
        async run(c, t) {
            const status = await c.dpkgStatus();
            t.exit(await c.install(), 0, "PACKAGES unset");
            t.ok((await c.indexCount()) === 0, "a package index was fetched");
            t.ok((await c.dpkgStatus()) === status, "dpkg's status file changed");
        },
    },
    {
        scenario: "Empty list is a no-op",
        on: "apt",
        network: "none",
        async run(c, t) {
            const status = await c.dpkgStatus();
            for (const value of EMPTY_LISTS) {
                t.exit(await c.install(value), 0, `PACKAGES=${JSON.stringify(value)}`);
            }
            t.ok((await c.indexCount()) === 0, "a package index was fetched");
            t.ok((await c.dpkgStatus()) === status, "dpkg's status file changed");
        },
    },
    {
        scenario: "Listed package already installed at its candidate version",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("bc"), 0, "first install of bc");
            const first = await c.version("bc");
            t.exit(await c.install("bc"), 0, "bc listed again");
            t.ok((await c.version("bc")) === first, `bc changed from ${first}`);
            const candidate = await c.text(
                "apt-get update -qq >/dev/null && apt-cache policy bc | sed -n 's/^  Candidate: //p'",
            );
            t.ok(candidate === first, `installed bc ${first} is not the candidate ${candidate}`);
        },
    },
    {
        scenario: "Pinned version is installed",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            const { pkg, older } = await twoVersionPackage(c);
            await c.text("rm -rf /var/lib/apt/lists/*");
            t.exit(await c.install(`${pkg}=${older}`), 0, `${pkg}=${older}`);
            t.ok((await c.installed(pkg)) && (await c.version(pkg)) === older, `${pkg} ${older} is not installed`);
        },
    },
    {
        scenario: "Unavailable pinned version fails",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("file,bc=0.0.0-apt-packages-absent"), "nonzero", "unavailable version of bc");
            t.ok(!(await c.installed("bc")) && !(await c.installed("file")), "a listed package was installed");
        },
    },
    {
        scenario: "Architecture the image has not enabled fails",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            const native = await c.text("dpkg --print-architecture");
            const foreign = native === "s390x" ? "ppc64el" : "s390x";
            t.exit(await c.install(`file,bc:${foreign}`), "nonzero", `bc:${foreign}`);
            t.ok(!(await c.installed("bc")) && !(await c.installed("file")), "a listed package was installed");
            t.ok((await c.text("dpkg --print-foreign-architectures")) === "", "a foreign architecture was enabled");
        },
    },
    {
        scenario: "URL or path is refused",
        on: "apt",
        network: "bridge",
        run: (c, t) => refuses(c, t, ["/tmp/bc.deb", "./bc.deb", "http://deb.debian.org/debian/bc.deb", "bc/stable"]),
    },
    {
        scenario: "Option-like entry is refused",
        on: "apt",
        network: "bridge",
        run: (c, t) => refuses(c, t, ["--allow-unauthenticated", "-y", "-oAPT::Get::AllowUnauthenticated=true"]),
    },
    {
        scenario: "Removal marker is refused",
        on: "apt",
        network: "bridge",
        run: (c, t) => refuses(c, t, ["bc-", "apt-", "bc=1.0-"]),
    },
    {
        scenario: "Upper-case package name is refused",
        on: "apt",
        network: "bridge",
        run: (c, t) => refuses(c, t, ["Python3.11", "Bc"]),
    },
    {
        scenario: "Shell metacharacters and inner whitespace are refused",
        on: "apt",
        network: "bridge",
        run: (c, t) =>
            refuses(c, t, [
                "x;touch /tmp/pwned",
                "$(touch /tmp/pwned)",
                "`touch /tmp/pwned`",
                "bc|touch /tmp/pwned",
                "bc&&touch /tmp/pwned",
                "bc>/tmp/pwned",
                "b*",
                "b?",
                "bc file",
                "bc\tfile",
            ]),
    },
    {
        scenario: "Package name ending in plus is installed",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("g++"), 0, "g++");
            t.ok(await c.installed("g++"), "g++ is not installed");
        },
    },
    {
        scenario: "Unknown package fails",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("bc,apt-packages-no-such-package"), "nonzero", "unknown package");
            t.ok(!(await c.installed("bc")), "bc was installed");
        },
    },
    {
        scenario: "Entry is not matched as a regular expression",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("bc,zlib1g.dev"), "nonzero", "zlib1g.dev");
            t.ok(!(await c.installed("bc")) && !(await c.installed("zlib1g-dev")), "a package was installed");
            // Premise: read as a regular expression, zlib1g.dev matches a package the repositories offer.
            t.ok((await c.sh("apt-cache show zlib1g-dev >/dev/null")).code === 0, "zlib1g-dev is not offered");
        },
    },
    {
        scenario: "Virtual package with several providers fails",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("bc,mail-transport-agent"), "nonzero", "mail-transport-agent");
            t.ok(!(await c.installed("bc")), "bc was installed");
            const providers = await c.text(
                "apt-cache showpkg mail-transport-agent | sed -n '/^Reverse Provides:/,$p' | tail -n +2 | grep -c . || true",
            );
            t.ok(Number(providers) >= 2, `mail-transport-agent has ${providers} provider(s), not several`);
        },
    },
    {
        scenario: "No version for the image's architecture",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            // Offered by the archives for another architecture only.
            const pkg = (await c.text("dpkg --print-architecture")) === "arm64" ? "grub-pc" : "grub-efi-arm64";
            t.exit(await c.install(`bc,${pkg}`), "nonzero", pkg);
            t.ok(!(await c.installed("bc")) && !(await c.installed(pkg)), "a listed package was installed");
        },
    },
    {
        scenario: "Present index is used as is",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            await c.text(
                "apt-get update -qq --error-on=any >/dev/null && " +
                    "apt-get install -qq -d -y --no-install-recommends bc >/dev/null",
            );
            await c.disconnect();
            const result = await c.install("bc");
            t.exit(result, 0, "offline install from the present index and downloaded archives");
            t.says(result, "using the package index the image already holds", "offline install");
            t.ok(await c.installed("bc"), "bc is not installed");
        },
    },
    {
        scenario: "Failed refresh fails the feature",
        on: "apt",
        network: "none",
        async run(c, t) {
            t.exit(await c.install("bc"), "nonzero", "refresh without network");
            t.ok(!(await c.installed("bc")), "bc was installed");
        },
    },
    {
        scenario: "Unverifiable repository fails the refresh",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            // Point every source's Signed-By at another keyring the image ships, which did not sign the archive.
            const swapped = await c.text(`
set -e
configured=$(sed -n 's/^Signed-By: *//p' /etc/apt/sources.list.d/*.sources | sort -u)
wrong=
for k in /usr/share/keyrings/*removed*.gpg /usr/share/keyrings/*.gpg; do
  [ -f "$k" ] || continue
  printf '%s\\n' "$configured" | grep -qx "$k" && continue
  wrong=$k
  break
done
[ -n "$wrong" ] || { echo "no other keyring in /usr/share/keyrings" >&2; exit 1; }
sed -i "s|^Signed-By: .*|Signed-By: $wrong|" /etc/apt/sources.list.d/*.sources
grep -c "^Signed-By: $wrong$" /etc/apt/sources.list.d/*.sources | awk -F: '{n += $NF} END {print n}'
`);
            t.ok(Number(swapped) > 0, "no Signed-By line was swapped");
            const result = await c.install("bc");
            t.exit(result, "nonzero", "refresh against the wrong keyring");
            t.ok(/not signed|NO_PUBKEY|signature/i.test(result.out), "the failure does not name the signature");
            t.ok(!(await c.installed("bc")), "bc was installed");
        },
    },
    {
        scenario: "Apt configuration is unchanged",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            const snapshot = () =>
                c.text(
                    "{ find /etc/apt /usr/share/keyrings -printf '%p %y %m %l\\n' | sort; " +
                        "find /etc/apt /usr/share/keyrings -type f -exec sha256sum {} + | sort; } | sha256sum",
                );
            const before = await snapshot();
            t.exit(await c.install("bc,file"), 0, "bc,file");
            t.ok((await snapshot()) === before, "/etc/apt or /usr/share/keyrings changed");
        },
    },
    {
        scenario: "Same list on the second install",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("bc"), 0, "first install of bc");
            t.exit(await c.install("bc"), 0, "second install of bc");
            t.ok(await c.installed("bc"), "bc is not installed");
        },
    },
    {
        scenario: "Different list on the second install",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("bc"), 0, "first install of bc");
            t.exit(await c.install("file"), 0, "second install of file");
            t.ok((await c.installed("bc")) && (await c.installed("file")), "bc and file are not both installed");
        },
    },
    {
        scenario: "Pin below the installed version on the second install",
        on: "apt",
        network: "bridge",
        async run(c, t) {
            const { pkg, older, candidate } = await twoVersionPackage(c);
            await c.text("rm -rf /var/lib/apt/lists/*");
            t.exit(await c.install(pkg), 0, `first install of ${pkg}`);
            const installed = await c.version(pkg);
            t.ok(installed === candidate, `${pkg} ${installed} is not the candidate ${candidate}`);
            t.exit(await c.install(`${pkg}=${older}`), "nonzero", `second install of ${pkg}=${older}`);
            t.ok((await c.version(pkg)) === installed, `${pkg} changed from ${installed}`);
        },
    },
    {
        scenario: "Omitted packages (image without apt-get)",
        on: "no-apt",
        network: "none",
        async run(c, t) {
            const before = await noAptSnapshot(c);
            t.exit(await c.install(), 0, "PACKAGES unset");
            t.ok((await noAptSnapshot(c)) === before, "the image changed");
        },
    },
    {
        scenario: "Empty list is a no-op (image without apt-get)",
        on: "no-apt",
        network: "none",
        async run(c, t) {
            const before = await noAptSnapshot(c);
            for (const value of EMPTY_LISTS) {
                t.exit(await c.install(value), 0, `PACKAGES=${JSON.stringify(value)}`);
            }
            t.ok((await noAptSnapshot(c)) === before, "the image changed");
        },
    },
    {
        scenario: "Image without apt-get fails clearly",
        on: "no-apt",
        network: "bridge",
        async run(c, t) {
            const before = await noAptSnapshot(c);
            const result = await c.install("bc");
            t.exit(result, 1, "bc");
            for (const word of ["apt-get", "Debian", "Ubuntu"]) t.says(result, word, "message");
            t.ok((await noAptSnapshot(c)) === before, "the image changed");
        },
    },
];

/** File names under the system directories plus the content of /etc and the apk database. */
function noAptSnapshot(c: Container): Promise<string> {
    return c.text(
        "{ find /bin /etc /lib /opt /root /sbin /usr /var -xdev 2>/dev/null | sort; " +
            "find /etc -type f -exec sha256sum {} + | sort; cat /lib/apk/db/installed; } | sha256sum",
    );
}

function aptImages(): string[] {
    const compat = JSON.parse(Deno.readTextFileSync(COMPATIBILITY)) as {
        images: { image: string; arch?: string[] }[];
    };
    return compat.images.filter((entry) => (entry.arch ?? ["amd64"]).includes(HOST_ARCH)).map((entry) => entry.image);
}

if (import.meta.main) {
    const args = parseArgs(Deno.args, { string: ["image", "only"], boolean: ["list"], collect: ["image"] });
    const images = (args.image as string[]).length > 0 ? (args.image as string[]) : [...aptImages(), NO_APT_IMAGE];
    const checks = CHECKS.filter((check) => !args.only || check.scenario.includes(args.only));
    const plan = images.flatMap((image) =>
        checks.filter((check) => (check.on === "no-apt") === (image === NO_APT_IMAGE)).map((check) => ({
            image,
            check,
        }))
    );
    if (args.list) {
        for (const { image, check } of plan) console.log(`${image}  ${check.scenario}  (network: ${check.network})`);
        Deno.exit(0);
    }
    const cleanup = async () => {
        await Promise.all([...live].map((name) => docker(["rm", "--force", name])));
        Deno.exit(130);
    };
    Deno.addSignalListener("SIGINT", cleanup);
    Deno.addSignalListener("SIGTERM", cleanup);

    console.log(`apt-packages direct checks: ${FEATURE_DIR}/install.sh, host ${HOST_ARCH}`);
    let failed = 0;
    for (const { image, check } of plan) {
        const t = new Asserter();
        let c: Container | undefined;
        try {
            c = await Container.start(image, check.network);
            await check.run(c, t);
        } catch (error) {
            t.failures.push(`error: ${error instanceof Error ? error.message : String(error)}`);
        } finally {
            await c?.remove();
        }
        const verdict = t.failures.length === 0 ? "PASS" : "FAIL";
        if (verdict === "FAIL") failed++;
        console.log(`${verdict}  ${image}  ${check.scenario}`);
        for (const failure of t.failures) console.log(`    - ${failure}`);
    }
    console.log(`\n${plan.length - failed} passed, ${failed} failed (${plan.length} checks)`);
    if (failed > 0) Deno.exit(1);
}
