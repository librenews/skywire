# Self-Contained VPS Deployment Guide

This guide assumes you are deploying to a single Ubuntu VPS (DigitalOcean Droplet, Hetzner Cloud, AWS EC2, etc.) where **both** the application and the database will run inside Docker.

## 1. Initial Server Setup

SSH into your server:
```bash
ssh root@your-server-ip
```

Install Docker & Docker Compose:
```bash
# Remove old versions (just in case)
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

# Clone your repo (you may need to generate an SSH key and add it to GitHub first)
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

# Database Configuration (These connect app to the local db container)
DB_USER=skywire
DB_PASSWORD=choose_a_strong_db_password
DB_NAME=skywire

# Hostname (Important for checking origins)
PHX_HOST=your-domain.com

# Skywire Settings
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

## 5. Run Migrations

You need to initialize the database:

```bash
docker compose run --rm app /app/bin/migrate
```

## 6. (Optional but Recommended) Automatic SSL with Caddy

To expose your app securely on `https://your-domain.com`, use Caddy. It handles certificates automatically.

1.  **Install Caddy** (Ubuntu):

    ```bash
    apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    apt install caddy
    ```

2.  **Configure Caddy**:

    ```bash
    nano /etc/caddy/Caddyfile
    ```

    Replace the contents with:

    ```text
    your-domain.com {
        reverse_proxy localhost:4000
    }
    ```

3.  **Reload Caddy**:

    ```bash
    systemctl reload caddy
    ```

Your app is now live at `https://your-domain.com`!

## Maintenance

**Update App:**
```bash
git pull origin main
docker compose build --no-cache
docker compose up -d
docker compose exec app /app/bin/migrate
```

**View Logs:**
```bash
docker compose logs -f --tail=100
```

**Generate API Token:**
```bash
docker compose exec app /app/bin/skywire eval 'Skywire.Release.gen_token("My App")'
```
