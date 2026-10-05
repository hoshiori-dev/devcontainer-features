#!/usr/bin/env bash
# Installs the Hugging Face CLI (hf) for the remote user by running Hugging Face's standalone installer, downloaded from
# https://raw.githubusercontent.com/huggingface/huggingface_hub/refs/tags/v<version>/utils/installers/install.sh,
# into the virtual environment ~/.hf-cli/venv of that user, and links it as /usr/local/bin/hf. The version `latest` is
# resolved from https://pypi.org/pypi/huggingface_hub/json. The installer's uv or pip runs in a clean environment with a
# constraint that pins huggingface_hub. With installSkill the CLI also generates ~/.agents/skills/hf-cli and the link
# ~/.claude/skills/hf-cli. A missing python3, python3-venv, or ca-certificates comes from the image's apt sources.
# Runs as root at image build time; the options `version` and `installSkill` arrive as VERSION and INSTALLSKILL.
set -euo pipefail

readonly LATEST_URL="https://pypi.org/pypi/huggingface_hub/json"
readonly INSTALLER_BASE_URL="https://raw.githubusercontent.com/huggingface/huggingface_hub/refs/tags"
readonly INSTALLER_TAG_PATH="utils/installers/install.sh"
# The first release whose installer accepts every argument this feature passes.
readonly MINIMUM_VERSION="1.27.0"
# The first uv release that checks package files against the index's hashes.
readonly MINIMUM_UV_VERSION="0.12.16"
# Releases before this one take --claude to link the skill into ~/.claude/skills; their installer passes it too.
readonly CLAUDE_FLAG_BEFORE_VERSION="1.33.0"
readonly FIRST_PARTY_PYTHON_DIR="/usr/local/python/current/bin"
readonly DISTRIBUTION_PYTHON="/usr/bin/python3"
readonly CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
readonly APT_LISTS_DIR="/var/lib/apt/lists"
readonly LINK_PATH="/usr/local/bin/hf"
# Paths below the remote user's home.
readonly VENV_SUFFIX=".hf-cli/venv"
readonly SKILL_SUFFIX=".agents/skills/hf-cli"
readonly CLAUDE_SKILL_SUFFIX=".claude/skills/hf-cli"
readonly SYSTEM_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
# Discards the build's PATH before the first command lookup: every command this script runs, and the python3 and uv the
# installer finds, come from these directories.
export PATH="${SYSTEM_PATH}"

VERSION="${VERSION-latest}"
INSTALLSKILL="${INSTALLSKILL-false}"

remote_user=""
remote_home=""
python_command=""
apt_packages=()
proxy_env=()
install_env=()
work_dir=""
resolved_version=""

log() {
  printf 'hf-cli: %s\n' "$*"
}

fail() {
  printf 'hf-cli: error: %s\n' "$*" >&2
  exit 1
}

# Removes the work directory on every exit, success or failure.
cleanup() {
  if [[ -n "${work_dir}" ]]; then rm --recursive --force "${work_dir}"; fi
}

# Succeeds when version $1 is lower than version $2; both have the form MAJOR.MINOR.PATCH.
older_than() {
  local lowest
  lowest="$(printf '%s\n' "$1" "$2" | sort --version-sort | head --lines=1)"
  [[ "$1" != "$2" && "${lowest}" == "$1" ]]
}

# Downloads URL $1 to file $2 with the selected interpreter, in an environment that holds only PATH and the proxy
# variables: HTTPS with the default certificate verification, no redirect followed, a 60-second timeout. On failure it
# prints one line with the cause and returns non-zero.
fetch() {
  env --ignore-environment PATH="${SYSTEM_PATH}" "${proxy_env[@]}" "${python_command}" - "$@" <<'PY'
import sys
import urllib.error
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


url, destination = sys.argv[1:]
try:
    with urllib.request.build_opener(NoRedirect).open(url, timeout=60) as response:
        status = response.status
        body = response.read()
except urllib.error.HTTPError as error:
    # A refused redirect arrives here with its 3xx status.
    cause = f"redirect refused (HTTP {error.code})" if 300 <= error.code < 400 else f"HTTP {error.code}"
    sys.exit(f"hf-cli: error: request to {url} failed: {cause}")
except Exception as error:
    # A proxy failure may carry credentials in its exception text; name only the exception class.
    sys.exit(f"hf-cli: error: request to {url} failed: {type(error).__name__}")
if status != 200:
    sys.exit(f"hf-cli: error: request to {url} failed: HTTP {status}")
with open(destination, "wb") as output:
    output.write(body)
PY
}

