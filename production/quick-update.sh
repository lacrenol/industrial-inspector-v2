#!/bin/bash

# Quick Update - Fast update without full rebuild
# Usage: ./quick-update.sh

set -e

echo "⚡ Quick Update - Industrial Inspector"
echo "===================================="

cd /opt/industrial-inspector

# Pull latest changes
echo "📥 Pulling latest changes..."
git pull origin master

# Restart containers (no rebuild)
echo "🔄 Restarting containers..."
cd production
docker-compose -f docker-compose.vertex.yml restart

# Wait for startup
echo "⏳ Waiting for startup..."
sleep 15

# Health check
echo "🏥 Health check..."
if curl -f http://localhost/api/health > /dev/null 2>&1; then
    echo "✅ Quick update successful!"
else
    echo "❌ Health check failed, running full update..."
    ./update-server.sh
fi

echo "🌐 App available at: http://localhost/api"
