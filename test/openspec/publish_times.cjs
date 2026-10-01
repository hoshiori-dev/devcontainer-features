// "Dependency released later": compares the registry publish time of every package of an installed
// tree with that of the OpenSpec version it holds.
//
//   node publish_times.cjs <prefix> <report file>
//
// Exits 1 when a package was published after the OpenSpec version. The report also lists, as
// "kept out:" lines, the dependencies that have a later release of the same major version, which
// an install without the bound could have taken.
const fs = require("node:fs");

const REGISTRY = "https://registry.npmjs.org/";
const MAIN = "@fission-ai/openspec";
const [prefix, reportFile] = process.argv.slice(2);

const documents = new Map();
function registryDocument(name) {
    if (!documents.has(name)) {
        documents.set(
            name,
            fetch(REGISTRY + name.replace("/", "%2f"), { redirect: "error" }).then((response) => {
                if (response.status !== 200) throw new Error(`${name}: the registry answered ${response.status}`);
                return response.json();
            }),
        );
    }
    return documents.get(name);
}

/** MAJOR.MINOR.PATCH as numbers, or undefined for a pre-release or anything else. */
function release(version) {
    const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(version);
    return match ? match.slice(1).map(Number) : undefined;
}

function newer(a, b) {
    for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] > b[i];
    return false;
}

(async () => {
    const packages = JSON.parse(fs.readFileSync(`${prefix}/package-lock.json`, "utf8")).packages;
    const mainVersion = packages[`node_modules/${MAIN}`].version;
    const bound = new Date((await registryDocument(MAIN)).time[mainVersion]);
    const lines = [`bound: ${MAIN} ${mainVersion}, published ${bound.toISOString()}`];
    const entries = Object.entries(packages).filter(([entry]) => entry !== "").map(([entry, value]) => [
        value.name ?? entry.slice(entry.lastIndexOf("node_modules/") + "node_modules/".length),
        value,
    ]);
    // All documents are requested at once, so the check takes a second or two.
    await Promise.all(entries.map(([name]) => registryDocument(name)));
    const late = [];
    for (const [name, value] of entries) {
        const document = await registryDocument(name);
        const published = new Date(document.time[value.version]);
        if (!(published.getTime() <= bound.getTime())) {
            late.push(`published after the bound: ${name} ${value.version} (${document.time[value.version]})`);
        }
        const installed = release(value.version);
        if (name === MAIN || !installed) continue;
        const later = Object.keys(document.versions).filter((version) => {
            const candidate = release(version);
            return candidate && candidate[0] === installed[0] && newer(candidate, installed) &&
                new Date(document.time[version]).getTime() > bound.getTime();
        });
        if (later.length > 0) lines.push(`kept out: ${name} ${later.join(", ")} (installed: ${value.version})`);
    }
    lines.push(...late, `${entries.length} packages, ${late.length} published after the bound`);
    fs.writeFileSync(reportFile, lines.join("\n") + "\n");
    process.exit(late.length === 0 ? 0 : 1);
})().catch((error) => {
    fs.writeFileSync(reportFile, `error: ${error.message}\n`);
    process.exit(1);
});
