#######################################
# Fedora Workstation 45 (GNOME), aarch64 and x86_64
#
# Not a script to run as a whole.
# Paste the parts you want into a terminal.
#######################################


#######################################
# SYSTEM UPDATE
#######################################

sudo dnf upgrade --refresh -y


#######################################
# BASE PACKAGES
#######################################

sudo dnf install -y curl wget valkey-compat-redis unzip zip gcc gcc-c++ make ca-certificates gnupg2 xdg-utils dnf5-plugins


#######################################
# RPM FUSION FREE + CODECS
#######################################

sudo dnf install -y distribution-gpg-keys
sudo rpmkeys --import "/usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-free-fedora-$(rpm -E %fedora)"
sudo dnf install -y --setopt=localpkg_gpgcheck=1 "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
sudo dnf install -y libavcodec-freeworld


#######################################
# VIDEO ACCELERATION + SENSORS, INTEL
# bare-metal x86_64, needs RPM Fusion free
#######################################

sudo dnf install -y libva-utils lm_sensors libva-intel-media-driver libva-intel-driver


#######################################
# VIDEO ACCELERATION + SENSORS, AMD
# bare-metal x86_64, needs RPM Fusion free
#######################################

sudo dnf install -y libva-utils lm_sensors mesa-va-drivers-freeworld


#######################################
# FIRMWARE, MICROCODE AND POWER PROFILES STATUS
#######################################

rpm -q microcode_ctl amd-ucode-firmware linux-firmware alsa-sof-firmware
systemctl is-active tuned-ppd


#######################################
# FIREWALL
#######################################

sudo dnf install -y firewalld
sudo systemctl enable --now firewalld
sudo firewall-cmd --set-default-zone=public
sudo firewall-cmd --permanent --zone=public --remove-service=ssh
sudo firewall-cmd --reload
sudo firewall-cmd --list-all


#######################################
# SHELL CONFIG
#######################################

cat >> ~/.bashrc <<'EOF'
export PATH="$HOME/.local/bin:$PATH"
alias k='kubectl'
alias g='gcloud'
alias t='terraform'
alias nonoclaude='nono run --allow-cwd  --read ~/.sdkman --read ~/.npm --read ~/.gradle --write ~/.gradle --read ~/.m2  --read ~/.embedmongo --profile claude-code -- claude'
EOF
source ~/.bashrc


#######################################
# NVM + NODE
#######################################

curl -f -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
source ~/.nvm/nvm.sh
nvm install 'lts/*'
nvm alias default 'lts/*'


#######################################
# SDKMAN + OPENJDK
#######################################

curl -fs https://get.sdkman.io | bash
source ~/.sdkman/bin/sdkman-init.sh
sdk install java 25.0.2.0+10-open
sdk default java 25.0.2.0+10-open


#######################################
# DOCKER
#######################################

curl -fsSL https://get.docker.com | sh
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"


#######################################
# DOCKER, PUBLISHED PORTS ON LOOPBACK ONLY
#######################################

printf '{\n  "ip": "127.0.0.1"\n}\n' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker


#######################################
# KUBECTL
#######################################

curl -fLO "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl


#######################################
# HELM
#######################################

sudo dnf install -y openssl
curl -f https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash


#######################################
# AWS CLI
#######################################

curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o awscliv2.zip
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip


#######################################
# TERRAFORM
#######################################

sudo tee /etc/yum.repos.d/hashicorp.repo <<'EOF'
[hashicorp]
name=HashiCorp Stable
baseurl=https://rpm.releases.hashicorp.com/RHEL/10/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://rpm.releases.hashicorp.com/gpg
EOF
sudo dnf install -y terraform


#######################################
# GOOGLE CLOUD SDK
#######################################

sudo tee /etc/yum.repos.d/google-cloud-cli.repo <<'EOF'
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el10-$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key-v10.gpg
EOF
sudo dnf install -y google-cloud-cli


#######################################
# CLAUDE CODE
#######################################

curl -fsSL https://claude.ai/install.sh | bash


#######################################
# NONO
#######################################

NONO_VERSION=$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/nolabs-ai/nono/releases/latest | sed 's#.*/v##')
sudo dnf install -y "https://github.com/nolabs-ai/nono/releases/download/v${NONO_VERSION}/nono-cli-${NONO_VERSION}-1.$(uname -m).rpm"


#######################################
# BRAVE BROWSER
#######################################

sudo tee /etc/yum.repos.d/brave-browser.repo <<'EOF'
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/$basearch
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
EOF
sudo dnf install -y brave-browser
xdg-settings set default-web-browser brave-browser.desktop


#######################################
# REMOVE FIREFOX
#######################################

