# Small, current Python base. slim keeps the image lean for a homelab demo.
FROM python:3.12-slim

WORKDIR /app

# Install deps first so Docker can cache this layer across code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Flush stdout immediately so the Elastic Agent / Filebeat sees logs in real time.
ENV PYTHONUNBUFFERED=1

EXPOSE 8000

CMD ["python", "app.py"]
