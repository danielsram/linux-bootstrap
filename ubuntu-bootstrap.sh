#!/usr/bin/env bash

set -euo pipefail

#######################################
# Ubuntu Bootstrap
#
# Supported:
# - Ubuntu ARM64
# - Ubuntu AMD64
#
# Designed for:
# - UTM Apple Silicon
# - Framework / normal laptops
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

INSTALL_AWS_CLI=true
INSTALL_TERRAFORM=true
INSTALL_GCLOUD=true
INSTALL_CLAUDE_CODE=true
INSTALL_LENS=true
INSTALL_MONGODB_COMPASS=true
INSTALL_NORDVPN=false


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
    ubuntu-restricted-extras


#######################################
# SHELL ALIASES
#######################################

log "Adding aliases"

append_if_missing \
"alias k='kubectl'" \
"$HOME/.bashrc"

append_if_missing \
"alias g='gcloud'" \
"$HOME/.bashrc"

append_if_missing \
"alias t='terraform'" \
"$HOME/.bashrc"

#######################################
# NVM + NODE
#######################################

log "Installing NVM"

if [ ! -d "$HOME/.nvm" ]; then

    curl -o- \
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

    curl -s \
    https://get.sdkman.io \
    | bash

fi


export SDKMAN_DIR="$HOME/.sdkman"

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



#######################################
# KUBECTL
#######################################

log "Installing kubectl"


if ! command_exists kubectl; then


    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)


    curl -LO \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"


    sudo install \
        -o root \
        -g root \
        -m 0755 \
        kubectl \
        /usr/local/bin/kubectl


    rm kubectl


else

    log "kubectl already installed"

fi



#######################################
# HELM
#######################################

log "Installing Helm"


if ! command_exists helm; then

    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
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


if ! snap list slack >/dev/null 2>&1; then

    sudo snap install slack

else

    log "Slack already installed"

fi



#######################################
# LENS
#######################################

if [ "$INSTALL_LENS" = true ]; then


log "Installing Lens"


if ! command_exists lens; then


    case "$ARCH" in

        arm64)
            LENS_ARCH="arm64"
            ;;

        amd64)
            LENS_ARCH="x64"
            ;;

    esac


    LENS_URL=$(curl -s https://api.k8slens.dev/binaries/latest \
    | grep -o "https[^\" ]*linux-${LENS_ARCH}[^\" ]*" \
    | head -1)


    if [ -n "$LENS_URL" ]; then


        wget "$LENS_URL" \
        -O lens.AppImage


        chmod +x lens.AppImage


        sudo mv \
        lens.AppImage \
        /usr/local/bin/lens


    else

        log "Lens package not found for architecture ${ARCH}"

    fi


else

    log "Lens already installed"

fi

fi



#######################################
# MONGODB COMPASS
#######################################

if [ "$INSTALL_MONGODB_COMPASS" = true ]; then


log "Installing MongoDB Compass"


if ! command_exists mongodb-compass; then


    case "$ARCH" in


        arm64)

            MONGO_PACKAGE="mongodb-compass_latest_arm64.deb"

            ;;


        amd64)

            MONGO_PACKAGE="mongodb-compass_latest_amd64.deb"

            ;;


    esac



    wget \
    "https://downloads.mongodb.com/compass/${MONGO_PACKAGE}" \
    -O mongodb-compass.deb



    if dpkg --info mongodb-compass.deb >/dev/null 2>&1; then


        sudo apt install -y \
        ./mongodb-compass.deb


    else

        log "MongoDB Compass package unavailable for ${ARCH}"

    fi


    rm -f mongodb-compass.deb


else

    log "MongoDB Compass already installed"

fi

fi



#######################################
# NORDVPN
#######################################

if [ "$INSTALL_NORDVPN" = true ]; then


log "Installing NordVPN"


if ! command_exists nordvpn; then


    sh <(
        curl -sSf \
        https://downloads.nordcdn.com/apps/linux/install.sh
    )


else

    log "NordVPN already installed"

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