# Runs the command "$@" as the remote user, in the environment install_env and nothing else from the build.
run_as_user() {
  if [[ "${remote_user}" == root ]]; then
    env --ignore-environment "${install_env[@]}" "$@"
  else
    runuser --user "${remote_user}" -- env --ignore-environment "${install_env[@]}" "$@"
  fi
}

# Prints the huggingface_hub version in the virtual environment $1, read by its interpreter as the remote user.
installed_version() {
  run_as_user "$1/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("huggingface_hub"))'
}

validate_options() {
  if [[ "${VERSION}" != latest ]]; then
    [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
      || fail "option version is \"${VERSION}\"; use \"latest\" or a stable release of the form MAJOR.MINOR.PATCH"
    if older_than "${VERSION}" "${MINIMUM_VERSION}"; then
      fail "option version is \"${VERSION}\"; use \"latest\" or a release that is at least ${MINIMUM_VERSION}"
    fi
  fi
  case "${INSTALLSKILL}" in
    true | false) ;;
    *) fail "option installSkill is \"${INSTALLSKILL}\"; use true or false" ;;
  esac
  readonly INSTALLSKILL
}

# Fails unless the image is Debian- or Ubuntu-based and runs on x86_64 or aarch64. Runs before VERSION becomes readonly:
# /etc/os-release assigns it too.
detect_platform() {
  local os_release
  local os_id
  local os_id_like
  local os_name
  local -a os_names
  local supported=false
  local architecture
  [[ -r /etc/os-release ]] || fail "cannot read /etc/os-release; use a Debian- or Ubuntu-based image"
  # shellcheck source=/dev/null
  os_release="$(. /etc/os-release && printf '%s|%s\n' "${ID:-}" "${ID_LIKE:-}")"
  os_id="${os_release%%|*}"
  os_id_like="${os_release#*|}"
  read -r -a os_names <<<"${os_id_like}"
  for os_name in "${os_id}" "${os_names[@]}"; do
    case "${os_name}" in
      debian | ubuntu) supported=true ;;
    esac
  done
  if [[ "${supported}" == false ]]; then
    fail "unsupported distribution \"${os_id}\" (ID_LIKE \"${os_id_like}\"); use a Debian- or Ubuntu-based image"
  fi
  architecture="$(uname --machine)"
  case "${architecture}" in
    x86_64 | aarch64) ;;
    *) fail "unsupported architecture \"${architecture}\"; use an x86_64 or aarch64 image" ;;
  esac
}

# Sets remote_user and remote_home. Fails unless the user and its home exist and, for a user other than root, runuser.
check_remote_user() {
  remote_user="${_REMOTE_USER:-root}"
  id "${remote_user}" >/dev/null 2>&1 \
    || fail "remote user \"${remote_user}\" does not exist in the image; set remoteUser to an existing user"
  remote_home="${_REMOTE_USER_HOME:-}"
  if [[ -z "${remote_home}" ]]; then
    remote_home="$(getent passwd "${remote_user}" | cut --delimiter=: --fields=6)"
  fi
  [[ -n "${remote_home}" && -d "${remote_home}" ]] \
    || fail "home directory \"${remote_home}\" of remote user \"${remote_user}\" does not exist; create it in the image"
  if [[ "${remote_user}" != root ]]; then
    command -v runuser >/dev/null \
      || fail "runuser is missing; it runs the installer as \"${remote_user}\";" \
        "add the package util-linux to the image"
  fi
}

