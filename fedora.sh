#!/usr/bin/env bash

set -euo pipefail

#######################################
# Fedora Bootstrap
#
# Supported:
# - Fedora Workstation 45 (GNOME), aarch64
# - Fedora Workstation 45 (GNOME), x86_64
#######################################


#######################################
# DEVELOPMENT VERSIONS
#######################################

# sdkman java version, empty = skip installation
JAVA_VERSION="25.0.2.0+10-open"

# Empty = skip installation
NODE_VERSION="lts/*"


#######################################
# FEATURE FLAGS
#######################################

INSTALL_RPMFUSION=true
INSTALL_HARDWARE_ENABLEMENT=true
CONFIGURE_FIREWALLD=true
DOCKER_BIND_LOOPBACK=true
INSTALL_AWS_CLI=true
INSTALL_TERRAFORM=true
INSTALL_GCLOUD=true
INSTALL_CLAUDE_CODE=true
INSTALL_NONO=true
REMOVE_FIREFOX=true
REMOVE_TELEMETRY=true
INSTALL_LENS=true
INSTALL_MONGODB_COMPASS=true
INSTALL_INSOMNIA=true
INSTALL_DELUGE=true
INSTALL_VLC=true
INSTALL_PROTONVPN=true


#######################################
# GLOBAL VARIABLES
#######################################

ARCH=$(uname -m)

CPU_VENDOR=$(awk -F': ' '/^vendor_id/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || true)

LOG_FILE="$HOME/fedora.log"


#######################################
# HELPERS
#######################################

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$LOG_FILE"
}


command_exists() {
    command -v "$1" >/dev/null 2>&1
}

append_if_missing() {
    local LINE="$1"
    local FILE="$2"
    grep -qxF "$LINE" "$FILE" || echo "$LINE" >> "$FILE"
}

rpm_installed() {
    rpm -q "$1" >/dev/null 2>&1
}

dnf_install() {
    local PACKAGE="$1"

    if ! rpm_installed "$PACKAGE"; then
        sudo dnf install -y "$PACKAGE"
    else
        log "$PACKAGE already installed"
    fi
}

dnf_remove() {
    local PACKAGE="$1"

    if rpm_installed "$PACKAGE"; then
        sudo dnf remove -y "$PACKAGE"
    else
        log "$PACKAGE not installed"
    fi
}

add_repo() {
    local ID="$1"
    local BASEURL="$2"
    local GPGKEY="${3:-}"

    {
        echo "[$ID]"
        echo "name=$ID"
        echo "baseurl=$BASEURL"
        echo "enabled=1"

        if [ -n "$GPGKEY" ]; then
            echo "gpgcheck=1"
            echo "gpgkey=$GPGKEY"
        else
            echo "gpgcheck=0"
        fi
    } | sudo tee "/etc/yum.repos.d/${ID}.repo"
}

#######################################
# SYSTEM CHECK
#######################################

DISTRO_ID=$(. /etc/os-release && echo "$ID")

if [ "$DISTRO_ID" != "fedora" ]; then

    log "This script is for Fedora — detected: $DISTRO_ID"

    exit 1

fi


FEDORA_VERSION=$(rpm -E %fedora)

log "Detected Fedora $FEDORA_VERSION, architecture: $ARCH"

case "$ARCH" in

    aarch64)
        log "Running aarch64 setup"
        KUBECTL_ARCH="arm64"
        TOOLBOX_SUFFIX="-arm64"
        ;;

    x86_64)
        log "Running x86_64 setup — CPU vendor: ${CPU_VENDOR:-unknown}"
        KUBECTL_ARCH="amd64"
        TOOLBOX_SUFFIX=""
        ;;

    *)
        log "Unsupported architecture: $ARCH"
        exit 1
        ;;

esac


#######################################
# SYSTEM UPDATE
#######################################

log "Updating system"

sudo dnf upgrade --refresh -y


#######################################
# BASE PACKAGES
#######################################

log "Installing base packages"


sudo dnf install -y \
    curl \
    wget \
    valkey-compat-redis \
    unzip \
    zip \
    gcc \
    gcc-c++ \
    make \
    ca-certificates \
    openssl \
    gnupg2 \
    xdg-utils \
    dnf5-plugins


#######################################
# RPM FUSION
#######################################

