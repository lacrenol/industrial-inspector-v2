#!/bin/bash

# Ready Deploy Script - Everything prepared for server
# Just run this on the server after cloning the repo

set -e

echo "🚀 Ready Deploy Script for Vertex AI"
echo "=================================="

# Check if we're on server
if [ ! -d "/opt/industrial-inspector" ]; then
    echo "❌ Not in /opt/industrial-inspector directory"
    echo "Please run: cd /opt/industrial-inspector && ./production/ready-deploy.sh"
    exit 1
fi

# Create production folder if not exists
if [ ! -d "production" ]; then
    echo "📁 Creating production folder..."
    mkdir -p production
fi

cd production

echo "📋 Creating all configuration files..."

# Create Dockerfile.vertex
cat > Dockerfile.vertex << 'DOCKERFILE_EOF'
FROM python:3.9-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libffi-dev \
    libssl-dev \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY ../requirements_vertex_ai.txt requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY ../backend /app

# Create logs directory
RUN mkdir -p logs

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run the application
CMD ["uvicorn", "main_vertex_ai:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
DOCKERFILE_EOF

echo "✅ Dockerfile.vertex created"

# Create docker-compose.vertex.yml
cat > docker-compose.vertex.yml << 'COMPOSE_EOF'
version: '3.8'

services:
  backend:
    build: 
      context: ..
      dockerfile: production/Dockerfile.vertex
    ports:
      - "8000:8000"
    environment:
      # Supabase Configuration
      - SUPABASE_URL=${SUPABASE_URL:-https://ienrlqnjfnoimuuoxmpp.supabase.co}
      - SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}
      - SUPABASE_BUCKET_IMAGES=${SUPABASE_BUCKET_IMAGES:-defect-images}
      - SUPABASE_BUCKET_REPORTS=${SUPABASE_BUCKET_REPORTS:-defect-reports}
      
      # Vertex AI Configuration (from ADC - no API keys needed)
      - PROJECT_ID=stroyka-489218
      - LOCATION=us-central1
      
      # Application Configuration
      - BACKEND_BASE_URL=${BACKEND_BASE_URL:-http://localhost:8000}
      - NODE_ENV=production
      - DAILY_LIMIT=${DAILY_LIMIT:-1000}
      
    volumes:
      - ./logs:/app/logs
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/nginx/ssl
    depends_on:
      - backend
    restart: unless-stopped

  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    restart: unless-stopped

volumes:
  redis_data:
COMPOSE_EOF

echo "✅ docker-compose.vertex.yml created"

# Create nginx.conf
cat > nginx.conf << 'NGINX_EOF'
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=upload:10m rate=2r/s;

    # Upstream backend
    upstream backend {
        server backend:8000;
    }

    # HTTP server
    server {
        listen 80;
        server_name yourdomain.com www.yourdomain.com;

        # API routes
        location /api/ {
            limit_req zone=api burst=20 nodelay;
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 300s;
            proxy_connect_timeout 75s;
        }

        # File upload routes (stricter rate limiting)
        location /api/defects/analyze {
            limit_req zone=upload burst=5 nodelay;
            client_max_body_size 10M;
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Health check
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
NGINX_EOF

echo "✅ nginx.conf created"

# Create .env.production
cat > .env.production << 'ENV_EOF'
# Supabase Configuration
SUPABASE_URL=https://ienrlqnjfnoimuuoxmpp.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImllbnJscW5qZm5vaW11dW94bXBwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjQ4NDQwOSwiZXhwIjoyMDg4MDYwNDA5fQ.A9L02dvxaaVGmgFEQQVjBCrX-PuFCLdnUjWbLdkrcQg
SUPABASE_BUCKET_IMAGES=defect-images
SUPABASE_BUCKET_REPORTS=defect-reports

# Vertex AI Configuration (ADC - no API keys needed)
PROJECT_ID=stroyka-489218
LOCATION=us-central1

# Server Configuration
BACKEND_BASE_URL=http://localhost:8000
DOMAIN_NAME=yourdomain.com
NODE_ENV=production
DAILY_LIMIT=1000
ENV_EOF

echo "✅ .env.production created"

# Create deploy_vertex_ai.sh
cat > deploy_vertex_ai.sh << 'DEPLOY_EOF'
#!/bin/bash

# Production Deployment Script for Vertex AI
set -e

ENVIRONMENT=${1:-staging}
DOMAIN="yourdomain.com"
BACKUP_DIR="/var/backups/industrial-inspector"
LOG_DIR="/var/log/industrial-inspector"

echo "🚀 Starting Vertex AI deployment to $ENVIRONMENT environment..."

# Create backup directories
sudo mkdir -p $BACKUP_DIR
sudo mkdir -p $LOG_DIR

# Pull latest code
echo "📥 Pulling latest code..."
cd /opt/industrial-inspector
git pull origin master

# Build and deploy with Vertex AI
echo "🔨 Building and deploying with Vertex AI..."
cd production
docker-compose -f docker-compose.vertex.yml down
docker-compose -f docker-compose.vertex.yml build
docker-compose -f docker-compose.vertex.yml up -d

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

echo "🎉 Vertex AI deployment to $ENVIRONMENT completed successfully!"
echo "🌐 Application available at: http://localhost"
echo "🧪 Vertex AI integration: stroyka-489218/us-central1"

# Show running containers
docker ps --filter "name=industrial-inspector"

echo ""
echo "🔍 Vertex AI Status Check:"
echo "   Project: stroyka-489218"
echo "   Region: us-central1"
echo "   Model: gemini-2.0-flash-preview"
echo "   Auth: ADC (Application Default Credentials)"
echo "   No API Keys Required ✅"
DEPLOY_EOF

# Make executable
chmod +x deploy_vertex_ai.sh

echo "✅ deploy_vertex_ai.sh created and made executable"

# Create main_vertex_ai.py in backend folder
cat > ../backend/main_vertex_ai.py << 'MAIN_EOF'
import asyncio
import base64
import io
import json
import os
import time
from datetime import datetime
from typing import List, Optional

from vertexai.generative_models import GenerativeModel, Part
import vertexai
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from PIL import Image
import httpx
from pydantic import BaseModel
from supabase import Client, create_client
from docx import Document

load_dotenv()

# Vertex AI Configuration
PROJECT_ID = "stroyka-489218"
LOCATION = "us-central1"
EXAMINER_INSTRUCTIONS = "Structural engineer. Analyze defect in photo. Classify: A(исправное) B(работоспособное) C(ограниченно) D(аварийное). JSON format: {\"description\": \"...\", \"status_category\": \"A|B|C|D\"}"

# Initialize Vertex AI
vertexai.init(project=PROJECT_ID, location=LOCATION)

# Rate limiting
REQUEST_COUNT = 0
LAST_RESET = datetime.now()
DAILY_LIMIT = 100  # Maximum requests per day

def check_rate_limit():
    global REQUEST_COUNT, LAST_RESET
    
    now = datetime.now()
    if now.date() > LAST_RESET.date():
        REQUEST_COUNT = 0
        LAST_RESET = now
    
    if REQUEST_COUNT >= DAILY_LIMIT:
        raise HTTPException(
            status_code=429, 
            detail=f"Daily limit of {DAILY_LIMIT} requests exceeded. Try again tomorrow."
        )
    
    REQUEST_COUNT += 1
    print(f"DEBUG: Request count: {REQUEST_COUNT}/{DAILY_LIMIT}")

# Supabase Configuration
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
SUPABASE_BUCKET_IMAGES = os.getenv("SUPABASE_BUCKET_IMAGES", "defect-images")
SUPABASE_BUCKET_REPORTS = os.getenv("SUPABASE_BUCKET_REPORTS", "defect-reports")

if not (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY):
    print("WARNING: Missing Supabase configuration")

# Initialize Supabase client
supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

# Initialize FastAPI
app = FastAPI(title="Industrial Defect Examiner API", version="1.0.0")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Pydantic models
class Axis(str):
    X = "X"
    Y = "Y"

class ConstructionType(str):
    Concrete = "Concrete"
    Brick = "Brick"
    Metal = "Metal"
    Roof = "Roof"

class DefectAnalyzeRequest(BaseModel):
    survey_id: str
    image_base64: Optional[str] = None
    image_url: Optional[str] = None
    axis: Axis
    construction_type: ConstructionType
    location: Optional[str] = None

class Defect(BaseModel):
    id: str
    survey_id: str
    image_url: str
    axis: Axis
    construction_type: ConstructionType
    location: Optional[str]
    description: str
    status_category: str

# Helper functions
def _parse_gemini_response(raw: str) -> dict[str, str]:
    """Parse Vertex AI response to extract description and status_category."""
    try:
        # Try to parse as JSON first
        data = json.loads(raw)
        if isinstance(data, dict):
            return {
                "description": data.get("description", "No description provided."),
                "status_category": data.get("status_category", "B")
            }
    except json.JSONDecodeError:
        pass
    
    # If not JSON, try to extract from text
    description = "No description provided."
    status_category = "B"
    
    # Look for description patterns
    if "description" in raw.lower():
        import re
        desc_match = re.search(r'description["\s]*:["\s]*"([^"]+)"', raw, re.IGNORECASE)
        if desc_match:
            description = desc_match.group(1)
    
    # Look for status category patterns
    if "status_category" in raw.lower():
        import re
        status_match = re.search(r'status_category["\s]*:["\s]*"([ABCD])"', raw, re.IGNORECASE)
        if status_match:
            status_category = status_match.group(1)
    
    return {
        "description": description,
        "status_category": status_category
    }

async def _analyze_defect_with_vertex_ai(
    image: Image.Image,
    axis: str,
    construction_type: str,
    location: Optional[str],
) -> dict:
    print(f"DEBUG: Vertex AI analysis started for {construction_type}, axis {axis}")
    
    try:
        model = GenerativeModel("gemini-2.0-flash-preview")
        print("DEBUG: Vertex AI model created")
        
        # Convert PIL image to bytes
        img_byte_arr = io.BytesIO()
        image.save(img_byte_arr, format="JPEG")
        img_bytes = img_byte_arr.getvalue()
        print(f"DEBUG: Image converted to bytes, size: {len(img_bytes)}")
        
        # Create image part for Vertex AI
        image_part = Part.from_data(img_bytes, mime_type="image/jpeg")
        print("DEBUG: Vertex AI image part created")
        
        prompt = f"""
{EXAMINER_INSTRUCTIONS}

Axis: {axis}
Type: {construction_type}
Location: {location or 'N/A'}

JSON format: {{"description": "...", "status_category": "A|B|C|D"}}
"""
        print(f"DEBUG: Prompt length: {len(prompt)} characters")
        
        # Generate content
        response = await asyncio.to_thread(
            model.generate_content,
            [prompt, image_part],
            generation_config={
                "temperature": 0.1,
                "max_output_tokens": 500,
            },
        )
        print("DEBUG: Vertex AI response received")
        
        raw = response.text
        print(f"DEBUG: Vertex AI raw response: {raw[:200]}...")
        
        data = _parse_gemini_response(raw)
        print(f"DEBUG: Parsed response: {data}")
        return data
        
    except Exception as e:
        print(f"DEBUG: Vertex AI analysis failed: {e}")
        return {
            "description": f"Analysis failed: {str(e)}",
            "status_category": "B"
        }

async def _fetch_image_as_pil(url: str) -> Image.Image:
    if not url:
        raise HTTPException(status_code=400, detail="image_url is required when image_base64 is not provided.")
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(url)
        if resp.status_code != 200:
            raise HTTPException(status_code=400, detail=f"Could not fetch image: {resp.status_code}")
        return Image.open(io.BytesIO(resp.content)).convert("RGB")

# API Endpoints
@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

@app.post("/defects/analyze", response_model=Defect)
async def analyze_defect(payload: DefectAnalyzeRequest):
    # Check rate limit
    check_rate_limit()
    
    print(f"DEBUG: Received analyze request for survey_id: {payload.survey_id}")
    
    if not (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY):
        raise HTTPException(status_code=500, detail="Backend is missing environment configuration.")

    # Obtain image either from base64 payload or by downloading from URL.
    image_bytes: Optional[bytes] = None
    if payload.image_base64:
        try:
            image_bytes = base64.b64decode(payload.image_base64)
            image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to decode base64 image: {e}")
    else:
        image = await _fetch_image_as_pil(payload.image_url or "")

    print("DEBUG: Starting Vertex AI analysis")
    gemini_result = await _analyze_defect_with_vertex_ai(
        image=image,
        axis=payload.axis,
        construction_type=payload.construction_type,
        location=payload.location,
    )
    print(f"DEBUG: Vertex AI result: {gemini_result}")

    # If we received raw bytes, upload them to Supabase Storage to obtain a stable public URL.
    image_url_to_store = payload.image_url
    if image_bytes is not None:
        try:
            filename = f"survey-{payload.survey_id}-{int(time.time())}.jpg"
            
            # Upload to Supabase Storage
            upload_result = supabase.storage.from_(SUPABASE_BUCKET_IMAGES).upload(
                path=filename,
                file=image_bytes,
                file_options={"content-type": "image/jpeg"},
            )
            
            # Get public URL
            public_info = supabase.storage.from_(SUPABASE_BUCKET_IMAGES).get_public_url(filename)
            image_url_to_store = public_info.get("publicUrl")
            
            if not image_url_to_store:
                image_url_to_store = f"https://{SUPABASE_URL.replace('https://', '')}.supabase.co/storage/v1/object/public/{SUPABASE_BUCKET_IMAGES}/{filename}"
                
        except Exception as e:
            print(f"WARNING: Failed to upload image to Supabase: {e}")
            image_url_to_store = f"failed-upload-{payload.survey_id}-{int(time.time())}.jpg"

    defect_row = {
        "survey_id": payload.survey_id,
        "image_url": image_url_to_store,
        "axis": payload.axis,
        "construction_type": payload.construction_type,
        "location": payload.location,
        "description": gemini_result["description"],
        "status_category": gemini_result["status_category"],
    }

    try:
        res = supabase.table("defects").insert(defect_row).execute()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save defect: {e}")

    if not res.data:
        raise HTTPException(status_code=500, detail="Supabase did not return defect.")

    row = res.data[0]
    return Defect(
        id=str(row["id"]),
        survey_id=row["survey_id"],
        image_url=row["image_url"],
        axis=row["axis"],
        construction_type=row["construction_type"],
        location=row.get("location"),
        description=row["description"],
        status_category=row["status_category"],
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
MAIN_EOF

echo "✅ main_vertex_ai.py created"

# Create requirements_vertex_ai.txt
cat > ../requirements_vertex_ai.txt << 'REQ_EOF'
fastapi==0.115.0
uvicorn[standard]==0.30.6
python-dotenv==1.0.1
python-docx==1.1.2
google-cloud-aiplatform>=1.38.0
supabase==2.6.0
httpx==0.27.2
Pillow==10.4.0
REQ_EOF

echo "✅ requirements_vertex_ai.txt created"

echo ""
echo "🎉 All files created successfully!"
echo ""
echo "📋 Files created:"
echo "   - Dockerfile.vertex"
echo "   - docker-compose.vertex.yml"
echo "   - nginx.conf"
echo "   - .env.production"
echo "   - deploy_vertex_ai.sh"
echo "   - ../backend/main_vertex_ai.py"
echo "   - ../requirements_vertex_ai.txt"
echo ""
echo "🚀 Now run deployment:"
echo "   ./deploy_vertex_ai.sh production"
echo ""
echo "🧪 After deployment, test with:"
echo "   curl -f http://localhost/api/health"
echo "   curl -X POST http://localhost/api/defects/analyze -H 'Content-Type: application/json' -d '{\"survey_id\": \"test\", \"axis\": \"X\", \"construction_type\": \"Concrete\"}'"
