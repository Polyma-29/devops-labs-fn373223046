FROM python:3.12-slim

# Create a non-privileged user and group
RUN useradd --create-home appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Switch to the non-privileged user
USER appuser

# Add a health check using Python's urllib (since slim images lack curl)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

# Use the JSON exec form for CMD
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]