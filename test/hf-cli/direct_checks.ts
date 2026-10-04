#!/usr/bin/env -S deno run --allow-read --allow-write=/tmp --allow-run=docker,devcontainer
// Acceptance observations that successful feature-build tests cannot express.
// Run after preserving test containers: ./test/hf-cli/direct_checks.ts ROOT_IMAGE UBUNTU_IMAGE
// Images must contain hf-cli, uv, and Python, as produced by `just test hf-cli --preserve`.
const [rootImage, ubuntuImage] = Deno.args;
if (!rootImage || !ubuntuImage) throw new Error("Supply a tested root image and a tested Ubuntu image.");
const source = await Deno.realPath("src/hf-cli/install.sh");
const results = await Deno.makeTempDir({ prefix: "hf-cli-observations-" });
const decoder = new TextDecoder();
async function docker(args: string[]) {
    const output = await new Deno.Command("docker", { args, stdout: "piped", stderr: "piped" }).output();
    return { code: output.code, text: decoder.decode(output.stdout) + decoder.decode(output.stderr) };
}
let passed = 0;
async function observation(label: string, command: string, expected = "", image = rootImage, network = "bridge") {
    const result = await docker([
        "run",
        "--rm",
        "--user",
        "root",
        "--network",
        network,
        "--mount",
        `type=bind,src=${source},dst=/tmp/hf-cli-install.sh,readonly`,
        "--entrypoint",
        "bash",
        image,
        "-euc",
        command,
    ]);
    await Deno.writeTextFile(`${results}/${label}.log`, result.text);
    const ok = expected ? result.code !== 0 && result.text.includes(expected) : result.code === 0;
    if (!ok) throw new Error(`${label}: exit ${result.code}; inspect ${results}/${label}.log`);
    console.log(`PASS ${label}`);
    passed++;
}
const install = "bash /tmp/hf-cli-install.sh";
const clean = "rm -f /usr/local/bin/hf; ";
await observation("malformed-short", `${clean}VERSION=2.0 ${install}`, "MAJOR.MINOR.PATCH", rootImage, "none");
await observation("prerelease", `${clean}VERSION=2.0.0rc0 ${install}`, "MAJOR.MINOR.PATCH", rootImage, "none");
await observation("below-floor", `${clean}VERSION=1.26.1 ${install}`, "at least 1.27.0", rootImage, "none");
await observation(
    "missing-user",
    `${clean}_REMOTE_USER=missing-hf-user VERSION=1.33.0 ${install}`,
    "missing-hf-user",
    rootImage,
    "none",
);
await observation(
    "unsupported-arch",
    `${clean}printf '#!/bin/sh\necho riscv64\n' > /usr/local/sbin/uname; chmod +x /usr/local/sbin/uname; VERSION=1.33.0 ${install}`,
    "Unsupported architecture: riscv64",
    rootImage,
    "none",
);
await observation(
    "missing-uv",
    `${clean}rm /usr/local/bin/uv; VERSION=1.33.0 ${install}`,
    "uv is missing",
    rootImage,
    "none",
);
await observation(
    "old-uv",
    `${clean}printf '#!/bin/sh\necho "uv 0.12.15"\n' > /usr/local/sbin/uv; chmod +x /usr/local/sbin/uv; VERSION=1.33.0 ${install}`,
    "uv 0.12.15 is too old",
    rootImage,
    "none",
);
await observation(
    "unreachable-latest",
    `${clean}VERSION=latest ${install}`,
    "https://pypi.org/pypi/huggingface_hub/json",
    rootImage,
    "none",
);
await observation("missing-tag", `${clean}VERSION=9.9.9 ${install}`, "refs/tags/v9.9.9");
await observation(
    "unsupported-distribution",
    `VERSION=1.33.0 ${install}`,
    "Unsupported distribution",
    "fedora:44",
    "none",
);
// This official Python image is Debian 11 with a real 3.9 interpreter; it needs no altered apt source.
await observation("old-python", `VERSION=1.33.0 ${install}`, "Python 3.10 or later", "python:3.9-bullseye", "none");
const wrapper = (body: string) =>
    `printf '%s\n' '#!/usr/bin/env bash' '${body}' > /usr/local/sbin/uv; chmod +x /usr/local/sbin/uv; `;
await observation(
    "absent-pypi-release",
    clean +
        wrapper(
            'if [[ "$1" == --version ]]; then exec /usr/local/bin/uv "$@"; fi; printf "huggingface_hub==9.9.9\\n" > "$UV_CONSTRAINT"; exec /usr/local/bin/uv "$@"',
        ) + `VERSION=1.33.0 ${install}`,
    "9.9.9",
);
await observation(
    "version-mismatch",
    clean +
        wrapper(
            'if [[ "$1" == --version ]]; then exec /usr/local/bin/uv "$@"; fi; unset UV_CONSTRAINT PIP_CONSTRAINT; exec /usr/local/bin/uv "$@"',
        ) + `VERSION=1.33.0 ${install}`,
    "differs from requested 1.33.0",
);
await observation(
    "skill-failure",
    `rm -rf /home/vscode/.agents /home/vscode/.claude; mkdir -p /home/vscode/.agents/skills; chmod 555 /home/vscode/.agents/skills; VERSION=$(/home/vscode/.hf-cli/venv/bin/python -c 'import importlib.metadata; print(importlib.metadata.version("huggingface_hub"))') INSTALLSKILL=true _REMOTE_USER=vscode _REMOTE_USER_HOME=/home/vscode ${install}`,
    "skill",
    ubuntuImage,
    "none",
);
// Compare bytes and mtimes, not just the top-level version: a transitive upgrade violates the contract too.
const fingerprint =
    `python3 -c 'import hashlib, os, pathlib; root=pathlib.Path(os.environ["HF_TEST_HOME"]) / ".hf-cli/venv"; [print(p.relative_to(root), p.stat().st_mtime_ns, hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(root.rglob("*")) if p.is_file()]'`;
for (const [image, user, home] of [[rootImage, "root", "/root"], [ubuntuImage, "vscode", "/home/vscode"]]) {
    await observation(
        `skill-only-and-identical-${user}`,
        `export HF_TEST_HOME=${home}; export _REMOTE_USER=${user} _REMOTE_USER_HOME=${home}; version=$(${home}/.hf-cli/venv/bin/python -c 'import importlib.metadata; print(importlib.metadata.version("huggingface_hub"))'); rm -rf ${home}/.agents/skills/hf-cli ${home}/.claude/skills/hf-cli; ${fingerprint} > /tmp/before; VERSION=$version INSTALLSKILL=false ${install}; ${fingerprint} > /tmp/same; cmp /tmp/before /tmp/same; VERSION=$version INSTALLSKILL=true ${install}; ${fingerprint} > /tmp/after; cmp /tmp/before /tmp/after; test -f ${home}/.agents/skills/hf-cli/SKILL.md; test -L ${home}/.claude/skills/hf-cli; VERSION=$version INSTALLSKILL=true ${install}; ${fingerprint} > /tmp/again; cmp /tmp/before /tmp/again; test ! -e ${home}/.cache/huggingface/.agent_harnesses.json`,
        "",
        image,
        "none",
    );
}
console.log(`${passed} observations passed; logs: ${results}`);
