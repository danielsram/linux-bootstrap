#!/usr/bin/env bash
#
# bootstrap.sh — developer workstation setup for Ubuntu (26.04 LTS "resolute", ARM64 and AMD64)
#
#   * idempotent — safe to re-run, already-installed things are skipped
#   * resilient — a failing install does not abort the run; it is logged and
#     listed under FAILED in the summary
#   * logs everything to a file, colored output on the terminal
#   * configured by the variables below, or by a bootstrap.env file next to the script
#
# Usage:
#
#   ./bootstrap.sh
#
# Run as a regular user, NOT under sudo — nvm, SDKMAN and Claude Code install
# into $HOME, and the Claude Code installer refuses to run under sudo. The
# script asks for sudo itself.
#
# The install order lives in main() at the bottom of this file.
#

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# CONFIGURATION
#
# Overridable by a bootstrap.env file next to the script (see
# bootstrap.env.example), which is sourced right below this block.
# =============================================================================

# --- Git identity (placeholders or empty = the git step is skipped) -----------
GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"

# --- Java --------------------------------------------------------------------
# SDKMAN identifiers are always full versions (e.g. 25.0.1-open) — there is no
# bare-major form. The major version and vendor are therefore given separately
# and resolved against `sdk list java` at runtime.
# Set JAVA_VERSION to pin one exact identifier and skip the lookup.
JAVA_MAJOR="${JAVA_MAJOR:-25}"
JAVA_VENDOR="${JAVA_VENDOR:-open}"
JAVA_VERSION="${JAVA_VERSION:-}"

# --- Other versions (empty = resolved at runtime, never hardcoded) ------------
NODE_VERSION="${NODE_VERSION:-lts/*}"
NVM_VERSION="${NVM_VERSION:-v0.40.3}"
KUBERNETES_MINOR="${KUBERNETES_MINOR:-}"
YQ_VERSION="${YQ_VERSION:-}"
MONGODB_COMPASS_VERSION="${MONGODB_COMPASS_VERSION:-}"
PROTONVPN_RELEASE_DEB="${PROTONVPN_RELEASE_DEB:-}"

# --- What to install ---------------------------------------------------------
INSTALL_BASE="${INSTALL_BASE:-true}"
INSTALL_CLI_TOOLS="${INSTALL_CLI_TOOLS:-true}"
INSTALL_PYTHON="${INSTALL_PYTHON:-true}"
INSTALL_YQ="${INSTALL_YQ:-true}"
INSTALL_GIT_CONFIG="${INSTALL_GIT_CONFIG:-true}"
INSTALL_JAVA="${INSTALL_JAVA:-true}"
INSTALL_NODE="${INSTALL_NODE:-true}"
INSTALL_DOCKER="${INSTALL_DOCKER:-true}"
INSTALL_KUBECTL="${INSTALL_KUBECTL:-true}"
INSTALL_HELM="${INSTALL_HELM:-true}"
INSTALL_TERRAFORM="${INSTALL_TERRAFORM:-true}"
INSTALL_AWS_CLI="${INSTALL_AWS_CLI:-true}"
INSTALL_GCLOUD="${INSTALL_GCLOUD:-true}"
INSTALL_CLAUDE_CODE="${INSTALL_CLAUDE_CODE:-true}"
INSTALL_BRAVE="${INSTALL_BRAVE:-true}"
INSTALL_CHROME="${INSTALL_CHROME:-true}"
INSTALL_SUBLIME="${INSTALL_SUBLIME:-true}"
INSTALL_INTELLIJ="${INSTALL_INTELLIJ:-true}"
INSTALL_LENS="${INSTALL_LENS:-true}"
INSTALL_MONGODB_COMPASS="${INSTALL_MONGODB_COMPASS:-true}"
INSTALL_SLACK="${INSTALL_SLACK:-true}"
INSTALL_SPOTIFY="${INSTALL_SPOTIFY:-true}"
INSTALL_VLC="${INSTALL_VLC:-true}"
INSTALL_ZOOM="${INSTALL_ZOOM:-true}"
INSTALL_INSOMNIA="${INSTALL_INSOMNIA:-true}"
INSTALL_DELUGE="${INSTALL_DELUGE:-true}"
INSTALL_PROTONVPN="${INSTALL_PROTONVPN:-true}"
INSTALL_NORDVPN="${INSTALL_NORDVPN:-false}"
INSTALL_SHELL_CONFIG="${INSTALL_SHELL_CONFIG:-true}"

LOG_FILE="${LOG_FILE:-}"

