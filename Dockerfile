# 腾讯云 CloudBase 云托管 — FastAPI + 前端静态资源（单容器）
ARG BUILD_REV=guazi-unified-v10
FROM node:20-alpine AS frontend-build
WORKDIR /app/frontend
COPY frontend/package.json frontend/package-lock.json* ./
RUN npm install
COPY frontend/ ./
RUN npm run build

FROM python:3.11-slim

WORKDIR /app

COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && python -c "from fastembed import TextEmbedding; TextEmbedding('BAAI/bge-small-zh-v1.5')"

COPY backend/ .
COPY --from=frontend-build /app/frontend/dist ./static

ENV PYTHONPATH=/app
ENV SERVE_STATIC=true
ENV AUTO_SYNC_SQL=false

EXPOSE 8000

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
