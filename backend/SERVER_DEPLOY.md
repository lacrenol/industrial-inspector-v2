# Запуск на сервере (Ubuntu, SSH)

Чтобы бэкенд работал и к нему можно было обращаться (сайт/документация/мобильное приложение).

---

## 1. Перенос файлов на сервер

По SSH скопируйте папку `backend` на сервер, например в `/opt/stroyka/backend`:

```bash
# С вашего ПК (в папке build):
scp -r backend USER@SERVER_IP:/opt/stroyka/
```

Или через git (если репозиторий есть):

```bash
# На сервере:
sudo mkdir -p /opt/stroyka && sudo chown $USER /opt/stroyka
git clone YOUR_REPO /opt/stroyka
# тогда бэкенд будет в /opt/stroyka/backend
```

---

## 2. Окружение на сервере

```bash
ssh USER@SERVER_IP
cd /opt/stroyka/backend

# Виртуальное окружение (если ещё нет ~/myenv)
python3.12 -m venv .venv
source .venv/bin/activate

# Зависимости для Vertex-бэкенда (только API план + health/docs)
pip install -r requirements-vertex.txt
```

ADC уже настроены (`gcloud auth application-default login` и `set-quota-project` делались ранее).

---

## 3. Запуск (чтобы «сайт грузился»)

### Вариант A: Вручную в терминале

```bash
cd /opt/stroyka/backend
source .venv/bin/activate   # или: source ~/myenv/bin/activate
python3 -m uvicorn app_vertex:app --host 0.0.0.0 --port 8000
```

- Документация API (сайт): **http://SERVER_IP:8000/docs**
- Health: **http://SERVER_IP:8000/health**
- После закрытия SSH процесс завершится.

### Вариант B: Скрипт

```bash
cd /opt/stroyka/backend
chmod +x run_server.sh
./run_server.sh
```

Тот же эффект, что в варианте A.

### Вариант C: Постоянно через systemd (рекомендуется)

```bash
cd /opt/stroyka/backend
sudo cp stroyka-backend.service /etc/systemd/system/
sudo sed -i "s/YOUR_USER/$USER/" /etc/systemd/system/stroyka-backend.service
sudo sed -i "s|/opt/stroyka/backend|$(pwd)|g" /etc/systemd/system/stroyka-backend.service
sudo systemctl daemon-reload
sudo systemctl enable stroyka-backend
sudo systemctl start stroyka-backend
sudo systemctl status stroyka-backend
```

После этого бэкенд поднимается после перезагрузки и не падает при отключении SSH.

---

## 4. Доступ снаружи (чтобы «сайт грузился» с вашего ПК/телефона)

1. **Файрвол на сервере** — откройте порт 8000:
   ```bash
   sudo ufw allow 8000/tcp
   sudo ufw reload
   ```

2. **Адрес для браузера и приложения:**
   - Документация (сайт): **http://ВАШ_IP_СЕРВЕРА:8000/docs**
   - В мобильном приложении в `mobile/src/config.ts` укажите:
     ```ts
     export const BACKEND_BASE_URL = "http://ВАШ_IP_СЕРВЕРА:8000";
     ```

3. Если сервер в облаке (GCP и т.д.) — в VPC/firewall тоже разрешите входящий трафик на порт 8000.

---

## 5. Проверка

- В браузере: **http://SERVER_IP:8000/docs** — должна открыться Swagger-страница.
- В терминале:
  ```bash
  curl http://127.0.0.1:8000/health
  curl -X POST http://127.0.0.1:8000/plan -H "Content-Type: application/json" -d '{"task_description":"Фундамент 6x8 м"}'
  ```

Если нужен полный бэкенд с Supabase и фото (main.py), на сервере понадобятся `.env` с ключами и `pip install -r requirements.txt`, а запуск: `uvicorn main:app --host 0.0.0.0 --port 8000` (или второй systemd-unit на другом порту).
