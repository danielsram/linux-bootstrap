# Ubuntu Bootstrap

A single script that sets up a workstation on Ubuntu, on **arm64** and **amd64**. 
Any other architecture exits immediately.

## Run

```bash
./ubuntu-bootstrap.sh
```

Run it as a **regular user, not under sudo** — nvm, SDKMAN and Claude Code install into `$HOME`, 
the Claude Code installer refuses to run under sudo, 
and the docker group would be granted to `root` instead of you.

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
INSTALL_PROTONVPN=true
```

## What it installs

| Group | Tools |
|---|---|
| Base | curl, wget, redis-cli, zip/unzip, build-essential, ca-certificates, gnupg, software-properties-common, apt-transport-https, lsb-release, xdg-utils, ubuntu-restricted-extras |
| Firewall | ufw — deny all inbound, allow outbound, low logging |
| Runtimes | Java via SDKMAN, Node via nvm |
| Containers / k8s | Docker + compose plugin, kubectl, Helm, Lens |
| Cloud / IaC | AWS CLI v2, Terraform, Google Cloud CLI |
| AI | Claude Code, nono (sandbox) |
| Apps | Brave (default browser), Chromium, IntelliJ IDEA Ultimate, Sublime Text, Slack, MongoDB Compass, Insomnia, Deluge, Proton VPN CLI |
| Shell | `~/.local/bin` on `PATH`; `k` (kubectl), `g` (gcloud), `t` (terraform), `nonoclaude` aliases appended to `~/.bashrc` |

redis-cli comes from the `redis-tools` package — there is no package by that name, and
the `redis` metapackage would install and start the server too. IntelliJ, Sublime Text,
Slack and Chromium come from snap.

## Good to know

- **Check the clock before running.** A guest clock behind real time makes apt reject
  freshly published repository metadata — `Release file ... is not valid yet` — which
  reads as a broken repo rather than a clock problem. UTM guests drift whenever the host
  sleeps. If `timedatectl` won't sync (NTP needs UDP 123, which some VM networks drop),
  take the time from an HTTPS response instead:

  ```bash
  sudo timedatectl set-ntp false
  sudo date -s "$(curl -sI https://google.com | grep -i '^date:' | sed 's/^[Dd]ate: //')"
  sudo hwclock --systohc
  ```

- **A failure stops the run.** The script is linear under `set -euo pipefail`, so the
  first failing command ends it. Slack, Lens and Insomnia are amd64-only and skip
  themselves on arm64; anything else lacking a build for your architecture needs its flag
  set to `false`, or its section deleted if it has no flag (Brave, IntelliJ, Sublime).
  Re-running is cheap: every section checks whether the tool is already there.
- **Firefox is removed and Brave becomes the default.** Ubuntu's Firefox is a snap plus a
  small integration deb; `REMOVE_FIREFOX` drops both. The snap's profile survives as a
  snapshot — `snap saved` lists it, `snap restore` brings it back. A release upgrade can
  reinstall the deb, since `ubuntu-desktop` recommends it. The default is set with
  `xdg-settings` and re-asserted on every run, so a manual change to Chromium gets reverted
  next time.
- **Telemetry is removed.** `REMOVE_TELEMETRY` purges `ubuntu-insights` and `ubuntu-report`.
  ubuntu-insights is the active one — installing it enables user timers that collect monthly
  and upload weekly; ubuntu-report only fires when a report is already queued. Both are
  `ubuntu-desktop` recommends, so the desktop is unaffected, and a release upgrade can bring
  them back.
- **Docker bypasses the firewall.** Published ports write their own iptables rules ahead
  of ufw's chains, so ufw cannot filter them. `DOCKER_BIND_LOOPBACK` writes
  `{"ip": "127.0.0.1"}` to `/etc/docker/daemon.json` so published ports default to
  loopback. Publish explicitly — `-p 0.0.0.0:8080:80` — when a container really must be
  reachable, including from the Mac host.
- **Log** — `$HOME/ubuntu-bootstrap.log`, appended across runs. It holds the script's own
  progress lines, not apt or curl output.