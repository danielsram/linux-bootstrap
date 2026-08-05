# Ubuntu Developer Bootstrap

A single self-contained `bootstrap.sh` that sets up a developer workstation on
Ubuntu 26.04 LTS (`resolute`), on both **arm64** (e.g. a UTM VM on an Apple
Silicon Mac) and **amd64**.

It is idempotent — re-running it is safe and already-completed steps are
skipped. A step that fails does not abort the run: the error is logged and the
step is listed under `FAILED` in the final summary.

## First installation on a clean Ubuntu

```bash
sudo apt update
sudo apt install -y git curl

git clone https://github.com/danielsram/ubuntu-bootstrap.git
cd ubuntu-bootstrap

cp bootstrap.env.example bootstrap.env
nano bootstrap.env          # at minimum GIT_NAME and GIT_EMAIL

./bootstrap.sh
```

Run it as your **regular user, not under sudo** — nvm, SDKMAN and Claude Code
install into `$HOME`, and the Claude Code installer refuses to run under sudo.
The script asks for sudo itself and keeps the ticket alive for the whole run.

When it finishes, **log out and back in** (or reboot) so the new `docker` group
membership takes effect, then start a fresh shell to pick up the aliases:

```bash
exec bash -l
docker run --rm hello-world
```

## Usage

```bash
./bootstrap.sh
```

There are no command-line options — the script takes no arguments. What runs is
decided entirely by the `INSTALL_*` variables in `bootstrap.env`, and the install
order is the sequence of `run` lines in `main()` at the bottom of the script.

To retry after a failure: fix the cause and run it again. Everything already
installed is skipped, so a re-run is cheap.

## Configuration

Everything is driven by variables. Defaults live in the `CONFIGURATION` block at
the top of `bootstrap.sh`; `bootstrap.env` (git-ignored, copied from
`bootstrap.env.example`) overrides them without editing the script.

Version variables left empty are resolved at runtime rather than hardcoded —
`KUBERNETES_MINOR` from `dl.k8s.io/release/stable.txt`, `YQ_VERSION` and
`MONGODB_COMPASS_VERSION` from the GitHub API, the IntelliJ build from the
JetBrains releases API.

## What it installs

| Group | Tools |
|---|---|
| Base | build-essential, ca-certificates, curl, wget, gnupg, git, zip/unzip, apt-transport-https, software-properties-common, lsb-release |
| CLI | jq, yq (mikefarah), htop, net-tools |
| Runtimes | OpenJDK 25 via SDKMAN, Node LTS via nvm, Python 3 + pip + venv |
| Containers / k8s | Docker CE + Compose + Buildx, kubectl, Helm, Lens |
| Cloud / IaC | Terraform, AWS CLI v2, Google Cloud CLI |
| AI | Claude Code (official installer) |
| Apps | Brave, Google Chrome, Sublime Text, IntelliJ IDEA Ultimate, MongoDB Compass, Slack, Spotify, VLC, Zoom, Insomnia, Deluge, ProtonVPN, optionally NordVPN |
| Shell | `k`/`g`/`t` aliases, kubectl + helm completion, nvm and SDKMAN init |

The shell configuration goes into `~/.bashrc` inside a marked block:

```
# >>> ubuntu-bootstrap >>>
...
# <<< ubuntu-bootstrap <<<
```

A re-run replaces that block rather than appending a duplicate, so anything you
write inside it is overwritten.

## ARM64 caveats

These have **no official ARM64 Linux build**: Google Chrome, Slack, Spotify,
Zoom, Insomnia, ProtonVPN. The script attempts them anyway and reports the real
apt/dpkg error under `FAILED`. On an arm64 machine set the corresponding
`INSTALL_*` variables to `false` in `bootstrap.env` to keep the output clean.

IntelliJ IDEA, Brave, Sublime Text, Docker, kubectl, Helm, Terraform, AWS CLI,
Google Cloud CLI and Claude Code all work on arm64.

## Notes on install methods

A few choices are deliberate:

- **yq** — the Ubuntu package named `yq` is a different tool, so mikefarah/yq is
  installed as a binary from GitHub releases into `/usr/local/bin`.
- **Slack and Spotify** — via snap. Slack's `.deb` URL embeds a version that
  cannot be resolved reliably, and Spotify's apt repo key filename embeds a
  fingerprint that gets rotated and silently breaks apt.
- **IntelliJ IDEA** — the official tarball (arch-aware, sha256-verified) is
  extracted to `/opt/intellij-idea-<build>`, with a stable
  `/opt/intellij-idea-ultimate` symlink, an `/usr/local/bin/idea` launcher and a
  `.desktop` entry. The snap is amd64 only.
- **Java** — SDKMAN identifiers are always full versions like `25.0.1-open`;
  there is no bare-major form, so no such string appears in the config. Set
  `JAVA_MAJOR` and `JAVA_VENDOR` and the script picks the newest matching
  identifier from `sdk list java`, reporting the available versions if none
  matches. `JAVA_VERSION` pins one exact identifier and skips the lookup.
- **Third-party apt suites** — Docker and HashiCorp key their repos by Ubuntu
  codename. The script probes `dists/<codename>/Release` and falls back through
  `questing → noble → jammy`, so it keeps working on a release that lands in
  those repos late.

## Log

Everything, including apt and curl output, is teed to
`$HOME/bootstrap-<timestamp>.log` (override with `LOG_FILE`). It contains ANSI
color sequences — read it with `less -R`.
