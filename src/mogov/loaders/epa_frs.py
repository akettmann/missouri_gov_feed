"""EPA Facility Registry Service (FRS), Missouri state file: every site EPA or a state program regulates
(factories, gas stations, farms with permits, landfills, auto shops, utilities...), with its name, street
address, coordinates, NAICS codes and the companies that own or operate it. dbt places each facility in the
districts that contain it, so an official's district can be listed with the businesses that operate there.

The state file is one zip of CSVs, refreshed by EPA every few months. Five of them are landed: facilities,
organizations (owners/operators per program record), NAICS codes, SIC codes (the older industry
classification, which many program records carry in place of a NAICS code; dbt maps it to a NAICS sector)
and alternative names (each program record's own spelling of the site name; dbt uses them to repair the few
facility and organization names where EPA's file lost a letter to U+FFFD).
Each row lands verbatim as a JSON object keyed by the CSV header. The files have a few rows where two
records are fused onto one line (a closing quote is missing); DuckDB's CSV reader dropped dozens of good rows
after each one, so the files are read with Python's csv module instead, and a row of the wrong width keeps
its fields under `_fields`.
"""

import csv
import io
import zipfile
from collections.abc import Iterator
from pathlib import Path

from mogov import db, obs
from mogov.config import CACHE_DIR
from mogov.http import fetch_to_file
from mogov.loaders import loader

log = obs.get_logger(__name__)

URL = "https://ordsext.epa.gov/FLA/www3/state_files/state_combined_mo.zip"
FILES = {  # raw table -> member of the zip
    "epa_frs_facilities": "MO_FACILITY_FILE.CSV",
    "epa_frs_organizations": "MO_ORGANIZATION_FILE.CSV",
    "epa_frs_naics": "MO_NAICS_FILE.CSV",
    "epa_frs_sic": "MO_SIC_FILE.CSV",
    "epa_frs_alt_names": "MO_ALTERNATIVE_NAME_FILE.CSV",
}


def read_rows(lines: Iterator[str], source: str) -> Iterator[tuple[str, dict]]:
    """(record key, {header: value}) per CSV row; the key is the file and its row number."""
    reader = csv.reader(lines)
    header = next(reader)
    for n, row in enumerate(reader, start=1):
        if len(row) == len(header):
            yield f"{source}:{n}", dict(zip(header, row, strict=True))
        else:
            yield f"{source}:{n}", {"_fields": row}


@loader("epa_frs", service="ordsext.epa.gov")
def load(shard: db.Shard) -> dict[str, int]:
    """Units: the five CSVs in the state zip, which is downloaded once and shared by the shards."""
    mine = {table: member for table, member in FILES.items() if shard.owns(table)}
    zip_path: Path | None = (
        fetch_to_file(URL, CACHE_DIR / "epa_frs" / "state_combined_mo.zip", max_age=30 * 86400) if mine else None
    )
    progress = obs.Progress("files", len(mine), log)
    with db.JsonSink(shard, source_url=URL, tables=FILES) as sink:
        for table, member in mine.items():
            with zipfile.ZipFile(zip_path) as zf, zf.open(member) as raw:
                lines = io.TextIOWrapper(raw, encoding="utf-8", newline="")
                sink.extend(table, read_rows(lines, member))
            progress.tick()
    progress.finish()
    return sink.counts
