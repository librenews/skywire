# DigitalOcean Deployment Guide

## Prerequisites

1. **DigitalOcean Managed PostgreSQL Database**
   - Created and running
   - Note the connection string

2. **Droplet or App Platform**
   - For Droplet: Docker installed
   - For App Platform: GitHub repo connected

---

## Option 1: DigitalOcean App Platform (Easiest)

### Step 1: Connect GitHub
1. Go to **App Platform** → **Create App**
2. Connect your GitHub repo: `librenews/skywire`
3. Select branch: `main`

### Step 2: Configure App
- **Type**: Web Service
- **Dockerfile Path**: `Dockerfile`
- **HTTP Port**: 4000

### Step 3: Attach Database
1. In the app settings, click **Create/Attach Database**
2. Select your existing managed PostgreSQL
3. DigitalOcean will auto-inject `${db.DATABASE_URL}`

### Step 4: Set Environment Variables
In App Platform → Settings → Environment Variables:

> **⚠️ IMPORTANT**: Do NOT use `${db.DATABASE_URL}` - it doesn't work with custom Dockerfiles!

Instead, copy the **actual connection string** from your database:

```
DATABASE_URL=postgresql://doadmin:PASSWORD@db-postgresql-nyc3-12345-do-user-123456-0.b.db.ondigitalocean.com:25060/defaultdb?sslmode=require
SECRET_KEY_BASE=<your generated secret>
PHX_SERVER=true
EVENT_RETENTION_DAYS=7
```

**How to get the connection string:**
1. Go to your Managed Database
2. Click "Connection Details"
3. Copy the full "Connection String"
4. Paste it as the value for `DATABASE_URL`


### Step 5: Deploy
Click **Deploy** - DigitalOcean builds and deploys automatically!

---

## Option 2: DigitalOcean Droplet (VPS)

### Step 1: Get Database Connection String
1. Go to your **Managed Database**
2. Click **Connection Details**
3. Copy the **Connection String**:
   ```
   postgresql://doadmin:password@db-postgresql-nyc3-12345.ondigitalocean.com:25060/defaultdb?sslmode=require
   ```

### Step 2: SSH into Droplet
```bash
ssh root@your-droplet-ip
```

### Step 3: Install Docker (if not installed)
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Install Docker Compose
apt-get install docker-compose-plugin
```

### Step 4: Clone Your Repo
```bash
git clone git@github.com:librenews/skywire.git
cd skywire
```

### Step 5: Create .env File
```bash
nano .env
```

Paste:
```bash
DATABASE_URL=postgresql://doadmin:YOUR_PASSWORD@db-postgresql-nyc3-12345.ondigitalocean.com:25060/defaultdb?sslmode=require
SECRET_KEY_BASE=<run: mix phx.gen.secret locally and paste>
PHX_HOST=your-droplet-ip-or-domain.com
PHX_SERVER=true
EVENT_RETENTION_DAYS=7
```

Save and exit (Ctrl+X, Y, Enter)

### Step 6: Run Migrations
```bash
# Build the image
docker build -t skywire .

# Run migrations
docker run --env-file .env skywire /app/bin/migrate
```

### Step 7: Start the App
Using Docker Compose:
```bash
docker compose up -d
```

Or using Docker directly:
```bash
docker run -d \
  --name skywire \
  -p 4000:4000 \
  --env-file .env \
  --restart unless-stopped \
  skywire
```

### Step 8: Verify
```bash
# Check logs
docker logs skywire

# Test health endpoint
curl http://localhost:4000/api/health
```

---

## Important: Database Connection Notes

### SSL Mode
DigitalOcean managed databases **require SSL**. Make sure your connection string has:
```
?sslmode=require
```

### Firewall Rules
In DigitalOcean Database settings:
1. Go to **Settings** → **Trusted Sources**
2. Add your Droplet's IP or App Platform IP range

### Connection Pooling
The app is configured with `pool_size: 10` by default. For production, you might want to adjust this in `config/runtime.exs`.

---

## Generate API Token

After deployment:

### App Platform
```bash
# Use the console
doctl apps logs <app-id> --follow

# Or SSH into the container (if enabled)
```

### Droplet
```bash
docker exec -it skywire /app/bin/skywire eval 'Skywire.Release.gen_token("My Consumer")'
```

---

## Monitoring

### Check Health
```bash
curl https://your-domain.com/api/health
```

### View Logs
```bash
# App Platform
doctl apps logs <app-id>

# Droplet
docker logs -f skywire
```

### Restart App
```bash
# App Platform
Redeploy from dashboard

# Droplet
docker restart skywire
# or
docker compose restart
```

---

## Troubleshooting

### Can't Connect to Database
1. Check firewall rules in Database → Trusted Sources
2. Verify connection string has `?sslmode=require`
3. Test connection:
   ```bash
   docker run --rm -it postgres:15 psql "postgresql://doadmin:password@..."
   ```

### App Won't Start
```bash
# Check logs
docker logs skywire

# Common issues:
# - Missing SECRET_KEY_BASE
# - Wrong DATABASE_URL
# - Database not accessible
```

### SSL Certificate Issues
If you see SSL errors, ensure:
```bash
DATABASE_URL=postgresql://...?sslmode=require
```

Not `?sslmode=verify-full` (unless you have the CA cert)
