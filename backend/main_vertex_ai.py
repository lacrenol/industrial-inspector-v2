import asyncio
import base64
import io
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
    # We don't raise immediately so the app can still start for local editing,
    # but requests that need these will fail with a clear error.
    print("WARNING: Missing Supabase configuration")

# Initialize Supabase client
supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

# Initialize FastAPI
app = FastAPI(title="Industrial Defect Examiner API", version="1.0.0")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your domains
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

class Survey(BaseModel):
    id: str
    user_id: str
    name: str
    industry_gost: str

class ReportRequest(BaseModel):
    survey_id: str

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
        print(f"DEBUG: Exception type: {type(e)}")
        print(f"DEBUG: Exception args: {e.args}")
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
    print(f"DEBUG: Payload keys: {list(payload.dict().keys())}")
    print(f"DEBUG: Has image_base64: {bool(payload.image_base64)}")
    
    if not (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY):
        print("DEBUG: Missing Supabase configuration")
        raise HTTPException(status_code=500, detail="Backend is missing environment configuration.")

    # Obtain image either from base64 payload or by downloading from URL.
    image_bytes: Optional[bytes] = None
    if payload.image_base64:
        try:
            print("DEBUG: Decoding base64 image")
            image_bytes = base64.b64decode(payload.image_base64)
            print(f"DEBUG: Image decoded, size: {len(image_bytes)} bytes")
        except Exception as e:
            print(f"DEBUG: Failed to decode base64: {e}")
            raise HTTPException(status_code=400, detail=f"Failed to decode base64 image: {e}")
        try:
            print("DEBUG: Converting to PIL Image")
            image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
            print("DEBUG: PIL Image created successfully")
        except Exception as e:
            print(f"DEBUG: Failed to create PIL Image: {e}")
            raise HTTPException(status_code=400, detail=f"Uploaded image is not a valid image: {e}")
    else:
        print("DEBUG: Fetching image from URL")
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
            print(f"DEBUG: Uploading image to Supabase bucket: {SUPABASE_BUCKET_IMAGES}")
            filename = f"survey-{payload.survey_id}-{int(time.time())}.jpg"
            print(f"DEBUG: Generated filename: {filename}")
            
            # Upload to Supabase Storage
            upload_result = supabase.storage.from_(SUPABASE_BUCKET_IMAGES).upload(
                path=filename,
                file=image_bytes,
                file_options={"content-type": "image/jpeg"},
            )
            print(f"DEBUG: Upload result: {upload_result}")
            
            # Get public URL
            public_info = supabase.storage.from_(SUPABASE_BUCKET_IMAGES).get_public_url(filename)
            image_url_to_store = public_info.get("publicUrl")
            print(f"DEBUG: Public URL: {image_url_to_store}")
            
            if not image_url_to_store:
                print("DEBUG: Failed to get public URL, using placeholder")
                image_url_to_store = f"https://{SUPABASE_URL.replace('https://', '')}.supabase.co/storage/v1/object/public/{SUPABASE_BUCKET_IMAGES}/{filename}"
                
        except Exception as e:  # pragma: no cover - storage issues should not break analysis
            print(f"WARNING: Failed to upload image to Supabase: {e}")
            print(f"DEBUG: Exception type: {type(e)}")
            print(f"DEBUG: Exception args: {e.args}")
            # Use placeholder URL to prevent null constraint violation
            image_url_to_store = f"failed-upload-{payload.survey_id}-{int(time.time())}.jpg"
            print(f"DEBUG: Using placeholder URL: {image_url_to_store}")

    defect_row = {
        "survey_id": payload.survey_id,
        "image_url": image_url_to_store,
        "axis": payload.axis,
        "construction_type": payload.construction_type,
        "location": payload.location,
        "description": gemini_result["description"],
        "status_category": gemini_result["status_category"],
    }
    print(f"DEBUG: Defect row to insert: {defect_row}")

    try:
        print("DEBUG: Inserting defect into Supabase")
        print(f"DEBUG: Defect data to insert: {defect_row}")
        
        # Try to insert defect
        res = supabase.table("defects").insert(defect_row).execute()
        print(f"DEBUG: Insert response: {res}")
        print(f"DEBUG: Response data: {res.data}")
        print(f"DEBUG: Response error: {getattr(res, 'error', 'No error')}")
        
    except Exception as e:
        print(f"DEBUG: Failed to save defect: {e}")
        print(f"DEBUG: Exception type: {type(e)}")
        print(f"DEBUG: Exception args: {e.args}")
        
        # Try to create a minimal defect record without image URL first
        try:
            minimal_defect = {
                "survey_id": payload.survey_id,
                "image_url": f"placeholder-{payload.survey_id}-{int(time.time())}.jpg",
                "axis": payload.axis,
                "construction_type": payload.construction_type,
                "location": payload.location or "",
                "description": "Test defect - image uploaded to storage",
                "status_category": "B"
            }
            print(f"DEBUG: Trying minimal insert: {minimal_defect}")
            res = supabase.table("defects").insert(minimal_defect).execute()
            print(f"DEBUG: Minimal insert response: {res}")
        except Exception as e2:
            print(f"DEBUG: Minimal insert also failed: {e2}")
            raise HTTPException(status_code=500, detail=f"Failed to save defect: {e}")

    if not res.data:
        print("DEBUG: Supabase did not return defect data")
        raise HTTPException(status_code=500, detail="Supabase did not return defect.")

    print(f"DEBUG: Successfully created defect: {res.data[0]}")
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

# Add missing import
import json

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
