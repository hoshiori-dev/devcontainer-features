#!/usr/bin/env -S deno run --allow-read --allow-run=docker
// Direct checks for pacman-packages: the spec scenarios a scenario test cannot assert — expected
// failures, two installs in one container, prepared or offline containers (design.md of the change
// that added the feature, decision "Direct checks for what a scenario cannot assert", and its Test
// plan). Runs src/pacman-packages/install.sh from this checkout, mounted read-only, as root in a
// throwaway container per check, and asserts the exit status, the message, and the image state.
// CI does not run it; paste its output into the PR's Validation section.
//
//   test/pacman-packages/direct_checks.ts [--image <ref>]... [--only <text>] [--list]
//
// Without --image it checks every image test/pacman-packages/compatibility.json lists for this
// machine's architecture, plus the pinned alpine image for the image without pacman. --only keeps
// the checks whose scenario contains <text>; --list prints the checks without running anything.
// It fails when no check would run, and without --image when the compatibility list has no image
// for this architecture. Needs docker and network access to the image's mirrors and, for the checks
// that need an outdated package, to the Arch Linux Archive; a check that needs no network runs
// offline. Package names and versions are read from the repositories at run time, so no fixed
// version goes stale.
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";
import { fromFileUrl } from "jsr:@std/path@1.1.6";

const FEATURE_DIR = fromFileUrl(new URL("../../src/pacman-packages", import.meta.url));
const COMPATIBILITY = fromFileUrl(new URL("./compatibility.json", import.meta.url));
const HOST_ARCH = Deno.build.arch === "aarch64" ? "arm64" : "amd64";

/** Outside the compatibility list: an image without pacman, whose /bin/sh is busybox (Docker Hub official image). */
const NO_PACMAN_IMAGE = "alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6";

/** Test-only host for previous package versions; the feature never reaches it. */
const ARCHIVE = "https://archive.archlinux.org/packages";

type Network = "bridge" | "none";

interface Result {
    code: number;
    stdout: string;
    /** stdout and stderr, in that order. */
    out: string;
}

async function docker(args: string[]): Promise<Result> {
    const output = await new Deno.Command("docker", { args, stdout: "piped", stderr: "piped" }).output();
    const decoder = new TextDecoder();
    const stdout = decoder.decode(output.stdout);
    return { code: output.code, stdout, out: stdout + decoder.decode(output.stderr) };
}

const live = new Set<string>();

class Container {
    private constructor(readonly name: string, readonly image: string) {}

    static async start(image: string, network: Network): Promise<Container> {
        const name = `pacman-packages-direct-${crypto.randomUUID().slice(0, 8)}`;
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

    /** Runs a POSIX sh script in the container; `args` arrive as "$1", "$2", … and are never parsed by a shell. */
    sh(script: string, ...args: string[]): Promise<Result> {
        return docker(["exec", this.name, "sh", "-c", script, "sh", ...args]);
    }

    /** Runs a script that must succeed and returns its trimmed standard output. */
    async text(script: string, ...args: string[]): Promise<string> {
        const result = await this.sh(script, ...args);
        if (result.code !== 0) throw new Error(`setup failed (exit ${result.code}): ${script}\n${result.out.trim()}`);
        return result.stdout.trim();
    }

    /** Runs the feature the way the CLI does, as root; `packages` undefined leaves PACKAGES unset. */
    install(packages?: string): Promise<Result> {
        const env = packages === undefined ? [] : ["--env", `PACKAGES=${packages}`];
        return docker(["exec", ...env, this.name, "/feature/install.sh"]);
    }

    async installed(pkg: string): Promise<boolean> {
        return (await this.sh('pacman -Qq -- "$1" >/dev/null 2>&1', pkg)).code === 0;
    }

    /** Names of all installed packages. */
    async installedNames(): Promise<Set<string>> {
        return new Set(lines(await this.text("pacman -Qq")));
    }

    version(pkg: string): Promise<string> {
        return this.text(`pacman -Q -- "$1" | awk '{print $2}'`, pkg);
    }

    /** The version the repositories offer; needs sync databases. */
    offered(pkg: string): Promise<string> {
        return this.text(`pacman -Si -- "$1" | sed -n 's/^Version *: //p' | head -n 1`, pkg);
    }

    /** `pacman -Q`: every installed package with its version. */
    localDb(): Promise<string> {
        return this.text("pacman -Q");
    }

    /** Number of files in /var/lib/pacman/sync. */
    async syncCount(): Promise<number> {
        return Number(await this.text("find /var/lib/pacman/sync -mindepth 1 | wc -l"));
    }

    /** Downloads the sync databases, for the runner's own queries. */
    async sync(): Promise<void> {
        await this.text("pacman -Sy >/dev/null");
    }

    /** Returns the container to the state the image ships in: no sync database, no cached package. */
    async clean(): Promise<void> {
        await this.text("rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/*");
    }

    async remove(): Promise<void> {
        await docker(["rm", "--force", this.name]);
        live.delete(this.name);
    }
}

class Asserter {
    readonly failures: string[] = [];
    /** What the check chose at run time, printed under its verdict. */
    readonly notes: string[] = [];
    /** Set by `again`: the reason to repeat the check once in a fresh container. */
    repeat?: string;