if [[ -f "$SCRIPT_DIR/bootstrap.env" ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/bootstrap.env"
fi

if [[ -z "${LOG_FILE:-}" ]]; then
    LOG_FILE="$HOME/bootstrap-$(date +%Y%m%d-%H%M%S).log"
fi

# Suites for third-party apt repos keyed by Ubuntu codename. A fresh Ubuntu
# release sometimes lands in those repos late — then a fallback is used.
APT_FALLBACK_SUITES=(questing noble jammy)

# =============================================================================
# STATE
# =============================================================================

OK_STEPS=()
SKIPPED_STEPS=()
FAILED_STEPS=()
TMP_DIR=""
SUDO_KEEPALIVE_PID=""
SUMMARY_PRINTED=false
DEB_ARCH=""
UNAME_ARCH=""
JB_KEY=""
UBUNTU_CODENAME=""

# =============================================================================
# LOGGING
#
# All log functions write to stderr so they never pollute the stdout of a
# function that returns its value that way (e.g. resolve_apt_suite).
# =============================================================================

C_RESET=""; C_RED=""; C_YELLOW=""; C_GREEN=""; C_BLUE=""; C_BOLD=""; C_DIM=""

setup_colors() {
    if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
        C_RESET=$'\033[0m'
        C_RED=$'\033[0;31m'
        C_YELLOW=$'\033[0;33m'
        C_GREEN=$'\033[0;32m'
        C_BLUE=$'\033[0;34m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
    fi
}

log_info()  { printf '%s[INFO ]%s %s\n' "$C_BLUE"   "$C_RESET" "$*" >&2; }
log_ok()    { printf '%s[OK   ]%s %s\n' "$C_GREEN"  "$C_RESET" "$*" >&2; }
log_warn()  { printf '%s[WARN ]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }

die() {
    log_error "$*"
    exit 1
}

# Signals "nothing to do" — recorded as SKIPPED rather than OK.
nothing_to_do() {
    log_info "$1"
    return 3
}

# =============================================================================
# THE RUNNER
# =============================================================================

# run <enabled> <name> <function>
run() {
    local enabled="$1" name="$2" fn="$3"

    if [[ "$enabled" != "true" ]]; then
        SKIPPED_STEPS+=("${name} (disabled)")
        return 0
    fi

    printf '\n%s=== %s %s%s ===%s\n' \
        "$C_BOLD" "$name" "$C_DIM" "$(date '+%H:%M:%S')" "$C_RESET" >&2

    # The install runs in a subshell so one failure cannot abort the whole run,
    # while errexit still holds INSIDE it (a failed curl must not be followed by
    # tar). The subshell has to be a standalone command, not part of an AND-OR
    # list: bash suppresses errexit for everything in a `cmd || ...` list and
    # that suppression propagates into the subshell, where a nested `set -e`
    # does not restore it. Hence dropping errexit in the parent around a bare
    # subshell that re-enables it for itself.
    local rc=0
    set +e
    ( set -e; "$fn" )
    rc=$?
    set -e

    case "$rc" in
        0) log_ok "${name} done"; OK_STEPS+=("$name") ;;
        3) SKIPPED_STEPS+=("$name") ;;
        *) log_error "${name} FAILED (exit ${rc}) — continuing"
           FAILED_STEPS+=("${name} (exit ${rc})") ;;
    esac
    return 0
}

# =============================================================================
# HELPERS
# =============================================================================

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

deb_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

apt_update_once() {
    local stamp="$TMP_DIR/.apt-updated"
    if [[ -f "$stamp" ]]; then
        return 0
    fi
    log_info "apt-get update"
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    : >"$stamp"
}

