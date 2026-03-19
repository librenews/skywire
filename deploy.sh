#!/bin/bash
set -e

echo "🚀 Deploying Skywire..."

# Discard any stale local changes (from sed commands, manual edits, etc.)
# and pull latest — always use this script instead of running git pull directly
git checkout -- .
git pull origin main

# Build the production track image
echo "🔨 Building production image..."
docker compose build track

# Restart all services
echo "♻️  Restarting services..."
docker compose rm -sf track
docker compose up -d

# Ensure all databases exist and are migrated
echo "🗄️  Preparing databases..."
docker compose exec track bin/rails db:create db:schema:load 2>/dev/null || true
docker compose exec track bin/rails db:migrate 2>/dev/null || true

echo "✅ Deploy complete!"
echo "   Logs: docker compose logs --tail 30 track"