    constructor(private readonly lastAttempt: boolean) {}

    ok(condition: boolean, message: string): void {
        if (!condition) this.failures.push(message);
    }

    note(message: string): void {
        this.notes.push(message);
    }

    /** `expected` is an exit status, or "nonzero" for any failure. */
    exit(result: Result, expected: number | "nonzero", what: string): void {
        const passed = expected === "nonzero" ? result.code !== 0 : result.code === expected;
        this.ok(passed, `${what}: expected exit ${expected}, got ${result.code}; output:\n${indent(result.out)}`);
    }

    says(result: Result, text: string, what: string): void {
        this.ok(result.out.includes(text), `${what}: output does not contain ${JSON.stringify(text)}`);
    }

    /** A finding that a mirror update during the check can cause: repeat once, then it is a failure. */
    again(message: string): void {
        if (this.lastAttempt) this.failures.push(message);
        else this.repeat = message;
    }
}

function indent(text: string): string {
    const all = text.trim().split("\n");
    const shown = all.length > 25 ? ["…", ...all.slice(-25)] : all;
    return shown.map((line) => `      ${line}`).join("\n");
}

function lines(text: string): string[] {
    return text.split("\n").map((line) => line.trim()).filter((line) => line !== "");
}

interface Check {
    /** The spec scenario(s) the check covers. */
    scenario: string;
    /** "pacman": every compatibility image; "no-pacman": the image without pacman. */
    on: "pacman" | "no-pacman";
    network: Network;
    run(c: Container, t: Asserter): Promise<void>;
}

/** Package lists that are valid but must leave the image untouched. */
const EMPTY_LISTS = ["", " , ,\t, ", ","];

const URL_OR_PATH = [
    "/tmp/bc.pkg.tar.zst",
    "./bc.pkg.tar.zst",
    `${ARCHIVE}/b/bc/bc.pkg.tar.zst`,
    "file:///tmp/bc.pkg.tar.zst",
    "extra/bc",
];
const OPTION_LIKE = ["--nodeps", "-dd", "--assume-installed=glibc", "-"];
const SHELL_AND_WHITESPACE = [
    "x;touch /tmp/pwned",
    "$(touch /tmp/pwned)",
    "`touch /tmp/pwned`",
    "bc|touch /tmp/pwned",
    "bc&&touch /tmp/pwned",
    "b*",
    "b?",
    "bc~1",
    "bc tree",
    "bc\ttree",
    // A non-ASCII letter: c with acute.
    "b\u0107",
];

/**
 * The words that name a refused entry. Not the bare entry: "-" is also in the "pacman-packages:" prefix of every
 * message, and quoted in the allowlist the refusal spells out.
 */
function refusal(entry: string): string {
    return `refusing the entry '${entry}'`;
}

/** Each refusal runs with a valid entry beside it, so a validation gap would install something. */
async function refuses(c: Container, t: Asserter, entries: string[]): Promise<void> {
    const before = await c.localDb();
    for (const entry of entries) {
        const what = `entry ${JSON.stringify(entry)}`;
        const result = await c.install(`tree,${entry}`);
        t.exit(result, 1, what);
        t.says(result, refusal(entry), what);
        t.ok((await c.syncCount()) === 0, `${what}: a sync database was downloaded`);
        t.ok((await c.localDb()) === before, `${what}: the installed packages changed`);
        t.ok((await c.sh("test ! -e /tmp/pwned")).code === 0, `${what}: a command in the entry ran`);
    }
}

/** On the image without pacman, where /bin/sh is busybox: the exit status and the message. */
async function refusesWithoutPacman(c: Container, t: Asserter, entries: string[]): Promise<void> {
    const shell = await c.text("readlink -f /bin/sh");
    t.ok(shell.includes("busybox"), `/bin/sh is ${shell}, not busybox`);
    for (const entry of entries) {
        const what = `entry ${JSON.stringify(entry)}`;
        const result = await c.install(`tree,${entry}`);
        t.exit(result, 1, what);
        t.says(result, refusal(entry), what);
        t.ok((await c.sh("test ! -e /tmp/pwned")).code === 0, `${what}: a command in the entry ran`);
    }
}

/**
 * The newest version of `pkg` in the Arch Linux Archive that is older than the one the repositories offer, with the
 * URL of its package file. `pacman -U <url>` verifies the detached signature beside it under the image's SigLevel.
 * Needs sync databases.
 */
async function previousVersion(c: Container, pkg: string): Promise<{ previous: string; current: string; url: string }> {
    const current = await c.offered(pkg);
    const arch = await c.text(`pacman -Si -- "$1" | sed -n 's/^Architecture *: //p' | head -n 1`, pkg);
    const directory = `${ARCHIVE}/${pkg[0]}/${pkg}/`;
    const listing = await c.text('curl -fsSL --retry 2 -- "$1"', directory);
    const prefix = `${pkg}-`;
    const suffix = `-${arch}.pkg.tar.zst`;
    const versions = [...listing.matchAll(/href="([^"]+)"/g)]
        .map((match) => match[1])
        .filter((file) => file.startsWith(prefix) && file.endsWith(suffix))
        .map((file) => file.slice(prefix.length, -suffix.length))
        // pkgver-pkgrel without an epoch, whose colon the listing would percent-encode.
        .filter((version) => /^[A-Za-z0-9._+]+-[0-9.]+$/.test(version));
    const previous = await c.text(
        `
current=$1
shift
best=
for v in "$@"; do
  [ "$(vercmp "$v" "$current")" -lt 0 ] || continue
  if [ -z "$best" ] || [ "$(vercmp "$v" "$best")" -gt 0 ]; then best=$v; fi
done
printf '%s\\n' "$best"
`,
        current,
        ...versions,
    );
    if (previous === "") throw new Error(`the Arch Linux Archive lists no version of ${pkg} older than ${current}`);
    return { previous, current, url: `${directory}${prefix}${previous}${suffix}` };
}

/** Installs the previous version of `pkg` from the Arch Linux Archive, so the container holds an outdated package. */
async function installPrevious(c: Container, pkg: string): Promise<{ previous: string; current: string }> {
    const { previous, current, url } = await previousVersion(c, pkg);
    await c.text('pacman -U --noconfirm -- "$1" >/dev/null', url);
    const installed = await c.version(pkg);
    if (installed !== previous) throw new Error(`${pkg} is at ${installed} after installing ${previous}`);
    return { previous, current };
}

/** Outdated installed packages, as a fresh synchronization and `pacman -Qu` list them. */
async function outdated(c: Container): Promise<string[]> {
    await c.sync();
    // pacman -Qu exits 1 when it lists nothing.
    return lines((await c.sh("pacman -Qu")).stdout);
}

/** Package names and, for every provided name without its version, the packages that provide it. */
async function repositoryNames(c: Container): Promise<{ names: Set<string>; providers: Map<string, Set<string>> }> {
    const names = new Set<string>();
    const providers = new Map<string, Set<string>>();
    let name = "";
    for (const line of (await c.text("pacman -Si")).split("\n")) {
        const field = line.match(/^(Name|Provides) +: (.*)$/);
        if (!field) continue;
        if (field[1] === "Name") {
            name = field[2].trim();
            names.add(name);
            continue;
        }
        for (const provided of field[2].trim().split(/\s+/)) {
            const bare = provided.replace(/[<>=].*$/, "");
            if (bare === "None" || bare === "") continue;
            if (!providers.has(bare)) providers.set(bare, new Set());
            providers.get(bare)!.add(name);
        }
    }
    return { names, providers };
}

/** The packages `pacman` would install for `target`, with their download sizes; undefined when it refuses. */
async function resolution(c: Container, target: string): Promise<Map<string, number> | undefined> {
    const result = await c.sh(`pacman -Sp --print-format '%n %s' --noconfirm -- "$1"`, target);
    if (result.code !== 0) return undefined;
    return new Map(
        lines(result.stdout).map((line) => {
            const [name, size] = line.split(" ");
            return [name, Number(size)];
        }),
    );
}

/**
 * A name that no package has and several packages provide, none of them installed, with the one provider `pacman`
 * itself chooses for it. Needs sync databases.
 */
async function providedName(c: Container): Promise<{ name: string; chosen: string; others: string[] }> {
    const { names, providers } = await repositoryNames(c);
    const installed = await c.installedNames();
    const candidates = [...providers]
        .filter(([provided, by]) => !names.has(provided) && !provided.includes(".so") && by.size > 1)
        .filter(([, by]) => [...by].every((pkg) => !installed.has(pkg)))
        .map(([provided]) => provided)
        .sort();
    // cron first: two small providers; the others in order, the first that resolves to one provider and few packages.
    const ordered = [...candidates.filter((name) => name === "cron"), ...candidates.filter((name) => name !== "cron")];
    for (const name of ordered.slice(0, 40)) {
        const resolved = await resolution(c, name);
        if (!resolved || resolved.size > 12) continue;
        const by = providers.get(name)!;
        const chosen = [...resolved.keys()].filter((pkg) => by.has(pkg));
        if (chosen.length !== 1) continue;
        return { name, chosen: chosen[0], others: [...by].filter((pkg) => pkg !== chosen[0]) };
    }
    throw new Error(`no provided name with several providers resolves to one small provider on ${c.image}`);
}

/**
 * The package group with the smallest download among those of two to four members, none installed, whose name is no
 * package and no provided name. Needs sync databases.
 */
async function smallGroup(c: Container): Promise<{ group: string; members: string[] }> {
    const { names, providers } = await repositoryNames(c);
    const installed = await c.installedNames();
    const groups = new Map<string, string[]>();
    for (const line of lines(await c.text("pacman -Sgg"))) {
        const [group, member] = line.split(" ");
        groups.set(group, [...(groups.get(group) ?? []), member]);
    }
    let best: { group: string; members: string[]; size: number } | undefined;
    for (const [group, members] of groups) {
        if (members.length < 2 || members.length > 4) continue;
        if (names.has(group) || providers.has(group) || members.some((member) => installed.has(member))) continue;
        const resolved = await resolution(c, group);
        if (!resolved || !members.every((member) => resolved.has(member))) continue;
        const size = [...resolved.values()].reduce((sum, bytes) => sum + bytes, 0);
        if (!best || size < best.size) best = { group, members, size };
    }
    if (!best) throw new Error(`no small package group is offered on ${c.image}`);
    return best;
}

/** The files under /etc/pacman.d and /etc/pacman.conf: names, link targets, and content, keyring included. */
function pacmanConfiguration(c: Container): Promise<string> {
    return c.text(
        "{ find /etc/pacman.conf /etc/pacman.d \\( -type f -o -type l -o -type d \\) -printf '%p %y %m %l\\n' | sort; " +
            "find /etc/pacman.conf /etc/pacman.d -type f -exec sha256sum {} + | sort; } | sha256sum",
    );
}

/** Packages whose name or version differs between two `pacman -Q` listings. */
function changedPackages(before: string, after: string): string[] {
    const earlier = new Set(lines(before));
    return lines(after).filter((line) => !earlier.has(line)).map((line) => line.split(" ")[0]);
}

/** The md5 sum the local database records for a package's backup file, as the package ships it. */
function backupSum(c: Container, pkg: string, file: string): Promise<string> {
    return c.text(
        `awk -v f="$2" '$1 == f && NF == 2 { print $2 }' /var/lib/pacman/local/"$1"-[0-9]*/files | head -n 1`,
        pkg,
        file.replace(/^\//, ""),
    );
}

const CHECKS: Check[] = [
    {
        scenario: "Omitted packages",
        on: "pacman",
        network: "none",
        async run(c, t) {
            const before = await c.localDb();
            t.exit(await c.install(), 0, "PACKAGES unset");
            t.ok((await c.syncCount()) === 0, "a sync database was downloaded");
            t.ok((await c.localDb()) === before, "the installed packages changed");
        },
    },
    {
        scenario: "Empty list is a no-op",
        on: "pacman",
        network: "none",
        async run(c, t) {
            const before = await c.localDb();
            for (const value of EMPTY_LISTS) {
                t.exit(await c.install(value), 0, `PACKAGES=${JSON.stringify(value)}`);
            }
            t.ok((await c.syncCount()) === 0, "a sync database was downloaded");
            t.ok((await c.localDb()) === before, "the installed packages changed");
        },
    },
    {
        scenario: "Listed package already up to date",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            const installDate = () =>
                c.text("awk '/^%INSTALLDATE%$/ { getline; print }' /var/lib/pacman/local/bc-[0-9]*/desc");
            t.exit(await c.install("bc"), 0, "first install of bc");
            const version = await c.version("bc");
            const date = await installDate();
            // A reinstall a second later would record another install date.
            await c.text("sleep 2");
            const second = await c.install("bc");
            t.exit(second, 0, "bc listed again");
            t.says(second, "is up to date -- skipping", "bc listed again");
            t.ok((await c.version("bc")) === version, `bc changed from ${version}`);
            t.ok((await installDate()) === date, "bc was reinstalled: its install date changed");
            await c.sync();
            const offered = await c.offered("bc");
            t.ok(offered === version, `installed bc ${version} is not the offered version ${offered}`);
            t.note(`bc ${version}, install date ${date} after both runs`);
        },
    },
    {
        scenario: "Outdated installed packages are upgraded",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            let stale = await outdated(c);
            if (stale.length === 0) {
                // Nothing outdated in this image build: make a small package outdated.
                const { previous, current } = await installPrevious(c, "tree");
                stale = [`tree ${previous} -> ${current}`];
            }
            await c.clean();
            t.note(`outdated before the run: ${stale.join("; ")}`);
            t.exit(await c.install("bc"), 0, `bc with ${stale.length} outdated package(s)`);
            t.ok(await c.installed("bc"), "bc is not installed");
            // A mirror update between the feature's synchronization and this one can list a package that was
            // current when the feature ran.
            const left = await outdated(c);
            if (left.length > 0) t.again(`still outdated after the feature ran: ${left.join("; ")}`);
        },
    },
    {
        scenario: "Satisfied constraint is installed",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            await c.sync();
            const bc = await c.offered("bc");
            const tree = await c.offered("tree");
            await c.clean();
            // name=<offered pkgver>, without the pkgrel, and name>=<offered version>.
            const entries = `bc=${bc.replace(/-[^-]*$/, "")},tree>=${tree}`;
            t.note(`packages: ${entries}`);
            t.exit(await c.install(entries), 0, entries);
            t.ok((await c.installed("bc")) && (await c.version("bc")) === bc, `bc ${bc} is not installed`);
            t.ok((await c.installed("tree")) && (await c.version("tree")) === tree, `tree ${tree} is not installed`);
        },
    },
    {
        scenario: "Unsatisfied constraint fails",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            await c.sync();
            const bc = await c.offered("bc");
            await c.clean();
            const before = await c.localDb();
            const entries = `tree,bc<${bc}`;
            t.note(`packages: ${entries}`);
            t.exit(await c.install(entries), "nonzero", entries);
            t.ok((await c.localDb()) === before, "a package was installed or upgraded");
        },
    },
    {
        scenario: "URL or path is refused",
        on: "pacman",
        network: "bridge",
        run: (c, t) => refuses(c, t, URL_OR_PATH),
    },
    {
        scenario: "Option-like entry is refused",
        on: "pacman",
        network: "bridge",
        run: (c, t) => refuses(c, t, OPTION_LIKE),
    },
    {
        scenario: "Shell metacharacters and inner whitespace are refused",
        on: "pacman",
        network: "bridge",
        run: (c, t) => refuses(c, t, SHELL_AND_WHITESPACE),
    },
    {
        scenario: "Unknown package fails",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            const before = await c.localDb();
            t.exit(await c.install("tree,pacman-packages-no-such-package"), "nonzero", "unknown package");
            t.ok((await c.localDb()) === before, "a package was installed or upgraded");
        },
    },
    {
        scenario: "Entry is not matched as a regular expression",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            const before = await c.localDb();
            t.exit(await c.install("tree,b."), "nonzero", "b.");
            t.ok((await c.localDb()) === before, "a package was installed or upgraded");
            // Premise: read as a regular expression, b. matches names of packages the repositories offer.
            await c.sync();
            const matched = lines((await c.sh("pacman -Ssq '^b.$'")).stdout);
            t.ok(matched.length > 0, "no offered package name matches the regular expression ^b.$");
            t.note(`b. names nothing; as a regular expression it matches ${matched.join(", ")}`);
        },
    },
    {
        scenario: "Name with several providers installs the first",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            await c.sync();
            const { name, chosen, others } = await providedName(c);
            await c.clean();
            const what = `${name} (pacman chooses ${chosen}; also provided by ${others.join(", ")})`;
            t.note(`packages: ${what}`);
            t.exit(await c.install(name), 0, what);
            t.ok(await c.installed(chosen), `${what}: ${chosen} is not installed`);
            for (const other of others) {
                t.ok(!(await c.installed(other)), `${what}: the provider ${other} is installed too`);
            }
        },
    },
    {
        scenario: "Group name installs the whole group",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            await c.sync();
            const { group, members } = await smallGroup(c);
            await c.clean();
            const what = `group ${group} (${members.join(", ")})`;
            t.note(`packages: ${what}`);
            t.exit(await c.install(group), 0, what);
            for (const member of members) t.ok(await c.installed(member), `${what}: ${member} is not installed`);
        },
    },
    {
        scenario: "Failed refresh fails the feature",
        on: "pacman",
        network: "none",
        async run(c, t) {
            const before = await c.localDb();
            const result = await c.install("bc");
            t.exit(result, "nonzero", "synchronization without network");
            t.says(result, "failed to synchronize", "synchronization without network");
            t.ok((await c.localDb()) === before, "a package was installed or upgraded");
        },
    },
    {
        scenario: "Untrusted signature fails the install",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            // A freshly initialized keyring trusts none of the keys that sign the repositories' packages.
            await c.text("rm -rf /etc/pacman.d/gnupg && pacman-key --init >/dev/null 2>&1");
            const before = await c.localDb();
            const result = await c.install("bc");
            t.exit(result, "nonzero", "install against a keyring without the Arch Linux keys");
            t.ok(/unknown trust|invalid or corrupted package \(PGP signature\)/.test(result.out), "no signature error");
            t.ok((await c.localDb()) === before, "a package was installed or upgraded");
        },
    },
    {
        scenario: "Pacman configuration is unchanged",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            // Bring the container current first, so the feature's transaction holds only bc and its dependencies.
            await c.text("pacman -Syu --noconfirm >/dev/null");
            await c.clean();
            const configuration = await pacmanConfiguration(c);
            const before = await c.localDb();
            const result = await c.install("bc");
            t.exit(result, 0, "bc");
            const changed = changedPackages(before, await c.localDb());
            t.ok(changed.includes("bc"), "bc is not installed");
            t.note(`the transaction installed or upgraded: ${changed.join(", ")}`);
            // The scenario's precondition, checked: no changed package owns a file there, and no key was imported.
            const owned = lines(
                (await c.sh('pacman -Qlq -- "$@" | grep -E "^/etc/pacman\\.(conf$|d/)"', ...changed)).stdout,
            );
            t.ok(owned.length === 0, `${changed.join(", ")} own ${owned.join(", ")}`);
            t.ok(
                !result.out.includes("Import PGP key"),
                "the transaction imported a packager key, so the scenario's precondition does not hold",
            );
            t.ok((await pacmanConfiguration(c)) === configuration, "/etc/pacman.conf or /etc/pacman.d changed");
        },
    },
    {
        scenario: "Missing certified key is fetched",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            const gpg = "gpg --homedir /etc/pacman.d/gnupg --batch";
            // The key that signs tree, which is not installed: read from the package's detached signature.
            await c.sync();
            await c.text("pacman -Sw --noconfirm tree >/dev/null");
            const signer = await c.text(
                `${gpg} --list-packets /var/cache/pacman/pkg/tree-*.sig 2>/dev/null | ` +
                    "sed -n 's/.*issuer fpr v[0-9]* \\([0-9A-F]*\\)).*/\\1/p' | head -n 1",
            );
            t.ok(/^[0-9A-F]{40}$/.test(signer), `no issuer fingerprint in tree's signature: ${signer}`);
            const key = await c.text(
                `${gpg} --with-colons --list-keys -- "$1" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'`,
                signer,
            );
            await c.text('pacman-key --delete "$1" >/dev/null 2>&1', key);
            const present = () => c.sh(`${gpg} --list-keys -- "$1" >/dev/null 2>&1`, key);
            t.ok((await present()).code !== 0, `the key ${key} is still in the keyring after its deletion`);
            await c.clean();
            const result = await c.install("tree");
            t.note(`tree is signed by ${signer}; deleted the key ${key} from the keyring`);
            t.exit(result, 0, `tree, signed by the deleted key ${key}`);
            t.says(result, "Import PGP key", "tree");
            t.ok(await c.installed("tree"), "tree is not installed");
            t.ok((await present()).code === 0, `the key ${key} is not back in the keyring`);
        },
    },
    {
        scenario: "Installation runs without a terminal",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            // No terminal, no input; a run that waited for input would end with timeout's status 124.
            const result = await docker([
                "exec",
                "--env",
                "PACKAGES=bc",
                c.name,
                "sh",
                "-c",
                "test ! -t 0 && test ! -t 1 && exec timeout 900 /feature/install.sh </dev/null",
            ]);
            t.exit(result, 0, "bc with stdin from /dev/null");
            t.ok(await c.installed("bc"), "bc is not installed");
        },
    },
    {
        scenario: "Conflict with an installed package fails",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("vim"), 0, "first install of vim");
            const result = await c.install("tree,gvim");
            t.exit(result, "nonzero", "tree,gvim with vim installed");
            t.says(result, "conflict", "tree,gvim with vim installed");
            t.ok(await c.installed("vim"), "vim is no longer installed");
            t.ok(!(await c.installed("gvim")) && !(await c.installed("tree")), "a listed package was installed");
        },
    },
    {
        scenario: "Changed configuration file is kept on upgrade",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            // nano ships /etc/nanorc as a backup file.
            const pkg = "nano";
            const file = "/etc/nanorc";
            await c.sync();
            const { previous, current } = await installPrevious(c, pkg);
            const shipped = await backupSum(c, pkg, file);
            t.ok(shipped !== "", `${pkg} ${previous} records no backup file ${file}`);
            await c.text(`echo '# changed by the pacman-packages direct checks' >> "$1"`, file);
            const changed = await c.text('sha256sum < "$1"', file);
            await c.clean();
            const what = `tree with ${pkg} ${previous} installed, ${current} offered`;
            t.note(`packages: ${what}; ${file} changed`);
            t.exit(await c.install("tree"), 0, what);
            const upgraded = await c.version(pkg);
            t.ok(upgraded === current, `${what}: ${pkg} is at ${upgraded}`);
            t.ok((await c.text('sha256sum < "$1"', file)) === changed, `${what}: ${file} lost its changed content`);
            // pacman writes <file>.pacnew only when the new package's copy differs from the old package's.
            const shippedNow = await backupSum(c, pkg, file);
            if (shippedNow !== shipped) {
                const pacnew = await c.sh(`md5sum < "$1.pacnew"`, file);
                t.ok(
                    pacnew.code === 0 && pacnew.stdout.startsWith(shippedNow),
                    `${what}: ${file}.pacnew is missing or is not the new package's copy`,
                );
                t.note(`${file} differs between the two versions; ${file}.pacnew is the new package's copy`);
            } else {
                t.note(`${file} is the same in ${pkg} ${previous} and ${current}, so no .pacnew is due`);
            }
        },
    },
    {
        scenario: "Same list on the second install",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("bc,tree"), 0, "first install of bc,tree");
            t.exit(await c.install("bc,tree"), 0, "second install of bc,tree");
            t.ok((await c.installed("bc")) && (await c.installed("tree")), "bc and tree are not both installed");
        },
    },
    {
        scenario: "Different list on the second install",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("bc"), 0, "first install of bc");
            t.exit(await c.install("tree"), 0, "second install of tree");
            t.ok((await c.installed("bc")) && (await c.installed("tree")), "bc and tree are not both installed");
        },
    },
    {
        scenario: "Constraint below the installed version on the second install",
        on: "pacman",
        network: "bridge",
        async run(c, t) {
            t.exit(await c.install("bc"), 0, "first install of bc");
            const installed = await c.version("bc");
            await c.sync();
            // A version that existed: the one before the offered version, from the Arch Linux Archive.
            const { previous } = await previousVersion(c, "bc");
            await c.clean();
            t.note(`bc ${installed} installed; second lists bc<${installed}, then bc=${previous}`);
            for (const entry of [`bc<${installed}`, `bc=${previous}`]) {
                t.exit(await c.install(entry), "nonzero", `second install of ${entry}`);
                t.ok((await c.version("bc")) === installed, `${entry}: bc changed from ${installed}`);
            }
        },
    },
    {
        scenario: "Omitted packages (image without pacman)",
        on: "no-pacman",
        network: "none",
        async run(c, t) {
            const before = await noPacmanSnapshot(c);
            t.exit(await c.install(), 0, "PACKAGES unset");
            t.ok((await noPacmanSnapshot(c)) === before, "the image changed");
        },
    },
    {
        scenario: "Empty list is a no-op (image without pacman)",
        on: "no-pacman",
        network: "none",
        async run(c, t) {
            const before = await noPacmanSnapshot(c);
            for (const value of EMPTY_LISTS) {
                t.exit(await c.install(value), 0, `PACKAGES=${JSON.stringify(value)}`);
            }
            t.ok((await noPacmanSnapshot(c)) === before, "the image changed");
        },
    },
    {
        scenario: "Image without pacman fails clearly",
        on: "no-pacman",
        network: "bridge",
        async run(c, t) {
            const before = await noPacmanSnapshot(c);
            const result = await c.install("bc");
            t.exit(result, 1, "bc");
            // "pacman" alone is also in the "pacman-packages:" prefix of every message.
            for (const words of ["pacman was not found", "Arch Linux"]) t.says(result, words, "message");
            t.ok((await noPacmanSnapshot(c)) === before, "the image changed");
        },
    },
    {
        scenario: "URL or path is refused (image without pacman)",
        on: "no-pacman",
        network: "bridge",
        run: (c, t) => refusesWithoutPacman(c, t, URL_OR_PATH),
    },
    {
        scenario: "Option-like entry is refused (image without pacman)",
        on: "no-pacman",
        network: "bridge",
        run: (c, t) => refusesWithoutPacman(c, t, OPTION_LIKE),
    },
    {
        scenario: "Shell metacharacters and inner whitespace are refused (image without pacman)",
        on: "no-pacman",
        network: "bridge",
        run: (c, t) => refusesWithoutPacman(c, t, SHELL_AND_WHITESPACE),
    },
];

