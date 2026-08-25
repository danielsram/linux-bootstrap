#!/usr/bin/env bash

set -euo pipefail

#######################################
# Debian Bootstrap
#
# Supported:
# - Debian 13 (trixie) with GNOME, ARM64
# - Debian 13 (trixie) with GNOME, AMD64
#######################################


#######################################
# DEVELOPMENT VERSIONS
#######################################

# sdkman java version, empty = skip installation
JAVA_VERSION="25.0.2-open"

# Empty = skip installation
NODE_VERSION="lts/*"


#######################################
# FEATURE FLAGS
#######################################

INSTALL_UFW=true
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

ARCH=$(dpkg --print-architecture)

LOG_FILE="$HOME/debian.log"


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

apt_install() {
    local PACKAGE="$1"

    if ! dpkg -s "$PACKAGE" >/dev/null 2>&1; then
        sudo apt install -y "$PACKAGE"
    else
        log "$PACKAGE already installed"
    fi
}

apt_purge() {
    local PACKAGE="$1"

    if dpkg -s "$PACKAGE" >/dev/null 2>&1; then
        sudo apt purge -y "$PACKAGE"
    else
        log "$PACKAGE not installed"
    fi
}

#######################################
# SYSTEM CHECK
#######################################

DISTRO_ID=$(. /etc/os-release && echo "$ID")

if [ "$DISTRO_ID" != "debian" ]; then

    log "This script is for Debian — detected: $DISTRO_ID"

    exit 1

fi


log "Detected architecture: $ARCH"

case "$ARCH" in

    arm64)
        log "Running ARM64 setup"
        ;;

    amd64)
        log "Running AMD64 setup"
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

sudo apt update
sudo apt upgrade -y


#######################################
# BASE PACKAGES
#######################################

log "Installing base packages"


sudo apt install -y \
    curl \
    wget \
    redis-tools \
    unzip \
    zip \
    build-essential \
    ca-certificates \
    gnupg \
    apt-transport-https \
    lsb-release \
    xdg-utils \
    libavcodec-extra


#######################################
# FIREWALL
#######################################

if [ "$INSTALL_UFW" = true ]; then

log "Configuring firewall"

apt_install ufw

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw logging low
# --force skips the interactive "may disrupt existing ssh connections" prompt
sudo ufw --force enable
sudo ufw status verbose

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
"alias nonoclaude='nono run --allow-cwd  --read ~/.sdkman --read ~/.npm --read ~/.gradle --write ~/.gradle --read ~/.m2 --profile claude-code -- claude'" \
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


# SDKMAN is not written for `set -euo pipefail`: sdkman-init.sh reads unset
# variables (ZSH_DISABLE_COMPFIX, SDKMAN_ENV, SDKMAN_OLD_PWD) under `set -u`,
# and `sdk list | grep -q` can return 141 via SIGPIPE under pipefail. Relaxed
# for the SDKMAN block, restored right after.
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


# errexit was off for the block above, so check the result explicitly.
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


if ! groups "$USER" | grep -q docker; then

    sudo usermod -aG docker "$USER"

fi


if ! dpkg -s docker-compose-plugin >/dev/null 2>&1; then

    sudo apt install -y docker-compose-plugin

fi


if [ "$DOCKER_BIND_LOOPBACK" = true ]; then

# Docker publishes ports via its own iptables rules, ahead of ufw's chains,
# so ufw cannot filter them. Binding to loopback by default closes that gap.
# Override per container with an explicit -p 0.0.0.0:8080:80 when a service
# genuinely needs to be reachable.
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
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"


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


    if [ "$ARCH" = "arm64" ]; then

        AWS_ARCH="aarch64"

    else

        AWS_ARCH="x86_64"

    fi


    curl \
    "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" \
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


    sudo install -m 0755 -d /etc/apt/keyrings


    curl -fsSL \
    https://apt.releases.hashicorp.com/gpg \
    | sudo gpg \
        --dearmor \
        -o /etc/apt/keyrings/hashicorp.gpg



    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp.gpg] \
https://apt.releases.hashicorp.com \
$(lsb_release -cs) main" \
    | sudo tee \
    /etc/apt/sources.list.d/hashicorp.list



    sudo apt update

    sudo apt install -y terraform


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


    sudo install -m 0755 -d /etc/apt/keyrings


    curl \
    https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | sudo gpg \
        --dearmor \
        -o /etc/apt/keyrings/google-cloud.gpg



    echo \
"deb [signed-by=/etc/apt/keyrings/google-cloud.gpg] \
https://packages.cloud.google.com/apt \
cloud-sdk main" \
    | sudo tee \
    /etc/apt/sources.list.d/google-cloud-sdk.list



    sudo apt update

    sudo apt install -y google-cloud-cli


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


        NONO_DEB="nono-cli_${NONO_VERSION}_${ARCH}.deb"


        wget \
        "https://github.com/nolabs-ai/nono/releases/download/v${NONO_VERSION}/${NONO_DEB}" \
        -O "$NONO_DEB"


        sudo apt install -y "./${NONO_DEB}"


        rm -f "$NONO_DEB"


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


    sudo curl -fsSLo \
    /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg


    echo \
"deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
https://brave-browser-apt-release.s3.brave.com/ stable main" \
    | sudo tee \
    /etc/apt/sources.list.d/brave-browser-release.list


    sudo apt update

    sudo apt install -y brave-browser


else

    log "Brave already installed"

fi


xdg-settings set default-web-browser brave-browser.desktop \
|| log "Could not set Brave as the default browser"



#######################################
# CHROMIUM
#######################################

log "Installing Chromium"


apt_install chromium



#######################################
# FIREFOX
#######################################

if [ "$REMOVE_FIREFOX" = true ]; then


log "Removing Firefox"


apt_purge firefox-esr


fi



#######################################
# TELEMETRY
#######################################

if [ "$REMOVE_TELEMETRY" = true ]; then

log "Removing telemetry"

apt_purge popularity-contest

fi


#######################################
# GNOME APPS
#######################################

log "Removing GNOME apps"

apt_purge gnome-tour
apt_purge gnome-maps
apt_purge gnome-calendar
apt_purge gnome-contacts
apt_purge totem
apt_purge showtime
apt_purge gnome-music


#######################################
# JETBRAINS TOOLBOX
#######################################

log "Installing JetBrains Toolbox"


if ! command_exists jetbrains-toolbox; then


    # Prerequisites from
    # https://www.jetbrains.com/help/idea/installation-guide.html#toolbox_linux
    sudo apt install -y \
    libxi6 \
    libxrender1 \
    libxtst6 \
    mesa-utils \
    libfontconfig \
    libgtk-3-bin \
    dbus-user-session \
    libxcb-keysyms1


    # amd64 is the bare .tar.gz, arm64 carries an -arm64 suffix — so the amd64
    # pattern cannot match the arm64 URL.
    case "$ARCH" in
        amd64) TOOLBOX_SUFFIX="" ;;
        arm64) TOOLBOX_SUFFIX="-arm64" ;;
    esac


    # Take the current URL from the releases API rather than pinning a version.
    # `|| true` keeps a no-match grep from killing the run under errexit.
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


        # The tarball unpacks to jetbrains-toolbox-<version>/bin/jetbrains-toolbox.
        # Toolbox relocates itself into ~/.local/share/JetBrains/Toolbox and writes
        # its own desktop entry on first launch, so /opt only holds the launcher.
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


    # The key is ASCII-armored despite the .gpg name, so dearmor it.
    curl -fsSL https://download.sublimetext.com/sublimehq-pub.gpg \
    | sudo gpg --dearmor --yes -o /usr/share/keyrings/sublimehq-pub.gpg


    # A flat repository — hence the trailing slash and no component. It carries
    # arm64 as well as amd64, so no architecture guard is needed.
    echo \
"deb [signed-by=/usr/share/keyrings/sublimehq-pub.gpg] \
https://download.sublimetext.com/ apt/stable/" \
    | sudo tee \
    /etc/apt/sources.list.d/sublime-text.list


    sudo apt update

    sudo apt install -y sublime-text


else

    log "Sublime already installed"

fi



#######################################
# SLACK
#######################################

log "Installing Slack"


# Slack publishes amd64 only — the repo's binary-arm64 index is empty.
if [ "$ARCH" != "amd64" ]; then

    log "Slack has no ${ARCH} build — skipping"

elif ! command_exists slack; then


    curl -fsSL https://packagecloud.io/slacktechnologies/slack/gpgkey \
    | sudo gpg --dearmor --yes -o /usr/share/keyrings/slack-archive-keyring.gpg


    # jessie is not a mistake — packagecloud publishes a single suite under that
    # name and Slack still pushes current builds to it. The deb's libgtk-3-0,
    # libatspi2.0-0 and libappindicator3-1 dependencies resolve on trixie as
    # virtual packages provided by the t64 renames.
    echo \
"deb [signed-by=/usr/share/keyrings/slack-archive-keyring.gpg] \
https://packagecloud.io/slacktechnologies/slack/debian/ jessie main" \
    | sudo tee \
    /etc/apt/sources.list.d/slack.list


    sudo apt update

    sudo apt install -y slack-desktop


else

    log "Slack already installed"

fi



#######################################
# LENS
#######################################

if [ "$INSTALL_LENS" = true ]; then


log "Installing Lens"


# Lens is amd64 only — their apt repo declares Architectures: amd64 and no
# arm64 AppImage is published.
if [ "$ARCH" != "amd64" ]; then

    log "Lens has no ${ARCH} build — skipping"

