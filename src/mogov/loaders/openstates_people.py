"""Open States `people` repo: current + retired MO legislators, statewide executives, municipal officials.

The YAML is the roster backbone for state officials: party, every role held (= past offices),
contact details, links and alternate names used to match people across other sources.
"""

import io
import tarfile

import yaml

from mogov import db
from mogov.config import CACHE_DIR
from mogov.http import fetch_to_file
from mogov.loaders import loader

TARBALL = "https://codeload.github.com/openstates/people/tar.gz/refs/heads/main"
CURRENT_CSV = "https://data.openstates.org/people/current/mo.csv"


@loader("openstates_people")
def load() -> dict[str, int]:
    path = fetch_to_file(TARBALL, CACHE_DIR / "openstates_people.tar.gz")
    records = []
    with tarfile.open(path, "r:gz") as tar:
        for member in tar:
            parts = member.name.split("/")
            # <root>/data/mo/<folder>/<file>.yml
            if not member.isfile() or len(parts) < 5 or parts[1:3] != ["data", "mo"]:
                continue
            if not parts[-1].endswith(".yml"):
                continue
            doc = yaml.safe_load(io.TextIOWrapper(tar.extractfile(member), encoding="utf-8"))
            folder = "/".join(parts[3:-1])
            key = f"{folder}/{parts[-1]}"
            records.append((key, {"folder": folder, "file": parts[-1], "doc": doc}))
    csv_path = fetch_to_file(CURRENT_CSV, CACHE_DIR / "openstates_mo_current.csv")
    return {
        "openstates_people": db.replace_json("openstates_people", records, source_url=TARBALL),
        # flat current roster; carries Wikidata QIDs, which the YAML often lacks
        "openstates_current_csv": db.replace_csv("openstates_current_csv", csv_path),
    }
