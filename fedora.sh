#######################################
# Fedora Workstation 45 (GNOME), aarch64 and x86_64
#
#######################################


#######################################
# REMOVE GNOME APPS
#######################################

sudo dnf remove -y gnome-tour gnome-maps gnome-calendar gnome-contacts showtime


#######################################
# REMOVE FIREFOX
#######################################

sudo dnf remove -y firefox


#######################################
# DISABLE DNF COUNT-ME
#######################################

sudo dnf config-manager setopt "*.countme=0"


#######################################
# SYSTEM UPDATE
#######################################

sudo dnf upgrade --refresh -y


#######################################
# FIREWALL
#######################################

sudo dnf install -y firewalld \
  && sudo systemctl enable --now firewalld \
  && sudo firewall-cmd --set-default-zone=public \
  && sudo firewall-cmd --permanent --zone=public --remove-service=ssh \
  && sudo firewall-cmd --reload \
  && sudo firewall-cmd --list-all


#######################################
# redis-cli
#######################################

sudo dnf install -y valkey-compat-redis


#######################################
# NVM + NODE
#######################################

NVM_VERSION=$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/nvm-sh/nvm/releases/latest | sed 's#.*/##') \
  && curl -f -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash \
  && { source ~/.nvm/nvm.sh; nvm install 'lts/*' && nvm alias default 'lts/*'; }


#######################################
# SDKMAN + OPENJDK
#######################################

curl -fs https://get.sdkman.io | bash \
  && { source ~/.sdkman/bin/sdkman-init.sh; sdk install java 25.0.2.0+10-open && sdk default java 25.0.2.0+10-open; }


#######################################
# DOCKER
#######################################

curl -fsSL https://get.docker.com | sh \
  && sudo systemctl enable --now docker \
  && sudo usermod -aG docker "$USER"

# published ports on loopback only
sudo tee /etc/docker/daemon.json <<'EOF' \
  && sudo systemctl restart docker
{
  "ip": "127.0.0.1",
  "default-network-opts": {
    "bridge": {
      "com.docker.network.bridge.host_binding_ipv4": "127.0.0.1"
    }
  }
}
EOF


#######################################
# KUBECTL
#######################################

KUBECTL_URL="https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')/kubectl" \
  && curl -fLO "$KUBECTL_URL" \
  && echo "$(curl -fsSL "${KUBECTL_URL}.sha256")  kubectl" | sha256sum --check - \
  && sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl; \
  rm -f kubectl


#######################################
# K9S
#######################################

sudo dnf install -y k9s


#######################################
# HELM
#######################################

sudo dnf install -y openssl \
  && curl -f https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash


#######################################
# AWS CLI
#######################################

curl -f "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o awscliv2.zip \
  && unzip -q awscliv2.zip \
  && sudo ./aws/install --update; \
  rm -rf aws awscliv2.zip


#######################################
# TERRAFORM
#######################################

sudo tee /etc/yum.repos.d/hashicorp.repo <<'EOF' \
  && sudo dnf install -y terraform
[hashicorp]
name=HashiCorp Stable
baseurl=https://rpm.releases.hashicorp.com/RHEL/10/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://rpm.releases.hashicorp.com/gpg
EOF


#######################################
# GOOGLE CLOUD SDK
#######################################

sudo tee /etc/yum.repos.d/google-cloud-cli.repo <<'EOF' \
  && sudo dnf install -y google-cloud-cli
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el10-$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key-v10.gpg
EOF


#######################################
# CLAUDE CODE
#######################################

curl -fsSL https://claude.ai/install.sh | bash


#######################################
# NONO
#######################################

NONO_VERSION=$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/nolabs-ai/nono/releases/latest | sed 's#.*/v##') \
  && NONO_RPM="nono-cli-${NONO_VERSION}-1.$(uname -m).rpm" \
  && curl -fLO "https://github.com/nolabs-ai/nono/releases/download/v${NONO_VERSION}/${NONO_RPM}" \
  && curl -fsSL "https://github.com/nolabs-ai/nono/releases/download/v${NONO_VERSION}/SHA256SUMS.txt" | sha256sum --check --ignore-missing - \
  && sudo dnf install -y "./${NONO_RPM}"; \
  rm -f "$NONO_RPM"


#######################################
# HERDR
#######################################

curl -fsSL https://herdr.dev/install.sh | sh


#######################################
# BRAVE BROWSER
#######################################

sudo tee /etc/yum.repos.d/brave-browser.repo <<'EOF' \
  && sudo dnf install -y brave-browser \
  && xdg-settings set default-web-browser brave-browser.desktop
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/$basearch
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
EOF


#######################################
# JETBRAINS TOOLBOX
#######################################

sudo dnf install -y libXi libXrender libXtst glx-utils fontconfig gtk3 xcb-util-keysyms \
  && TOOLBOX_URL=$(curl -fsSL "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" | grep -o "https://download\.jetbrains\.com/toolbox/jetbrains-toolbox-[0-9.]*$(uname -m | sed 's/x86_64//;s/aarch64/-arm64/')\.tar\.gz" | head -1) \
  && curl -fLO "$TOOLBOX_URL" \
  && sudo mkdir -p /opt/jetbrains-toolbox \
  && curl -fsSL "${TOOLBOX_URL}.sha256" | sha256sum --check - \
  && sudo tar -xzf "$(basename "$TOOLBOX_URL")" -C /opt/jetbrains-toolbox --strip-components=1 \
  && sudo ln -sf /opt/jetbrains-toolbox/bin/jetbrains-toolbox /usr/local/bin/jetbrains-toolbox; \
  rm -f "$(basename "$TOOLBOX_URL")"