/** File names under the system directories plus the content of /etc and the apk database. */
function noPacmanSnapshot(c: Container): Promise<string> {
    return c.text(
        "{ find /bin /etc /lib /opt /root /sbin /usr /var -xdev 2>/dev/null | sort; " +
            "find /etc -type f -exec sha256sum {} + | sort; cat /lib/apk/db/installed; } | sha256sum",
    );
}

function pacmanImages(): string[] {
    const compat = JSON.parse(Deno.readTextFileSync(COMPATIBILITY)) as {
        images: { image: string; arch?: string[] }[];
    };
    return compat.images.filter((entry) => (entry.arch ?? ["amd64"]).includes(HOST_ARCH)).map((entry) => entry.image);
}

if (import.meta.main) {
    const args = parseArgs(Deno.args, { string: ["image", "only"], boolean: ["list"], collect: ["image"] });
    const given = args.image as string[];
    const listed = pacmanImages();
    const images = given.length > 0 ? given : [...listed, NO_PACMAN_IMAGE];
    const checks = CHECKS.filter((check) => !args.only || check.scenario.includes(args.only));
    const plan = images.flatMap((image) =>
        checks.filter((check) => (check.on === "no-pacman") === (image === NO_PACMAN_IMAGE)).map((check) => ({
            image,
            check,
        }))
    );
    if (args.list) {
        for (const { image, check } of plan) console.log(`${image}  ${check.scenario}  (network: ${check.network})`);
        Deno.exit(0);
    }
    // As `just test`: a run that checked nothing, or nothing on an image with pacman, fails instead of passing.
    if (given.length === 0 && listed.length === 0) {
        console.error(
            `error: no image in ${COMPATIBILITY} lists ${HOST_ARCH}, so no check would run against pacman. ` +
                "Pass --image <ref> to check one anyway.",
        );
        Deno.exit(1);
    }
    if (plan.length === 0) {
        console.error("error: no check matches --image and --only, so nothing would run. See --list.");
        Deno.exit(1);
    }
    const cleanup = async () => {
        await Promise.all([...live].map((name) => docker(["rm", "--force", name])));
        Deno.exit(130);
    };
    Deno.addSignalListener("SIGINT", cleanup);
    Deno.addSignalListener("SIGTERM", cleanup);

    console.log(`pacman-packages direct checks: ${FEATURE_DIR}/install.sh, host ${HOST_ARCH}`);
    let failed = 0;
    for (const { image, check } of plan) {
        let t = new Asserter(false);
        // A second attempt only when the check asks for one (Asserter.again), in a fresh container.
        for (const lastAttempt of [false, true]) {
            t = new Asserter(lastAttempt);
            let c: Container | undefined;
            try {
                c = await Container.start(image, check.network);
                await check.run(c, t);
            } catch (error) {
                t.failures.push(`error: ${error instanceof Error ? error.message : String(error)}`);
            } finally {
                await c?.remove();
            }
            if (t.repeat === undefined) break;
            console.log(`AGAIN ${image}  ${check.scenario}\n    - ${t.repeat}`);
        }
        const verdict = t.failures.length === 0 ? "PASS" : "FAIL";
        if (verdict === "FAIL") failed++;
        console.log(`${verdict}  ${image}  ${check.scenario}`);
        for (const failure of t.failures) console.log(`    - ${failure}`);
        for (const note of t.notes) console.log(`    note: ${note}`);
    }
    console.log(`\n${plan.length - failed} passed, ${failed} failed (${plan.length} checks)`);
    if (failed > 0) Deno.exit(1);
}
