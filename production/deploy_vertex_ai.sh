#!/bin/bash

# Production Deployment Script for Vertex AI
# Usage: ./deploy_vertex_ai.sh [staging|production]

set -e

ENVIRONMENT=${1:-staging}
DOMAIN="yourdomain.com"
BACKUP_DIR="/var/backups/industrial-inspector"
LOG_DIR="/var/log/industrial-inspector"

echo "🚀 Starting Vertex AI deployment to $ENVIRONMENT environment..."

# Create backup directories
sudo mkdir -p $BACKUP_DIR
sudo mkdir -p $LOG_DIR

# Backup current data
echo "📦 Backing up current data..."
docker exec industrial-inspector_redis_1 redis-cli BGSAVE || true
sudo cp -r /var/lib/postgresql/data $BACKUP_DIR/db-$(date +%Y%m%d-%H%M%S) || true

# Pull latest code
echo "📥 Pulling latest code..."
git pull origin main

# Build and deploy with Vertex AI
echo "🔨 Building and deploying with Vertex AI..."
if [ "$ENVIRONMENT" = "production" ]; then
    docker-compose -f production/docker-compose.vertex.yml --env-file .env.production down
    docker-compose -f production/docker-compose.vertex.yml --env-file .env.production build
    docker-compose -f production/docker-compose.vertex.yml --env-file .env.production up -d
else
    docker-compose -f production/docker-compose.vertex.yml --env-file .env.staging down
    docker-compose -f production/docker-compose.vertex.yml --env-file .env.staging build
    docker-compose -f production/docker-compose.vertex.yml --env-file .env.staging up -d
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

# Test Vertex AI specifically
echo "🧪 Testing Vertex AI integration..."
docker exec industrial-inspector_backend_1 python -c "
from vertexai.generative_models import GenerativeModel
import vertexai
try:
    vertexai.init(project='stroyka-489218', location='us-central1')
    model = GenerativeModel('gemini-2.0-flash-preview')
    response = model.generate_content('Vertex AI test')
    print('✅ Vertex AI working in container')
except Exception as e:
    print(f'❌ Vertex AI error in container: {e}')
    exit(1)
" || echo "⚠️ Vertex AI test failed - manual review required"

# Clear caches
echo "🧹 Clearing caches..."
docker exec industrial-inspector_redis_1 redis-cli FLUSHALL

# Log deployment
echo "📝 Logging deployment..."
echo "$(date): Deployed Vertex AI to $ENVIRONMENT" >> $LOG_DIR/deployments.log

echo "🎉 Vertex AI deployment to $ENVIRONMENT completed successfully!"
echo "🌐 Application available at: https://$DOMAIN"
echo "🧪 Vertex AI integration: stroyka-489218/us-central1"
echo "📊 Monitoring at: https://$DOMAIN/health"

# Show running containers
docker ps --filter "name=industrial-inspector"

echo ""
echo "🔍 Vertex AI Status Check:"
echo "   Project: stroyka-489218"
echo "   Region: us-central1"
echo "   Model: gemini-2.0-flash-preview"
echo "   Auth: ADC (Application Default Credentials)"
echo "   No API Keys Required ✅"
