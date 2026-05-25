# ── Stage 1: dependency install ──────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# Pin requirements before installing — never install into the final image as root
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: hardened runtime ─────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

# Create a dedicated non-root user and group.
# Reason: container escape via root gives node-level access; UID 1001 avoids
# collision with common host UIDs while remaining unprivileged.
RUN groupadd --gid 1001 appgroup \
    && useradd --uid 1001 --gid appgroup --no-create-home --shell /sbin/nologin appuser

WORKDIR /app

# Copy installed packages from builder layer
COPY --from=builder /install /usr/local

# Copy application source
COPY --chown=appuser:appgroup app.py .

# Switch to non-root before the process starts
USER appuser

EXPOSE 5000

# Use gunicorn (production WSGI server).
# --tmp-dir /tmp: gunicorn needs a writable temp dir; we mount an emptyDir
# at /tmp in the K8s pod spec so readOnlyRootFilesystem=true still works.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--tmp-dir", "/tmp", "app:app"]
