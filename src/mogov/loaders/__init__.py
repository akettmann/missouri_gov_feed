"""Loader registry. Each loader extracts one source and lands it verbatim as Parquet under RAW_DIR.

Stage 1 loaders depend only on the outside world. Stage 2 loaders need a first dbt build (e.g. the
case-history loader looks up the judges/lawyers that dbt identified), so `mogov run` does
stage 1 -> dbt build -> stage 2 -> dbt build.
"""

from collections.abc import Callable

REGISTRY: dict[str, Callable[[], dict[str, int]]] = {}
STAGE: dict[str, int] = {}


def loader(name: str, stage: int = 1):
    def register(fn: Callable[[], dict[str, int]]):
        REGISTRY[name] = fn
        STAGE[name] = stage
        return fn

    return register


def load_all_modules() -> None:
    import importlib
    import pkgutil

    for mod in pkgutil.iter_modules(__path__):
        importlib.import_module(f"{__name__}.{mod.name}")