apt_install() {
    local missing=()
    local pkg
    for pkg in "$@"; do
        if ! deb_installed "$pkg"; then
            missing+=("$pkg")
        fi
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        log_info "already installed: $*"
        return 0
    fi
    apt_update_once
    log_info "installing: ${missing[*]}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

# Some projects publish an ASCII-armored key, others a ready-made binary
# keyring — so dearmor is attempted and the raw file used if it fails.
add_apt_repo() {
    local name="$1" key_url="$2" repo_line="$3"
    local list="/etc/apt/sources.list.d/${name}.list"
    local keyring="/etc/apt/keyrings/${name}.gpg"

    if [[ -f "$list" && -f "$keyring" ]] && grep -qxF "$repo_line" "$list"; then
        log_info "apt repo '$name' is already configured"
        return 0
    fi

    log_info "configuring apt repo '$name'"
    local raw="$TMP_DIR/aptkey.raw"
    local armored="$TMP_DIR/aptkey.gpg"
    rm -f "$raw" "$armored"
    curl -fsSL --retry 3 "$key_url" -o "$raw"
    sudo install -m 0755 -d /etc/apt/keyrings
    if gpg --batch --yes --dearmor -o "$armored" "$raw" 2>/dev/null; then
        sudo install -m 0644 "$armored" "$keyring"
    else
        sudo install -m 0644 "$raw" "$keyring"
    fi

    printf '%s\n' "$repo_line" | sudo tee "$list" >/dev/null
    rm -f "$TMP_DIR/.apt-updated"   # a new repo needs a refresh
}

# Prints the first suite for which dists/<suite>/Release exists in the repo.
resolve_apt_suite() {
    local base="$1"
    shift
    local suite
    for suite in "$@"; do
        if curl -fsS --max-time 15 -o /dev/null "${base}/dists/${suite}/Release" 2>/dev/null; then
            log_info "repo ${base} → suite '${suite}'"
            printf '%s' "$suite"
            return 0
        fi
        log_warn "repo ${base} has no suite '${suite}', trying the next one"
    done
    return 1
}

install_deb_url() {
    local url="$1" name="$2"
    local file="$TMP_DIR/${name}.deb"
    log_info "downloading ${name}: ${url}"
    curl -fL --retry 3 --progress-bar "$url" -o "$file"
    apt_update_once
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$file"
}

snap_install() {
    local name="$1"
    if ! command_exists snap; then
        apt_install snapd
    fi
    if snap list "$name" >/dev/null 2>&1; then
        log_info "snap '$name' is already installed"
        return 0
    fi
    log_info "installing snap '$name'"
    sudo snap install "$name"
}

add_to_group() {
    local group="$1"
    if id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$group"; then
        log_info "user ${USER} is already in the ${group} group"
        return 0
    fi
    sudo usermod -aG "$group" "$USER"
    log_warn "user ${USER} added to the ${group} group — a logout/login is required"
    : >"$TMP_DIR/.needs-relogin"
}

# =============================================================================
# PREFLIGHT
# =============================================================================

preflight() {
    if [[ "${EUID}" -eq 0 ]]; then
        die "do not run this as root or under sudo — nvm, SDKMAN and Claude Code install into \$HOME and the Claude Code installer refuses to run under sudo. Run it as a regular user; it asks for sudo itself."
    fi
    command_exists sudo || die "sudo is not available, but it is required to install system packages"

    [[ -r /etc/os-release ]] || die "/etc/os-release is missing — this is not a Linux distribution this script handles"
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || die "this script targets Ubuntu, but it is running on '${PRETTY_NAME:-${ID:-unknown}}'"
    UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    [[ -n "$UBUNTU_CODENAME" ]] || die "could not determine the Ubuntu codename from /etc/os-release"
    if [[ "${VERSION_ID:-}" != "26.04" ]]; then
        log_warn "this script targets Ubuntu 26.04 LTS, running on ${VERSION_ID:-?} (${UBUNTU_CODENAME}) — continuing"
    fi
    log_info "system: ${PRETTY_NAME:-Ubuntu ${VERSION_ID:-?}} (${UBUNTU_CODENAME})"

    DEB_ARCH="$(dpkg --print-architecture)"
    case "$DEB_ARCH" in
        amd64) UNAME_ARCH="x86_64";  JB_KEY="linux" ;;
        arm64) UNAME_ARCH="aarch64"; JB_KEY="linuxARM64" ;;
        *) die "unsupported architecture: $DEB_ARCH (supported: amd64, arm64)" ;;
    esac
    log_info "architecture: $DEB_ARCH ($UNAME_ARCH)"

    local url reachable=false
    for url in https://archive.ubuntu.com https://api.github.com; do
        if curl -fsS --max-time 10 -o /dev/null "$url" 2>/dev/null; then
            log_info "internet connectivity OK (${url})"
            reachable=true
            break
        fi
    done
    [[ "$reachable" == "true" ]] || die "no internet connectivity (neither archive.ubuntu.com nor api.github.com is reachable)"

    TMP_DIR="$(mktemp -d)"
    trap cleanup EXIT
    trap 'log_warn "interrupted by the user"; exit 130' INT TERM
    trap 'log_error "error on line ${LINENO}: ${BASH_COMMAND}"' ERR

    log_info "requesting sudo privileges (password is entered once)"
    sudo -v || die "sudo authentication failed"
    # Keep the sudo ticket alive so a long install is not interrupted by a prompt.
    (
        while true; do
            sudo -n true 2>/dev/null || exit 0
            sleep 50
            kill -0 "$$" 2>/dev/null || exit 0
        done
    ) &
    SUDO_KEEPALIVE_PID=$!
}

