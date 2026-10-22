// Codex's own parser/editor preserves TOML and enforces managed policy without exposing configuration values.
import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { createInterface } from "node:readline";

const server = spawn("codex", ["app-server", "--listen", "stdio://"], {
    cwd: homedir(),
    stdio: ["pipe", "pipe", "ignore"],
});
const pending = new Map();
let nextId = 0;
const timer = setTimeout(() => fail("configuration check timed out; inspect Codex configuration and retry"), 20000);

function fail(message) {
    console.error(`codex: error: ${message}`);
    server.kill();
    process.exit(1);
}

server.on("error", () => fail("cannot start Codex; verify the installed release"));
server.on("exit", () => {
    if (pending.size) fail("configuration is unavailable; inspect syntax and managed policy locally");
});
createInterface({ input: server.stdout }).on("line", (line) => {
    let message;
    try {
        message = JSON.parse(line);
    } catch {
        fail("unsupported configuration protocol; select a supported stable release");
    }
    if (pending.has(message.id)) {
        pending.get(message.id)(message);
        pending.delete(message.id);
    }
});

async function request(method, params) {
    const reply = await new Promise((resolve) => {
        const id = ++nextId;
        pending.set(id, resolve);
        server.stdin.write(JSON.stringify({ id, method, params }) + "\n");
    });
    // Upstream errors can contain configuration values; keep them out of build and initialization logs.
    if (reply.error) fail("cannot configure file credentials; inspect Codex configuration and managed policy locally");
    return reply.result;
}

try {
    await request("initialize", { clientInfo: { name: "codex_feature", version: "1.0.0" } });
    server.stdin.write(JSON.stringify({ method: "initialized" }) + "\n");
    const { requirements } = await request("configRequirements/read", {});
    const managed = requirements?.cliAuthCredentialsStore;
    if (managed && managed !== "file") fail("managed policy conflicts with file credentials; ask its administrator");
    const { config } = await request("config/read", { includeLayers: false });
    const profile = config.profile;
    const profileStore = profile ? config.profiles?.[profile]?.cli_auth_credentials_store : undefined;
    const backend = profileStore ?? config.cli_auth_credentials_store;
    if (backend && backend !== "file" && backend !== "auto") {
        fail("credential configuration conflicts; select file storage explicitly before retrying");
    }
    if (backend !== "file") {
        const keyPath = profileStore
            ? `profiles.${JSON.stringify(profile)}.cli_auth_credentials_store`
            : "cli_auth_credentials_store";
        console.log("codex: selecting file credential storage in the private configuration");
        await request("config/value/write", { keyPath, value: "file", mergeStrategy: "replace" });
        const updated = (await request("config/read", { includeLayers: false })).config;
        const actual = profile ? updated.profiles?.[profile]?.cli_auth_credentials_store : undefined;
        if ((actual ?? updated.cli_auth_credentials_store) !== "file") {
            fail("file credentials remain overridden; resolve the conflicting configuration before retrying");
        }
    }
} finally {
    clearTimeout(timer);
    server.kill();
}
