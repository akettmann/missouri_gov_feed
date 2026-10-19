# Image for Cloud Run jobs (see docs/environment.md). Loaders: `mogov load <source>` with --tasks N on the job
# for sharding; dbt: `mogov build`. Data lives on a mounted volume (Cloud Storage FUSE) at MOGOV_DATA_DIR.
FROM python:3.13-slim

COPY --from=ghcr.io/astral-sh/uv:0.6.17 /uv /usr/local/bin/uv

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    MOGOV_DATA_DIR=/data \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY src ./src
COPY dbt ./dbt
RUN uv sync --frozen --no-dev

ENTRYPOINT ["mogov"]
CMD ["--help"]
