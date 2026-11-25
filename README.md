# Linux Bootstrap

Three scripts that set up the same workstation, one per distro, on **arm64** and **amd64**
(`aarch64` and `x86_64` in Fedora's naming). Any other architecture exits immediately.

`amd64` is the distro name for **x86-64**, and it covers Intel and AMD equally — an Intel
laptop is an amd64 machine here, supported by every script. On bare metal they also detect
the CPU vendor and install the matching microcode, firmware and video acceleration.

Run it as a **regular user, not under sudo** — nvm, SDKMAN and Claude Code install into `$HOME`, 
the Claude Code installer refuses to run under sudo, 
and the docker group would be granted to `root` instead of you.

## Ubuntu

```bash
./ubuntu.sh
```

- Firefox is a snap plus a small integration deb, and `REMOVE_FIREFOX` drops both. The snap's
  profile survives as a snapshot — `snap saved` lists it, `snap restore` brings it back. A
  release upgrade can reinstall the deb, since `ubuntu-desktop` recommends it.
- `REMOVE_TELEMETRY` purges `ubuntu-insights` and `ubuntu-report`. ubuntu-insights is the
  active one — installing it enables user timers that collect monthly and upload weekly;
  ubuntu-report only fires when a report is already queued. Both are `ubuntu-desktop`
  recommends, so the desktop is unaffected, and a release upgrade can bring them back.
- Base packages also include `software-properties-common` and `ubuntu-restricted-extras`.

## Debian

```bash
./debian.sh
```

- Chromium is installed from Debian main — a real deb, not a snap. It also satisfies
  `gnome-core`'s browser recommends, so apt stops trying to pull Firefox back.
- `REMOVE_FIREFOX` purges `firefox-esr`.
- `REMOVE_TELEMETRY` purges `popularity-contest`, Debian's analogue of the Ubuntu telemetry
  packages.
- `ubuntu-restricted-extras` does not exist, so only its codecs are installed, via
  `libavcodec-extra` from main. No Microsoft core fonts and no `unrar` — those need contrib
  and non-free, and the script leaves the system's apt sources alone.
- No `software-properties-common` — Debian 13 dropped it from every component.

## Fedora

```bash
./fedora.sh
```

Written for Fedora Workstation 45 (dnf5). Package names and vendor repositories were checked
against Fedora 45 on 25 November 2026. Two flags differ from the other scripts:
`INSTALL_RPMFUSION` is new and `CONFIGURE_FIREWALLD` replaces `INSTALL_UFW`.

- **RPM Fusion free** is enabled for `libavcodec-freeworld`, the full codec set that Fedora's
  own `libavcodec-free` leaves out. The release package is signature-checked against the key
  Fedora ships in `distribution-gpg-keys`. RPM Fusion nonfree is not enabled.
- **firewalld, not ufw.** Workstation's default zone `FedoraWorkstation` accepts inbound TCP and
  UDP on ports 1025–65535. The script makes `public` the default zone and removes `ssh` from
  it, which leaves mDNS and the DHCPv6 client — close to what ufw's default deny lets
  through. Denied packets are not logged: firewalld's `LogDenied` has no rate limit like
  ufw's `logging low`.
- **Hardware enablement installs only VA-API and `lm_sensors`.** Workstation already ships
  microcode and firmware, so they are asserted and logged, as on Ubuntu. Intel gets
  `libva-intel-media-driver` from Fedora plus `libva-intel-driver` from RPM Fusion for older
  generations. AMD gets `mesa-va-drivers-freeworld` from RPM Fusion — Fedora's Mesa is built
  without H.264 and H.265 — so with `INSTALL_RPMFUSION=false` an AMD machine has no hardware
  decode for those. The power service checked is `tuned-ppd`, which `tlp` conflicts with.
- `redis-cli` comes from `valkey-compat-redis`. Fedora replaced Redis with Valkey, and the
  package pulls in the Valkey server; its service stays disabled.
- **Docker CE is installed next to the preinstalled Podman.** RPM packages do not start
  services, so the script enables `docker.service` itself.
- **Terraform comes from HashiCorp's `RHEL/10` repository.** Their `fedora/45` repository
  exists but carries no `terraform` package yet. gcloud uses Google's `cloud-sdk-el10`
  repository.
- **Slack's repository runs with `gpgcheck=0`.** `fedora/21` is the single suite Slack
  publishes, and the package's daily cron job rewrites `slack.repo` with the check off — the
  script writes the same file rather than one that would be replaced.
- **Insomnia is a one-off rpm from the GitHub release**, unsigned, and does not update through
  dnf. Kong's rpm repositories answer 200 and are empty. MongoDB Compass is a one-off rpm too.
- `REMOVE_FIREFOX` removes `firefox`. `REMOVE_TELEMETRY` sets `countme=0` on every repository
  — DNF's weekly installation counter, the closest thing Fedora has to popularity-contest.
- GNOME Tour, Maps, Calendar, Contacts and Showtime are removed, as on Debian.
- Proton VPN's tray icon needs the AppIndicator extension enabled once in the Extensions
  app, as on Debian.

## NixOS

`nixos/` declares the same workstation as a flake (NixOS 26.05 + home-manager) instead of a
script. Feature flags sit at the top of `nixos/configuration.nix`; aliases, the default browser
and the appindicator extension live in `nixos/home.nix`.

```bash
sudo nixos-generate-config --show-hardware-config > nixos/hosts/laptop/hardware-configuration.nix
git add nixos/hosts/laptop/hardware-configuration.nix   # flakes ignore untracked files
sudo nixos-rebuild switch --flake ./nixos#laptop
```

Rename `dan` and `laptop` in the three files first. What differs from the scripts:

- **Hardware enablement is mostly generated.** `nixos-generate-config` writes microcode and
  `kvm-intel`/`kvm-amd` for the machine it runs on, and nothing for a VM guest.
  `hardware.enableRedistributableFirmware` covers the whole Debian firmware list.
- **No SDKMAN or nvm.** One JDK 25 and Node 24 come from nixpkgs; use a `devShell` per project
  for other versions. `nix-ld` is enabled so IDEs downloaded by JetBrains Toolbox still run.
- **Firefox and telemetry need no removal** — NixOS installs neither.
- **Docker still bypasses the firewall**, so `daemon.settings.ip = "127.0.0.1"` stays.
- **nono from nixpkgs lags upstream** — 0.61.1 in 26.05 against v0.80.0 on GitHub (checked
  13 October 2026).
- Updates are `nix flake update` + `nixos-rebuild switch`; a bad generation rolls back from
  the boot menu.

## Hardware

`INSTALL_HARDWARE_ENABLEMENT` covers what a bare-metal x86-64 laptop needs and the base
package list does not. It runs only when all three hold: the architecture is amd64, the
machine is not a VM (`systemd-detect-virt`), and the CPU vendor is recognised. arm64 and VM
guests log a skip and carry on — microcode is inert under a hypervisor, which disables the
loader as soon as it sees the CPUID hypervisor bit, so installing it in a guest achieves
nothing except the false impression of being patched.

What gets installed differs sharply per distro:

- **Ubuntu needs almost nothing.** `linux-image-generic` depends on `intel-microcode`,
  `amd64-microcode` and `linux-firmware`, and `linux-firmware` recommends
  `firmware-sof-signed`, so a stock desktop already has them. The script asserts them and
  logs their status instead of installing, then adds only VA-API and `lm-sensors`.
- **Debian installs the lot.** `linux-image-*-amd64` carries no such dependency and nothing
  pulls non-free firmware after installation, so the script installs microcode, Intel or AMD
  GPU firmware, `firmware-sof-signed` for the Intel SOF audio DSP, and the Wi-Fi and
  speaker-amp firmware most laptops need to have working network and sound at all.

Radio and audio firmware is installed for **both** vendors rather than split by CPU: Wi-Fi
vendor does not track CPU vendor, and Intel Wi-Fi is common in AMD laptops. Only microcode,
iGPU firmware and the VA-API driver follow the CPU.

Worth knowing before you run it:

- **Debian needs the `non-free-firmware` component**, where every microcode and firmware
  package lives. The installer enables it whenever it installed non-free firmware during
  setup, which is near-universal on real hardware. If it did not, the script names the
  unreachable packages and continues rather than failing: add `non-free-firmware` to the
  `Components:` line of `/etc/apt/sources.list.d/debian.sources` — trixie uses deb822, not
  the old one-line `sources.list` — then `sudo apt update` and re-run.
- **Microcode and firmware load at boot.** Reboot before checking whether anything changed.
- **No TLP.** `tlp` declares `Conflicts: power-profiles-daemon`, so installing it removes
  GNOME's power manager along with the power-mode selector in Settings. The script leaves
  `power-profiles-daemon` alone and warns if it is inactive or if `tlp` is already there.
- **`sensors-detect` is not run.** Its own man page warns that `--auto` "isn't necessarily
  safe as the internal logic may lead to potentially dangerous probes being attempted", up
  to SMBus lockup. CPU temperature does not need it — `coretemp` and `k10temp` autoload from
  the modalias. Run it by hand if you also want Super-I/O fan and voltage readings.
- Debian pins `firmware-nonfree` at the trixie release snapshot. Very new hardware may need
  the newer build in `trixie-backports`, which the script will not add for you.

## Configure

```bash
JAVA_VERSION="25.0.2-open"   # SDKMAN identifier; empty = skip
NODE_VERSION="lts/*"         # empty = skip

INSTALL_HARDWARE_ENABLEMENT=true
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
```

## What it installs

| Group | Tools |
|---|---|
| Base | curl, wget, redis-tools, zip/unzip, build-essential, ca-certificates, gnupg, apt-transport-https, lsb-release, xdg-utils — plus the codecs and fonts named in the distro sections above |
| Hardware | Bare-metal x86-64 only: CPU microcode, Wi-Fi/audio/GPU firmware, VA-API video decode, lm-sensors — chosen per CPU vendor. See [Hardware](#hardware) |
| Firewall | ufw — deny all inbound, allow outbound, low logging |
| Runtimes | Java via SDKMAN, Node via nvm |
| Containers / k8s | Docker + compose plugin, kubectl, Helm, Lens |
| Cloud / IaC | AWS CLI v2, Terraform, Google Cloud CLI |
| AI | Claude Code, nono (sandbox) |
| Apps | Brave (default browser), Chromium (Debian only), JetBrains Toolbox, Sublime Text, Slack, MongoDB Compass, Insomnia, Deluge, VLC, Proton VPN |
| Shell | `~/.local/bin` on `PATH`; `k` (kubectl), `g` (gcloud), `t` (terraform), `nonoclaude` aliases appended to `~/.bashrc` |

## Good to know

- **Check the clock before running.** A guest clock behind real time makes apt reject
  freshly published repository metadata — `Release file ... is not valid yet` — which
  reads as a broken repo rather than a clock problem.
- **A failure stops the run.** The script is linear under `set -euo pipefail`, so the
  first failing command ends it. Slack, Lens and Insomnia are amd64-only and skip
  themselves on arm64; anything else lacking a build for your architecture needs its flag
  set to `false`, or its section deleted if it has no flag (Brave, JetBrains Toolbox, Sublime).
  Re-running is cheap: every section checks whether the tool is already there.
- **Firefox is removed and Brave becomes the default.** What `REMOVE_FIREFOX` actually purges
  differs per distro. The default is set with `xdg-settings` and re-asserted on every run.
- **Docker bypasses the firewall.** Published ports write their own iptables rules ahead
  of ufw's chains, so ufw cannot filter them. `DOCKER_BIND_LOOPBACK` writes
  `{"ip": "127.0.0.1"}` to `/etc/docker/daemon.json` so published ports default to
  loopback. Publish explicitly — `-p 0.0.0.0:8080:80` — when a container really must be
  reachable, including from the Mac host.
- **Proton VPN's tray icon needs a GNOME extension.** The script installs
  `gnome-shell-extension-appindicator`. Ubuntu enables it by default; on Debian enable it once
  in the Extensions app and log back in, otherwise the app runs without a tray icon.
- **Log** — `$HOME/ubuntu.log`, `$HOME/debian.log` or `$HOME/fedora.log`, appended across runs. It holds the
  script's own progress lines, not apt or curl output.
