"""Loader registry. Each loader extracts one source and lands it verbatim as Parquet under RAW_DIR.

Stage 1 loaders depend only on the outside world. Stage 2 loaders need a first dbt build (e.g. the
case-history loader looks up the judges/lawyers that dbt identified), so `mogov run` does
stage 1 -> dbt build -> stage 2 -> dbt build.

A loader is `load(shard: db.Shard) -> {raw table: rows landed}`. It lists its work units (files, PDFs,
people...), processes only the units `shard.owns()`, and writes its part of each table through `db`.
Every shard lists the same units, so N independent processes split the work without coordinating.

`service` names the upstream a loader talks to (its host, by default the loader's own name). Loaders of
one service run one after another in a shard; different services run concurrently. `slow` loaders are
started first so they don't become the tail of a run.
"""

from collections.abc import Callable

from mogov.db import Shard

LoadFn = Callable[[Shard], dict[str, int]]
REGISTRY: dict[str, LoadFn] = {}
STAGE: dict[str, int] = {}
SERVICE: dict[str, str] = {}
SLOW: set[str] = set()


def loader(name: str, stage: int = 1, *, service: str | None = None, slow: bool = False):
    def register(fn: LoadFn):
        REGISTRY[name] = fn
        STAGE[name] = stage
        SERVICE[name] = service or name
        if slow:
            SLOW.add(name)
        return fn

    return register


def load_all_modules() -> None:
    import importlib
    import pkgutil

    for mod in pkgutil.iter_modules(__path__):
        importlib.import_module(f"{__name__}.{mod.name}")
