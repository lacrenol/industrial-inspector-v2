#!/bin/bash

# Update Server Script - Pull latest changes and redeploy
# Usage: ./update-server.sh [production|staging]

set -e

ENVIRONMENT=${1:-production}
BACKUP_DIR="/var/backups/industrial-inspector"
LOG_DIR="/var/log/industrial-inspector"

echo "🔄 Updating Industrial Inspector Server"
echo "======================================"
echo "Environment: $ENVIRONMENT"
echo "Timestamp: $(date)"
echo ""

# Check if we're in the right directory
if [ ! -d "/opt/industrial-inspector" ]; then
    echo "❌ Not in /opt/industrial-inspector directory"
    echo "Please run: cd /opt/industrial-inspector && ./production/update-server.sh"
    exit 1
fi

cd /opt/industrial-inspector

# Create backup directories
sudo mkdir -p $BACKUP_DIR
sudo mkdir -p $LOG_DIR

# Backup current data
echo "📦 Creating backup..."
sudo cp -r production $BACKUP_DIR/production-$(date +%Y%m%d-%H%M%S) || true
docker-compose -f production/docker-compose.vertex.yml exec -T redis redis-cli BGSAVE || true
echo "✅ Backup completed"

# Pull latest changes
echo "📥 Pulling latest changes from repository..."
git pull origin master
echo "✅ Latest code pulled"

# Check if production folder exists, create if not
if [ ! -d "production" ]; then
    echo "📁 Production folder missing, running ready-deploy..."
    chmod +x production/ready-deploy.sh
    ./production/ready-deploy.sh
fi

cd production

# Update Docker images
echo "🐳 Updating Docker images..."
docker-compose -f docker-compose.vertex.yml pull
echo "✅ Docker images updated"

# Build new images
echo "🔨 Building new Docker images..."
docker-compose -f docker-compose.vertex.yml build --no-cache
echo "✅ Docker images built"

# Stop old containers
echo "🛑 Stopping old containers..."
docker-compose -f docker-compose.vertex.yml down
echo "✅ Old containers stopped"

# Start new containers
echo "🚀 Starting new containers..."
docker-compose -f docker-compose.vertex.yml up -d
echo "✅ New containers started"

# Wait for services to be ready
echo "⏳ Waiting for services to start (30 seconds)..."
sleep 30

# Health checks
echo "🏥 Running health checks..."

# Check backend health
echo "Checking backend..."
if curl -f http://localhost/api/health > /dev/null 2>&1; then
    echo "✅ Backend is healthy"
else
    echo "❌ Backend health check failed"
    echo "📋 Backend logs:"
    docker-compose -f docker-compose.vertex.yml logs backend
    exit 1
fi

# Check containers status
echo "📊 Checking container status..."
docker-compose -f docker-compose.vertex.yml ps

# Test Vertex AI integration
echo "🧪 Testing Vertex AI integration..."
docker-compose -f docker-compose.vertex.yml exec -T backend python -c "
from vertexai.generative_models import GenerativeModel
import vertexai
try:
    vertexai.init(project='stroyka-489218', location='us-central1')
    model = GenerativeModel('gemini-2.0-flash-preview')
    response = model.generate_content('Test')
    print('✅ Vertex AI working correctly')
except Exception as e:
    print(f'❌ Vertex AI error: {e}')
    exit(1)
" || echo "⚠️ Vertex AI test failed - check logs"

# Update mobile app configuration if needed
echo "📱 Checking mobile app configuration..."
if [ -f "../mobile/src/config.ts" ]; then
    echo "Mobile config found, checking URL..."
    grep -q "BACKEND_BASE_URL" ../mobile/src/config.ts && echo "✅ Mobile config OK" || echo "⚠️ Mobile config may need update"
fi

# Log update
echo "📝 Logging update..."
echo "$(date): Updated to latest version - Environment: $ENVIRONMENT" >> $LOG_DIR/updates.log

# Show final status
echo ""
echo "🎉 Update completed successfully!"
echo "================================"
echo "🌐 Application: http://localhost"
echo "🔗 API: http://localhost/api"
echo "🏥 Health: http://localhost/api/health"
echo "📊 Containers: docker-compose -f production/docker-compose.vertex.yml ps"
echo "📋 Logs: docker-compose -f production/docker-compose.vertex.yml logs -f"
echo ""
echo "🔍 Vertex AI Status:"
echo "   Project: stroyka-489218"
echo "   Region: us-central1"
echo "   Model: gemini-2.0-flash-preview"
echo "   Auth: ADC (Application Default Credentials)"
echo ""
echo "📱 Mobile App Update:"
echo "   Update BACKEND_BASE_URL to: http://$(curl -s ifconfig.me):8000/api"
echo ""

# Show running containers
echo "📋 Running containers:"
docker ps --filter "name=industrial-inspector" || docker ps

echo ""
echo "✅ Server update complete! Ready for use."
