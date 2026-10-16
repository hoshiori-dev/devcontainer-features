#!/usr/bin/env bash
# Installs verified upstream TinyTeX bundles to the remote user's ~/.TinyTeX and links commands in ~/.local/bin.
# Runs as root at image build time; options arrive as PROFILE, LANGUAGES, PACKAGES, and CTANMIRROR.
set -euo pipefail

readonly RELEASE_METADATA="https://api.github.com/repos/rstudio/tinytex-releases/releases/tags/daily"
readonly RELEASE_DOWNLOAD="https://github.com/rstudio/tinytex-releases/releases/download/daily"
readonly CTAN_REPOSITORY="https://mirror.ctan.org/systems/texlive/tlnet"
readonly ENV_DIR="/usr/local/share/latex"
readonly APT_LISTS_DIR="/var/lib/apt/lists"
readonly ENV_MARKER="${ENV_DIR}/.devcontainer-latex"
readonly PROFILE_PATH="/etc/profile.d/latex.sh"
readonly DOWNLOAD_ARGS="--proto =https --proto-redir =https --fail --location --silent --show-error --output"
readonly INSTALL_MARKER=".devcontainer-latex"
readonly REMOTE_USER="${_REMOTE_USER-}"
readonly REMOTE_HOME="${_REMOTE_USER_HOME-}"
readonly TEX_DIR="${REMOTE_HOME}/.TinyTeX"
readonly TIMING_RECORD="${TEX_DIR}/.devcontainer-latex-timings"
readonly FONT_CACHE_MARKER="${TEX_DIR}/.devcontainer-latex-font-cache"
readonly USER_BIN="${REMOTE_HOME}/.local/bin"

PROFILE="${PROFILE-standard}"
LANGUAGES="${LANGUAGES-zh,ja}"
PACKAGES="${PACKAGES-}"
CTANMIRROR="${CTANMIRROR-}"

os_id=""
arch=""
work_dir=""
tex_bin=""
zh=false
ja=false
fresh=false
backup_dir=""
replacement_started=false
replacement_complete=false
extra_packages=()

log() { printf 'latex: %s\n' "$*"; }
fail() { printf 'latex: error: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if ${replacement_started} && ! ${replacement_complete}; then
    rm --recursive --force "${TEX_DIR}"
    if [[ -n "${backup_dir}" ]]; then mv -- "${backup_dir}" "${TEX_DIR}"; fi
    replacement_started=false
    backup_dir=""
  elif ${replacement_complete} && [[ -n "${backup_dir}" ]]; then
    rm --recursive --force "${backup_dir}"
    backup_dir=""
  fi
  if [[ -n "${work_dir}" ]]; then rm --recursive --force "${work_dir}"; fi
}

fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 "$@"
}

# Runs a command without shell interpolation as the target user, with its actual home and TeX PATH.
as_user() {
  if [[ "${REMOTE_USER}" == root ]]; then
    env HOME="${REMOTE_HOME}" PATH="${tex_bin:+${tex_bin}:}${USER_BIN}:${PATH}" TEXLIVE_DOWNLOADER= \
      TL_DOWNLOAD_PROGRAM=/usr/bin/curl TL_DOWNLOAD_ARGS="${DOWNLOAD_ARGS}" \
      TEXLIVE_DOWNLOAD_PROGRAM=/usr/bin/curl TEXLIVE_DOWNLOAD_ARGS="${DOWNLOAD_ARGS}" "$@"
  else
    runuser --user "${REMOTE_USER}" -- env HOME="${REMOTE_HOME}" \
      PATH="${tex_bin:+${tex_bin}:}${USER_BIN}:${PATH}" TEXLIVE_DOWNLOADER= \
      TL_DOWNLOAD_PROGRAM=/usr/bin/curl TL_DOWNLOAD_ARGS="${DOWNLOAD_ARGS}" \
      TEXLIVE_DOWNLOAD_PROGRAM=/usr/bin/curl TEXLIVE_DOWNLOAD_ARGS="${DOWNLOAD_ARGS}" "$@"
  fi
}

