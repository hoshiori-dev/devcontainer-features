#!/usr/bin/env bash
# Installs the Deno CLI at image build time. Supported images must already have Bash.
# The option arrives as VERSION; matching installed versions keep the existing executable.
set -euo pipefail

readonly BIN_DIR=/usr/local/bin
readonly TOOLS_ROOT=/usr/local/share/deno
readonly LATEST_URL=https://dl.deno.land/release-latest.txt
readonly RELEASES_URL=https://github.com/denoland/deno/releases/download
# HTTPS on every hop, redirects included; an HTTP error status fails the request. A connection
# that does not open in 30 s, or stalls below 1 KiB/s for 60 s, fails instead of hanging the build.
readonly CURL=(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3
    --connect-timeout 30 --speed-limit 1024 --speed-time 60)

# Shared installation state used by the exit trap.
tmp=""
staged=""
manager_ran=""

# Platform selection shared by prerequisite and release handling.
FAMILY=""
TARGET=""

log() { echo "deno feature: $*"; }
fail() {
    echo "deno feature: $*" >&2
    exit 1
}

check_platform() {
    local glibc loader os_id os_like os_name word glibc_version glibc_major glibc_minor machine
    # Identify the C library before checking the distribution or architecture.
    glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null)" || glibc=""
    case "${glibc}" in
        "glibc "*) ;;
        *)
            for loader in /lib/ld-musl-*; do
                [[ ! -e "${loader}" ]] || fail "this image uses musl; Deno publishes glibc builds only."
            done
            fail "the C library could not be identified; Deno needs glibc 2.27 or newer."
            ;;
    esac

    # Read /etc/os-release in subshells: it defines VERSION, which would overwrite the option.
    [[ -r /etc/os-release ]] || fail "cannot read /etc/os-release; supported families are Debian, Fedora, and openSUSE."
    # shellcheck source=/dev/null
    os_id="$(. /etc/os-release && echo "${ID:-}")"
    # shellcheck source=/dev/null
    os_like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
    # shellcheck source=/dev/null
    os_name="$(. /etc/os-release && echo "${PRETTY_NAME:-${ID:-unknown}}")"
    FAMILY=""
    for word in ${os_id} ${os_like}; do
        case "${word}" in
            debian | ubuntu) FAMILY=debian ;;
            fedora | rhel | centos) FAMILY=fedora ;;
            opensuse) FAMILY=opensuse ;;
            *) continue ;;
        esac
        break
    done
    [[ -n "${FAMILY}" ]] || fail "unsupported distribution \"${os_name}\" (ID=${os_id}); supported families are Debian, Fedora, and openSUSE."

    glibc_version="${glibc#glibc }"
    glibc_major="${glibc_version%%.*}"
    glibc_minor="${glibc_version#*.}"
    glibc_minor="${glibc_minor%%.*}"
    case "${glibc_major}" in '' | *[!0-9]*) glibc_major="" ;; esac
    case "${glibc_minor}" in '' | *[!0-9]*) glibc_minor="" ;; esac
    if [[ -z "${glibc_major}" ]] || [[ -z "${glibc_minor}" ]]; then
        fail "cannot read the glibc version from \"${glibc}\"; Deno needs glibc 2.27 or newer."
    fi
    if [[ "${glibc_major}" -lt 2 ]] || { [[ "${glibc_major}" -eq 2 ]] && [[ "${glibc_minor}" -lt 27 ]]; }; then
        fail "glibc ${glibc_version} found; Deno needs glibc 2.27 or newer."
    fi

    machine="$(uname -m)"
    case "${machine}" in
        x86_64) TARGET="x86_64-unknown-linux-gnu" ;;
        aarch64 | arm64) TARGET="aarch64-unknown-linux-gnu" ;;
        *) fail "unsupported architecture \"${machine}\"; Deno publishes Linux builds for amd64 (x86_64) and arm64 (aarch64) only." ;;
    esac
}

