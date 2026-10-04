#!/usr/bin/env bash
# Runs the release-tagged Hugging Face standalone installer for the remote user.
# uv and pip use a clean environment and a constraint pinning huggingface_hub.
set -euo pipefail

VERSION="${VERSION-latest}"
INSTALLSKILL="${INSTALLSKILL-false}"
readonly LATEST_URL='https://pypi.org/pypi/huggingface_hub/json'
readonly INSTALLER_BASE='https://raw.githubusercontent.com/huggingface/huggingface_hub/refs/tags'
readonly SYSTEM_PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH="$SYSTEM_PATH"

log() { echo "hf-cli feature: $*"; }
fail() { echo "hf-cli feature: error: $*" >&2; exit 1; }
older_than() { [[ "$1" != "$2" && "$(printf '%s\n' "$1" "$2" | sort -V | head -n 1)" == "$1" ]]; }
validate_version() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'version must be latest or MAJOR.MINOR.PATCH (stable releases only).'
    older_than "$1" '1.27.0' && fail 'version must be at least 1.27.0.'
    return 0
}

[[ "$VERSION" == latest ]] || validate_version "$VERSION"
case "$INSTALLSKILL" in true|false) ;; *) fail 'installSkill must be true or false.' ;; esac
# Fail before any download on unsupported platforms or missing users.
distribution=$(
    # os-release also defines VERSION; keep its variables out of the feature's options.
    # shellcheck source=/dev/null
    source /etc/os-release
    printf ' %s %s ' "${ID:-}" "${ID_LIKE:-}"
)
case "$distribution" in
    *' debian '*|*' ubuntu '*) ;;
    *) fail "Unsupported distribution:$distribution; use a Debian- or Ubuntu-based image." ;;
esac
architecture=$(uname -m)
case "$architecture" in x86_64|aarch64) ;; *) fail "Unsupported architecture: $architecture." ;; esac
remote_user="${_REMOTE_USER:-root}"
id "$remote_user" >/dev/null 2>&1 || fail "Remote user does not exist: $remote_user."
remote_home="${_REMOTE_USER_HOME:-$(getent passwd "$remote_user" | cut -d: -f6)}"
[[ -n "$remote_home" && -d "$remote_home" ]] || fail "Home directory does not exist for $remote_user."
if [[ "$remote_user" != root ]]; then
    command -v runuser >/dev/null || fail 'runuser is required to install as the remote user.'
fi

# Prefer the first-party feature's interpreter, then standard system commands.
# Keep interpreter selection separate from upstream's python3-before-python discovery.
python_candidates=(/usr/local/python/current/bin/python3 /usr/local/python/current/bin/python)
IFS=: read -r -a system_directories <<< "$SYSTEM_PATH"
for command_name in python3 python; do
    for directory in "${system_directories[@]}"; do
        if [[ -x "$directory/$command_name" ]]; then python_candidates+=("$directory/$command_name"); fi
    done
done
python_command=''
system_venv_missing=false
python_found=false
for candidate in "${python_candidates[@]}"; do
    [[ -x "$candidate" ]] || continue
    python_found=true
    "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1 || continue
    if "$candidate" -c 'import venv, ensurepip' >/dev/null 2>&1; then
        python_command="$candidate"
        break
    fi
    if [[ "$(readlink -f "$candidate")" == /usr/bin/python3.* ]]; then system_venv_missing=true; fi
done
packages=()
if [[ "$python_found" == false ]]; then
    packages+=(python3 python3-venv)
elif [[ -z "$python_command" && "$system_venv_missing" == true ]]; then
    packages+=(python3-venv)
elif [[ -z "$python_command" ]]; then
    fail 'No usable Python: Python 3.10 or later with venv and ensurepip is required. Configure ghcr.io/devcontainers/features/python:1 with a suitable version.'