validate_options() {
  local token
  local selection="${LANGUAGES}"
  case "${PROFILE}" in basic | standard | full) ;; *) fail "invalid profile; use basic, standard, or full" ;; esac
  [[ -n "${selection}" ]] || fail "languages is empty; use zh, ja, zh,ja, or none"
  while :; do
    token="${selection%%,*}"
    token="${token#"${token%%[![:space:]]*}"}"
    token="${token%"${token##*[![:space:]]}"}"
    case "${token}" in
      zh) zh=true ;;
      ja) ja=true ;;
      none) [[ "${LANGUAGES}" =~ ^[[:space:]]*none[[:space:]]*$ ]] || fail "none cannot be combined with languages" ;;
      *) fail "invalid languages token; use zh, ja, or none" ;;
    esac
    [[ "${selection}" == *,* ]] || break
    selection="${selection#*,}"
  done
  read -r -a extra_packages <<< "${PACKAGES//,/ }"
  [[ "${PACKAGES}" != *$'\n'* && "${PACKAGES}" != *$'\r'* ]] || fail "packages must be one line"
  for token in "${extra_packages[@]}"; do
    [[ "${token}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || fail "invalid package name; provide TeX Live names only"
  done
  if [[ -n "${CTANMIRROR}" ]]; then
    [[ "${CTANMIRROR}" =~ ^https://[a-zA-Z0-9.-]+(:[0-9]+)?(/[a-zA-Z0-9._~%+/-]*)?$ ]] \
      || fail "ctanMirror must be an HTTPS repository URL without credentials"
  fi
  readonly PROFILE LANGUAGES PACKAGES CTANMIRROR
}

detect_platform() {
  [[ "$(id --user)" == 0 ]] || fail "run the installer as root at image build time"
  [[ -r /etc/os-release ]] || fail "cannot read /etc/os-release; use a supported glibc image"
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  case "${os_id}" in debian | ubuntu | fedora | almalinux | arch) ;;
    *) fail "unsupported distribution ${os_id}; use an image in the compatibility list" ;;
  esac
  if compgen -G '/lib/ld-musl-*' >/dev/null; then fail "musl is unsupported; use a glibc image"; fi
  case "$(uname --machine)" in
    x86_64) arch=x86_64 ;;
    aarch64) [[ "${os_id}" != arch ]] || fail "Arch ARM is not in the compatibility list"; arch=arm64 ;;
    *) fail "unsupported architecture; use amd64 or arm64" ;;
  esac
  [[ -n "${REMOTE_USER}" && "${REMOTE_HOME}" == /* && "${REMOTE_HOME}" != / ]] \
    || fail "missing target user/home; use the Dev Container Feature installer"
  id "${REMOTE_USER}" >/dev/null 2>&1 || fail "target user does not exist; create it before this feature"
  [[ -d "${REMOTE_HOME}" ]] || fail "invalid target home"
  if [[ -e "${ENV_DIR}" && ! -f "${ENV_MARKER}" ]]; then
    fail "unmanaged PATH bridge directory; move ${ENV_DIR} before retrying"
  fi
  if [[ -e "${PROFILE_PATH}" ]]; then
    grep -qx '# Managed by the latex Dev Container Feature.' "${PROFILE_PATH}" \
      || fail "unmanaged shell configuration at ${PROFILE_PATH}; move it before retrying"
  fi
}

# Checks required OS packages locally so repeat installation needs no repository refresh.
dependencies_installed() {
  local status
  case "${os_id}" in
    debian | ubuntu)
      if ! status="$(dpkg-query --show --showformat='${db:Status-Status}\n' "$@" 2>/dev/null)"; then return 1; fi
      status="${status//installed/}"
      [[ -z "${status//$'\n'/}" ]]
      ;;
    fedora | almalinux) rpm --query "$@" >/dev/null 2>&1 ;;
    arch) pacman --query "$@" >/dev/null 2>&1 ;;
  esac
}

install_dependencies() {
  local dependencies=()
  local fonts=()
  log "installing signed system dependencies for ${os_id}"
  case "${os_id}" in
    debian | ubuntu)
      dependencies=(ca-certificates curl tar xz-utils perl fontconfig python3 python3-pygments
        libyaml-tiny-perl libfile-homedir-perl libunicode-linebreak-perl util-linux gnupg)
      if ${zh} || ${ja}; then fonts+=(fonts-noto-cjk); fi
      if ${ja}; then fonts+=(fonts-ipaexfont); fi
      if dependencies_installed "${dependencies[@]}" "${fonts[@]}"; then
        log "required system packages are already installed"
      else
        apt-get update || fail "apt metadata failed; check the image's repositories"
        DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
          "${dependencies[@]}" "${fonts[@]}" || fail "apt dependencies failed; check repository availability"
      fi
      ;;
    fedora | almalinux)
      dependencies=(ca-certificates curl tar xz perl-interpreter fontconfig python3 python3-pygments
        perl-Digest-MD5 perl-Digest-SHA perl-Data-Dumper perl-Time-HiRes perl-File-Find perl-File-Temp
        perl-open perl-lib perl-sigtrap perl-File-Copy perl-Unicode-Normalize perl-Getopt-Long perl-PathTools perl-Pod-Usage
        perl-FindBin perl-Fcntl perl-POSIX perl-IO
        perl-YAML-Tiny perl-File-HomeDir perl-Unicode-LineBreak util-linux gnupg2 libxcrypt-compat)
      if ${zh} || ${ja}; then
        fonts+=(google-noto-sans-cjk-fonts google-noto-serif-cjk-vf-fonts)
      fi
      if [[ "${os_id}" == fedora ]] && ${ja}; then fonts+=(ipa-exmincho-fonts ipa-exgothic-fonts); fi
      if dependencies_installed "${dependencies[@]}" "${fonts[@]}"; then
        log "required system packages are already installed"
      elif [[ "${os_id}" == almalinux ]]; then
        dnf --enablerepo=crb install --assumeyes --setopt=install_weak_deps=False \
          "${dependencies[@]}" "${fonts[@]}" || fail "dnf dependencies failed; check vendor CRB availability"
      else
        dnf install --assumeyes --setopt=install_weak_deps=False "${dependencies[@]}" "${fonts[@]}" \
          || fail "dnf dependencies failed; check the image's repositories"
      fi
      ;;
    arch)
      dependencies=(ca-certificates curl tar xz perl fontconfig python python-pygments
        perl-yaml-tiny perl-file-homedir perl-unicode-linebreak util-linux gnupg libxcrypt-compat)
      if ${zh} || ${ja}; then fonts+=(noto-fonts-cjk); fi
      if ${ja}; then fonts+=(otf-ipaexfont); fi
      if dependencies_installed "${dependencies[@]}" "${fonts[@]}"; then
        log "required system packages are already installed"
      else
        pacman --sync --refresh --sysupgrade --noconfirm --needed "${dependencies[@]}" "${fonts[@]}" \
          || fail "pacman dependencies failed; check the image's signed repositories"
      fi
      ;;
  esac
  python3 -c 'import sys; assert sys.version_info >= (3, 8)' || fail "Python 3.8 or newer is required"
}


install_packages() {
  local repository="${CTANMIRROR:-${CTAN_REPOSITORY}}"
  local inventory
  local package
  local selected=(latex-bin xetex luahbtex luaotfload fontspec latexmk latexindent chktex)
  local missing=()
  local seen=' '
  if [[ "${PROFILE}" == standard ]]; then
    selected+=(biblatex biber natbib ieeetran acmart listings minted tcolorbox cleveref siunitx booktabs multirow fvextra
      tabularray caption enumitem ifoddpage relsize ncctools cmap algorithm2e algorithms algpseudocodex
      pgf pgfplots standalone)
  elif [[ "${PROFILE}" == full ]]; then
    selected+=(scheme-full)
  fi
  if ${zh}; then selected+=(xecjk ctex zhnumber unicode-data fandol); fi
  if ${ja}; then
    selected+=(luatexja zxjatype xecjk ptex uptex platex uplatex japanese-otf pxjahyper bxjscls
      pbibtex-base ptex-fontmaps haranoaji jsclasses)
    if [[ "${os_id}" == almalinux ]]; then selected+=(ipaex); fi
  fi
  selected+=("${extra_packages[@]}")
  log "configuring tlmgr repository ${repository}"
  as_user tlmgr option repository "${repository}" || fail "cannot configure TeX Live repository"
  inventory="$(as_user tlmgr info --only-installed --data name)" || fail "cannot read installed TeX packages"
  for package in "${selected[@]}"; do
    if [[ "${seen}" == *" ${package} "* ]]; then continue; fi
    seen+="${package} "
    if ! [[ $'\n'"${inventory}"$'\n' == *$'\n'"${package}"$'\n'* ]]; then missing+=("${package}"); fi
  done
  if (( ${#missing[@]} )); then
    log "installing missing TeX packages: ${missing[*]}"
    as_user tlmgr install "${missing[@]}" \
      || fail "package installation failed; check names and availability, or rebuild from a current base / configure a matching TeX Live year"
  fi
  if ${ja}; then
    log "selecting Harano Aji Japanese font maps"
    as_user kanji-config-updmap-sys haranoaji || fail "cannot configure Japanese fonts"
  fi
}

configure_environment() {
  local executable
  local target
  log "linking TeX commands to ${USER_BIN}"
  as_user mkdir --parents "${USER_BIN}"
  for executable in "${tex_bin}"/*; do
    target="${USER_BIN}/${executable##*/}"
    if [[ -e "${target}" || -L "${target}" ]]; then
      [[ -L "${target}" && "$(readlink "${target}")" == *[Tt]iny[Tt]e[Xx]*/bin/* ]] \
        || fail "command conflict at ${target}; move the unrelated file before retrying"
    fi
  done
  log "warming system and target-user Lua font caches"
  fc-cache || fail "fontconfig cache generation failed"
  as_user luaotfload-tool --update || fail "Lua font cache generation failed"
  as_user touch "${FONT_CACHE_MARKER}"
  for target in "${USER_BIN}"/*; do
    if [[ -L "${target}" && "$(readlink "${target}")" == *[Tt]iny[Tt]e[Xx]*/bin/* ]]; then
      rm -- "${target}"
    fi
  done
  as_user tlmgr option sys_bin "${USER_BIN}"
  as_user tlmgr path add || fail "cannot expose TeX commands in the user bin directory"
  mkdir --parents "${ENV_DIR}"
  touch "${ENV_MARKER}"
  [[ ! -e "${ENV_DIR}/bin" || -L "${ENV_DIR}/bin" ]] || fail "unexpected PATH bridge; move it before retrying"
  ln --symbolic --force --no-target-directory "${USER_BIN}" "${ENV_DIR}/bin"
  cat > "${PROFILE_PATH}" <<'SH'
# Managed by the latex Dev Container Feature.
export TEXLIVE_DOWNLOADER=
export TL_DOWNLOAD_PROGRAM=/usr/bin/curl TEXLIVE_DOWNLOAD_PROGRAM=/usr/bin/curl
export TL_DOWNLOAD_ARGS="--proto =https --proto-redir =https --fail --location --silent --show-error --output"
export TEXLIVE_DOWNLOAD_ARGS="${TL_DOWNLOAD_ARGS}"
case ":${PATH}:" in
  *:/usr/local/share/latex/bin:*) ;;
  *) export PATH="/usr/local/share/latex/bin:${PATH}" ;;
esac
SH

}

clean_dependencies() {
  log "cleaning system package caches"
  case "${os_id}" in
    debian | ubuntu) apt-get clean; rm --recursive --force "${APT_LISTS_DIR:?}"/* ;;
    fedora | almalinux) dnf clean all ;;
    arch) pacman --sync --clean --clean --noconfirm ;;
  esac
}

main() {
  local started=${SECONDS}
  validate_options
  detect_platform
  trap cleanup EXIT
  install_dependencies
  # shellcheck source=src/latex/scripts/bundle.sh
  source "$(dirname "${BASH_SOURCE[0]}")/scripts/bundle.sh"
  install_bundle
  install_packages
  configure_environment
  clean_dependencies
  replacement_complete=true
  cleanup
  printf '%s %s %s %s\n' "${PROFILE}" "${fresh}" "${arch}" "$((SECONDS - started))" \
    | as_user tee --append "${TIMING_RECORD}"
  log "installation complete: profile=${PROFILE}, architecture=${arch}, elapsed=$((SECONDS - started))s"
}
main "$@"
