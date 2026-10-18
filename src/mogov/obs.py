"""Observability: structlog logging and OpenTelemetry metrics.

Logs: human-readable console output by default; MOGOV_LOG_JSON=1 for JSON lines. MOGOV_LOG_LEVEL sets the
level (default INFO).
Metrics: exported over OTLP/HTTP when OTEL_EXPORTER_OTLP_ENDPOINT is set (standard OTel env vars apply),
printed to the console at exit when MOGOV_METRICS_CONSOLE=1, otherwise recorded but not exported.
"""

import logging
import os
import sys

import structlog
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import ConsoleMetricExporter, PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource

_configured = False


def configure() -> None:
    global _configured
    if _configured:
        return
    _configured = True

    level = getattr(logging, os.environ.get("MOGOV_LOG_LEVEL", "INFO").upper(), logging.INFO)
    renderer = (
        structlog.processors.JSONRenderer()
        if os.environ.get("MOGOV_LOG_JSON") == "1"
        else structlog.dev.ConsoleRenderer(colors=sys.stderr.isatty())
    )
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.format_exc_info,
            renderer,
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


def get_logger(name: str | None = None):
    configure()
    return structlog.get_logger(name)


def shutdown() -> None:
    """Flush metric exporters (call before process exit)."""
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
