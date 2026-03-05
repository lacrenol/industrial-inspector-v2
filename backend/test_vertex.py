#!/usr/bin/env python3
"""
Диагностический скрипт для проверки доступа к Vertex AI (Gemini) через google-genai.
Использует vertexai=True и явный quota_project_id = stroyka-489218.
Если скрипт вернёт 404 — API может быть отключено или зависло;
попробуйте: gcloud services disable aiplatform.googleapis.com --force
             gcloud services enable aiplatform.googleapis.com
"""

import os
import sys

# Явно задаём quota project для биллинга/квот
os.environ.setdefault("GOOGLE_CLOUD_QUOTA_PROJECT", "stroyka-489218")

def main():
    try:
        from google import genai
    except ImportError:
        print("ERROR: Package 'google-genai' not installed.")
        print("Run: pip install google-genai")
        sys.exit(1)

    project_id = "stroyka-489218"
    location = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")

    print("Vertex AI diagnostic (google-genai, vertexai=True)")
    print(f"  project_id = {project_id}")
    print(f"  location  = {location}")
    print(f"  GOOGLE_CLOUD_QUOTA_PROJECT = {os.environ.get('GOOGLE_CLOUD_QUOTA_PROJECT', 'not set')}")
    print()

    try:
        # Клиент Vertex AI; quota_project_id задаётся через env GOOGLE_CLOUD_QUOTA_PROJECT
        # или через credentials. Для явной передачи в клиент смотрим, поддерживает ли API.
        client = genai.Client(
            vertexai=True,
            project=project_id,
            location=location,
        )
        print("Client created successfully.")
    except Exception as e:
        print(f"ERROR creating Client: {type(e).__name__}: {e}")
        sys.exit(2)

    model_name = "gemini-1.5-flash-002"
    print(f"Calling generate_content (model={model_name})...")

    try:
        response = client.models.generate_content(
            model=model_name,
            contents="Reply with exactly: OK",
        )
        text = getattr(response, "text", None) or str(response)
        print(f"Response: {text[:200]}")
        print("SUCCESS: Vertex AI API is reachable.")
        return 0
    except Exception as e:
        err_type = type(e).__name__
        err_msg = str(e)
        print(f"ERROR: {err_type}: {err_msg}")

        if "404" in err_msg or "NOT_FOUND" in err_msg.upper():
            print()
            print(">>> 404/NOT_FOUND: API or model may be disabled or stuck.")
            print(">>> Try restarting the Vertex AI API:")
            print("    gcloud services disable aiplatform.googleapis.com --force")
            print("    gcloud services enable aiplatform.googleapis.com")
            print(">>> Or enable it if never enabled:")
            print("    gcloud services enable aiplatform.googleapis.com")
            sys.exit(404)
        if "403" in err_msg or "PERMISSION_DENIED" in err_msg.upper():
            print()
            print(">>> 403: Check IAM (Vertex AI User / appropriate role) and billing.")
            sys.exit(403)
        if "DefaultCredentialsError" in err_type or "credentials" in err_msg.lower():
            print()
            print(">>> No credentials: set up Application Default Credentials.")
            print("    Local: gcloud auth application-default login")
            print("    Server: set GOOGLE_APPLICATION_CREDENTIALS to service account JSON path.")
            sys.exit(401)
        sys.exit(3)

if __name__ == "__main__":
    sys.exit(main())
