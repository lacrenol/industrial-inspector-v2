"""
FastAPI-приложение Stroyka (Vertex AI).

Запуск на Ubuntu Server (headless):
  cd /path/to/backend
  source ~/myenv/bin/activate
  python3 -m uvicorn app_vertex:app --host 0.0.0.0 --port 8000

Авторизация только через ADC. API-ключи не используются.
"""

import logging
import sys
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from ai_manager import QuotaExceededError, VertexAIError, VertexAIManager

# Логирование в stdout для headless (systemd, Docker)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Stroyka API (Vertex AI)",
    description="Backend для проекта Stroyka на базе Gemini 2.0 через Vertex AI, ADC.",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class PlanRequest(BaseModel):
    """Текстовое описание строительной задачи."""

    task_description: str


class PlanResponse(BaseModel):
    """Структурированный план (от Gemini)."""

    plan: dict[str, Any]


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "stroyka-vertex"}


@app.post("/plan", response_model=PlanResponse)
def get_construction_plan(request: PlanRequest) -> PlanResponse:
    """
    Принимает текстовое описание строительной задачи,
    возвращает структурированный план от Gemini 2.0 (Vertex AI).
    """
    if not request.task_description or not request.task_description.strip():
        raise HTTPException(status_code=400, detail="task_description is required")

    try:
        manager = VertexAIManager.get_instance()
        plan = manager.generate_structured_plan(request.task_description)
        return PlanResponse(plan=plan)
    except QuotaExceededError as e:
        logger.warning("Quota exceeded: %s", e)
        raise HTTPException(status_code=429, detail="Quota exceeded. Try again later.") from e
    except VertexAIError as e:
        logger.exception("Vertex AI error: %s", e)
        raise HTTPException(status_code=502, detail=str(e)) from e
