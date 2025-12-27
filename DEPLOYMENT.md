# Deployment Guide

## Quick Deploy to Fly.io (Recommended)

### 1. Install Fly CLI
```bash
brew install flyctl
# or
curl -L https://fly.io/install.sh | sh
```

### 2. Login
```bash
fly auth login
```

### 3. Create Postgres Database
```bash
fly postgres create --name skywire-db --region iad
```

### 4. Create App and Deploy
```bash
# In your skywire directory
fly launch --no-deploy

# Attach the database
fly postgres attach skywire-db

# Set secrets
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)

# Deploy!
fly deploy
```

### 5. Verify
```bash
# Check status
fly status

# View logs
fly logs

# Check health
curl https://skywire.fly.dev/api/health
```

### Environment Variables on Fly.io

```bash
# View all secrets
fly secrets list

# Set a secret
fly secrets set EVENT_RETENTION_DAYS=7

# Unset a secret
fly secrets unset SOME_VAR
```

---

## Alternative: Render

### 1. Connect GitHub
1. Go to https://render.com
2. Sign up/login with GitHub
3. Click "New +" → "Web Service"
4. Connect repository: `librenews/skywire`

### 2. Configure Service
- **Name**: skywire
- **Environment**: Elixir
- **Build Command**: `mix deps.get && mix compile`
- **Start Command**: `mix phx.server`

### 3. Add Postgres
1. Click "New +" → "PostgreSQL"
2. Name it `skywire-db`
3. Copy the "Internal Database URL"

### 4. Set Environment Variables
In the Render dashboard, go to "Environment" tab:

```
DATABASE_URL=<paste internal database URL>
SECRET_KEY_BASE=<generate with: mix phx.gen.secret>
PHX_HOST=skywire.onrender.com
PORT=4000
EVENT_RETENTION_DAYS=7
PHX_SERVER=true
MIX_ENV=prod
```

### 5. Deploy
Click "Manual Deploy" → "Deploy latest commit"

---

## Alternative: Railway

### 1. Create Project
1. Go to https://railway.app
2. "New Project" → "Deploy from GitHub repo"
3. Select `librenews/skywire`

### 2. Add Postgres
1. Click "New" → "Database" → "Add PostgreSQL"
2. Railway auto-sets `DATABASE_URL`

### 3. Set Variables
In the "Variables" tab:

```
SECRET_KEY_BASE=<generate with: mix phx.gen.secret>
EVENT_RETENTION_DAYS=7
PHX_SERVER=true
MIX_ENV=prod
PORT=4000
```

### 4. Deploy
Railway auto-deploys on git push

---

## Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | Yes | - | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Yes | - | Phoenix secret (generate with `mix phx.gen.secret`) |
| `PHX_HOST` | No | example.com | Your domain name |
| `PORT` | No | 4000 | HTTP port |
| `EVENT_RETENTION_DAYS` | No | 7 | Days to keep events before trimming |
| `PHX_SERVER` | Yes | - | Set to `true` to start server |
| `MIX_ENV` | No | prod | Environment (prod/dev/test) |

---

## Post-Deployment

### Generate API Token
```bash
# SSH into your Fly.io instance
fly ssh console

# Generate token
/app/bin/skywire eval 'Skywire.Release.gen_token("My Consumer App")'
```

Or create a remote task:
```bash
fly ssh console -C "/app/bin/skywire eval 'Skywire.Release.gen_token(\"My App\")'"
```

### Monitor the Service
```bash
# Fly.io
fly logs
fly status
fly dashboard

# Check health endpoint
curl https://your-app.fly.dev/api/health
```

### Scale Up
```bash
# Fly.io - increase memory
fly scale memory 1024

# Fly.io - add more instances
fly scale count 2
```

---

## Troubleshooting

### Database Connection Issues
```bash
# Fly.io - check database connection
fly postgres connect -a skywire-db

# Verify DATABASE_URL is set
fly secrets list
```

### Migration Issues
```bash
# Fly.io - run migrations manually
fly ssh console -C "/app/bin/migrate"
```

### View Logs
```bash
# Fly.io
fly logs --app skywire

# Render
Check the "Logs" tab in dashboard

# Railway
Check the "Deployments" → "Logs" tab
```
