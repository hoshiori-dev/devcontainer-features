#!/usr/bin/env -S deno run --allow-run=docker
// Verify both clients reject a wheel whose bytes disagree with its index digest.
// Usage: ./test/hf-cli/hash_checks.ts ROOT_PIP_IMAGE ROOT_UV_IMAGE
const [pipImage, uvImage] = Deno.args;
if (!pipImage || !uvImage) throw new Error("Supply the tested pip and uv images.");
const fixture = String.raw`
mkdir -p /tmp/hash-index/simple/hf-hash-probe
python3 - <<'PY'
import pathlib, zipfile
root = pathlib.Path('/tmp/hash-index')
with zipfile.ZipFile(root / 'hf_hash_probe-1.0.0-py3-none-any.whl', 'w') as wheel:
    wheel.writestr('hf_hash_probe.py', 'VALUE = 1\n')
    wheel.writestr('hf_hash_probe-1.0.0.dist-info/METADATA', 'Metadata-Version: 2.1\nName: hf-hash-probe\nVersion: 1.0.0\n')
    wheel.writestr('hf_hash_probe-1.0.0.dist-info/WHEEL', 'Wheel-Version: 1.0\nGenerator: fixture\nRoot-Is-Purelib: true\nTag: py3-none-any\n')
    wheel.writestr('hf_hash_probe-1.0.0.dist-info/RECORD', '')
(root / 'simple/hf-hash-probe/index.html').write_text('<a href="../../hf_hash_probe-1.0.0-py3-none-any.whl#sha256=' + '0' * 64 + '">wheel</a>')
PY
python3 -m http.server 8181 --bind 127.0.0.1 --directory /tmp/hash-index >/tmp/hash-server.log 2>&1 &
server=$!
trap 'kill "$server"' EXIT
python3 - <<'PY'
import time, urllib.request
for attempt in range(100):
    try:
        urllib.request.urlopen('http://127.0.0.1:8181/simple/hf-hash-probe/').close()
        break
    except OSError:
        time.sleep(0.05)
else:
    raise SystemExit('fixture server did not start')
PY
python3 -m venv /tmp/hash-venv
`;
for (const [client, image] of [["pip", pipImage], ["uv", uvImage]]) {
    const install = client === "pip"
        ? "env -i PATH=/usr/bin:/bin PIP_CONFIG_FILE=/dev/null PIP_NO_CACHE_DIR=1 PIP_ONLY_BINARY=:all: /tmp/hash-venv/bin/python -m pip install --index-url http://127.0.0.1:8181/simple hf-hash-probe"
        : "env -i PATH=/usr/bin:/bin UV_NO_CONFIG=1 UV_NO_CACHE=1 UV_NO_BUILD=1 /usr/local/bin/uv pip install --python /tmp/hash-venv/bin/python --index-url http://127.0.0.1:8181/simple hf-hash-probe";
    const command = fixture + `
if ${install} >/tmp/hash-failure.log 2>&1; then cat /tmp/hash-failure.log; exit 1; fi
cat /tmp/hash-failure.log
rg_digest='${client === "pip" ? "THESE PACKAGES DO NOT MATCH THE HASHES" : "Hash mismatch"}'
grep -q "$rg_digest" /tmp/hash-failure.log
/tmp/hash-venv/bin/python -c 'import importlib.util; assert importlib.util.find_spec("hf_hash_probe") is None'
python3 - <<'PY'
import hashlib, pathlib
root = pathlib.Path('/tmp/hash-index')
digest = hashlib.sha256((root / 'hf_hash_probe-1.0.0-py3-none-any.whl').read_bytes()).hexdigest()
(root / 'simple/hf-hash-probe/index.html').write_text('<a href="../../hf_hash_probe-1.0.0-py3-none-any.whl#sha256=' + digest + '">wheel</a>')
PY
${install}
/tmp/hash-venv/bin/python -c 'import hf_hash_probe; assert hf_hash_probe.VALUE == 1'
`;
    const result = await new Deno.Command("docker", {
        args: ["run", "--rm", "--network", "none", "--user", "root", "--entrypoint", "bash", image, "-euc", command],
        stdout: "piped",
        stderr: "piped",
    }).output();
    console.log(new TextDecoder().decode(result.stdout) + new TextDecoder().decode(result.stderr));
    if (!result.success) throw new Error(`${client}: hash observation failed with exit ${result.code}`);
    console.log(`PASS ${client}: wrong hash rejected, correct hash accepted`);
}
