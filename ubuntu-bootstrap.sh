#!/usr/bin/env bash

set -euo pipefail

#######################################
# Ubuntu Bootstrap
#
# Supported:
# - Ubuntu ARM64
# - Ubuntu AMD64
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
INSTALL_PROTONVPN=true


#######################################
# GLOBAL VARIABLES
#######################################

ARCH=$(dpkg --print-architecture)

LOG_FILE="$HOME/ubuntu-bootstrap.log"


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


echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" \
| sudo debconf-set-selections


# redis-cli ships in redis-tools — there is no package by that name, and the
# redis metapackage would install and start the server as well.
sudo apt install -y \
    curl \
    wget \
    redis-tools \
    unzip \
    zip \
    build-essential \
    ca-certificates \
    gnupg \
    software-properties-common \
    apt-transport-https \
    lsb-release \
    xdg-utils \
    ubuntu-restricted-extras


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
"alias nonoclaude='nono run --allow-cwd --read ~/.npm --read ~/.gradle --read ~/.m2 --profile claude-code -- claude'" \
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


if ! snap list chromium >/dev/null 2>&1; then

    sudo snap install chromium

else

    log "Chromium already installed"

fi



#######################################
# FIREFOX
#######################################

if [ "$REMOVE_FIREFOX" = true ]; then


log "Removing Firefox"


if snap list firefox >/dev/null 2>&1; then

    sudo snap remove firefox

else

    log "Firefox snap not installed"

fi


apt_purge firefox


fi



#######################################
# TELEMETRY
#######################################

if [ "$REMOVE_TELEMETRY" = true ]; then

log "Removing telemetry"

apt_purge ubuntu-insights
apt_purge ubuntu-report

fi


#######################################
# INTELLIJ IDEA ULTIMATE
#######################################

log "Installing IntelliJ IDEA Ultimate"


if ! snap list intellij-idea-ultimate >/dev/null 2>&1; then

    sudo snap install \
    intellij-idea-ultimate \
    --classic

else

    log "IntelliJ already installed"

fi



#######################################
# SUBLIME TEXT
#######################################

log "Installing Sublime Text"


if ! snap list sublime-text >/dev/null 2>&1; then

    sudo snap install \
    sublime-text \
    --classic

else

    log "Sublime already installed"

fi



#######################################
# SLACK
#######################################

log "Installing Slack"


# The slack snap is published for amd64 only — snapd refuses it on arm64 with
# "not available on stable for this architecture". Use the web app there.
if [ "$ARCH" != "amd64" ]; then

    log "Slack has no ${ARCH} build — skipping"

elif ! snap list slack >/dev/null 2>&1; then

    sudo snap install slack

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


# The insomnia snap is published for amd64 only.
if [ "$ARCH" != "amd64" ]; then

    log "Insomnia has no ${ARCH} build — skipping"

elif ! snap list insomnia >/dev/null 2>&1; then

    sudo snap install insomnia

else

    log "Insomnia already installed"

fi

fi



#######################################
# DELUGE
#######################################

if [ "$INSTALL_DELUGE" = true ]; then


log "Installing Deluge"


# Architecture: all, so this works on arm64 too.
apt_install deluge


fi



#######################################
# PROTON VPN
#######################################

if [ "$INSTALL_PROTONVPN" = true ]; then


log "Installing Proton VPN CLI"


if ! dpkg -s proton-vpn-cli >/dev/null 2>&1; then


    # Proton VPN is not in the Ubuntu archive — this release package adds their
    # apt repo. Bump the version and checksum together from
    # https://protonvpn.com/support/cli-debian-ubuntu when it goes stale.
    PROTONVPN_RELEASE="protonvpn-stable-release_1.0.8_all.deb"
    PROTONVPN_SHA256="0b14e71586b22e498eb20926c48c7b434b751149b1f2af9902ef1cfe6b03e180"


    wget \
    "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/${PROTONVPN_RELEASE}" \
    -O "$PROTONVPN_RELEASE"


    echo "${PROTONVPN_SHA256}  ${PROTONVPN_RELEASE}" | sha256sum --check -


    sudo dpkg -i "./${PROTONVPN_RELEASE}"


    rm -f "$PROTONVPN_RELEASE"


    sudo apt update

    sudo apt install -y proton-vpn-cli


else

    log "Proton VPN CLI already installed"

fi

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
echo "- Logout/login for Docker permissions"
echo "- Restart recommended"
echo "- Review $LOG_FILE if something failed"
echo ""