#######################################
# SUBLIME TEXT
#######################################

sudo tee /etc/yum.repos.d/sublime-text.repo <<'EOF' \
  && sudo dnf install -y sublime-text
[sublime-text]
name=Sublime Text
baseurl=https://download.sublimetext.com/rpm/stable/$basearch
enabled=1
gpgcheck=1
gpgkey=https://download.sublimetext.com/sublimehq-pub.gpg
EOF


#######################################
# SLACK
# x86_64 only
#######################################

sudo tee /etc/yum.repos.d/slack.repo <<'EOF' \
  && sudo dnf install -y slack
[slack]
name=slack
baseurl=https://packagecloud.io/slacktechnologies/slack/fedora/21/$basearch
enabled=1
gpgcheck=0
repo_gpgcheck=1
gpgkey=https://packagecloud.io/slacktechnologies/slack/gpgkey
EOF


#######################################
# FREELENS
#######################################

FREELENS_VERSION=$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/freelensapp/freelens/releases/latest | sed 's#.*/v##') \
  && FREELENS_RPM="Freelens-${FREELENS_VERSION}-linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').rpm" \
  && curl -fLO "https://github.com/freelensapp/freelens/releases/download/v${FREELENS_VERSION}/${FREELENS_RPM}" \
  && curl -fsSL "https://github.com/freelensapp/freelens/releases/download/v${FREELENS_VERSION}/${FREELENS_RPM}.sha256" | sha256sum --check - \
  && sudo dnf install -y "./${FREELENS_RPM}"; \
  rm -f "$FREELENS_RPM"


#######################################
# MONGODB COMPASS
# x86_64 only
# Installed with rpm --excludepath, not dnf: its /usr/lib/.build-id links
# are the same files Slack ships, and the second of the two is refused.
#######################################

COMPASS_URL=$(curl -s https://s3.amazonaws.com/info-mongodb-com/com-download-center/compass.json | grep -o 'https://downloads\.mongodb\.com/compass/mongodb-compass-[0-9.]*\.x86_64\.rpm' | head -1) \
  && curl -fLO "$COMPASS_URL" \
  && sudo rpmkeys --import https://pgp.mongodb.com/compass.asc \
  && sudo dnf install -y at-spi2-core gnome-keyring gtk3 libXScrnSaver libXtst libnotify libsecret libuuid nss xdg-utils \
  && sudo rpm -Uvh --excludepath=/usr/lib/.build-id "$(basename "$COMPASS_URL")"; \
  rm -f "$(basename "$COMPASS_URL")"


#######################################
# INSOMNIA
# x86_64 only
#######################################

INSOMNIA_VERSION=$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/Kong/insomnia/releases/latest | sed -E 's#.*/core(@|%40)##') \
  && sudo dnf install -y "https://github.com/Kong/insomnia/releases/download/core@${INSOMNIA_VERSION}/Insomnia.Core-${INSOMNIA_VERSION}.rpm"


#######################################
# DELUGE
#######################################

sudo dnf install -y deluge-gtk

# Deluge incoming port
# Deluge picks a random port by default, so set the same one there:
# Preferences > Network > Incoming Port: untick Random, enter 6881.
sudo firewall-cmd --permanent --zone=public --add-port=6881/tcp --add-port=6881/udp \
  && sudo firewall-cmd --reload


#######################################
# VLC
#######################################

sudo dnf install -y vlc

# VLC, H.264/HEVC DECODERS
sudo dnf install -y distribution-gpg-keys \
  && sudo rpmkeys --import "/usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-free-fedora-$(rpm -E %fedora)" \
  && sudo dnf install -y --setopt=localpkg_gpgcheck=1 "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  && sudo dnf install -y libavcodec-freeworld


#######################################
# PROTON VPN
#######################################

sudo tee /etc/yum.repos.d/protonvpn-stable.repo <<'EOF' \
  && sudo dnf install -y proton-vpn-gnome-desktop \
  && sudo dnf install -y libappindicator-gtk3 gnome-shell-extension-appindicator gnome-extensions-app
[protonvpn-fedora-stable]
name=ProtonVPN Fedora Stable repository
baseurl=https://repo.protonvpn.com/fedora-$releasever-stable
enabled=1
gpgcheck=1
gpgkey=https://repo.protonvpn.com/fedora-$releasever-stable/public_key.asc
EOF


#######################################
# NORDVPN
#######################################

sudo tee /etc/yum.repos.d/nordvpn.repo <<'EOF' \
  && sudo dnf install -y nordvpn \
  && sudo usermod -aG nordvpn "$USER"
[nordvpn]
name=NordVPN
baseurl=https://repo.nordvpn.com/yum/nordvpn/centos/$basearch
enabled=1
gpgcheck=1
gpgkey=https://repo.nordvpn.com/gpg/nordvpn_public.asc
EOF