if [ "$INSTALL_RPMFUSION" = true ]; then

log "Enabling RPM Fusion free"


if ! rpm_installed rpmfusion-free-release; then

    sudo dnf install -y distribution-gpg-keys

    sudo rpmkeys --import \
    "/usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-free-fedora-${FEDORA_VERSION}"

    sudo dnf install -y --setopt=localpkg_gpgcheck=1 \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm"

else

    log "RPM Fusion free already enabled"

fi


dnf_install libavcodec-freeworld

fi


#######################################
# HARDWARE ENABLEMENT
#######################################

if [ "$INSTALL_HARDWARE_ENABLEMENT" = true ]; then

log "Configuring hardware enablement"


if [ "$ARCH" != "x86_64" ]; then

    log "Hardware enablement is x86-64 only — skipping on ${ARCH}"

elif systemd-detect-virt --quiet; then

    log "Virtualised guest ($(systemd-detect-virt)) — skipping hardware enablement"

else

    log "Firmware and microcode status:"

    rpm -q microcode_ctl amd-ucode-firmware linux-firmware alsa-sof-firmware 2>&1 \
    | tee -a "$LOG_FILE" || true


    HW_PACKAGES=(
        libva-utils
        lm_sensors
    )

    case "$CPU_VENDOR" in

        GenuineIntel)
            log "Intel CPU detected — adding Intel VA-API"
            HW_PACKAGES+=(
                libva-intel-media-driver
            )
            if [ "$INSTALL_RPMFUSION" = true ]; then
                HW_PACKAGES+=(
                    libva-intel-driver
                )
            fi
            ;;

        AuthenticAMD)
            if [ "$INSTALL_RPMFUSION" = true ]; then
                log "AMD CPU detected — adding AMD VA-API"
                HW_PACKAGES+=(
                    mesa-va-drivers-freeworld
                )
            else
                log "AMD CPU detected — RPM Fusion is off, so VA-API stays without H.264 and H.265"
            fi
            ;;

        *)
            log "Unrecognised CPU vendor '${CPU_VENDOR:-unknown}' — installing the vendor-neutral set only"
            ;;

    esac


    sudo dnf install -y "${HW_PACKAGES[@]}"


    if rpm_installed tlp; then

        log "WARNING: tlp is installed and conflicts with tuned — GNOME's power mode selector will be missing"

    elif systemctl is-active --quiet tuned-ppd || systemctl is-active --quiet power-profiles-daemon; then

        log "Power profiles service is active"

    else

        log "WARNING: neither tuned-ppd nor power-profiles-daemon is active — GNOME power profiles unavailable"

    fi

fi

fi


#######################################
# FIREWALL
#######################################

if [ "$CONFIGURE_FIREWALLD" = true ]; then

log "Configuring firewall"

dnf_install firewalld

sudo systemctl enable --now firewalld

sudo firewall-cmd --set-default-zone=public
sudo firewall-cmd --permanent --zone=public --remove-service=ssh
sudo firewall-cmd --reload
sudo firewall-cmd --list-all

fi


#######################################
# SHELL CONFIG
#######################################

log "Adding shell config"

append_if_missing \
'export PATH="$HOME/.local/bin:$PATH"' \
"$HOME/.bashrc"

export PATH="$HOME/.local/bin:$PATH"

append_if_missing \
"alias k='kubectl'" \
"$HOME/.bashrc"

append_if_missing \
"alias g='gcloud'" \
"$HOME/.bashrc"

append_if_missing \
"alias t='terraform'" \
"$HOME/.bashrc"

append_if_missing \
"alias nonoclaude='nono run --allow-cwd  --read ~/.sdkman --read ~/.npm --read ~/.gradle --write ~/.gradle --read ~/.m2  --read ~/.embedmongo --profile claude-code -- claude'" \
"$HOME/.bashrc"

#######################################
# NVM + NODE
#######################################

log "Installing NVM"

if [ ! -d "$HOME/.nvm" ]; then

    curl -f -o- \
    https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh \
    | bash

fi


export NVM_DIR="$HOME/.nvm"

source "$NVM_DIR/nvm.sh"


if [ -n "$NODE_VERSION" ]; then

    log "Installing Node $NODE_VERSION"


    if ! nvm list | grep -q "$NODE_VERSION"; then
        nvm install "$NODE_VERSION"
    fi


    nvm alias default "$NODE_VERSION"

