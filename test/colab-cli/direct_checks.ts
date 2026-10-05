#!/usr/bin/env -S deno run --allow-read --allow-write=/tmp --allow-run=docker
// Failure and repeat-install observations on images built by `just test colab-cli --preserve`.
// Usage: ./test/colab-cli/direct_checks.ts ROOT_IMAGE NON_ROOT_IMAGE
const [rootImage, userImage] = Deno.args;
if (!rootImage || !userImage) throw new Error("Supply tested root and non-root images.");
const scratch = await Deno.makeTempDir({ prefix: "colab-cli-observations-" });
// Every observation runs the same source snapshot, even if development continues while Docker starts it.
const source = `${scratch}/install.sh`;
await Deno.writeTextFile(source, await Deno.readTextFile("src/colab-cli/install.sh"));
const decoder = new TextDecoder();
let passed = 0;
async function observe(label: string, command: string, expected = "", image = rootImage, network = "none") {
    const result = await new Deno.Command("docker", {
        args: [
            "run",
            "--rm",
            "--user",
            "root",
            "--network",
            network,
            "--mount",
            `type=bind,src=${source},dst=/tmp/colab-cli-install.sh,readonly`,
            "--entrypoint",
            "bash",
            image,
            "-euc",
            command,
        ],
        stdout: "piped",
        stderr: "piped",
    }).output();
    const text = decoder.decode(result.stdout) + decoder.decode(result.stderr);
    await Deno.writeTextFile(`${scratch}/${label}.log`, text);
    if (expected ? result.code === 0 || !text.includes(expected) : result.code !== 0) {
        throw new Error(`${label}: exit ${result.code}; inspect ${scratch}/${label}.log`);
    }
    console.log(`PASS ${label}`);
    passed++;
}
const install = "bash /tmp/colab-cli-install.sh";
const python = "/usr/local/share/uv/tools/google-colab-cli/bin/python";
for (const version of ["", "0.7", "v0.7.2", "0.7.2rc1", "--help", "0.7.2\n0.7.4"]) {
    // Controlled literals are single-quoted as shell arguments; no input is evaluated as shell code.
    await observe(`invalid-${passed}`, `VERSION='${version}' ${install}`, "option version is");
}
await observe(
    "unsupported-distribution",
    `printf 'ID=alpine\n' >/etc/os-release; ${install}`,
    "unsupported distribution",
);
await observe(
    "unsupported-architecture",
    `printf '#!/bin/sh\necho riscv64\n' >/usr/local/sbin/uname; chmod +x /usr/local/sbin/uname; ${install}`,
    "unsupported architecture",
);
await observe(
    "older-uv",
    `printf '#!/bin/sh\necho "uv 0.12.15"\n' >/usr/local/bin/uv; ${install}`,
    "uv 0.12.15 does not verify package hashes",
);
await observe("missing-user", `_REMOTE_USER=missing-colab-user ${install}`, "remote user missing-colab-user");
await observe(
    "missing-release",
    `VERSION=9999.9999.9999 ${install}`,
    "cannot install google-colab-cli 9999.9999.9999",
    rootImage,
    "bridge",
);
await observe(
    "download-failure",
    `VERSION=9999.9999.9999 ${install}`,
    "cannot install google-colab-cli 9999.9999.9999",
);
const fingerprint = `${python} -I -c '
from pathlib import Path
import hashlib
root = Path("/usr/local/share/uv/tools/google-colab-cli")
for p in sorted(root.rglob("*")):
    if p.is_file(): print(p.relative_to(root), p.stat().st_mtime_ns, hashlib.sha256(p.read_bytes()).hexdigest())'`;
for (const [image, user] of [[rootImage, "root"], [userImage, "vscode"]]) {
    await observe(
        `same-release-${user}`,
        `version=$(${python} -I -c 'from importlib.metadata import version; print(version("google-colab-cli"))'); ` +
            `${fingerprint} >/tmp/before; VERSION=$version _REMOTE_USER=${user} ${install}; ` +
            `${fingerprint} >/tmp/after; cmp /tmp/before /tmp/after`,
        "",
        image,
    );
}
await observe(
    "latest-unchanged",
    `${fingerprint} >/tmp/before; VERSION=latest _REMOTE_USER=vscode ${install}; ` +
        `${fingerprint} >/tmp/after; cmp /tmp/before /tmp/after`,
    "",
    userImage,
    "bridge",
);
await observe(
    "changed-and-downgraded-release",
    `export PATH="$PATH:/usr/local/share/uv/bin"; ` +
        `UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python uv --no-config tool install --python 3.12 --managed-python pycowsay; ` +
        `VERSION=0.7.4 ${install}; VERSION=0.7.2 ${install}; ` +
        `${python} -I -c 'from importlib.metadata import version; assert version("google-colab-cli") == "0.7.2"'; ` +
        // The current stable release cannot be a permanent literal; a publication race requires a rerun.
        `latest=$(${python} -I -c 'import json, urllib.request; print(json.load(urllib.request.urlopen("https://pypi.org/pypi/google-colab-cli/json"))["info"]["version"])'); ` +
        `VERSION=latest ${install}; ` +
        `test "$(${python} -I -c 'from importlib.metadata import version; print(version("google-colab-cli"))')" = "$latest"; pycowsay hello`,
    "",
    rootImage,
    "bridge",
);
console.log(`${passed} observations passed; logs: ${scratch}`);
