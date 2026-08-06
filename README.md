# Linux Bootstrap

Two scripts that set up the same workstation, one per distro, on **arm64** and **amd64**. 
Any other architecture exits immediately.

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

## Configure

```bash
JAVA_VERSION="25.0.2-open"   # SDKMAN identifier; empty = skip
NODE_VERSION="lts/*"         # empty = skip

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
| Firewall | ufw — deny all inbound, allow outbound, low logging |
| Runtimes | Java via SDKMAN, Node via nvm |
| Containers / k8s | Docker + compose plugin, kubectl, Helm, Lens |
| Cloud / IaC | AWS CLI v2, Terraform, Google Cloud CLI |
| AI | Claude Code, nono (sandbox) |
| Apps | Brave (default browser), Chromium (Debian only), JetBrains Toolbox, Sublime Text, Slack, MongoDB Compass, Insomnia, Deluge, VLC, Proton VPN CLI |
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
- **Log** — `$HOME/ubuntu.log` or `$HOME/debian.log`, appended across runs. It holds the
  script's own progress lines, not apt or curl output.
