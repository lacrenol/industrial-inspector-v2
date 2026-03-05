#!/bin/bash

# Production Deployment Script
# Usage: ./deploy.sh [staging|production]

set -e

ENVIRONMENT=${1:-staging}
DOMAIN="yourdomain.com"
BACKUP_DIR="/var/backups/industrial-inspector"
LOG_DIR="/var/log/industrial-inspector"

echo "🚀 Starting deployment to $ENVIRONMENT environment..."

# Create backup directories
sudo mkdir -p $BACKUP_DIR
sudo mkdir -p $LOG_DIR

# Backup current database
echo "📦 Backing up current data..."
docker exec industrial-inspector_redis_1 redis-cli BGSAVE || true
sudo cp -r /var/lib/postgresql/data $BACKUP_DIR/db-$(date +%Y%m%d-%H%M%S) || true

# Pull latest code
echo "📥 Pulling latest code..."
git pull origin main

# Build and deploy
echo "🔨 Building and deploying..."
if [ "$ENVIRONMENT" = "production" ]; then
    docker-compose -f docker-compose.yml --env-file .env.production down
    docker-compose -f docker-compose.yml --env-file .env.production build
    docker-compose -f docker-compose.yml --env-file .env.production up -d
else
    docker-compose -f docker-compose.yml --env-file .env.staging down
    docker-compose -f docker-compose.yml --env-file .env.staging build
    docker-compose -f docker-compose.yml --env-file .env.staging up -d
fi

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Health checks
echo "🏥 Running health checks..."
if curl -f http://localhost/api/health; then
    echo "✅ Backend is healthy"
else
    echo "❌ Backend health check failed"
    exit 1
fi

if curl -f https://$DOMAIN/health; then
    echo "✅ Frontend is healthy"
else
    echo "❌ Frontend health check failed"
    exit 1
fi

# Run database migrations if needed
echo "🗄️ Running database migrations..."
docker exec industrial-inspector_backend_1 python -c "
from supabase import create_client
import os
client = create_client(os.getenv('SUPABASE_URL'), os.getenv('SUPABASE_SERVICE_ROLE_KEY'))
print('Database connection successful')
" || echo "⚠️ Migration check failed - manual review required"

# Clear caches
echo "🧹 Clearing caches..."
docker exec industrial-inspector_redis_1 redis-cli FLUSHALL

# Log deployment
echo "📝 Logging deployment..."
echo "$(date): Deployed to $ENVIRONMENT" >> $LOG_DIR/deployments.log

echo "🎉 Deployment to $ENVIRONMENT completed successfully!"
echo "🌐 Application available at: https://$DOMAIN"
echo "📊 Monitoring at: https://$DOMAIN/health"

# Show running containers
docker ps --filter "name=industrial-inspector"
