# Ubuntu Developer Bootstrap

## First installation on clean Ubuntu

Install the minimum required tools:

```bash
sudo apt update
sudo apt install -y git curl
```

Clone the repository:

```bash
git clone <your-repository-url>
cd ubuntu-bootstrap
```

Prepare configuration:

```bash
cp bootstrap.env.example bootstrap.env
nano bootstrap.env
```

Run:

```bash
chmod +x setup-dev.sh setup-desktop.sh
./setup-dev.sh
./setup-desktop.sh
```

After installation logout/login or reboot (Docker group permissions).