# Sets python_command to the first usable interpreter (Python 3.10 or later with venv and ensurepip): python3, then
# python, of the first-party Python feature, then of each SYSTEM_PATH directory. The selection is the feature's own:
# the upstream installer only looks up python3, then python, on its PATH, where create_work_dir puts this interpreter
# first. When the image has no interpreter, or only the distribution's without venv support, python_command stays empty
# and apt_packages names what to install.
select_python() {
  local -a candidates=("${FIRST_PARTY_PYTHON_DIR}/python3" "${FIRST_PARTY_PYTHON_DIR}/python")
  local -a system_directories
  local command_name
  local directory
  local candidate
  local python_found=false
  local venv_package_missing=false
  IFS=: read -r -a system_directories <<<"${SYSTEM_PATH}"
  for command_name in python3 python; do
    for directory in "${system_directories[@]}"; do
      if [[ -x "${directory}/${command_name}" ]]; then candidates+=("${directory}/${command_name}"); fi
    done
  done
  for candidate in "${candidates[@]}"; do
    if [[ ! -x "${candidate}" ]]; then continue; fi
    python_found=true
    if ! "${candidate}" -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1; then continue; fi
    if "${candidate}" -c 'import venv, ensurepip' >/dev/null 2>&1; then
      python_command="${candidate}"
      break
    fi
    # Debian and Ubuntu ship venv support for their own interpreter in the separate package python3-venv, so a new
    # enough /usr/bin/python3.* that lacks it becomes usable once that package is installed.
    if [[ "$(readlink --canonicalize "${candidate}")" == /usr/bin/python3.* ]]; then venv_package_missing=true; fi
  done
  if [[ "${python_found}" == false ]]; then
    apt_packages+=(python3 python3-venv)
  elif [[ -z "${python_command}" && "${venv_package_missing}" == true ]]; then
    apt_packages+=(python3-venv)
  elif [[ -z "${python_command}" ]]; then
    fail "no usable Python: Python 3.10 or later with venv and ensurepip is required;" \
      "configure ghcr.io/devcontainers/features/python:1 with a suitable version"
  fi
}

