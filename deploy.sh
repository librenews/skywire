#!/bin/bash
set -e

echo "🚀 Deploying Skywire..."

# Pull latest code
git pull origin main

# Build the production track image (includes asset compilation)
echo "🔨 Building production images..."
docker compose -f docker-compose.yml -f docker-compose.prod.yml build track

# Restart all services with production overrides
echo "♻️  Restarting services..."
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

echo "✅ Deploy complete! Check logs with:"
echo "   docker compose -f docker-compose.yml -f docker-compose.prod.yml logs --tail 30 track"
