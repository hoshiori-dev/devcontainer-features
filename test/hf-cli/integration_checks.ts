#!/usr/bin/env -S deno run --allow-read --allow-write=/tmp --allow-run=docker,devcontainer
// Exercises a proxy-only install and a real devcontainer rebuild with a populated uv volume.
// Usage: ./test/hf-cli/integration_checks.ts ROOT_IMAGE UBUNTU_IMAGE
const [rootImage, ubuntuImage] = Deno.args;
if (!rootImage || !ubuntuImage) throw new Error("Supply the tested root and Ubuntu images.");
const source = await Deno.realPath("src/hf-cli/install.sh");
const scratch = await Deno.makeTempDir({ prefix: "hf-cli-integration-" });
const prefix = `hf-cli-${crypto.randomUUID().slice(0, 8)}`;
const network = `${prefix}-internal`;
const proxy = `${prefix}-proxy`;
const proxyImage = `${prefix}-proxy-image`;
const decoder = new TextDecoder();
async function run(tool: string, args: string[], label: string, expectedFailure = false) {
    const output = await new Deno.Command(tool, { args, stdout: "piped", stderr: "piped" }).output();
    const stdout = decoder.decode(output.stdout);
    const text = stdout + decoder.decode(output.stderr);
    await Deno.writeTextFile(`${scratch}/${label}.log`, text);
    if ((output.code !== 0) !== expectedFailure) {
        throw new Error(`${label}: exit ${output.code}; inspect ${scratch}/${label}.log`);
    }
    console.log(`PASS ${label}`);
    return stdout;
}
let container = "";
let volume = "";
try {
    await Deno.writeTextFile(
        `${scratch}/Dockerfile`,
        `FROM ${rootImage}
USER root
RUN apt-get update && apt-get install -y --no-install-recommends tinyproxy && rm -rf /var/lib/apt/lists/*
RUN printf 'User tinyproxy\\nGroup tinyproxy\\nPort 8888\\nTimeout 60\\nLogFile "/tmp/tinyproxy.log"\\nPidFile "/tmp/tinyproxy.pid"\\nMaxClients 20\\nAllow 0.0.0.0/0\\nConnectPort 443\\n' > /etc/tinyproxy/tinyproxy.conf
ENTRYPOINT ["tinyproxy", "-d"]
`,
    );
    await run("docker", ["build", "-t", proxyImage, scratch], "proxy-image");
    await run("docker", ["network", "create", "--internal", network], "internal-network");
    await run("docker", ["run", "-d", "--name", proxy, "--network", "bridge", proxyImage], "proxy-start");
    await run("docker", ["network", "connect", network, proxy], "proxy-connect");
    const args = [
        "run",
        "--rm",
        "--user",
        "root",
        "--network",
        network,
        "--mount",
        `type=bind,src=${source},dst=/tmp/hf-cli-install.sh,readonly`,
    ];
    const command = "rm -rf /root/.hf-cli; rm -f /usr/local/bin/hf; VERSION=1.33.0 bash /tmp/hf-cli-install.sh";
    const failure = await run(
        "docker",
        [...args, "--entrypoint", "bash", rootImage, "-euc", command],
        "without-proxy",
        true,
    );
    // The tools write failures on stderr; the saved log proves it was the feature's first download.
    const failureLog = await Deno.readTextFile(`${scratch}/without-proxy.log`);
    if (!failureLog.includes("Cannot fetch") || failure.includes("Installed hf")) {
        throw new Error("Expected download failure without proxy.");
    }
    await run("docker", [
        ...args,
        "-e",
        `http_proxy=http://${proxy}:8888`,
        "-e",
        `https_proxy=http://${proxy}:8888`,
        "--entrypoint",
        "bash",
        rootImage,
        "-euc",
        command,
    ], "proxy-only-install");

    // Image metadata supplies uv's actual named volume and creation hook; no custom mounts or repairs.
    const workspace = `${scratch}/workspace`;
    await Deno.mkdir(`${workspace}/.devcontainer`, { recursive: true });
    await Deno.writeTextFile(
        `${workspace}/.devcontainer/devcontainer.json`,
        JSON.stringify({
            image: ubuntuImage,
            remoteUser: "vscode",
            userEnvProbe: "none",
        }),
    );
    const upArgs = ["up", "--workspace-folder", workspace, "--log-format", "text"];
    const started = JSON.parse(await run("devcontainer", upArgs, "volume-create"));
    container = started.containerId;
    const mounts = JSON.parse(
        await run("docker", ["inspect", container, "--format", "{{json .Mounts}}"], "volume-inspect"),
    );
    volume = mounts.find((m: { Destination: string }) => m.Destination === "/var/lib/uv")?.Name;
    if (!volume) throw new Error("uv named volume was not mounted.");
    await run("docker", [
        "exec",
        "-u",
        "vscode",
        container,
        "bash",
        "-euc",
        'test -z "$(ls -A /var/lib/uv)"; test -w /var/lib/uv; hf version; uv pip install --target /tmp/hf-cli-cache-fixture pycowsay==0.0.0.2; test -n "$(ls -A /var/lib/uv)"',
    ], "empty-volume-and-fill");
    const rebuilt = JSON.parse(await run("devcontainer", [...upArgs, "--remove-existing-container"], "volume-rebuild"));
    container = rebuilt.containerId;
    await run("docker", [
        "exec",
        "-u",
        "vscode",
        container,
        "bash",
        "-euc",
        'test -n "$(ls -A /var/lib/uv)"; hf version; uv pip install --offline --target /tmp/hf-cli-cache-fixture pycowsay==0.0.0.2',
    ], "nonempty-volume-after-rebuild");
    console.log(`Proxy and mounted-volume observations passed; logs: ${scratch}`);
} finally {
    // Remove only resources this invocation created; keep logs for the PR's acceptance record.
    for (
        const args of [
            ...(container ? [["rm", "-f", container]] : []),
            ...(volume ? [["volume", "rm", volume]] : []),
            ["rm", "-f", proxy],
            ["network", "rm", network],
            ["image", "rm", proxyImage],
        ]
    ) await new Deno.Command("docker", { args, stdout: "null", stderr: "null" }).output();
}
