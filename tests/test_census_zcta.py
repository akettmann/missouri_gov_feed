import zipfile
from datetime import date

import duckdb
import pytest

from mogov import db
from mogov.loaders import census_zcta

HEADER = ["GEOID", "GEOIDFQ", "ALAND", "AWATER", "ALAND_SQMI", "AWATER_SQMI", "INTPTLAT", "INTPTLONG"]
ROWS = [
    ["65101", "860Z200US65101", "339026851", "15433316", "130.9", "5.9", "38.497429", "-92.133270"],
    ["63101", "860Z200US63101", "937564", "0", "0.4", "0", "38.631397", "-90.192757"],
]


def _zip(path, name: str, sep: str):
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr(name, "\n".join(sep.join(r) for r in [HEADER, *ROWS]) + "\n")
    return path


@pytest.fixture(autouse=True)
def dirs(tmp_path, monkeypatch):
    monkeypatch.setattr(db, "RAW_DIR", tmp_path / "raw")
    monkeypatch.setattr(census_zcta, "CACHE_DIR", tmp_path / "cache")
    (tmp_path / "cache" / "census_zcta").mkdir(parents=True)
    return tmp_path


def _landed():
    return duckdb.sql(
        f"select geoid, intptlat, intptlong from read_parquet('{db.raw_glob('census_zcta_gazetteer')}') order by 1"
    ).fetchall()


@pytest.mark.parametrize("sep", ["|", "\t"])
def test_lands_pipe_and_tab_files(dirs, monkeypatch, sep):
    year = date.today().year
    fake = _zip(dirs / "src.zip", f"{year}_Gaz_zcta_national.txt", sep)
    monkeypatch.setattr(census_zcta, "fetch_to_file", lambda url, dest, max_age: fake)
    assert census_zcta.load(db.UNSHARDED) == {"census_zcta_gazetteer": 2}
    assert _landed() == [("63101", "38.631397", "-90.192757"), ("65101", "38.497429", "-92.133270")]


def test_falls_back_to_previous_vintage(dirs, monkeypatch):
    year = date.today().year
    good = _zip(dirs / "good.zip", f"{year - 1}_Gaz_zcta_national.txt", "|")
    not_zip = dirs / "page.html"
    not_zip.write_text("<html>not yet published</html>")
    calls = []

    def fetch(url, dest, max_age):
        calls.append(url)
        if f"/{year}_Gazetteer/" in url:
            return not_zip  # this year's listing exists but serves a page, not a zip
        return good

    monkeypatch.setattr(census_zcta, "fetch_to_file", fetch)
    assert census_zcta.load(db.UNSHARDED) == {"census_zcta_gazetteer": 2}
    assert [f"/{year}_Gazetteer/" in u for u in calls] == [True, False]
