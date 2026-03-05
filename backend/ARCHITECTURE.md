# Stroyka Backend — архитектура (Vertex AI)

## Окружение

- **OS:** Ubuntu Server (headless, SSH)
- **Python:** 3.12, виртуальное окружение `~/myenv`
- **Авторизация:** только Application Default Credentials (ADC). Создание API-ключей в организации запрещено.

## Структура каталога

```
backend/
├── ai_manager.py      # Клиент Vertex AI (project=stroyka-489218, location=us-central1)
├── app_vertex.py      # FastAPI-приложение для эндпоинтов на Vertex AI
├── main.py            # Основное приложение (Supabase, прежние эндпоинты; может использовать API key)
├── requirements.txt
├── requirements-vertex.txt   # Минимальные зависимости для запуска только Vertex-части
├── test_vertex.py     # Диагностика подключения к Vertex AI
└── ARCHITECTURE.md    # Этот файл
```

## Рекомендуемая схема

1. **Vertex AI (без API key)** — всё, что связано с Gemini на сервере:
   - `ai_manager.py` — единственная точка входа к Vertex (инициализация через ADC).
   - `app_vertex.py` — FastAPI с эндпоинтами, которые вызывают `VertexAIManager`.

2. **Запуск только Vertex-бэкенда на сервере:**
   ```bash
   source ~/myenv/bin/activate
   pip install -r requirements-vertex.txt
   python3 -m uvicorn app_vertex:app --host 0.0.0.0 --port 8000
   ```

3. **Первый эндпоинт:** `POST /plan` — принимает текстовое описание строительной задачи, возвращает структурированный план (JSON) от Gemini 2.0.

## Обработка ошибок (headless)

- **429 / Quota exceeded:** повторные попытки с экспоненциальной задержкой (см. `ai_manager.py`). В ответе API — 429.
- Логи пишутся в stdout (удобно для systemd, Docker, SSH).

## Зависимости для Vertex-части

В `requirements-vertex.txt`: fastapi, uvicorn, google-genai. Остальное (Supabase, PIL и т.д.) нужно только для `main.py`.
