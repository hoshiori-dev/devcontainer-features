#!/usr/bin/env -S deno run --check --allow-read --allow-run=docker
// Direct checks for apk-packages: the spec scenarios a scenario test cannot assert — expected
// failures, two installs in one container, prepared or offline containers (design.md of the change
// that added the feature, decision "Direct checks for what a scenario cannot assert", and its Test
// plan). Runs src/apk-packages/install.sh from this checkout, mounted read-only, as root in a
// throwaway container per check, and asserts the exit status, the message, and the image state.
// CI does not run it; paste its output into the PR's Validation section.
//
//   test/apk-packages/direct_checks.ts [--image <ref>]... [--only <text>] [--list]
//
// Without --image it checks every image test/apk-packages/compatibility.json lists for this
// machine's architecture, plus three pinned images outside that list: the first releases of both
// Alpine branches, whose installed packages lag their repositories, and a Debian image without apk.
// --only keeps the checks whose scenario contains <text>; --list prints the checks without running
// anything. Needs docker and network access to the images' repositories; a check that needs no
// network runs offline. Versions are read at run time, so no fixed version goes stale.
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";
import { fromFileUrl } from "jsr:@std/path@1.1.6";

const FEATURE_DIR = fromFileUrl(new URL("../../src/apk-packages", import.meta.url));
const COMPATIBILITY = fromFileUrl(new URL("./compatibility.json", import.meta.url));
const HOST_ARCH = Deno.build.arch === "aarch64" ? "arm64" : "amd64";

/**
 * Outside the compatibility list: alpine:3.24.0 (apk-tools 3.0.6) and alpine:3.22.0 (apk-tools 2.14.9), Docker Hub
 * official images pinned by digest. Every point release of a branch updates at least alpine-release, so they hold
 * installed packages the repositories offer in a newer version.
 */
const LAGGING_IMAGES = [
    "alpine@sha256:a2d49ea686c2adfe3c992e47dc3b5e7fa6e6b5055609400dc2acaeb241c829f4",
    "alpine@sha256:8a1f59ffb675680d47db6337b49d22281a139e9d709335b492be023728e11715",
];

/** Outside the compatibility list: an image without apk (Docker Hub official image, pinned by digest). */
const NO_APK_IMAGE = "debian:12@sha256:f37a335e82bca302e955fa39f9dfe28f1be618f016f8a2b56318e5a5111afc26";

/** A run that has not ended by then is stopped and counts as failed, so a question apk asked cannot hang the runner. */
const INSTALL_TIMEOUT_MS = 600_000;

type Network = "bridge" | "none";

/** "apk": every compatibility image; "lagging": the first-release images; "no-apk": the image without apk. */
type Kind = "apk" | "lagging" | "no-apk";

interface Result {
    code: number;
    /** stdout and stderr, in that order. */
    out: string;
}

async function docker(args: string[], timeoutMs?: number): Promise<Result> {
    const signal = timeoutMs === undefined ? undefined : AbortSignal.timeout(timeoutMs);
    const decoder = new TextDecoder();
    try {
        const output = await new Deno.Command("docker", { args, stdout: "piped", stderr: "piped", signal }).output();
        const out = decoder.decode(output.stdout) + decoder.decode(output.stderr);
        if (signal?.aborted) return { code: 124, out: `${out}\n(stopped after ${timeoutMs} ms)` };
        return { code: output.code, out };
    } catch (error) {
        if (signal?.aborted) return { code: 124, out: `(stopped after ${timeoutMs} ms)` };
        throw error;
    }
}

/** Whether the command prints `text` within `timeoutMs`; the command is stopped as soon as it does, or at the limit. */
async function printsWithin(args: string[], text: string, timeoutMs: number): Promise<boolean> {
    const child = new Deno.Command("docker", { args, stdin: "null", stdout: "piped", stderr: "null" }).spawn();
    const stop = () => {
        try {
            child.kill();
        } catch {
            // already exited
        }
    };
    const timer = setTimeout(stop, timeoutMs);
    const decoder = new TextDecoder();
    let seen = "";
    try {
        for await (const chunk of child.stdout) {
            seen += decoder.decode(chunk, { stream: true });
            if (seen.includes(text)) return true;
        }
        return false;
    } finally {
        clearTimeout(timer);
        stop();
        await child.status;
    }
}

