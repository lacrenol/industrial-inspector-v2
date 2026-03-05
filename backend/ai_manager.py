"""
Stroyka AI Manager — инициализация Vertex AI через ADC (без API ключей).

Используется только google-genai с vertexai=True, project и location.
Соответствует политике организации: iam.managed.disableServiceAccountApiKeyCreation.
Подходит для headless (Ubuntu Server, SSH).

Quota project задаётся через ADC, например:
  gcloud auth application-default set-quota-project stroyka-489218
"""

from __future__ import annotations

import logging
import os
import time
from typing import Any, Optional

from google import genai
from google.genai import types

logger = logging.getLogger(__name__)

# Константы проекта Stroyka (Vertex AI)
PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "stroyka-489218")
LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")
DEFAULT_MODEL = os.environ.get("STROYKA_GEMINI_MODEL", "gemini-2.0-flash")

# Поведение при превышении квоты и повторных попытках
MAX_RETRIES = 3
INITIAL_BACKOFF = 2.0
MAX_BACKOFF = 60.0


class VertexAIError(Exception):
    """Базовое исключение для ошибок Vertex AI."""

    pass


class QuotaExceededError(VertexAIError):
    """Превышена квота (429 / ResourceExhausted)."""

    pass


class VertexAIManager:
    """
    Клиент Vertex AI для проекта Stroyka.
    Инициализация только через ADC (Application Default Credentials).
    API-ключи не используются.
    """

    _instance: Optional["VertexAIManager"] = None

    def __init__(
        self,
        project_id: str = PROJECT_ID,
        location: str = LOCATION,
        credentials: Any = None,
    ) -> None:
        if credentials is not None:
            logger.warning("Explicit credentials passed; ADC is recommended for headless.")
        self._project_id = project_id
        self._location = location
        self._client = genai.Client(
            vertexai=True,
            project=project_id,
            location=location,
            credentials=credentials,
        )
        logger.info(
            "Vertex AI client initialized: project=%s, location=%s (ADC)",
            project_id,
            location,
        )

    @classmethod
    def get_instance(
        cls,
        project_id: str = PROJECT_ID,
        location: str = LOCATION,
    ) -> "VertexAIManager":
        """Возвращает единственный экземпляр менеджера (singleton)."""
        if cls._instance is None:
            cls._instance = cls(project_id=project_id, location=location)
        return cls._instance

    @property
    def client(self) -> genai.Client:
        return self._client

    def generate_structured_plan(
        self,
        task_description: str,
        model: str = DEFAULT_MODEL,
    ) -> dict[str, Any]:
        """
        Принимает текстовое описание строительной задачи и возвращает
        структурированный план от Gemini (JSON).

        Учитывает квоты: при 429 выполняет повторные попытки с экспоненциальной задержкой.
        Подходит для headless (логирование вместо интерактива).
        """
        user_content = (
            "You are a construction planning assistant. Given a construction task description, "
            "output a structured execution plan. Reply only with valid JSON.\n\n"
            f"Construction task:\n{task_description}\n\n"
            "Provide a JSON object with keys: title (string), steps (array of objects with order, action, duration_estimate), risks (array of strings), materials_mentioned (array of strings)."
        )

        last_error: Optional[Exception] = None
        backoff = INITIAL_BACKOFF

        for attempt in range(1, MAX_RETRIES + 1):
            try:
                response = self._client.models.generate_content(
                    model=model,
                    contents=user_content,
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        temperature=0.2,
                        max_output_tokens=2048,
                    ),
                )
                text = getattr(response, "text", None) or ""
                if not text:
                    raise VertexAIError("Empty response from model")
                import json
                return json.loads(text)
            except Exception as e:
                last_error = e
                err_msg = str(e).lower()
                is_quota = "429" in err_msg or "resource exhausted" in err_msg or "quota" in err_msg
                if is_quota and attempt < MAX_RETRIES:
                    logger.warning(
                        "Quota/rate limit (attempt %s/%s), retrying in %.1fs: %s",
                        attempt,
                        MAX_RETRIES,
                        backoff,
                        e,
                    )
                    time.sleep(backoff)
                    backoff = min(backoff * 2, MAX_BACKOFF)
                else:
                    if is_quota:
                        raise QuotaExceededError(f"Quota exceeded after {MAX_RETRIES} attempts: {e}") from e
                    raise VertexAIError(f"Vertex AI request failed: {e}") from e

        raise VertexAIError(f"Failed after {MAX_RETRIES} attempts: {last_error}") from last_error