sudo dnf remove -y firefox


#######################################
# DISABLE DNF COUNT-ME
#######################################

sudo dnf config-manager setopt "*.countme=0"


#######################################
# REMOVE GNOME APPS
#######################################

sudo dnf remove -y gnome-tour gnome-maps gnome-calendar gnome-contacts showtime


#######################################
# JETBRAINS TOOLBOX
#######################################

sudo dnf install -y libXi libXrender libXtst glx-utils fontconfig gtk3 xcb-util-keysyms
TOOLBOX_URL=$(curl -fsSL "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" | grep -o "https://download\.jetbrains\.com/toolbox/jetbrains-toolbox-[0-9.]*$(uname -m | sed 's/x86_64//;s/aarch64/-arm64/')\.tar\.gz" | head -1)
curl -fLO "$TOOLBOX_URL"
sudo mkdir -p /opt/jetbrains-toolbox
curl -fsSL "${TOOLBOX_URL}.sha256" | sha256sum --check - && sudo tar -xzf "$(basename "$TOOLBOX_URL")" -C /opt/jetbrains-toolbox --strip-components=1
sudo ln -sf /opt/jetbrains-toolbox/bin/jetbrains-toolbox /usr/local/bin/jetbrains-toolbox
rm -f "$(basename "$TOOLBOX_URL")"


#######################################
# SUBLIME TEXT
#######################################

sudo tee /etc/yum.repos.d/sublime-text.repo <<'EOF'
[sublime-text]
name=Sublime Text
baseurl=https://download.sublimetext.com/rpm/stable/$basearch
enabled=1
gpgcheck=1
gpgkey=https://download.sublimetext.com/sublimehq-pub.gpg
EOF
sudo dnf install -y sublime-text


#######################################
# SLACK
# x86_64 only
#######################################

sudo tee /etc/yum.repos.d/slack.repo <<'EOF'
[slack]
name=slack
baseurl=https://packagecloud.io/slacktechnologies/slack/fedora/21/$basearch
enabled=1
gpgcheck=0
EOF
sudo dnf install -y slack


#######################################
# FREELENS
#######################################

FREELENS_VERSION=$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/freelensapp/freelens/releases/latest | sed 's#.*/v##')
FREELENS_RPM="Freelens-${FREELENS_VERSION}-linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').rpm"
curl -fLO "https://github.com/freelensapp/freelens/releases/download/v${FREELENS_VERSION}/${FREELENS_RPM}"
curl -fsSL "https://github.com/freelensapp/freelens/releases/download/v${FREELENS_VERSION}/${FREELENS_RPM}.sha256" | sha256sum --check - && sudo dnf install -y "./${FREELENS_RPM}"
rm -f "$FREELENS_RPM"


#######################################
# MONGODB COMPASS
# x86_64 only
#######################################

sudo dnf install -y "$(curl -s https://s3.amazonaws.com/info-mongodb-com/com-download-center/compass.json | grep -o 'https://downloads\.mongodb\.com/compass/mongodb-compass-[0-9.]*\.x86_64\.rpm' | head -1)"


#######################################
# INSOMNIA
# x86_64 only
#######################################

INSOMNIA_VERSION=$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/Kong/insomnia/releases/latest | sed -E 's#.*/core(@|%40)##')
sudo dnf install -y "https://github.com/Kong/insomnia/releases/download/core@${INSOMNIA_VERSION}/Insomnia.Core-${INSOMNIA_VERSION}.rpm"


#######################################
# DELUGE
#######################################

sudo dnf install -y deluge-gtk


#######################################
# VLC
#######################################

sudo dnf install -y vlc


#######################################
# PROTON VPN
#######################################

sudo tee /etc/yum.repos.d/protonvpn-stable.repo <<'EOF'
[protonvpn-fedora-stable]
name=ProtonVPN Fedora Stable repository
baseurl=https://repo.protonvpn.com/fedora-$releasever-stable
enabled=1
gpgcheck=1
gpgkey=https://repo.protonvpn.com/fedora-$releasever-stable/public_key.asc
EOF
sudo dnf install -y proton-vpn-gnome-desktop
sudo dnf install -y libappindicator-gtk3 gnome-shell-extension-appindicator gnome-extensions-app


#######################################
# NORDVPN
#######################################

sudo tee /etc/yum.repos.d/nordvpn.repo <<'EOF'
[nordvpn]
name=NordVPN
baseurl=https://repo.nordvpn.com/yum/nordvpn/centos/$basearch
enabled=1
gpgcheck=1
gpgkey=https://repo.nordvpn.com/gpg/nordvpn_public.asc
EOF
sudo dnf install -y nordvpn
sudo usermod -aG nordvpn "$USER"