/** POSIX sh helpers prepended to every script run in a container; the Alpine images run them in busybox sh. */
const HELPERS = String.raw`
installed() { apk info -e "$1" >/dev/null 2>&1; }
version() { awk -v p="$1" '$0 == "P:" p { f = 1 } f && /^V:/ { print substr($0, 3); exit }' /lib/apk/db/installed; }
offered() { apk --no-cache search -x "$1" 2>/dev/null | sed -n "s/^$1-\([0-9]\)/\1/p" | head -n 1; }
`;

const live = new Set<string>();

class Container {
    private constructor(readonly name: string, readonly image: string) {}

    static async start(image: string, network: Network): Promise<Container> {
        const name = `apk-packages-direct-${crypto.randomUUID().slice(0, 8)}`;
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

    /**
     * Runs the feature the way the CLI does, as root; `packages` undefined leaves PACKAGES unset. `cwd` is the
     * directory the feature is started from, and `tty` attaches a terminal without any input.
     */
    install(
        packages?: string,
        options: { cwd?: string; tty?: boolean; upgradePackages?: boolean } = {},
    ): Promise<Result> {
        const args = ["exec"];
        if (packages !== undefined) args.push("--env", `PACKAGES=${packages}`);
        if (options.cwd) args.push("--workdir", options.cwd);
        if (options.tty) args.push("--tty");
        if (options.upgradePackages !== undefined) args.push("--env", `UPGRADEPACKAGES=${options.upgradePackages}`);
        return docker([...args, this.name, "/feature/install.sh"], INSTALL_TIMEOUT_MS);
    }

    async installed(pkg: string): Promise<boolean> {
        return (await this.sh(`installed '${pkg}'`)).code === 0;
    }

    /** The installed version of a package, read from apk's installed database. */
    version(pkg: string): Promise<string> {
        return this.text(`version '${pkg}'`);
    }

    /** The version the image's repositories offer, read without leaving an index in the image. */
    async offered(pkg: string): Promise<string> {
        const version = await this.text(`offered '${pkg}'`);
        if (version === "") throw new Error(`the repositories of ${this.image} offer no ${pkg}`);
        return version;
    }

    async inWorld(entry: string): Promise<boolean> {
        return (await this.sh(`grep -Fqx -- '${entry}' /etc/apk/world`)).code === 0;
    }

    /**
     * Hash of apk's world, its installed database, the names in /var/cache/apk, and the feature's temporary
     * directories: equal before and after means nothing was installed, removed, recorded, fetched, or left behind.
     */
    state(): Promise<string> {
        return this.text(
            "{ cat /etc/apk/world /lib/apk/db/installed; ls -A /var/cache/apk; " +
                "ls -d /tmp/apk-packages.* 2>/dev/null || true; } | sha256sum",
        );
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
    on: Kind;
    network: Network;
    run(c: Container, t: Asserter): Promise<void>;
}

/** Package lists that are valid but must leave the image untouched. */
const EMPTY_LISTS = ["", " , ,\t, ", ","];

/**
 * Each refusal runs offline with a valid entry beside it. The message naming the entry, not the exit status, shows
 * that validation came before the apk check and before any index refresh: offline, a refresh also exits 1, with
 * another message.
 */
async function refuses(c: Container, t: Asserter, entries: string[]): Promise<void> {
    const state = await c.state();
    for (const entry of entries) {
        const what = `entry ${JSON.stringify(entry)}`;
        const result = await c.install(`file,${entry}`);
        t.exit(result, 1, what);
        t.says(result, `refusing the entry '${entry}'`, what);
        t.ok((await c.state()) === state, `${what}: apk's world, its installed database, or a cache changed`);
        t.ok((await c.sh("test ! -e /tmp/pwned")).code === 0, `${what}: a command in the entry ran`);
    }
}

/** A list that must fail: non-zero exit, none of `pkgs` installed, and the image state as it was. */
async function failsCleanly(c: Container, t: Asserter, packages: string, pkgs: string[]): Promise<Result> {
    const state = await c.state();
    const result = await c.install(packages);
    t.exit(result, "nonzero", packages);
    for (const pkg of pkgs) t.ok(!(await c.installed(pkg)), `${packages}: ${pkg} was installed`);
    t.ok((await c.state()) === state, `${packages}: apk's world, its installed database, or a cache changed`);
    return result;
}

/** Hash of every path under /etc/apk except the world: names, types, modes, owners, link targets, and contents. */
function apkConfiguration(c: Container): Promise<string> {
    return c.text(
        "{ find /etc/apk -mindepth 1 ! -path /etc/apk/world -exec stat -c '%n %F %a %u:%g %N' {} + | sort; " +
            "find /etc/apk -type f ! -path /etc/apk/world -exec sha256sum {} + | sort; } | sha256sum",
    );
}

/** File names under the system directories plus the content of /etc and the dpkg database. */
function noApkSnapshot(c: Container): Promise<string> {
    return c.text(
        "{ find /bin /etc /lib /opt /root /sbin /tmp /usr /var -xdev 2>/dev/null | sort; " +
            "find /etc -type f -exec sha256sum {} + | sort; sha256sum /var/lib/dpkg/status; } | sha256sum",
    );
}

const CHECKS: Check[] = [
    {
        scenario: "Listed packages are upgraded on request",
        on: "lagging",
        network: "bridge",
        async run(c, t) {
            const first =
                (await c.text(`apk --no-cache version -l '<' 2>/dev/null | awk '$2 == "<" { print $1, $3 }'`)).split(
                    "\n",
                )[0];
            if (!first) throw new Error(`no installed package lags the repositories on ${c.image}`);
            const [installedAs, newer] = first.split(" ");
            const pkg = installedAs.replace(/-[0-9][^-]*-r[0-9]+$/, "");
            const before = await c.version(pkg);
            t.exit(await c.install(pkg, { upgradePackages: false }), 0, "upgrade disabled");
            t.ok(await c.version(pkg) === before, "upgradePackages=false changed the installed version");
            t.exit(await c.install(pkg, { upgradePackages: true }), 0, "upgrade enabled");
            t.ok(await c.version(pkg) === newer, "upgradePackages=true did not install the offered newer version");
            t.ok(await c.inWorld(pkg), "the upgraded package is missing from world");
        },
    },

    {
        scenario: "Omitted packages",
        on: "apk",
        network: "none",
        async run(c, t) {
            const state = await c.state();
            t.exit(await c.install(), 0, "PACKAGES unset");
            t.ok((await c.state()) === state, "apk's world, its installed database, or a cache changed");
        },
    },
    {
        scenario: "Empty list is a no-op",
        on: "apk",
        network: "none",
        async run(c, t) {
            const state = await c.state();
            for (const value of EMPTY_LISTS) {
                t.exit(await c.install(value), 0, `PACKAGES=${JSON.stringify(value)}`);
            }
            t.ok((await c.state()) === state, "apk's world, its installed database, or a cache changed");
        },
    },
    {
        scenario: "Listed package already installed stays at its version",
        on: "lagging",
        network: "bridge",
        async run(c, t) {
            // Installed packages the repositories offer in a newer version: "<name>-<installed> <offered>" lines.
            const lagging = () =>
                c.text(`apk --no-cache version -l '<' 2>/dev/null | awk '$2 == "<" { print $1, $3 }'`);
            const first = (await lagging()).split("\n")[0];
            if (first === "") {
                throw new Error(`no installed package lags the repositories on ${c.image}; the check cannot run`);
            }
            const [installedAs, newer] = first.split(" ");
            const pkg = installedAs.replace(/-[0-9][^-]*-r[0-9]+$/, "");
            const before = await c.version(pkg);
            t.ok(before !== "" && before !== newer, `${pkg} ${before} does not lag the offered ${newer}`);
            t.exit(await c.install(pkg), 0, pkg);
            t.ok((await c.version(pkg)) === before, `${pkg} changed from ${before} to ${await c.version(pkg)}`);
            t.ok(await c.inWorld(pkg), `apk's world does not hold ${pkg}`);
            t.ok((await lagging()).split("\n").includes(first), `the repositories no longer offer a newer ${pkg}`);
            console.log(`      ${pkg} stayed at ${before}; the repositories offer ${newer}`);
        },
    },
    {
        scenario: "Pinned version is installed",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            const version = await c.offered("tree");
            t.exit(await c.install(`tree=${version}`), 0, `tree=${version}`);
            t.ok(
                (await c.installed("tree")) && (await c.version("tree")) === version,
                `tree ${version} is not installed`,
            );
            t.ok(await c.inWorld(`tree=${version}`), `apk's world does not hold tree=${version}`);
        },
    },
    {
        scenario: "Prefix constraint is installed",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            const prefix = (await c.offered("tree")).replace(/-r[0-9]+$/, "");
            t.exit(await c.install(`tree~${prefix}`), 0, `tree~${prefix}`);
            const version = (await c.installed("tree")) ? await c.version("tree") : "";
            t.ok(
                version.startsWith(prefix),
                `the installed tree ${JSON.stringify(version)} does not start with ${prefix}`,
            );
            t.ok(await c.inWorld(`tree~${prefix}`), `apk's world does not hold tree~${prefix}`);
        },
    },
    {
        scenario: "Range constraint is installed",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            const version = await c.offered("tree");
            t.exit(await c.install(`tree>=${version}`), 0, `tree>=${version}`);
            t.ok(
                (await c.installed("tree")) && (await c.version("tree")) === version,
                `tree ${version} is not installed`,
            );
            t.ok(await c.inWorld(`tree>=${version}`), `apk's world does not hold tree>=${version}`);
        },
    },
    {
        scenario: "Unsatisfied range constraint fails",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            await failsCleanly(c, t, `file,tree<${await c.offered("tree")}`, ["file", "tree"]);
        },
    },
    {
        scenario: "Malformed constraint fails",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            await failsCleanly(c, t, "file,tree>", ["file", "tree"]);
        },
    },
    {
        scenario: "Configured tag selects its repository",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            // Tag the image's community repository; ripgrep is offered by community only.
            const tagged = await c.text(
                String
                    .raw`sed -i 's|^\(.*/community\)$|@t \1|' /etc/apk/repositories && grep -c '^@t .*/community$' /etc/apk/repositories`,
            );
            t.ok(tagged === "1", "the community repository line was not tagged");
            // Premise: the untagged name no longer resolves, so only the tag can select the repository.
            t.ok(
                (await c.sh("apk --no-cache add --simulate ripgrep")).code !== 0,
                "premise: ripgrep resolves without the tag",
            );
            const repositories = await c.text("sha256sum /etc/apk/repositories");
            t.exit(await c.install("ripgrep@t"), 0, "ripgrep@t");
            t.ok(await c.installed("ripgrep"), "ripgrep is not installed");
            t.ok(await c.inWorld("ripgrep@t"), "apk's world does not hold ripgrep@t");
            t.ok((await c.text("sha256sum /etc/apk/repositories")) === repositories, "/etc/apk/repositories changed");
        },
    },
    {
        scenario: "Unavailable pinned version fails",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            await failsCleanly(c, t, "file,tree=0.0.0-r0", ["file", "tree"]);
        },
    },
    {
        scenario: "Tag the image does not configure fails",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            const repositories = await c.text("sha256sum /etc/apk/repositories");
            await failsCleanly(c, t, "file,tree@apkpackagesabsent", ["file", "tree"]);
            t.ok((await c.text("sha256sum /etc/apk/repositories")) === repositories, "/etc/apk/repositories changed");
        },
    },
    {
        scenario: "URL or path is refused",
        on: "apk",
        network: "none",
        run: (c, t) =>
            refuses(c, t, [
                "/tmp/tree.apk",
                "./tree.apk",
                "tree.apk/",
                "https://example.com/tree.apk",
                "community/tree",
            ]),
    },
    {
        scenario: "Option-like entry is refused",
        on: "apk",
        network: "none",
        run: (c, t) => refuses(c, t, ["--allow-untrusted", "-u", "--force-missing-repositories", "-X"]),
    },
    {
        scenario: "Conflict marker is refused",
        on: "apk",
        network: "none",
        async run(c, t) {
            await refuses(c, t, ["!busybox", "!tree"]);
            t.ok(await c.installed("busybox"), "busybox was removed");
        },
    },
    {
        scenario: "Shell metacharacters and inner whitespace are refused",
        on: "apk",
        network: "none",
        run: (c, t) =>
            refuses(c, t, [
                "x;touch /tmp/pwned",
                "$(touch /tmp/pwned)",
                "`touch /tmp/pwned`",
                "tree|touch /tmp/pwned",
                "tree&&touch /tmp/pwned",
                "tree$HOME",
                "t*",
                "t?",
                "tree file",
                "tree\tfile",
                "trée",
                "tr\u0435e",
            ]),
    },
    {
        scenario: "Unknown package fails",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            await failsCleanly(c, t, "file,apk-packages-no-such-package,tree", ["file", "tree"]);
        },
    },
    {
        scenario: "Provided name installs a provider",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("cmd:jq"), 0, "cmd:jq");
            t.ok((await c.sh("command -v jq >/dev/null && jq --version")).code === 0, "no jq command is installed");
            t.ok(await c.inWorld("cmd:jq"), "apk's world does not hold cmd:jq");
        },
    },
    {
        scenario: "Entry is not read as a package file",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            // A signed package file in the directory the feature is started from, listed by its file name.
            const file = await c.text(
                "mkdir /start && apk --no-cache fetch -q -o /start tree >/dev/null 2>&1; ls /start",
            );
            t.ok(/^tree-.*\.apk$/.test(file), `apk fetch left ${JSON.stringify(file)} in /start`);
            // Premise: started from that directory, apk itself reads the argument as that file.
            t.ok(
                (await c.sh(`cd /start && apk --no-cache add --simulate '${file}'`)).code === 0,
                "premise: apk does not read the file name as a package file",
            );
            const state = await c.state();
            const result = await c.install(file, { cwd: "/start" });
            t.exit(result, "nonzero", file);
            t.ok(!(await c.installed("tree")), "tree was installed from the file");
            t.ok((await c.state()) === state, "apk's world, its installed database, or a cache changed");
        },
    },
    {
        scenario: "Unavailable repository fails the feature",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            // A repository line whose index answers HTTP 404, beside the image's own.
            await c.text(String.raw`sed -n 's|/main$|/nonexistent|p' /etc/apk/repositories >>/etc/apk/repositories`);
            t.ok(
                (await c.text("grep -c '/nonexistent$' /etc/apk/repositories")) === "1",
                "the failing repository line was not added",
            );
            // Premise: apk add alone skips the failing repository and would install from the others.
            t.ok(
                (await c.sh("apk --no-cache add --simulate file")).code === 0,
                "premise: apk add alone does not skip the failing repository",
            );
            const result = await failsCleanly(c, t, "file", ["file"]);
            t.says(result, "apk update failed", "message");
        },
    },
    {
        scenario: "Index present in the image is not used",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            // The image's own cache holds a fresh index and the package files; then the network goes away.
            await c.text("ln -s /var/cache/apk /etc/apk/cache && apk update -q && apk cache download file >/dev/null");
            const cached = await c.text("ls /var/cache/apk");
            t.ok(/APKINDEX/.test(cached) && /file-/.test(cached), `the cache holds only: ${cached}`);
            await c.disconnect();
            // Premise: a plain apk add would install from that cache without the network.
            t.ok(
                (await c.sh("apk add --simulate file")).code === 0,
                "premise: apk add does not install from the cached index offline",
            );
            const result = await failsCleanly(c, t, "file", ["file"]);
            t.says(result, "apk update failed", "message");
        },
    },
    {
        scenario: "Unverifiable repository fails the refresh",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            await c.text('mkdir /keys.moved && mv /etc/apk/keys/* /keys.moved/ && test -z "$(ls -A /etc/apk/keys)"');
            const result = await failsCleanly(c, t, "file", ["file"]);
            t.ok(/UNTRUSTED/.test(result.out), "the failure does not name the untrusted signature");
        },
    },
    {
        scenario: "Apk configuration is unchanged",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            const before = await apkConfiguration(c);
            t.exit(await c.install("file,tree"), 0, "file,tree");
            t.ok((await c.installed("file")) && (await c.installed("tree")), "file and tree are not both installed");
            t.ok((await apkConfiguration(c)) === before, "a path under /etc/apk other than the world changed");
        },
    },
    {
        scenario: "Interactive default is overridden",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            await c.text("touch /etc/apk/interactive");
            // Premise, in a second container: with a terminal, apk itself asks on this image and waits.
            const other = await Container.start(c.image, "bridge");
            try {
                await other.text("touch /etc/apk/interactive");
                t.ok(
                    await printsWithin(
                        ["exec", "--tty", other.name, "apk", "--no-cache", "add", "file"],
                        "[Y/n]",
                        120_000,
                    ),
                    "premise: apk does not ask a question with /etc/apk/interactive and a terminal",
                );
            } finally {
                await other.remove();
            }
            const result = await c.install("file", { tty: true });
            t.exit(result, 0, "file with a terminal attached");
            t.ok(!/\[Y\/n\]|Do you want to continue/.test(result.out), "the feature's apk asked a question");
            t.ok(await c.installed("file"), "file is not installed");
        },
    },
    {
        scenario: "Caches are removed (image with a configured cache that holds a file)",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            await c.text("ln -s /var/cache/apk /etc/apk/cache && echo kept >/var/cache/apk/kept");
            const cache = () => c.text("cd /var/cache/apk && ls -A && sha256sum ./*");
            const before = await cache();
            t.exit(await c.install("file,tree"), 0, "file,tree");
            t.ok((await cache()) === before, "/var/cache/apk changed");
            t.ok((await c.text("ls -d /tmp/apk-packages.* 2>/dev/null || true")) === "", "a feature directory is left");
            const fetched = await c.text(
                String.raw`find / -xdev \( -name 'APKINDEX*' -o -name '*.apk' \) 2>/dev/null || true`,
            );
            t.ok(fetched === "", `index or package files remain: ${fetched}`);
        },
    },
    {
        scenario: "Same list on the second install",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("file,tree"), 0, "first install of file,tree");
            t.exit(await c.install("file,tree"), 0, "second install of file,tree");
            t.ok((await c.installed("file")) && (await c.installed("tree")), "file and tree are not both installed");
        },
    },
    {
        scenario: "Different list on the second install",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("file"), 0, "first install of file");
            t.exit(await c.install("tree"), 0, "second install of tree");
            t.ok((await c.installed("file")) && (await c.installed("tree")), "file and tree are not both installed");
            t.ok((await c.inWorld("file")) && (await c.inWorld("tree")), "apk's world does not hold file and tree");
        },
    },
    {
        scenario: "Later entry replaces the earlier constraint",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            const version = await c.offered("tree");
            t.exit(await c.install(`tree=${version}`), 0, `first install of tree=${version}`);
            t.ok(
                await c.inWorld(`tree=${version}`),
                `apk's world does not hold tree=${version} after the first install`,
            );
            t.exit(await c.install("tree"), 0, "second install of tree");
            t.ok(await c.inWorld("tree"), "apk's world does not hold tree without a constraint");
            t.ok(!(await c.inWorld(`tree=${version}`)), `apk's world still holds tree=${version}`);
            t.ok((await c.version("tree")) === version, `tree changed from ${version}`);
        },
    },
    {
        scenario: "Unsatisfiable constraint on the second install",
        on: "apk",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("tree"), 0, "first install of tree");
            const version = await c.version("tree");
            const state = await c.state();
            t.exit(await c.install(`tree<${version}`), "nonzero", `second install of tree<${version}`);
            t.ok((await c.version("tree")) === version, `tree changed from ${version}`);
            t.ok((await c.state()) === state, "apk's world, its installed database, or a cache changed");
        },
    },
    {
        scenario: "Omitted packages (image without apk)",
        on: "no-apk",
        network: "none",
        async run(c, t) {
            const before = await noApkSnapshot(c);
            t.exit(await c.install(), 0, "PACKAGES unset");
            t.ok((await noApkSnapshot(c)) === before, "the image changed");
        },
    },
    {
        scenario: "Empty list is a no-op (image without apk)",
        on: "no-apk",
        network: "none",
        async run(c, t) {
            const before = await noApkSnapshot(c);
            for (const value of EMPTY_LISTS) {
                t.exit(await c.install(value), 0, `PACKAGES=${JSON.stringify(value)}`);
            }
            t.ok((await noApkSnapshot(c)) === before, "the image changed");
        },
    },
    {
        scenario: "Image without apk fails clearly",
        on: "no-apk",
        network: "bridge",
        async run(c, t) {
            const before = await noApkSnapshot(c);
            const result = await c.install("file,tree>=1");
            t.exit(result, 1, "file,tree>=1");
            for (const word of ["apk", "Alpine Linux"]) t.says(result, word, "message");
            t.ok((await noApkSnapshot(c)) === before, "the image changed");
        },
    },
    {
        scenario: "URL or path is refused (image without apk: validation comes before the apk check)",
        on: "no-apk",
        network: "none",
        async run(c, t) {
            const before = await noApkSnapshot(c);
            const result = await c.install("file,/tmp/tree.apk");
            t.exit(result, 1, "file,/tmp/tree.apk");
            t.says(result, "refusing the entry '/tmp/tree.apk'", "message");
            t.ok(!result.out.includes("was not found"), "the apk check ran before validation");
            t.ok((await noApkSnapshot(c)) === before, "the image changed");
        },
    },
];

function compatibilityImages(): string[] {
    const compat = JSON.parse(Deno.readTextFileSync(COMPATIBILITY)) as {
        images: { image: string; arch?: string[] }[];
    };
    return compat.images.filter((entry) => (entry.arch ?? ["amd64"]).includes(HOST_ARCH)).map((entry) => entry.image);
}

function kindOf(image: string): Kind {
    if (image === NO_APK_IMAGE) return "no-apk";
    return LAGGING_IMAGES.includes(image) ? "lagging" : "apk";
}

if (import.meta.main) {
    const args = parseArgs(Deno.args, { string: ["image", "only"], boolean: ["list"], collect: ["image"] });
    const images = (args.image as string[]).length > 0
        ? (args.image as string[])
        : [...compatibilityImages(), ...LAGGING_IMAGES, NO_APK_IMAGE];
    const checks = CHECKS.filter((check) => !args.only || check.scenario.includes(args.only));
    const plan = images.flatMap((image) =>
        checks.filter((check) => check.on === kindOf(image)).map((check) => ({ image, check }))
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

    console.log(`apk-packages direct checks: ${FEATURE_DIR}/install.sh, host ${HOST_ARCH}`);
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