validate_version() {
    local requested="$1"
    # Option check before any network access, apt included. Unset means the default; empty is invalid.
    if [[ "${requested}" != latest && ! "${requested}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        fail "option version is \"${requested}\"; use \"latest\" or an exact release version MAJOR.MINOR.PATCH such as 2.9.7."
    fi
}

# Remove downloads, staging, and package-manager caches on success and failure alike.
cleanup() {
    local status=$?
    rm -rf "${tmp}"
    if [[ -n "${staged}" ]]; then rm -f "${staged}"; fi
    case "${manager_ran}" in
        apt-get) apt-get clean; rm -rf /var/lib/apt/lists/* ;;
        dnf) dnf clean all ;;
        zypper) zypper --non-interactive clean --all ;;
    esac
    return "${status}"
}

ensure_prerequisites() {
    local bundle manager
    local missing_packages=()
    command -v curl >/dev/null 2>&1 || missing_packages+=(curl)
    local ca_present=0
    for bundle in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem; do
        if [[ -s "${bundle}" ]]; then ca_present=1; break; fi
    done
    if ((!ca_present)); then
        if [[ "${FAMILY}" == opensuse ]]; then
            missing_packages+=(ca-certificates-mozilla)
        else
            missing_packages+=(ca-certificates)
        fi
    fi
    command -v unzip >/dev/null 2>&1 || missing_packages+=(unzip)
    if ((${#missing_packages[@]} == 0)); then return; fi
    case "${FAMILY}" in
        debian) manager=apt-get ;;
        fedora) manager=dnf ;;
        opensuse) manager=zypper ;;
    esac
    command -v "${manager}" >/dev/null 2>&1 ||
        fail "missing ${missing_packages[*]}; this family needs ${manager} to install them."
    log "installing ${missing_packages[*]} with ${manager}"
    manager_ran="${manager}"
    case "${manager}" in
        apt-get)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y --no-install-recommends "${missing_packages[@]}"
            ;;
        dnf) dnf install -y --setopt=install_weak_deps=False "${missing_packages[@]}" ;;
        zypper)
            zypper --non-interactive refresh
            zypper --non-interactive --no-refresh install --no-recommends "${missing_packages[@]}"
            ;;
    esac
}

# fetch <url> <file>: 0 when downloaded, 4 when the server answered 404; any other failure exits.
fetch() {
    local url="$1" out="$2" code status=0
    code="$("${CURL[@]}" --output "${out}" --write-out '%{http_code}' "${url}" 2>"${tmp}/curl.err")" || status=$?
    if ((status == 0)); then return 0; fi
    rm -f "${out}"
    if [[ "${code}" == 404 ]]; then return 4; fi
    fail "downloading ${url} failed (HTTP ${code:-none}, curl exit ${status}): $(cat "${tmp}/curl.err")"
}

resolve_version() {
    local requested="$1" pointer version
    if [[ "${requested}" == latest ]]; then
        fetch "${LATEST_URL}" "${tmp}/latest" || fail "${LATEST_URL} answered 404; cannot resolve \"latest\"."
        pointer="$(<"${tmp}/latest")"
        pointer="${pointer#"${pointer%%[![:space:]]*}"}"
        pointer="${pointer%"${pointer##*[![:space:]]}"}"
        if [[ ! "${pointer}" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
            fail "the latest-release pointer ${LATEST_URL} returned \"${pointer:0:200}\", which is not v<MAJOR>.<MINOR>.<PATCH>; nothing was installed."
        fi
        version="${BASH_REMATCH[1]}"
        log "latest resolves to ${version}" >&2
    else
        version="${requested}"
    fi
    echo "${version}"
}

# Reject unrelated or remapped groups before prerequisites or downloads change the image.
check_tools_group() {
    local uid entry gid members member account _password _account_uid primary_gid _rest
    if [[ -z "${_REMOTE_USER:-}" || "${_REMOTE_USER}" == root ]] ||
        ! uid="$(id -u -- "${_REMOTE_USER}" 2>/dev/null)" || [[ "${uid}" == 0 ]]; then
        return
    fi
    entry="$(getent group deno)" || return 0
    IFS=: read -r account _password gid members <<<"${entry}"
    [[ "${gid}" != "$(id -g -- "${_REMOTE_USER}")" ]] ||
        fail "group deno is the primary group of '${_REMOTE_USER}'; use a separate primary group so UID/GID remapping preserves tools access."
    local member_list=()
    IFS=, read -r -a member_list <<<"${members}"
    for member in "${member_list[@]}"; do
        [[ "${member}" == "${_REMOTE_USER}" ]] || fail "group deno belongs to another account: ${member}. Use a group reserved for this feature."
    done
    while IFS=: read -r account _password _account_uid primary_gid _rest; do
        [[ "${primary_gid}" != "${gid}" ]] ||
            fail "group deno is the primary group of another account: ${account}. Use a group reserved for this feature."
    done < <(getent passwd)
}

# Re-apply directory access without changing existing tools' ownership.
setup_tools_root() {
    local group=root mode=0755 uid
    if [[ -n "${_REMOTE_USER:-}" && "${_REMOTE_USER}" != root ]] &&
        uid="$(id -u -- "${_REMOTE_USER}" 2>/dev/null)" && [[ "${uid}" != 0 ]]; then
        getent group deno >/dev/null || groupadd --system deno
        case " $(id -nG -- "${_REMOTE_USER}") " in
            *" deno "*) ;;
            *) usermod -aG deno "${_REMOTE_USER}" ;;
        esac
        group=deno
        mode=2775
    fi
    mkdir -p "${TOOLS_ROOT}/bin" /etc/profile.d
    chown -h -- "root:${group}" "${TOOLS_ROOT}" "${TOOLS_ROOT}/bin"
    chmod "${mode}" "${TOOLS_ROOT}" "${TOOLS_ROOT}/bin"
    cat > /etc/profile.d/deno.sh <<'PROFILE'
case ":${PATH}:" in
    *:/usr/local/share/deno/bin:*) ;;
    *) export PATH="${PATH}:/usr/local/share/deno/bin" ;;
esac
PROFILE
    chmod 0644 /etc/profile.d/deno.sh
    log "global tools go to ${TOOLS_ROOT}/bin, group ${group}, mode ${mode}"
}

# Version reported by a deno executable: the second field of the first line of --version.
reported_version() {
    local out first _name reported
    out="$("$1" --version 2>/dev/null)" || return 0
    first="${out%%$'\n'*}"
    read -r _name reported _ <<<"${first}" || true
    echo "${reported:-}"
}

# expected_hash <checksum file> <name>: the hash of its single line, whose name field must be <name>.
expected_hash() {
    local file="$1" name="$2" lines line
    mapfile -t lines <"${tmp}/${file}"
    ((${#lines[@]} == 1)) || fail "${file} must hold exactly one line; it holds ${#lines[@]}. Nothing was installed."
    line="${lines[0]%$'\r'}"
    if [[ ! "${line}" =~ ^([0-9A-Fa-f]{64})\ [\ *](.+)$ || "${BASH_REMATCH[2]}" != "${name}" ]]; then
        fail "${file} is not a SHA-256 line for ${name}. Nothing was installed."
    fi
    echo "${BASH_REMATCH[1],,}"
}

actual_hash() {
    local sum
    sum="$(sha256sum "$1")"
    echo "${sum%% *}"
}

download_verified_release() {
    local version="$1" name status code missing_list archive_expected exe_expected archive_actual exe_actual
    local archive="deno-${TARGET}.zip"
    local archive_sum="${archive}.sha256sum" exe_sum="deno-${TARGET}.sha256sum"
    # Checksum files come first; a missing file requires distinguishing an old release from a missing archive.
    local base="${RELEASES_URL}/v${version}"
    local missing_sums=()
    for name in "${archive_sum}" "${exe_sum}"; do
        fetch "${base}/${name}" "${tmp}/${name}" || missing_sums+=("${name}")
    done
    if ((${#missing_sums[@]} > 0)); then
        status=0
        code="$("${CURL[@]}" --head --output /dev/null --write-out '%{http_code}' "${base}/${archive}" 2>"${tmp}/curl.err")" ||
            status=$?
        if ((status == 0)); then
            missing_list="${missing_sums[0]}${missing_sums[1]:+ and ${missing_sums[1]}}"
            fail "the Deno ${version} release lacks ${missing_list}; this feature installs only releases that publish both" \
                "${archive_sum} and ${exe_sum} (2.7.14, and 2.8.0 or later). Nothing was installed."
        elif [[ "${code}" == 404 ]]; then
            fail "Deno ${version} has no release archive ${archive} (unknown version, or none for this architecture)." \
                "Nothing was installed."
        fi
        fail "checking ${base}/${archive} failed (HTTP ${code:-none}, curl exit ${status}): $(cat "${tmp}/curl.err")"
    fi

    archive_expected="$(expected_hash "${archive_sum}" "${archive}")"
    exe_expected="$(expected_hash "${exe_sum}" deno)"

    log "downloading ${base}/${archive}"
    fetch "${base}/${archive}" "${tmp}/${archive}" || fail "${base}/${archive} answered 404. Nothing was installed."
    archive_actual="$(actual_hash "${tmp}/${archive}")"
    if [[ "${archive_actual}" != "${archive_expected}" ]]; then
        fail "checksum mismatch for the archive ${archive}: expected ${archive_expected}, got ${archive_actual}." \
            "Nothing was extracted or installed."
    fi

    mkdir "${tmp}/extract"
    unzip -q "${tmp}/${archive}" deno -d "${tmp}/extract" ||
        fail "${archive} holds no file named deno, or unzip failed. Nothing was installed."
    if [[ ! -f "${tmp}/extract/deno" || -L "${tmp}/extract/deno" ]]; then
        fail "${archive} holds no regular file named deno. Nothing was installed."
    fi
    exe_actual="$(actual_hash "${tmp}/extract/deno")"
    if [[ "${exe_actual}" != "${exe_expected}" ]]; then
        fail "checksum mismatch for the extracted executable deno from ${archive}: expected ${exe_expected}," \
            "got ${exe_actual}. It was not installed."
    fi
}

# Verify the staged executable and configure tools before replacing the previous binary.
install_release() {
    local version="$1" staged_version
    mkdir -p "${BIN_DIR}"
    staged="$(mktemp "${BIN_DIR}/.deno.XXXXXX")"
    cp "${tmp}/extract/deno" "${staged}"
    chmod 0755 "${staged}"
    staged_version="$(reported_version "${staged}")"
    if [[ "${staged_version}" != "${version}" ]]; then
        fail "the verified executable reports version \"${staged_version}\", not ${version}. It was not installed."
    fi
    setup_tools_root
    mv -fT "${staged}" "${BIN_DIR}/deno"
    staged=""
    log "installed Deno ${version} at ${BIN_DIR}/deno"
}

main() {
    local requested="${VERSION-latest}" version
    check_platform
    validate_version "${requested}"
    check_tools_group

    tmp="$(mktemp -d)"
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    ensure_prerequisites
    version="$(resolve_version "${requested}")"
    if [[ -x "${BIN_DIR}/deno" && "$(reported_version "${BIN_DIR}/deno")" == "${version}" ]]; then
        log "Deno ${version} is already installed at ${BIN_DIR}/deno; skipping the download."
        setup_tools_root
        return
    fi

    download_verified_release "${version}"
    install_release "${version}"
}

main "$@"