fi



#######################################
# SDKMAN + OPENJDK
#######################################

log "Installing SDKMAN"


if [ ! -d "$HOME/.sdkman" ]; then

    curl -fs \
    https://get.sdkman.io \
    | bash

fi


export SDKMAN_DIR="$HOME/.sdkman"


set +euo pipefail

source "$SDKMAN_DIR/bin/sdkman-init.sh"



if [ -n "$JAVA_VERSION" ]; then


    log "Installing Java $JAVA_VERSION"


    if ! sdk list java | grep -q "$JAVA_VERSION"; then

        log "Java version not available:"
        sdk list java
        exit 1

    fi


    if ! sdk list java | grep installed | grep -q "$JAVA_VERSION"; then

        sdk install java "$JAVA_VERSION"

    fi


    sdk default java "$JAVA_VERSION"


    java -version

fi


set -euo pipefail


if [ -n "$JAVA_VERSION" ] && ! command_exists java; then

    log "Java $JAVA_VERSION installation failed"

    exit 1

fi


#######################################
# DOCKER
#######################################

log "Installing Docker"


if ! command_exists docker; then

    curl -fsSL https://get.docker.com | sh

else

    log "Docker already installed"

fi


sudo systemctl enable --now docker


if ! groups "$USER" | grep -q docker; then

    sudo usermod -aG docker "$USER"

fi


dnf_install docker-compose-plugin


if [ "$DOCKER_BIND_LOOPBACK" = true ]; then

if [ ! -f /etc/docker/daemon.json ]; then

sudo install -m 0755 -d /etc/docker
printf '{\n  "ip": "127.0.0.1"\n}\n' | sudo tee /etc/docker/daemon.json >/dev/null
sudo systemctl restart docker

else

log "/etc/docker/daemon.json already exists — leaving it alone"

fi

fi



#######################################
# KUBECTL
#######################################

log "Installing kubectl"


if ! command_exists kubectl; then


    KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt) || true


    if [ -z "$KUBECTL_VERSION" ]; then

        log "Could not resolve the stable kubectl version — skipping"

    else


        curl -fLO \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl"


        sudo install \
            -o root \
            -g root \
            -m 0755 \
            kubectl \
            /usr/local/bin/kubectl


        rm kubectl


    fi


else

    log "kubectl already installed"

fi



#######################################
# HELM
#######################################

log "Installing Helm"


if ! command_exists helm; then

    curl -f https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    | bash

else

    log "Helm already installed"

fi



#######################################
# AWS CLI
#######################################

if [ "$INSTALL_AWS_CLI" = true ]; then


log "Installing AWS CLI"


if ! command_exists aws; then


    curl \
    "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" \
    -o awscliv2.zip


    unzip awscliv2.zip


    sudo ./aws/install


    rm -rf aws awscliv2.zip


else

    log "AWS CLI already installed"

fi

fi



#######################################
# TERRAFORM
#######################################

if [ "$INSTALL_TERRAFORM" = true ]; then


log "Installing Terraform"


if ! command_exists terraform; then


    add_repo hashicorp \
    'https://rpm.releases.hashicorp.com/RHEL/10/$basearch/stable' \
    https://rpm.releases.hashicorp.com/gpg


    sudo dnf install -y terraform


else

    log "Terraform already installed"

fi

fi

#######################################
# GOOGLE CLOUD SDK
#######################################

if [ "$INSTALL_GCLOUD" = true ]; then


log "Installing Google Cloud SDK"


if ! command_exists gcloud; then


    add_repo google-cloud-cli \
    'https://packages.cloud.google.com/yum/repos/cloud-sdk-el10-$basearch' \
    https://packages.cloud.google.com/yum/doc/rpm-package-key-v10.gpg


    sudo dnf install -y google-cloud-cli


else

    log "gcloud already installed"

fi

fi

#######################################
# CLAUDE CODE
#######################################

if [ "$INSTALL_CLAUDE_CODE" = true ]; then


log "Installing Claude Code"


if ! command_exists claude; then


    curl -fsSL \
    https://claude.ai/install.sh \
    | bash


else

    log "Claude Code already installed"

fi

fi

#######################################
# NONO
#######################################

if [ "$INSTALL_NONO" = true ]; then

log "Installing nono"

