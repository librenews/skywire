# GPU Server Deployment Guide (NVIDIA A40)

This guide is for a fresh Ubuntu 22.04+ server with an NVIDIA GPU.

## 1. System & Driver Setup
SSH into your server:
```bash
ssh root@your-server-ip
```

### Install Basic Tools & Docker
```bash
# Update System
apt-get update && apt-get upgrade -y
apt-get install -y curl git nano htop build-essential

# Remove old Docker versions
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do apt-get remove $pkg; done

# Install Docker
curl -fsSL https://get.docker.com | sh
```

### Install NVIDIA Drivers & Container Toolkit (CRITICAL)
This allows Docker to access the GPU.

```bash
# 1. Add NVIDIA Repository
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# 2. Update & Install Toolkit
apt-get update
apt-get install -y nvidia-container-toolkit

# 3. Configure Docker Runtime
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# 4. Verify GPU Access
docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
# (You should see the NVIDIA A40 listed in the output)
```

### Configure System limits (For OpenSearch)
```bash
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
```

## 2. Deploy Application

### Clone Repository
```bash
mkdir -p /opt/skywire
cd /opt/skywire
git clone https://github.com/librenews/skywire.git .
```

### Setup Environment
```bash
cp .env.example .env
nano .env
```
**Edit `.env` values:**
- `SECRET_KEY_BASE`: Generate one (`openssl rand -base64 48`).
- `REDIS_PASSWORD`: Create a strong password.
- `PHX_HOST`: `your-domain.com`.
- `CLOUDFLARE_*`: Leave empty (We are using Local AI!).

### Start the Stack
```bash
docker compose up -d --build
```

### Monitor Startup (Model Download)
The first startup will take ~2-5 minutes as it downloads the 1.5GB embedding model.
```bash
docker compose logs -f app
```
Wait until you see: `[info] Local ML Serving started successfully.`

## 3. (Optional) SSL with Caddy
To expose your app securely on `https://your-domain.com`:

```bash
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -y caddy
```

Edit Caddyfile (`nano /etc/caddy/Caddyfile`):
```text
your-domain.com {
    reverse_proxy localhost:4000
}
```

Reload: `systemctl reload caddy`.
