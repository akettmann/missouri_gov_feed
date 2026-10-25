"""Observability: structlog logging and OpenTelemetry metrics.

Logs: human-readable console output by default; JSON lines when MOGOV_LOG_JSON=1 or when running as a
Cloud Run job (CLOUD_RUN_JOB is set), with `severity`/`message` keys so Cloud Logging parses them.
MOGOV_LOG_LEVEL sets the level (default INFO).
Metrics: exported over OTLP/HTTP when OTEL_EXPORTER_OTLP_ENDPOINT is set (standard OTel env vars apply),
printed to the console at exit when MOGOV_METRICS_CONSOLE=1, otherwise recorded but not exported.
"""

import logging
import os
import sys
import time

import structlog
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import ConsoleMetricExporter, PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource

_configured = False
_shut_down = False


def configure() -> None:
    global _configured
    if _configured:
        return
    _configured = True

    level = getattr(logging, os.environ.get("MOGOV_LOG_LEVEL", "INFO").upper(), logging.INFO)
    as_json = os.environ.get("MOGOV_LOG_JSON", "1" if os.environ.get("CLOUD_RUN_JOB") else "0") == "1"
    renderer = (
        [_cloud_logging_keys, structlog.processors.JSONRenderer()]
        if as_json
        else [structlog.dev.ConsoleRenderer(colors=sys.stderr.isatty())]
    )
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.format_exc_info,
            *renderer,
        ],
        wrapper_class=structlog.make_filtering_bound_logger(level),
        logger_factory=structlog.PrintLoggerFactory(file=sys.stderr),
    )

    readers = []
    if os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT"):
        from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter

        readers.append(PeriodicExportingMetricReader(OTLPMetricExporter()))
    if os.environ.get("MOGOV_METRICS_CONSOLE") == "1":
        readers.append(PeriodicExportingMetricReader(ConsoleMetricExporter(out=sys.stderr)))
    metrics.set_meter_provider(
        MeterProvider(resource=Resource.create({"service.name": "missouri-gov-feed"}), metric_readers=readers)
    )


def _cloud_logging_keys(_logger, _method, event: dict) -> dict:
    """Cloud Logging reads `severity` and `message` from JSON log lines."""
    event["severity"] = event.pop("level", "info").upper()
    event["message"] = event.pop("event", "")
    return event


def get_logger(name: str | None = None):
    configure()
    return structlog.get_logger(name)


def flush() -> None:
    """Export pending metrics now (worker processes exit without running atexit handlers)."""
    provider = metrics.get_meter_provider()
    if hasattr(provider, "force_flush"):
        provider.force_flush()


def shutdown() -> None:
    """Flush metric exporters (call before process exit). Safe to call repeatedly: the SDK allows one shutdown
    and logs an error on the second, and both the CLI's `finally` and its atexit hook call this."""
    global _shut_down
    if _shut_down:
        return
    _shut_down = True
    provider = metrics.get_meter_provider()
    if hasattr(provider, "shutdown"):
        provider.shutdown()


_meter = metrics.get_meter("mogov")
rows_landed = _meter.create_counter("mogov.loader.rows", unit="{row}", description="Rows landed per raw table")
loader_duration = _meter.create_histogram("mogov.loader.duration", unit="s", description="Loader wall time")
loader_failures = _meter.create_counter("mogov.loader.failures", description="Loaders that raised")
http_requests = _meter.create_counter(
    "mogov.http.requests", description="HTTP requests, attributed by host and whether served from cache"
)
http_bytes = _meter.create_counter("mogov.http.bytes", unit="By", description="Bytes downloaded from the network")
http_duration = _meter.create_histogram(
    "mogov.http.duration", unit="s", description="Network request time (cache hits excluded), by host and status"
)
loader_progress = _meter.create_gauge(
    "mogov.loader.progress", unit="1", description="Fraction of a loader phase's known work done (0-1)"
)


class Progress:
    """Logs `loader.progress` every MOGOV_PROGRESS_SECONDS (default 15) while working through `total` items,
    and once more at the end. Cheap enough to tick per item."""

    interval = float(os.environ.get("MOGOV_PROGRESS_SECONDS", "15"))

    def __init__(self, phase: str, total: int, log=None):
        self.phase, self.total, self.done, self.reported = phase, total, 0, None
        self.log = log or get_logger("mogov.progress")
        self.started = self.last = time.monotonic()

    def tick(self, n: int = 1) -> None:
        self.done += n
        now = time.monotonic()
        if now - self.last >= self.interval:
            self.last = now
            self._emit(now)

    def finish(self) -> None:
        if self.reported != self.done:
            self._emit(time.monotonic())

    def _emit(self, now: float) -> None:
        self.reported = self.done
        elapsed = now - self.started
        frac = self.done / self.total if self.total else 1.0
        eta = elapsed / frac - elapsed if 0 < frac < 1 else 0
        ctx = structlog.contextvars.get_contextvars()
        loader_progress.set(frac, {"phase": self.phase, **{k: str(ctx[k]) for k in ("loader", "shard") if k in ctx}})
        self.log.info(
            "loader.progress",
            phase=self.phase,
            done=round(self.done, 1),
            total=self.total,
            pct=round(100 * frac, 1),
            elapsed_s=round(elapsed),
            eta_s=round(eta),
        )