fi
[[ -s /etc/ssl/certs/ca-certificates.crt ]] || packages+=(ca-certificates)
if (( ${#packages[@]} )); then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends "${packages[@]}"
    rm -rf /var/lib/apt/lists/*
fi
if [[ -z "$python_command" ]]; then python_command=/usr/bin/python3; fi
"$python_command" -c 'import sys, venv, ensurepip; sys.exit(sys.version_info < (3, 10))' || fail 'Python 3.10 or later with venv and ensurepip is required; configure ghcr.io/devcontainers/features/python:1 with a suitable version.'
log "Using Python: $python_command ($("$python_command" --version))"
if command -v uv >/dev/null; then
    uv_version=$(uv --version | awk '{print $2}')
    [[ "$uv_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Cannot read uv version: $uv_version."
    older_than "$uv_version" '0.12.16' && fail "uv $uv_version is too old; uv 0.12.16 or later is required."
    log "Using existing uv $uv_version for package installation."
else
    log 'uv is absent; the upstream installer will use pip.'
fi

# Only proxy routing variables pass through. No build index, argument, CA or credential settings do.
proxy_env=()
for variable in HTTP_PROXY HTTPS_PROXY NO_PROXY ALL_PROXY http_proxy https_proxy no_proxy all_proxy; do
    if [[ -v "$variable" ]]; then proxy_env+=("$variable=${!variable}"); fi
done
fetch() {
    env -i PATH="$SYSTEM_PATH" "${proxy_env[@]}" "$python_command" - "$@" <<'PY'
import sys
import urllib.request

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

url, destination = sys.argv[1:]
try:
    with urllib.request.build_opener(NoRedirect).open(url, timeout=60) as response:
        if response.status != 200:
            raise RuntimeError(f"HTTP {response.status}")
        with open(destination, "wb") as output:
            output.write(response.read())
except Exception:
    # Proxy failures may carry credentials in their exception text; name only the requested URL.
    sys.exit(f"hf-cli feature: error: Cannot fetch {url}; a direct HTTPS 200 response is required.")
PY
}

temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT
chmod 755 "$temporary_dir"
# Execute the selected interpreter by its stable path, so the venv never links to
# a temporary symlink or accidentally uses an older python3 elsewhere on PATH.
mkdir "$temporary_dir/bin"
printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$python_command" > "$temporary_dir/bin/python3"
chmod 755 "$temporary_dir/bin/python3"
if [[ "$VERSION" == latest ]]; then
    fetch "$LATEST_URL" "$temporary_dir/latest.json"
    VERSION=$("$python_command" - "$temporary_dir/latest.json" <<'PY'
import json, sys
try:
    value = json.load(open(sys.argv[1]))["info"]["version"]
    if not isinstance(value, str):
        raise ValueError()
    print(value)
except Exception:
    sys.exit("hf-cli feature: error: Invalid response from https://pypi.org/pypi/huggingface_hub/json.")
PY
    )
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid release version from $LATEST_URL; expected MAJOR.MINOR.PATCH."
    validate_version "$VERSION"
fi
log "Resolved huggingface_hub version: $VERSION"
printf 'huggingface_hub==%s\n' "$VERSION" > "$temporary_dir/constraints.txt"
chmod 644 "$temporary_dir/constraints.txt"
install_env=(
    "HOME=$remote_home" "USER=$remote_user" "PATH=$temporary_dir/bin:$SYSTEM_PATH"
    UV_NO_CONFIG=1 UV_NO_CACHE=1 UV_NO_BUILD=1 UV_COMPILE_BYTECODE=1
    "UV_CONSTRAINT=$temporary_dir/constraints.txt" "PIP_CONSTRAINT=$temporary_dir/constraints.txt"
    PIP_CONFIG_FILE=/dev/null PIP_NO_CACHE_DIR=1 PIP_ONLY_BINARY=:all:
    HF_HUB_DISABLE_UPDATE_CHECK=1 HF_HUB_OFFLINE=1
    "${proxy_env[@]}"
)
run_as_user() {
    if [[ "$remote_user" == root ]]; then
        env -i "${install_env[@]}" "$@"
    else
        runuser -u "$remote_user" -- env -i "${install_env[@]}" "$@"
    fi
}
cd "$remote_home"
venv="$remote_home/.hf-cli/venv"
skill="$remote_home/.agents/skills/hf-cli/SKILL.md"
installed_version=''
if [[ -f "$venv/.hf_installer_marker" && -x "$venv/bin/python" ]]; then
    installed_version=$(run_as_user "$venv/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("huggingface_hub"))' 2>/dev/null) || installed_version=''
fi
if [[ "$installed_version" == "$VERSION" ]]; then
    log "Skipping package installation: huggingface_hub $VERSION is already installer-managed."
    if [[ "$INSTALLSKILL" == true ]] && ! grep -Fq "huggingface_hub v$VERSION" "$skill" 2>/dev/null; then
        # Old CLI releases need --claude; their installer used the same flag.
        skill_arguments=(skills add hf-cli --global --force)
        if older_than "$VERSION" '1.33.0'; then skill_arguments+=(--claude); fi
        run_as_user "$venv/bin/hf" "${skill_arguments[@]}" || fail "Could not generate skill: $skill."
    fi
else
    installer="$temporary_dir/install.sh"
    fetch "$INSTALLER_BASE/v$VERSION/utils/installers/install.sh" "$installer"
    chmod 644 "$installer"
    log "Installer tag v$VERSION; SHA-256 $(sha256sum "$installer" | cut -d' ' -f1)"
    arguments=(--no-modify-path --force)
    if [[ "$INSTALLSKILL" == false ]]; then arguments+=(--exclude-skill); fi
    run_as_user bash "$installer" "${arguments[@]}"
fi

# Check the installed contract before exposing the CLI system-wide.
installed_version=$(run_as_user "$venv/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("huggingface_hub"))')
[[ "$installed_version" == "$VERSION" ]] || fail "Installed huggingface_hub $installed_version differs from requested $VERSION."
[[ -f "$venv/.hf_installer_marker" ]] || fail 'The installer marker is missing.'
if [[ "$INSTALLSKILL" == true ]]; then
    grep -Fq "huggingface_hub v$VERSION" "$skill" 2>/dev/null || fail "Missing skill for $VERSION: $skill."
    [[ "$(readlink -f "$remote_home/.claude/skills/hf-cli")" == "$(dirname "$skill")" ]] || fail "Missing skill link: $remote_home/.claude/skills/hf-cli."
fi
run_as_user "$venv/bin/hf" version
ln -sfn "$venv/bin/hf" /usr/local/bin/hf
log "Installed hf $VERSION for $remote_user."
