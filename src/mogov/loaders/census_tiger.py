"""Census TIGER/Line boundaries for Missouri: state senate (SLDU) and house (SLDL) districts, congressional
districts, counties (judicial circuits are groups of counties) and places (cities, for mayors).

Each shapefile feature lands as one row: its attribute table verbatim, its geometry as GeoJSON (lon/lat,
NAD83, as published), plus the layer, vintage and file it came from. dbt joins districts to officials.

Vintages: each layer comes from the newest TIGER year that has it (the state-house file can lag a year).
Congressional districts are kept per Congress: after Missouri's 2025 redistricting the newest vintage holds
only the next Congress's map (cd120), while today's members represent the cd119 districts, so the newest
file for every Congress number found in the last few vintages is landed.

Counties come only as a national file (about 80 MB); its non-Missouri features are skipped while landing.
"""

import io
import re
import zipfile
from datetime import date

import shapefile

from mogov import db, obs
from mogov.config import CACHE_DIR
from mogov.http import fetch, fetch_to_file
from mogov.loaders import loader

log = obs.get_logger(__name__)

BASE = "https://www2.census.gov/geo/tiger"
STATE_FP = "29"
VINTAGES_BACK = 3  # how many TIGER years to look through, newest first
LAYERS = {  # layer -> (TIGER folder, file-name pattern for a vintage year)
    "sldu": ("SLDU", r"tl_{y}_29_sldu\.zip"),
    "sldl": ("SLDL", r"tl_{y}_29_sldl\.zip"),
    "cd": ("CD", r"tl_{y}_29_cd\d+\.zip"),
    "county": ("COUNTY", r"tl_{y}_us_county\.zip"),
    "place": ("PLACE", r"tl_{y}_29_place\.zip"),
}


def _candidates(layer: str) -> dict[str, list[tuple[int, str]]]:
    """{file kind: [(vintage, file name), newest first]} for a layer. The kind drops the year (29_sldl.zip;
    29_cd119.zip, one per Congress), so each kind lands once, from its newest vintage that downloads."""
    folder, pattern = LAYERS[layer]
    found: dict[str, list[tuple[int, str]]] = {}
    this_year = date.today().year
    for year in range(this_year, this_year - VINTAGES_BACK, -1):
        listing = fetch(f"{BASE}/TIGER{year}/{folder}/", max_age=7 * 86400).decode("utf-8", "replace")
        for name in sorted(set(re.findall(pattern.format(y=year), listing))):
            found.setdefault(re.sub(r"^tl_\d{4}_", "", name), []).append((year, name))
    if not found:
        raise RuntimeError(f"no TIGER {folder} file in the last {VINTAGES_BACK} vintages")
    return found


def _download(layer: str, candidates: list[tuple[int, str]]):
    """The newest candidate that is really a zip. A listing can name a file that isn't there yet: in
    October 2026 TIGER2026/SLDL listed tl_2026_29_sldl.zip but served a short HTML page for it."""
    for vintage, name in candidates:
        url = f"{BASE}/TIGER{vintage}/{LAYERS[layer][0]}/{name}"
        # a vintage's files don't change once published
        path = fetch_to_file(url, CACHE_DIR / "census_tiger" / name, max_age=None)
        if zipfile.is_zipfile(path):
            return vintage, name, url, path
        log.warning("census_tiger.not_a_zip", url=url, effect="trying the previous vintage")
        path.unlink(missing_ok=True)
    raise RuntimeError(f"no downloadable TIGER file among {candidates}")


def _features(path, layer: str, vintage: int, name: str):
    with zipfile.ZipFile(path) as zf:
        stem = name.removesuffix(".zip")
        members = {ext: io.BytesIO(zf.read(f"{stem}.{ext}")) for ext in ("shp", "shx", "dbf")}
        cpg = f"{stem}.cpg"
        encoding = zf.read(cpg).decode().strip() if cpg in zf.namelist() else "utf-8"
    with shapefile.Reader(**members, encoding=encoding) as shp:
        for i, feature in enumerate(shp.iterShapeRecords()):
            props = feature.record.as_dict()
            if layer == "county" and props.get("STATEFP") != STATE_FP:
                continue
            yield (
                f"{name}/{i}",
                {
                    "layer": layer,
                    "vintage": vintage,
                    "file": name,
                    "properties": props,
                    "geometry": feature.shape.__geo_interface__,
                },
            )


@loader("census_tiger", service="www2.census.gov")
def load(shard: db.Shard) -> dict[str, int]:
    """Units: shapefile kinds (29_sldl.zip, 29_cd119.zip, us_county.zip...)."""
    units = [(layer, kind, files) for layer in LAYERS for kind, files in _candidates(layer).items()]
    mine = shard.take(units, key=lambda u: u[1])
    progress = obs.Progress("shapefiles", len(mine), log)
    with db.JsonSink(shard, source_url=BASE, tables=["census_tiger_features"]) as sink:
        for layer, _, files in mine:
            vintage, name, url, path = _download(layer, files)
            for key, payload in _features(path, layer, vintage, name):
                sink.add("census_tiger_features", key, payload, source_url=url)
            progress.tick()
        progress.finish()
    return sink.counts