if ! command_exists nono; then

    NONO_TAG_URL=$(curl -sIL -o /dev/null -w '%{url_effective}' \
    https://github.com/nolabs-ai/nono/releases/latest) || true

    NONO_VERSION="${NONO_TAG_URL##*/v}"


    if [ -z "$NONO_VERSION" ] || [ "$NONO_VERSION" = "$NONO_TAG_URL" ]; then

        log "Could not resolve the latest nono version — skipping"

    else

        sudo dnf install -y \
        "https://github.com/nolabs-ai/nono/releases/download/v${NONO_VERSION}/nono-cli-${NONO_VERSION}-1.${ARCH}.rpm"

    fi


else

    log "nono already installed"

fi

fi

#######################################
# BRAVE BROWSER
#######################################

log "Installing Brave Browser"


if ! command_exists brave-browser; then


    add_repo brave-browser \
    'https://brave-browser-rpm-release.s3.brave.com/$basearch' \
    https://brave-browser-rpm-release.s3.brave.com/brave-core.asc


    sudo dnf install -y brave-browser


else

    log "Brave already installed"

fi


xdg-settings set default-web-browser brave-browser.desktop \
|| log "Could not set Brave as the default browser"



#######################################
# FIREFOX
#######################################

if [ "$REMOVE_FIREFOX" = true ]; then


log "Removing Firefox"


dnf_remove firefox


fi



#######################################
# TELEMETRY
#######################################

if [ "$REMOVE_TELEMETRY" = true ]; then

log "Disabling DNF count-me"

sudo dnf config-manager setopt "*.countme=0"

fi


#######################################
# GNOME APPS
#######################################

log "Removing GNOME apps"

dnf_remove gnome-tour
dnf_remove gnome-maps
dnf_remove gnome-calendar
dnf_remove gnome-contacts
dnf_remove showtime


#######################################
# JETBRAINS TOOLBOX
#######################################

log "Installing JetBrains Toolbox"


if ! command_exists jetbrains-toolbox; then


    sudo dnf install -y \
    libXi \
    libXrender \
    libXtst \
    glx-utils \
    fontconfig \
    gtk3 \
    xcb-util-keysyms


    TOOLBOX_URL=$(curl -fsSL \
    "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" \
    | grep -o "https://download\.jetbrains\.com/toolbox/jetbrains-toolbox-[0-9.]*${TOOLBOX_SUFFIX}\.tar\.gz" \
    | head -1) || true


    if [ -z "$TOOLBOX_URL" ]; then

        log "Could not resolve a JetBrains Toolbox download URL — skipping"

    else


        TOOLBOX_TAR=$(basename "$TOOLBOX_URL")


        wget "$TOOLBOX_URL" -O "$TOOLBOX_TAR"


        curl -fsSL "${TOOLBOX_URL}.sha256" | sha256sum --check -


        sudo rm -rf /opt/jetbrains-toolbox
        sudo install -m 0755 -d /opt/jetbrains-toolbox

        sudo tar -xzf "$TOOLBOX_TAR" \
        -C /opt/jetbrains-toolbox \
        --strip-components=1

        sudo ln -sf \
        /opt/jetbrains-toolbox/bin/jetbrains-toolbox \
        /usr/local/bin/jetbrains-toolbox


        rm -f "$TOOLBOX_TAR"


    fi


else

    log "JetBrains Toolbox already installed"

fi


log "Run jetbrains-toolbox and sign in to install IDEA Ultimate"



#######################################
# SUBLIME TEXT
#######################################

log "Installing Sublime Text"


if ! command_exists subl; then


    add_repo sublime-text \
    'https://download.sublimetext.com/rpm/stable/$basearch' \
    https://download.sublimetext.com/sublimehq-pub.gpg


    sudo dnf install -y sublime-text


else

    log "Sublime already installed"

fi



#######################################
# SLACK
#######################################

log "Installing Slack"


if [ "$ARCH" != "x86_64" ]; then

    log "Slack has no ${ARCH} build — skipping"

elif ! command_exists slack; then


    add_repo slack \
    'https://packagecloud.io/slacktechnologies/slack/fedora/21/$basearch'


    sudo dnf install -y slack


else

    log "Slack already installed"

fi



#######################################
# LENS
#######################################

if [ "$INSTALL_LENS" = true ]; then


log "Installing Lens"


if [ "$ARCH" != "x86_64" ]; then

    log "Lens has no ${ARCH} build — skipping"

elif ! rpm_installed lens; then


    add_repo lens \
    https://downloads.k8slens.dev/rpm/packages \
    https://downloads.k8slens.dev/keys/gpg


    sudo dnf install -y lens


else

    log "Lens already installed"

fi

fi



#######################################
# MONGODB COMPASS
#######################################

if [ "$INSTALL_MONGODB_COMPASS" = true ]; then


log "Installing MongoDB Compass"


if [ "$ARCH" != "x86_64" ]; then

    log "MongoDB Compass has no ${ARCH} build — skipping"

elif ! command_exists mongodb-compass; then


    MONGO_URL=$(curl -s https://s3.amazonaws.com/info-mongodb-com/com-download-center/compass.json \
    | grep -o 'https://downloads\.mongodb\.com/compass/mongodb-compass-[0-9.]*\.x86_64\.rpm' \
    | head -1) || true


    if [ -z "$MONGO_URL" ]; then

        log "Could not resolve a MongoDB Compass download URL — skipping"

    else

        sudo dnf install -y "$MONGO_URL"

    fi


else

    log "MongoDB Compass already installed"

fi

fi



#######################################
# INSOMNIA
#######################################

if [ "$INSTALL_INSOMNIA" = true ]; then


log "Installing Insomnia"


if [ "$ARCH" != "x86_64" ]; then

    log "Insomnia has no ${ARCH} build — skipping"

elif ! rpm_installed insomnia; then


    INSOMNIA_VERSION=$(curl -sIL -o /dev/null -w '%{url_effective}' \
    https://github.com/Kong/insomnia/releases/latest \
    | sed -E -n 's#.*/core(@|%40)([0-9.]+)$#\2#p') || true


    if [ -z "$INSOMNIA_VERSION" ]; then

        log "Could not resolve the latest Insomnia version — skipping"

    else

        sudo dnf install -y \
        "https://github.com/Kong/insomnia/releases/download/core@${INSOMNIA_VERSION}/Insomnia.Core-${INSOMNIA_VERSION}.rpm"

    fi


else

    log "Insomnia already installed"

fi

fi



#######################################
# DELUGE
#######################################

if [ "$INSTALL_DELUGE" = true ]; then


log "Installing Deluge"


dnf_install deluge-gtk


fi



#######################################
# VLC
#######################################

if [ "$INSTALL_VLC" = true ]; then


log "Installing VLC"

dnf_install vlc


fi



#######################################
# PROTON VPN
#######################################

if [ "$INSTALL_PROTONVPN" = true ]; then


log "Installing Proton VPN"


if ! rpm_installed proton-vpn-gnome-desktop; then


    add_repo protonvpn-fedora-stable \
    'https://repo.protonvpn.com/fedora-$releasever-stable' \
    'https://repo.protonvpn.com/fedora-$releasever-stable/public_key.asc'


    sudo dnf install -y proton-vpn-gnome-desktop


else

    log "Proton VPN already installed"

fi


dnf_install libappindicator-gtk3
dnf_install gnome-shell-extension-appindicator
dnf_install gnome-extensions-app


fi



#######################################
# FINAL CHECKS
#######################################

log "Running final checks"


echo ""
echo "======================================"
echo " Installed versions"
echo "======================================"
echo ""


command_exists java && java -version || true

command_exists node && node -v || true

command_exists npm && npm -v || true

command_exists docker && docker --version || true

command_exists kubectl && kubectl version --client || true

command_exists helm && helm version || true

command_exists terraform && terraform version || true

command_exists aws && aws --version || true

command_exists gcloud && gcloud --version || true

command_exists claude && claude --version || true

command_exists redis-cli && redis-cli --version || true

command_exists vainfo && vainfo 2>/dev/null | grep -i 'driver version' || true

command_exists sensors && sensors || true


echo ""
echo "======================================"
echo " Bootstrap completed"
echo "======================================"
echo ""

echo "IMPORTANT:"
echo "- Run jetbrains-toolbox and sign in to install IDEA Ultimate"
echo "- Logout/login for Docker permissions"
echo "- Restart if the system update brought a new kernel, firmware or microcode"
echo "- Review $LOG_FILE if something failed"
echo ""
