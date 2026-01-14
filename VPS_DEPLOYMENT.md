# Self-Contained VPS Deployment Guide

This guide assumes you are deploying to a single lightweight VPS (e.g., 2 vCPU, 4GB RAM) where the application, OpenSearch, and Redis will run inside Docker.

## 1. Initial Server Setup

SSH into your server:
```bash
ssh root@your-server-ip
```

Install Docker & Docker Compose:
```bash
# Remove old versions
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done

# Install using the official convenience script
curl -fsSL https://get.docker.com | sh

# Configure System for OpenSearch (Critical!)
# Increase max_map_count for the JVM
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
```

## 2. Clone Repository

```bash
mkdir -p /opt/skywire
cd /opt/skywire

# Clone your repo
git clone https://github.com/librenews/skywire.git .
```

## 3. Configuration

Create your production `.env` file:

```bash
cp .env.example .env
nano .env
```

**Fill in these values:**

```bash
# Phoenix Secret (Generate with: mix phx.gen.secret)
SECRET_KEY_BASE=YOUR_GENERATED_SECRET_KEY

# Cloudflare Workers AI (For Real-time Embeddings)
# If left blank, app runs in "Keyword Only" mode.
CLOUDFLARE_ACCOUNT_ID=your_cf_account_id
CLOUDFLARE_API_TOKEN=your_cf_api_token

# Hostname
PHX_HOST=skywire.your-domain.com

# Settings
EVENT_RETENTION_DAYS=7
```

## 4. Launch

Start the stack:

```bash
docker compose up -d
```

Check logs to ensure it started:

```bash
docker compose logs -f app
```

*Note: The application automatically initializes the OpenSearch indices on startup. No manual migration command is needed.*

## 5. (Optional) Automatic SSL with Caddy

To expose your app securely on `https://your-domain.com`, use Caddy.

1.  **Install Caddy** (Ubuntu):
    ```bash
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    sudo apt update
    sudo apt install caddy
    ```

2.  **Configure Caddy**:
    ```bash
    nano /etc/caddy/Caddyfile
    ```

    Replace contents with:
    ```text
    your-domain.com {
        reverse_proxy localhost:4000
    }
    ```

3.  **Reload Caddy**:
    ```bash
    systemctl reload caddy
    ```

## Maintenance

**Update App:**
```bash
git pull origin main
docker compose build --no-cache
docker compose up -d
```

**View Logs:**
```bash
docker compose logs -f --tail=100
```
