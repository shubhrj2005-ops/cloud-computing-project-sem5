# ───────────────────────────────────────────────────────────────────────────
#  Dockerfile – Flask Visitor Counter
#  Multi-stage build: builder installs deps, final image is slim
# ───────────────────────────────────────────────────────────────────────────

# ── Stage 1: builder (install Python packages) ─────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /install

# Copy only the requirements file first (layer-cache optimisation)
COPY app/requirements.txt .

# Install dependencies into a local folder (no system-wide install)
RUN pip install --no-cache-dir --prefix=/install/deps -r requirements.txt


# ── Stage 2: final slim image ──────────────────────────────────────────────
FROM python:3.11-slim

# Non-root user for security
RUN groupadd --gid 1001 appuser && \
    useradd  --uid 1001 --gid 1001 --no-create-home appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install/deps /usr/local

# Copy application source
COPY app/ .

# Change ownership
RUN chown -R appuser:appuser /app

USER appuser

# Environment defaults (overrideable at runtime)
ENV FLASK_PORT=5000 \
    REDIS_HOST=redis \
    REDIS_PORT=6379 \
    REDIS_DB=0 \
    APP_TITLE="Cloud Visitor Counter" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

EXPOSE 5000

# Healthcheck so Docker knows when the container is live
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

# Use gunicorn for production-grade serving
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "60", "app:app"]
