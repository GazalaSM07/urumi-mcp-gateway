FROM python:3.12-slim
RUN pip install --no-cache-dir fastapi==0.115.12 uvicorn[standard]==0.34.1
WORKDIR /app
COPY main.py .
RUN useradd -u 10001 -m app
USER 10001
EXPOSE 8002
CMD uvicorn main:app --host 0.0.0.0 --port ${PORT:-8002}