# Fails when a uv on SYSTEM_PATH is older than MINIMUM_UV_VERSION: the installer would use it. Without uv the installer
# uses pip.
check_uv() {
  local uv_path
  local uv_output
  local uv_version
  if ! command -v uv >/dev/null; then
    log "uv is absent; the upstream installer will use pip"
    return
  fi
  uv_path="$(command -v uv)"
  uv_output="$(uv --version)"
  # "uv 0.12.16 (…)" names the version in its second word.
  uv_version="${uv_output#* }"
  uv_version="${uv_version%% *}"
  [[ "${uv_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "cannot read the version of ${uv_path} from \"${uv_output}\";" \
      "provide uv ${MINIMUM_UV_VERSION} or later, or remove it so that the installer uses pip"
  if older_than "${uv_version}" "${MINIMUM_UV_VERSION}"; then
    fail "uv ${uv_version} is too old (${uv_path});" \
      "provide uv ${MINIMUM_UV_VERSION} or later, or remove it so that the installer uses pip"
  fi
  log "using ${uv_path} (uv ${uv_version}) for package installation"
}

# Installs the packages select_python asked for, and ca-certificates when the CA bundle is missing, with apt-get.
install_prerequisites() {
  if [[ ! -s "${CA_BUNDLE}" ]]; then apt_packages+=(ca-certificates); fi
  if ((${#apt_packages[@]} == 0)); then return; fi
  log "installing ${apt_packages[*]} with apt-get from the apt sources the image configures"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update \
    || fail "cannot update the apt package lists to install ${apt_packages[*]};" \
      "check the image's apt sources and the build's network and proxy"
  apt-get install --yes --no-install-recommends "${apt_packages[@]}" \
    || fail "cannot install ${apt_packages[*]}; check the image's apt sources and the build's network and proxy"
  rm --recursive --force "${APT_LISTS_DIR:?}"/*
}

# Takes the distribution's interpreter when no candidate was usable before apt-get ran, then fails unless the selected
# interpreter is Python 3.10 or later with venv and ensurepip.
confirm_python() {
  local python_version
  if [[ -z "${python_command}" ]]; then python_command="${DISTRIBUTION_PYTHON}"; fi
  "${python_command}" -c 'import sys, venv, ensurepip; sys.exit(sys.version_info < (3, 10))' \
    || fail "${python_command} is not Python 3.10 or later with venv and ensurepip;" \
      "configure ghcr.io/devcontainers/features/python:1 with a suitable version"
  python_version="$("${python_command}" --version)"
  log "using ${python_command} (${python_version})"
}

# Sets proxy_env to the build's proxy routing variables, the only ones that pass through to the feature's requests and
# to the installer: no index, argument, CA, or credential setting does. A variable that is set but empty passes too.
collect_proxy_variables() {
  if [[ -v HTTP_PROXY ]]; then proxy_env+=("HTTP_PROXY=${HTTP_PROXY}"); fi
  if [[ -v HTTPS_PROXY ]]; then proxy_env+=("HTTPS_PROXY=${HTTPS_PROXY}"); fi
  if [[ -v NO_PROXY ]]; then proxy_env+=("NO_PROXY=${NO_PROXY}"); fi
  if [[ -v ALL_PROXY ]]; then proxy_env+=("ALL_PROXY=${ALL_PROXY}"); fi
  if [[ -v http_proxy ]]; then proxy_env+=("http_proxy=${http_proxy}"); fi
  if [[ -v https_proxy ]]; then proxy_env+=("https_proxy=${https_proxy}"); fi
  if [[ -v no_proxy ]]; then proxy_env+=("no_proxy=${no_proxy}"); fi
  if [[ -v all_proxy ]]; then proxy_env+=("all_proxy=${all_proxy}"); fi
}

# Creates the work directory and, in it, the python3 that the installer finds first on its PATH.
create_work_dir() {
  work_dir="$(mktemp --directory)"
  # World-readable: through runuser, the remote user reads the installer, the constraint file, and the shim here.
  chmod 755 "${work_dir}"
  # The shim runs the selected interpreter by its stable path, so the venv never links to a temporary symlink and never
  # takes an older python3 from elsewhere on PATH.
  mkdir "${work_dir}/bin"
  printf '#!/usr/bin/env bash\nexec %q "$@"\n' "${python_command}" >"${work_dir}/bin/python3"
  chmod 755 "${work_dir}/bin/python3"
}

# Sets resolved_version: VERSION when it names a release, otherwise the release that info.version of LATEST_URL names.
resolve_version() {
  if [[ "${VERSION}" != latest ]]; then
    resolved_version="${VERSION}"
  else
    log "requesting the latest huggingface_hub release from ${LATEST_URL}"
    fetch "${LATEST_URL}" "${work_dir}/latest.json" \
      || fail "cannot fetch ${LATEST_URL}; check the build's network and proxy, or set the option version to a release"
    resolved_version="$(
      "${python_command}" - "${work_dir}/latest.json" "${LATEST_URL}" <<'PY'
import json, sys
try:
    value = json.load(open(sys.argv[1]))["info"]["version"]
    if not isinstance(value, str):
        raise ValueError()
    print(value)
except Exception:
    sys.exit(f"hf-cli: error: invalid response from {sys.argv[2]}: it holds no info.version string")
PY
    )"
    [[ "${resolved_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
      || fail "${LATEST_URL} names the release \"${resolved_version}\", which is not of the form MAJOR.MINOR.PATCH;" \
        "set the option version to a release"
    if older_than "${resolved_version}" "${MINIMUM_VERSION}"; then
      fail "${LATEST_URL} names the release ${resolved_version}, which is below ${MINIMUM_VERSION};" \
        "set the option version to a release that is at least ${MINIMUM_VERSION}"
    fi
  fi
  log "resolved huggingface_hub version: ${resolved_version}"
}

# Writes the constraint that pins huggingface_hub and sets install_env, the whole environment of every command run as
# the remote user: the shim first on PATH, uv and pip limited to their default index, to wheels, and to no cache or
# configuration file, the CLI offline, and the proxy variables.
prepare_install_environment() {
  printf 'huggingface_hub==%s\n' "${resolved_version}" >"${work_dir}/constraints.txt"
  chmod 644 "${work_dir}/constraints.txt"
  install_env=(
    "HOME=${remote_home}" "USER=${remote_user}" "PATH=${work_dir}/bin:${SYSTEM_PATH}"
    UV_NO_CONFIG=1 UV_NO_CACHE=1 UV_NO_BUILD=1 UV_COMPILE_BYTECODE=1
    "UV_CONSTRAINT=${work_dir}/constraints.txt" "PIP_CONSTRAINT=${work_dir}/constraints.txt"
    PIP_CONFIG_FILE=/dev/null PIP_NO_CACHE_DIR=1 PIP_ONLY_BINARY=:all:
    HF_HUB_DISABLE_UPDATE_CHECK=1 HF_HUB_OFFLINE=1
    "${proxy_env[@]}"
  )
  # Commands run through runuser start in a directory the remote user owns.
  cd "${remote_home}"
}

# Downloads and runs the installer of the resolved version's tag. When an installer-managed venv already holds that
# version, it keeps the venv and only generates the skill, if the option asks for one that this version has not written.
install_cli() {
  local venv="${remote_home}/${VENV_SUFFIX}"
  local skill="${remote_home}/${SKILL_SUFFIX}/SKILL.md"
  local installer="${work_dir}/install.sh"
  local installer_url="${INSTALLER_BASE_URL}/v${resolved_version}/${INSTALLER_TAG_PATH}"
  local installer_digest
  local -a installer_arguments=(--no-modify-path --force)
  local -a skill_arguments=(skills add hf-cli --global --force)
  local present_version=""
  if [[ -f "${venv}/.hf_installer_marker" && -x "${venv}/bin/python" ]]; then
    # An earlier venv that cannot run, for example after its interpreter was removed, gets a full reinstall instead of
    # failing the build, so the probe's error is discarded here.
    if ! present_version="$(installed_version "${venv}" 2>/dev/null)"; then present_version=""; fi
  fi
  if [[ "${present_version}" == "${resolved_version}" ]]; then
    log "skipping package installation: huggingface_hub ${resolved_version} is already installer-managed in ${venv}"
    if [[ "${INSTALLSKILL}" == true ]] \
      && ! grep --fixed-strings --quiet --no-messages "huggingface_hub v${resolved_version}" "${skill}"; then
      if older_than "${resolved_version}" "${CLAUDE_FLAG_BEFORE_VERSION}"; then skill_arguments+=(--claude); fi
      log "generating the skill ${skill} with ${venv}/bin/hf as ${remote_user}"
      run_as_user "${venv}/bin/hf" "${skill_arguments[@]}" \
        || fail "cannot generate the skill ${skill}; read the output of hf above"
    fi
    return
  fi
  log "downloading the installer ${installer_url} to ${installer}"
  fetch "${installer_url}" "${installer}" \
    || fail "cannot fetch ${installer_url}; check that huggingface_hub release ${resolved_version} exists," \
      "and the build's network and proxy"
  chmod 644 "${installer}"
  installer_digest="$(sha256sum "${installer}")"
  log "installer tag v${resolved_version}; SHA-256 ${installer_digest%% *}"
  if [[ "${INSTALLSKILL}" == false ]]; then installer_arguments+=(--exclude-skill); fi
  log "running the installer as ${remote_user} to create ${venv}"
  run_as_user bash "${installer}" "${installer_arguments[@]}" \
    || fail "the installer of huggingface_hub ${resolved_version} failed; read its output above"
}

# Fails unless the venv holds exactly the resolved version and the installer's marker and, with installSkill, the skill
# names that version and the Claude link points to it. Runs before the CLI is linked for every user.
verify_install() {
  local venv="${remote_home}/${VENV_SUFFIX}"
  local skill_dir="${remote_home}/${SKILL_SUFFIX}"
  local claude_link="${remote_home}/${CLAUDE_SKILL_SUFFIX}"
  local actual_version
  actual_version="$(installed_version "${venv}")"
  [[ "${actual_version}" == "${resolved_version}" ]] \
    || fail "installed huggingface_hub ${actual_version} differs from requested ${resolved_version};" \
      "read the output above"
  [[ -f "${venv}/.hf_installer_marker" ]] \
    || fail "the installer marker ${venv}/.hf_installer_marker is missing; read the output above"
  if [[ "${INSTALLSKILL}" == true ]]; then
    grep --fixed-strings --quiet --no-messages "huggingface_hub v${resolved_version}" "${skill_dir}/SKILL.md" \
      || fail "missing skill for huggingface_hub ${resolved_version}: ${skill_dir}/SKILL.md; read the output above"
    [[ "$(readlink --canonicalize "${claude_link}")" == "${skill_dir}" ]] \
      || fail "missing skill link ${claude_link} to ${skill_dir}; read the output above"
  fi
  run_as_user "${venv}/bin/hf" version
}

link_cli() {
  local venv="${remote_home}/${VENV_SUFFIX}"
  log "linking ${LINK_PATH} to ${venv}/bin/hf"
  ln --symbolic --force --no-dereference "${venv}/bin/hf" "${LINK_PATH}"
  log "installed hf ${resolved_version} for ${remote_user}"
}

main() {
  validate_options
  detect_platform
  readonly VERSION
  check_remote_user
  select_python
  check_uv
  install_prerequisites
  confirm_python
  collect_proxy_variables
  trap cleanup EXIT
  create_work_dir
  resolve_version
  prepare_install_environment
  install_cli
  verify_install
  link_cli
}

main "$@"