cleanup() {
    local rc=$?
    trap - EXIT INT TERM

    if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi

    if [[ "$SUMMARY_PRINTED" == "false" ]]; then
        local total=$((${#OK_STEPS[@]} + ${#SKIPPED_STEPS[@]} + ${#FAILED_STEPS[@]}))
        if [[ "$total" -gt 0 ]]; then
            summary
        fi
    fi

    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
    return "$rc"
}

# =============================================================================
# INSTALLS — base system
# =============================================================================

install_base() {
    apt_install \
        build-essential ca-certificates curl wget gnupg git \
        zip unzip apt-transport-https software-properties-common lsb-release
}

install_cli_tools() {
    apt_install jq htop net-tools
}

install_python() {
    apt_install python3 python3-pip python3-venv
}

# The Ubuntu package named `yq` is a different tool, so mikefarah/yq comes from
# GitHub releases.
install_yq() {
    if command_exists yq && yq --version 2>/dev/null | grep -q 'mikefarah'; then
        nothing_to_do "mikefarah/yq is already installed ($(yq --version 2>/dev/null))"
        return
    fi

    apt_install jq
    local version="$YQ_VERSION"
    if [[ -z "$version" ]]; then
        version="$(curl -fsSL --retry 3 https://api.github.com/repos/mikefarah/yq/releases/latest | jq -r '.tag_name')"
    fi
    [[ -n "$version" && "$version" != "null" ]] || die "could not determine the yq version"

    log_info "yq ${version} for ${DEB_ARCH}"
    curl -fL --retry 3 "https://github.com/mikefarah/yq/releases/download/${version}/yq_linux_${DEB_ARCH}" \
        -o "$TMP_DIR/yq"
    sudo install -m 0755 "$TMP_DIR/yq" /usr/local/bin/yq
}

install_git_config() {
    if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" \
        || "$GIT_NAME" == "YOUR_NAME" || "$GIT_EMAIL" == "YOUR_EMAIL" ]]; then
        nothing_to_do "GIT_NAME/GIT_EMAIL are not set in bootstrap.env"
        return
    fi
    apt_install git
    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
    git config --global init.defaultBranch main
    git config --global pull.rebase true
    log_info "git identity: ${GIT_NAME} <${GIT_EMAIL}>"
}

# =============================================================================
# INSTALLS — runtimes
# =============================================================================

# Neither SDKMAN nor its init script is written for `set -eu`, so both are turned
# off around every call into it.
install_java() {
    export SDKMAN_DIR="$HOME/.sdkman"
    apt_install zip unzip curl

    if [[ ! -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
        log_info "installing SDKMAN (rcupdate=false — we manage shell rc ourselves)"
        curl -fsSL "https://get.sdkman.io?rcupdate=false" | bash
    fi
    [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] || die "SDKMAN installation failed"

    # Without this, sdk asks "set as default? (Y/n)" and the script would hang.
    mkdir -p "$SDKMAN_DIR/etc"
    touch "$SDKMAN_DIR/etc/config"
    if grep -q '^sdkman_auto_answer=' "$SDKMAN_DIR/etc/config"; then
        sed -i 's/^sdkman_auto_answer=.*/sdkman_auto_answer=true/' "$SDKMAN_DIR/etc/config"
    else
        printf 'sdkman_auto_answer=true\n' >>"$SDKMAN_DIR/etc/config"
    fi

    set +eu
    # shellcheck disable=SC1091
    source "$SDKMAN_DIR/bin/sdkman-init.sh"
    set -eu

    local identifier="$JAVA_VERSION"
    if [[ -n "$identifier" ]]; then
        if [[ "$identifier" != *.* ]]; then
            log_warn "JAVA_VERSION='${identifier}' has no patch version — SDKMAN identifiers look like 25.0.1-open, so this will most likely fail"
        fi
        log_info "using the pinned identifier '${identifier}'"
    else
        set +e
        local listing
        listing="$(sdk list java 2>/dev/null)"
        set -e

        # Newest matching non-early-access build for the major + vendor.
        identifier="$(printf '%s\n' "$listing" \
            | tr ' |' '\n\n' \
            | grep -E "^${JAVA_MAJOR}(\.[0-9A-Za-z]+)*-${JAVA_VENDOR}\$" \
            | grep -v -e '\.ea\.' -e '-ea' \
            | head -n 1)"

        if [[ -z "$identifier" ]]; then
            log_error "SDKMAN offers no OpenJDK ${JAVA_MAJOR} from vendor '${JAVA_VENDOR}'."
            log_error "Available ${JAVA_MAJOR}.x versions (pick one and set JAVA_VERSION in bootstrap.env):"
            printf '%s\n' "$listing" | grep -E "(^|[ |])${JAVA_MAJOR}\." >&2 || log_error "  none"
            die "OpenJDK ${JAVA_MAJOR} (${JAVA_VENDOR}) is not available in SDKMAN"
        fi
        log_info "OpenJDK ${JAVA_MAJOR} (${JAVA_VENDOR}) resolved to '${identifier}'"
    fi

    if [[ -d "$SDKMAN_DIR/candidates/java/$identifier" ]]; then
        nothing_to_do "OpenJDK ${identifier} is already installed"
        return
    fi

    set +eu
    sdk install java "$identifier" </dev/null
    sdk default java "$identifier" </dev/null
    set -eu

    [[ -d "$SDKMAN_DIR/candidates/java/$identifier" ]] \
        || die "sdk install java ${identifier} failed"
    log_info "OpenJDK ${identifier} installed and set as default"
}

install_node() {
    export NVM_DIR="$HOME/.nvm"

    if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
        local tag="$NVM_VERSION"
        local url="https://raw.githubusercontent.com/nvm-sh/nvm/${tag}/install.sh"

        # If the pinned tag is gone, resolve the current one rather than break
        # on a stale constant.
        if ! curl -fsS --max-time 15 -o /dev/null "$url" 2>/dev/null; then
            log_warn "nvm tag ${tag} is not available, resolving the latest from the GitHub API"
            apt_install jq
            tag="$(curl -fsSL --retry 3 https://api.github.com/repos/nvm-sh/nvm/releases/latest | jq -r '.tag_name')"
            [[ -n "$tag" && "$tag" != "null" ]] || die "could not determine the nvm version"
            url="https://raw.githubusercontent.com/nvm-sh/nvm/${tag}/install.sh"
        fi

        log_info "installing nvm ${tag} (PROFILE=/dev/null — we manage shell rc ourselves)"
        curl -fsSL "$url" | PROFILE=/dev/null bash
    fi
    [[ -s "$NVM_DIR/nvm.sh" ]] || die "nvm installation failed"

    set +eu
    # shellcheck disable=SC1091
    source "$NVM_DIR/nvm.sh"
    set -eu

    log_info "nvm install '${NODE_VERSION}'"
    nvm install "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"
    nvm use default >/dev/null
    log_info "node $(node -v), npm $(npm -v)"
}

# =============================================================================
# INSTALLS — containers, Kubernetes, cloud
# =============================================================================

install_docker() {
    local suite
    suite="$(resolve_apt_suite "https://download.docker.com/linux/ubuntu" \
        "$UBUNTU_CODENAME" "${APT_FALLBACK_SUITES[@]}")" \
        || die "the Docker repo has no suite for ${UBUNTU_CODENAME} nor any fallback"

    add_apt_repo docker "https://download.docker.com/linux/ubuntu/gpg" \
        "deb [arch=${DEB_ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${suite} stable"

    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
    add_to_group docker
}

install_kubectl() {
    local minor="$KUBERNETES_MINOR"
    if [[ -z "$minor" ]]; then
        local stable
        stable="$(curl -fsSL --retry 3 https://dl.k8s.io/release/stable.txt)"
        minor="$(printf '%s' "$stable" | sed -E 's|^v?([0-9]+\.[0-9]+).*|\1|')"
        [[ -n "$minor" ]] || die "could not determine the current Kubernetes minor version"
        log_info "current stable Kubernetes: ${stable} → repo v${minor}"
    fi

    local base="https://pkgs.k8s.io/core:/stable:/v${minor}/deb"
    add_apt_repo kubernetes "${base}/Release.key" \
        "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] ${base}/ /"
    apt_install kubectl
}

install_helm() {
    add_apt_repo helm "https://baltocdn.com/helm/signing.asc" \
        "deb [arch=${DEB_ARCH} signed-by=/etc/apt/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main"
    apt_install helm
}

install_terraform() {
    local suite
    suite="$(resolve_apt_suite "https://apt.releases.hashicorp.com" \
        "$UBUNTU_CODENAME" "${APT_FALLBACK_SUITES[@]}")" \
        || die "the HashiCorp repo has no suite for ${UBUNTU_CODENAME} nor any fallback"

    add_apt_repo hashicorp "https://apt.releases.hashicorp.com/gpg" \
        "deb [arch=${DEB_ARCH} signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${suite} main"
    apt_install terraform
}

install_aws_cli() {
    apt_install unzip
    log_info "AWS CLI v2 for ${UNAME_ARCH}"
    curl -fL --retry 3 --progress-bar \
        "https://awscli.amazonaws.com/awscli-exe-linux-${UNAME_ARCH}.zip" -o "$TMP_DIR/awscliv2.zip"
    unzip -q -o "$TMP_DIR/awscliv2.zip" -d "$TMP_DIR"
    sudo "$TMP_DIR/aws/install" --update   # --update makes this idempotent
}

install_gcloud() {
    add_apt_repo google-cloud-sdk "https://packages.cloud.google.com/apt/doc/apt-key.gpg" \
        "deb [signed-by=/etc/apt/keyrings/google-cloud-sdk.gpg] https://packages.cloud.google.com/apt cloud-sdk main"
    apt_install google-cloud-cli
}

# The official installer installs into $HOME/.claude and refuses to run under
# sudo — hence no sudo here.
install_claude_code() {
    if command_exists claude; then
        nothing_to_do "Claude Code is already installed ($(claude --version 2>/dev/null | head -n1))"
        return
    fi
    log_info "installing Claude Code via the official installer"
    curl -fsSL https://claude.ai/install.sh | bash
}

# =============================================================================
# INSTALLS — browsers and desktop applications
#
# Note on ARM64: Chrome, Slack, Spotify, Zoom, Insomnia and ProtonVPN have no
# official ARM64 Linux builds. By design the install is attempted anyway — a
# failure is logged, listed in the summary, and the run continues.
# =============================================================================

install_brave() {
    add_apt_repo brave-browser \
        "https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg" \
        "deb [arch=${DEB_ARCH} signed-by=/etc/apt/keyrings/brave-browser.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main"
    apt_install brave-browser
}

install_chrome() {
    if deb_installed google-chrome-stable; then
        nothing_to_do "Google Chrome is already installed"
        return
    fi
    if [[ "$DEB_ARCH" != "amd64" ]]; then
        log_warn "Google Chrome for Linux is amd64 only — this will most likely fail on ${DEB_ARCH}"
    fi
    install_deb_url "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" google-chrome
}

install_sublime() {
    add_apt_repo sublimehq "https://download.sublimetext.com/sublimehq-pub.gpg" \
        "deb [signed-by=/etc/apt/keyrings/sublimehq.gpg] https://download.sublimetext.com/ apt/stable/"
    apt_install sublime-text
}

# The official tarball works on both architectures; the snap is amd64 only.
install_intellij() {
    apt_install jq
    local json build url checksum_url
    log_info "resolving the current IntelliJ IDEA Ultimate from the JetBrains API"
    json="$(curl -fsSL --retry 3 \
        "https://data.services.jetbrains.com/products/releases?code=IIU&latest=true&type=release")"
    build="$(printf '%s' "$json" | jq -r '.IIU[0].build // empty')"
    url="$(printf '%s' "$json" | jq -r --arg key "$JB_KEY" '.IIU[0].downloads[$key].link // empty')"
    checksum_url="$(printf '%s' "$json" | jq -r --arg key "$JB_KEY" '.IIU[0].downloads[$key].checksumLink // empty')"

    [[ -n "$build" ]] || die "the JetBrains API returned no build number"
    [[ -n "$url" ]] || die "JetBrains offers no build for ${JB_KEY} (${DEB_ARCH})"

    local target="/opt/intellij-idea-${build}"
    if [[ -d "$target" ]]; then
        nothing_to_do "IntelliJ IDEA build ${build} is already in ${target}"
        return
    fi

    local archive="$TMP_DIR/intellij-idea-${build}.tar.gz"
    log_info "downloading IntelliJ IDEA Ultimate build ${build} (${JB_KEY})"
    curl -fL --retry 3 --progress-bar "$url" -o "$archive"

    if [[ -n "$checksum_url" ]]; then
        local expected
        expected="$(curl -fsSL --retry 3 "$checksum_url" | awk 'NR==1 {print $1}')"
        if [[ -n "$expected" ]]; then
            log_info "verifying sha256"
            printf '%s  %s\n' "$expected" "$archive" | sha256sum -c -
        else
            log_warn "could not read the checksum, continuing without verification"
        fi
    fi

    log_info "extracting into ${target}"
    sudo mkdir -p "$target"
    sudo tar -xzf "$archive" -C "$target" --strip-components=1

    # A stable, build-independent path for the launcher and the .desktop entry.
    sudo ln -sfn "$target" /opt/intellij-idea-ultimate

    local launcher="/opt/intellij-idea-ultimate/bin/idea"
    if [[ ! -x "$launcher" && -x "/opt/intellij-idea-ultimate/bin/idea.sh" ]]; then
        launcher="/opt/intellij-idea-ultimate/bin/idea.sh"
    fi
    sudo ln -sfn "$launcher" /usr/local/bin/idea

    local icon="/opt/intellij-idea-ultimate/bin/idea.svg"
    if [[ ! -f "$icon" ]]; then
        icon="/opt/intellij-idea-ultimate/bin/idea.png"
    fi

    log_info "creating the .desktop entry"
    sudo tee /usr/share/applications/intellij-idea-ultimate.desktop >/dev/null <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=IntelliJ IDEA Ultimate
Comment=Capable and Ergonomic IDE for JVM
Icon=${icon}
Exec="${launcher}" %f
Terminal=false
Categories=Development;IDE;
StartupWMClass=jetbrains-idea
DESKTOP
}

install_lens() {
    add_apt_repo lens "https://downloads.k8slens.dev/keys/gpg" \
        "deb [arch=${DEB_ARCH} signed-by=/etc/apt/keyrings/lens.gpg] https://downloads.k8slens.dev/apt/debian stable main"
    apt_install lens
}

install_mongodb_compass() {
    if deb_installed mongodb-compass; then
        nothing_to_do "MongoDB Compass is already installed"
        return
    fi
    apt_install jq
    local version="$MONGODB_COMPASS_VERSION"
    if [[ -z "$version" ]]; then
        version="$(curl -fsSL --retry 3 https://api.github.com/repos/mongodb-js/compass/releases/latest \
            | jq -r '.tag_name' | sed -E 's/^v//')"
    fi
    [[ -n "$version" && "$version" != "null" ]] || die "could not determine the MongoDB Compass version"
    install_deb_url "https://downloads.mongodb.com/compass/mongodb-compass_${version}_${DEB_ARCH}.deb" \
        mongodb-compass
}

# Slack's .deb URL embeds a version that cannot be resolved reliably, so snap is
# the only route that avoids guessing it. There is no arm64 Slack snap.
install_slack() {
    snap_install slack
}

# Spotify's apt repo key filename embeds a fingerprint that gets rotated and
# silently breaks apt — snap is the more durable choice.
install_spotify() {
    snap_install spotify
}

install_vlc() {
    apt_install vlc
}

install_zoom() {
    if deb_installed zoom; then
        nothing_to_do "Zoom is already installed"
        return
    fi
    if [[ "$DEB_ARCH" != "amd64" ]]; then
        log_warn "Zoom publishes no official ARM64 .deb — this will most likely fail on ${DEB_ARCH}"
    fi
    install_deb_url "https://zoom.us/client/latest/zoom_${DEB_ARCH}.deb" zoom
}

install_insomnia() {
    if deb_installed insomnia; then
        nothing_to_do "Insomnia is already installed"
        return
    fi
    if [[ "$DEB_ARCH" != "amd64" ]]; then
        log_warn "the Insomnia .deb is amd64 only — this will most likely fail on ${DEB_ARCH}"
    fi
    install_deb_url \
        "https://updates.insomnia.rest/downloads/ubuntu/latest?app=com.insomnia.app&channel=stable" \
        insomnia
}

install_deluge() {
    apt_install deluge
}

install_protonvpn() {
    if deb_installed proton-vpn-gnome-desktop; then
        nothing_to_do "ProtonVPN is already installed"
        return
    fi
    if [[ "$DEB_ARCH" != "amd64" ]]; then
        log_warn "ProtonVPN publishes no official ARM64 packages — this will most likely fail on ${DEB_ARCH}"
    fi

    local deb_url="$PROTONVPN_RELEASE_DEB"
    if [[ -z "$deb_url" ]]; then
        # Newest release package from the repo index, so no hardcoded version.
        local base="https://repo.protonvpn.com/debian/dists/stable/main/binary-all"
        local newest
        newest="$(curl -fsSL --retry 3 "${base}/" 2>/dev/null \
            | grep -o 'protonvpn-stable-release_[0-9.]*_all\.deb' \
            | sort -V | tail -n 1)"
        [[ -n "$newest" ]] || die "could not find a protonvpn-stable-release .deb in ${base}/"
        deb_url="${base}/${newest}"
    fi

    install_deb_url "$deb_url" protonvpn-stable-release
    rm -f "$TMP_DIR/.apt-updated"   # the release package adds Proton's own repo
    apt_install proton-vpn-gnome-desktop
}

install_nordvpn() {
    if command_exists nordvpn; then
        nothing_to_do "NordVPN is already installed"
        return
    fi
    log_info "installing NordVPN via the official installer"
    curl -fsSL --retry 3 https://downloads.nordcdn.com/apps/linux/install.sh -o "$TMP_DIR/nordvpn.sh"
    sudo sh "$TMP_DIR/nordvpn.sh" -n
    add_to_group nordvpn
}

# =============================================================================
# INSTALLS — shell configuration
# =============================================================================

install_shell_config() {
    local rc="$HOME/.bashrc"
    local begin="# >>> ubuntu-bootstrap >>>"
    local end="# <<< ubuntu-bootstrap <<<"

    touch "$rc"

    # Drop any existing block and append a fresh one, so a re-run replaces
    # rather than duplicates.
    if grep -qF "$begin" "$rc"; then
        log_info "updating the existing ubuntu-bootstrap block in ${rc}"
        awk -v b="$begin" -v e="$end" '
            $0 == b { skip = 1 }
            skip != 1 { print }
            $0 == e { skip = 0 }
        ' "$rc" >"$TMP_DIR/bashrc"
        cat "$TMP_DIR/bashrc" >"$rc"
    else
        log_info "adding the ubuntu-bootstrap block to ${rc}"
    fi

    {
        printf '%s\n' "$begin"
        cat <<'RCBLOCK'
# Managed by bootstrap.sh — manual edits here are overwritten on the next run.

export PATH="$HOME/.local/bin:$PATH"

alias k='kubectl'
alias g='git'
alias t='terraform'

if command -v kubectl >/dev/null 2>&1; then
    source <(kubectl completion bash)
    complete -o default -F __start_kubectl k
fi

if command -v helm >/dev/null 2>&1; then
    source <(helm completion bash)
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

export SDKMAN_DIR="$HOME/.sdkman"
[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && . "$SDKMAN_DIR/bin/sdkman-init.sh"
RCBLOCK
        printf '%s\n' "$end"
    } >>"$rc"

    log_info "k/g/t aliases, kubectl+helm completion, nvm and SDKMAN init"
}

# =============================================================================
# SUMMARY
# =============================================================================

version_of() {
    local label="$1"
    shift
    local out=""
    if command_exists "$1"; then
        out="$( "$@" 2>&1 | head -n 1 || true )"
    fi
    printf '  %-18s %s\n' "$label" "${out:-—}" >&2
}

summary() {
    SUMMARY_PRINTED=true

    # java/node are not on this shell's PATH until SDKMAN/nvm are sourced.
    set +eu
    if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
        export SDKMAN_DIR="$HOME/.sdkman"
        # shellcheck disable=SC1091
        source "$HOME/.sdkman/bin/sdkman-init.sh"
    fi
    if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
        export NVM_DIR="$HOME/.nvm"
        # shellcheck disable=SC1091
        source "$HOME/.nvm/nvm.sh"
    fi
    export PATH="$HOME/.local/bin:$PATH"
    set -eu

    printf '\n%s======================== SUMMARY ========================%s\n' "$C_BOLD" "$C_RESET" >&2
    printf '\n%sInstalled tool versions%s\n' "$C_BOLD" "$C_RESET" >&2

    version_of "java"       java -version
    version_of "node"       node -v
    version_of "npm"        npm -v
    version_of "python3"    python3 --version
    version_of "docker"     docker --version
    version_of "compose"    docker compose version
    version_of "kubectl"    kubectl version --client
    version_of "helm"       helm version --short
    version_of "terraform"  terraform version
    version_of "aws"        aws --version
    version_of "gcloud"     gcloud --version
    version_of "claude"     claude --version
    version_of "git"        git --version
    version_of "jq"         jq --version
    version_of "yq"         yq --version
    version_of "brave"      brave-browser --version
    version_of "chrome"     google-chrome --version
    version_of "subl"       subl --version
    version_of "vlc"        vlc --version
    version_of "deluge"     deluge --version

    # IntelliJ has no cheap --version (the launcher would start the IDE), so
    # report the build the stable symlink points at.
    local idea="—"
    if [[ -L /opt/intellij-idea-ultimate ]]; then
        idea="$(basename "$(readlink -f /opt/intellij-idea-ultimate)")"
    fi
    printf '  %-18s %s\n' "intellij" "$idea" >&2

    local entry
    if [[ ${#OK_STEPS[@]} -gt 0 ]]; then
        printf '\n%sOK (%d)%s\n' "$C_GREEN" "${#OK_STEPS[@]}" "$C_RESET" >&2
        for entry in "${OK_STEPS[@]}"; do printf '  %s\n' "$entry" >&2; done
    fi
    if [[ ${#SKIPPED_STEPS[@]} -gt 0 ]]; then
        printf '\n%sSKIPPED (%d)%s\n' "$C_BLUE" "${#SKIPPED_STEPS[@]}" "$C_RESET" >&2
        for entry in "${SKIPPED_STEPS[@]}"; do printf '  %s\n' "$entry" >&2; done
    fi
    if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
        printf '\n%sFAILED (%d)%s\n' "$C_RED" "${#FAILED_STEPS[@]}" "$C_RESET" >&2
        for entry in "${FAILED_STEPS[@]}"; do printf '  %s\n' "$entry" >&2; done
        printf '\n  Details are in the log. Fix the cause and re-run ./bootstrap.sh —\n' >&2
        printf '  everything already installed is skipped.\n' >&2
        if [[ "$DEB_ARCH" == "arm64" ]]; then
            printf '  Note: Chrome, Slack, Spotify, Zoom, Insomnia and ProtonVPN have\n' >&2
            printf '        no official ARM64 Linux builds.\n' >&2
        fi
    fi

    if [[ -n "$TMP_DIR" && -f "$TMP_DIR/.needs-relogin" ]]; then
        printf '\n%s[WARN ]%s Log out and back in (or reboot) — new group memberships only\n' \
            "$C_YELLOW" "$C_RESET" >&2
        printf '        take effect in a new session (docker without sudo).\n' >&2
    fi

    printf '\n  Log:       %s\n' "$LOG_FILE" >&2
    printf '  New shell: exec bash -l\n' >&2
    printf '%s=========================================================%s\n\n' "$C_BOLD" "$C_RESET" >&2
}

# =============================================================================
# MAIN — the install order
# =============================================================================

main() {
    setup_colors

    if [[ $# -gt 0 ]]; then
        die "this script takes no arguments; configure it via bootstrap.env (see bootstrap.env.example)"
    fi

    # Captures apt/curl output too. Colors land in the log as ANSI sequences —
    # read it with `less -R`.
    touch "$LOG_FILE" || die "cannot write to the log file ${LOG_FILE}"
    exec > >(tee -a "$LOG_FILE") 2>&1

    printf '%sUbuntu developer bootstrap — %s%s\n' \
        "$C_BOLD" "$(date '+%Y-%m-%d %H:%M:%S')" "$C_RESET" >&2

    preflight

    run "$INSTALL_BASE"             base             install_base
    run "$INSTALL_CLI_TOOLS"        cli-tools        install_cli_tools
    run "$INSTALL_PYTHON"           python           install_python
    run "$INSTALL_YQ"               yq               install_yq
    run "$INSTALL_GIT_CONFIG"       git-config       install_git_config

    run "$INSTALL_JAVA"             java             install_java
    run "$INSTALL_NODE"             node             install_node

    run "$INSTALL_DOCKER"           docker           install_docker
    run "$INSTALL_KUBECTL"          kubectl          install_kubectl
    run "$INSTALL_HELM"             helm             install_helm
    run "$INSTALL_TERRAFORM"        terraform        install_terraform
    run "$INSTALL_AWS_CLI"          aws-cli          install_aws_cli
    run "$INSTALL_GCLOUD"           gcloud           install_gcloud
    run "$INSTALL_CLAUDE_CODE"      claude-code      install_claude_code

    run "$INSTALL_BRAVE"            brave            install_brave
    run "$INSTALL_CHROME"           chrome           install_chrome
    run "$INSTALL_SUBLIME"          sublime          install_sublime
    run "$INSTALL_INTELLIJ"         intellij         install_intellij
    run "$INSTALL_LENS"             lens             install_lens
    run "$INSTALL_MONGODB_COMPASS"  mongodb-compass  install_mongodb_compass
    run "$INSTALL_SLACK"            slack            install_slack
    run "$INSTALL_SPOTIFY"          spotify          install_spotify
    run "$INSTALL_VLC"              vlc              install_vlc
    run "$INSTALL_ZOOM"             zoom             install_zoom
    run "$INSTALL_INSOMNIA"         insomnia         install_insomnia
    run "$INSTALL_DELUGE"           deluge           install_deluge
    run "$INSTALL_PROTONVPN"        protonvpn        install_protonvpn
    run "$INSTALL_NORDVPN"          nordvpn          install_nordvpn

    run "$INSTALL_SHELL_CONFIG"     shell-config     install_shell_config

    summary

    if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
        log_error "finished with ${#FAILED_STEPS[@]} failed step(s)"
        exit 1
    fi
    log_ok "all done"
}

main "$@"