elif ! command_exists lens; then


    sudo install -m 0755 -d /etc/apt/keyrings


    curl -fsSL \
    https://downloads.k8slens.dev/keys/gpg \
    | sudo gpg \
        --dearmor \
        -o /etc/apt/keyrings/lens.gpg



    echo \
"deb [arch=amd64 signed-by=/etc/apt/keyrings/lens.gpg] \
https://downloads.k8slens.dev/apt/debian \
stable main" \
    | sudo tee \
    /etc/apt/sources.list.d/lens.list



    sudo apt update

    sudo apt install -y lens


else

    log "Lens already installed"

fi

fi



#######################################
# MONGODB COMPASS
#######################################

if [ "$INSTALL_MONGODB_COMPASS" = true ]; then


log "Installing MongoDB Compass"


# MongoDB publishes Compass for linux/x64 only — the download centre manifest
# lists no arm64 build.
if [ "$ARCH" != "amd64" ]; then

    log "MongoDB Compass has no ${ARCH} build — skipping"

elif ! command_exists mongodb-compass; then


    # The _latest_ filename does not exist — S3 reports the missing key as
    # "AccessDenied" — so take the current versioned URL from the manifest.
    # `|| true` keeps a no-match grep from killing the run under errexit.
    MONGO_URL=$(curl -s https://s3.amazonaws.com/info-mongodb-com/com-download-center/compass.json \
    | grep -o 'https://downloads\.mongodb\.com/compass/mongodb-compass_[0-9.]*_amd64\.deb' \
    | head -1) || true


    if [ -z "$MONGO_URL" ]; then

        log "Could not resolve a MongoDB Compass download URL — skipping"

    else


        wget "$MONGO_URL" \
        -O mongodb-compass.deb


        sudo apt install -y \
        ./mongodb-compass.deb


        rm -f mongodb-compass.deb


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


# Kong publishes Insomnia for amd64 only — the repo declares Architectures: amd64 i386.
if [ "$ARCH" != "amd64" ]; then

    log "Insomnia has no ${ARCH} build — skipping"

elif ! command_exists insomnia; then


    curl -fsSL \
    https://packages.konghq.com/public/insomnia/gpg.474B9148D779222B.key \
    | sudo gpg --dearmor --yes -o /usr/share/keyrings/kong-insomnia-archive-keyring.gpg


    # The ubuntu path is deliberate: Kong's deb/debian suites are all empty, and
    # under deb/ubuntu only focal actually carries packages — every other codename
    # answers 200 with an empty index. The deb itself installs fine on trixie.
    echo \
"deb [signed-by=/usr/share/keyrings/kong-insomnia-archive-keyring.gpg] \
https://packages.konghq.com/public/insomnia/deb/ubuntu focal main" \
    | sudo tee \
    /etc/apt/sources.list.d/insomnia.list


    sudo apt update

    sudo apt install -y insomnia


else

    log "Insomnia already installed"

fi

fi



#######################################
# DELUGE
#######################################

if [ "$INSTALL_DELUGE" = true ]; then


log "Installing Deluge"


apt_install deluge


fi



#######################################
# VLC
#######################################

if [ "$INSTALL_VLC" = true ]; then


log "Installing VLC"

apt_install vlc


fi



#######################################
# PROTON VPN
#######################################

if [ "$INSTALL_PROTONVPN" = true ]; then


log "Installing Proton VPN"


if ! dpkg -s proton-vpn-gnome-desktop >/dev/null 2>&1; then


    # Proton VPN is not in the Debian archive — this release package adds their
    # apt repo. Bump the version and checksum together from
    # https://protonvpn.com/support/linux-vpn-debian-ubuntu when it goes stale.
    PROTONVPN_RELEASE="protonvpn-stable-release_1.0.8_all.deb"
    PROTONVPN_SHA256="0b14e71586b22e498eb20926c48c7b434b751149b1f2af9902ef1cfe6b03e180"


    wget \
    "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/${PROTONVPN_RELEASE}" \
    -O "$PROTONVPN_RELEASE"


    echo "${PROTONVPN_SHA256}  ${PROTONVPN_RELEASE}" | sha256sum --check -


    sudo dpkg -i "./${PROTONVPN_RELEASE}"


    rm -f "$PROTONVPN_RELEASE"


    sudo apt update

    sudo apt install -y proton-vpn-gnome-desktop


else

    log "Proton VPN already installed"

fi


# System tray support for the GUI, per the Proton VPN docs. Debian ships the extension
# disabled — enable it once in the Extensions app and re-login for the tray icon.
apt_install gnome-shell-extension-appindicator
apt_install gnome-shell-extension-prefs


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


echo ""
echo "======================================"
echo " Bootstrap completed"
echo "======================================"
echo ""

echo "IMPORTANT:"
echo "- Run jetbrains-toolbox and sign in to install IDEA Ultimate"
echo "- Logout/login for Docker permissions"
echo "- Restart recommended"
echo "- Review $LOG_FILE if something failed"
echo ""
