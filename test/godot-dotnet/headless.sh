# shellcheck shell=bash
# Sourced by the godot-dotnet test scripts: the minimal projects of the spec's "Headless use" requirement, and the
# assertions more than one test script uses. The scripts run as the remote user and source
# dev-container-features-test-lib first.

readonly LINK="/usr/local/bin/godot"
readonly INSTALL_ROOT="/opt/godot-dotnet"
readonly MARKER="${INSTALL_ROOT}/.devcontainer-feature-godot-dotnet"
# The line the minimal C# project's script prints when its node is ready.
readonly CSHARP_LINE="HELLO_FROM_CSHARP"

# Writes a minimal project into the new directory $1: a project.godot whose application/run/main_scene names main.tscn,
# a scene holding one node.
make_project() {
  mkdir "$1"
  cat >"$1/project.godot" <<'PROJECT'
config_version=5

[application]

config/name="Minimal"
run/main_scene="res://main.tscn"
PROJECT
  cat >"$1/main.tscn" <<'SCENE'
[gd_scene format=3]

[node name="Main" type="Node"]
SCENE
}

# Writes a minimal C# project into the new directory $1: the scene's node carries a C# script that prints CSHARP_LINE
# when it is ready, and CsTest.csproj uses the Godot.NET.Sdk of the installed release, the version `godot --version`
# reports padded to three parts, with the target framework the release's own GodotPlugins.runtimeconfig.json names.
# The assembly is named after config/name.
make_csharp_project() {
  local version
  local release
  local framework
  version="$(godot --version)" || return 1
  version="${version%%.stable.*}"
  if [[ "${version}" =~ ^[0-9]+\.[0-9]+$ ]]; then version+=".0"; fi
  release="$(dirname "$(readlink -f "${LINK}")")"
  framework="$(sed -n 's/^.*"tfm": *"\([^"]*\)".*$/\1/p' \
    "${release}/GodotSharp/Api/Release/GodotPlugins.runtimeconfig.json")"
  [[ -n "${framework}" ]] || return 1
  mkdir "$1"
  cat >"$1/project.godot" <<PROJECT
config_version=5

[application]

config/name="CsTest"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("${version%.*}", "C#")

[dotnet]

project/assembly_name="CsTest"
PROJECT
  cat >"$1/CsTest.csproj" <<CSPROJ
<Project Sdk="Godot.NET.Sdk/${version}">
  <PropertyGroup>
    <TargetFramework>${framework}</TargetFramework>
    <EnableDynamicLoading>true</EnableDynamicLoading>
  </PropertyGroup>
</Project>
CSPROJ
  cat >"$1/Main.cs" <<CSHARP
using Godot;

public partial class Main : Node
{
    public override void _Ready()
    {
        GD.Print("${CSHARP_LINE}");
    }
}
CSHARP
  cat >"$1/main.tscn" <<'SCENE'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://Main.cs" id="1"]

[node name="Main" type="Node"]
script = ExtResource("1")
SCENE
  printf '  Godot.NET.Sdk/%s, %s\n' "${version}" "${framework}"
}

# `godot --headless --path $1 --build-solutions --quit` exits 0 and leaves the assembly CsTest.dll under
# $1/.godot/mono/temp/bin/; the command's output goes to $2 and is shown when the check fails.
builds_csharp_project() {
  local assembly
  if ! godot --headless --path "$1" --build-solutions --quit </dev/null >"$2" 2>&1; then
    tail -n 20 "$2"
    return 1
  fi
  assembly="$(find "$1/.godot/mono/temp/bin" -name CsTest.dll -print -quit 2>/dev/null)"
  if [[ -z "${assembly}" ]]; then
    printf '  no CsTest.dll under %s/.godot/mono/temp/bin\n' "$1"
    tail -n 20 "$2"
    return 1
  fi
  printf '  built %s\n' "${assembly}"
}

# `godot --headless --path $1 --quit-after 10` exits 0 and its output holds CSHARP_LINE; the output goes to $2 and is
# shown when the check fails.
runs_csharp_project() {
  if ! godot --headless --path "$1" --quit-after 10 </dev/null >"$2" 2>&1 || ! grep -qx "${CSHARP_LINE}" "$2"; then
    tail -n 20 "$2"
    return 1
  fi
}

# `godot --version` exits 0 and prints exactly $1, ".stable.mono.official.", and a hexadecimal commit hash.
godot_reports_version() {
  local output
  output="$(godot --version)" || return 1
  printf "  got '%s', expected '%s.stable.mono.official.<hash>'\n" "${output}" "$1"
  [[ "${output}" == "$1.stable.mono.official."* && "${output#"$1.stable.mono.official."}" =~ ^[0-9a-f]+$ ]]
}

# `command -v godot` prints /usr/local/bin/godot, a symbolic link to the executable godot in a directory directly under
# /opt/godot-dotnet.
godot_links_into_release() {
  local found
  local target
  found="$(command -v godot)" || return 1
  target="$(readlink "${LINK}")" || return 1
  printf '  command -v godot: %s, link target: %s\n' "${found}" "${target}"
  [[ "${found}" == "${LINK}" && "${target}" =~ ^/opt/godot-dotnet/[^/]+/godot$ && -x "${target}" ]]
}

# /opt/godot-dotnet holds the marker and exactly one other entry, the release directory the link points into.
one_release_directory() {
  local entries
  local release
  release="$(dirname "$(readlink "${LINK}")")" || return 1
  entries="$(find "${INSTALL_ROOT}" -mindepth 1 -maxdepth 1 | sort)"
  printf '  entries of %s:\n%s\n' "${INSTALL_ROOT}" "${entries}"
  [[ "${entries}" == "$(printf '%s\n%s' "${MARKER}" "${release}" | sort)" && -d "${release}" ]]
}

# Prints the tag the latest-release link names when called, read as install.sh reads it, without following the
# redirect.
latest_release_tag() {
  local location
  local tag
  location="$(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --retry 3 \
    --head --output /dev/null --write-out '%{redirect_url}' \
    https://github.com/godotengine/godot/releases/latest)" || return 1
  if [[ -z "${location}" ]]; then
    echo 'the latest-release link did not redirect to a release' >&2
    return 1
  fi
  tag="${location%%[?#]*}"
  tag="${tag%/}"
  printf '%s\n' "${tag##*/}"
}

# No temporary directory or temporary link of install.sh remains, and /opt/godot-dotnet holds no release directory but
# the one the link points into. The directories are listable by every user, so the globs expand for the remote user
# too.
no_install_residue() {
  local path
  for path in /tmp/godot-dotnet-feature.* "${TMPDIR:-/tmp}"/godot-dotnet-feature.* \
    /usr/local/bin/.godot-dotnet-feature.*; do
    if [[ -e "${path}" || -L "${path}" ]]; then
      printf '  residue: %s\n' "${path}"
      return 1
    fi
  done
  one_release_directory
}
