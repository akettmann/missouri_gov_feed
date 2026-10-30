import itertools
import os
import subprocess
import sys
import threading
from datetime import UTC, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
from typing import ClassVar

import httpx
import lxml.html
import pytest

from mogov import http
from mogov.loaders import mo_revisor
from mogov.loaders.mo_revisor import parse_chapter, parse_repeals, parse_section, parse_toc

FIXTURES = Path(__file__).parent / "fixtures" / "mo_revisor"


def read(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def test_toc_lists_chapters_under_their_title():
    # home page cut after its first two titles
    rows = parse_toc(read("home_excerpt.html"))
    assert [r["chapter"] for r in rows] == ["1", "2", "3", "7", "8", "9", "10", "11", "12", "14"]
    assert rows[0] == {
        "title": "I LAWS AND STATUTES",
        "chapter": "1",
        "chapter_name": "Laws in Force and Construction of Statutes",
    }
    assert rows[-1]["title"] == "II SOVEREIGNTY, JURISDICTION AND EMBLEMS"


def test_chapter_lists_each_section_version_once():
    versions = parse_chapter(read("chapter_1.html"))
    assert len(versions) == 54
    assert versions[:2] == [("1.010", 42), ("1.016", 51044)]
    # four-digit section numbers exist (1.1001-1.1010), so a section ID isn't always NNN.NNN
    assert ("1.1001", 57722) in versions


def test_section_text_heading_and_history():
    s = parse_section(read("section_1.010.html"))
    assert s["title_line"] == "Title I LAWS AND STATUTES"
    assert s["effective"] == "Effective - 28 Aug 2015, 2 histories"
    assert not s["historical"]
    assert s["heading"].startswith("1.010. Common law in force")
    first, second = s["text"].split("\n\n")[:2]
    assert first.startswith(s["heading"] + " 1. The common law of England")
    assert second.startswith("2. The general assembly expressly excludes")
    assert s["footnotes"][0] == "(RSMo 1939 § 645, A.L. 1957 p. 587, A.L. 2015 S.B. 239)"
    assert s["html"].startswith('<div style="margin:.1em 0em .4em .5em;">')
    assert "<form" not in s["html"]


def test_future_effective_version():
    s = parse_section(read("section_27.117_bid60727.html"))
    assert s["effective"] == "Effective - 01 Jul 2027, 2 histories, see footnote"
    assert s["footnotes"][0] == "(L. 2026 H.B. 2273, et al. merged with H.B. 2637 & 3155 merged with S.B. 999)"


def test_tables_keep_their_rows():
    s = parse_section(read("section_28.160.html"))
    paragraphs = s["text"].split("\n\n")
    assert paragraphs[1].splitlines()[0] == "For issuing commission to notary public\t$15.00"
    assert paragraphs[2].startswith("2. There is hereby established")
    # the soft-hyphen spacer paragraphs around the table are dropped
    assert all(p.strip("\xad ") for p in paragraphs)


def test_repeals_and_transfers():
    rows = parse_repeals(read("rx_excerpt.html"))
    assert rows[0] == {
        "kind": "repealed",
        "section": "1.022",
        "bid": 36218,
        "note": "(Repealed L. 1975 H.B. 945 § 1)",
        "date": "9/28/1975",
    }
    assert [r["kind"] for r in rows] == ["repealed"] * 3 + ["transferred"] * 2
    assert rows[3]["note"] == "(Transferred 1959; now 442.560 )"


def test_block_page_raises_and_is_not_cached(tmp_path, monkeypatch):
    # the site answers a blocked IP with a redirect to Block.aspx, which serves a 200 page
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/Block.aspx"):
            return httpx.Response(200, text="<html>Blocked</html>")
        return httpx.Response(302, headers={"location": "https://revisor.mo.gov/main/Block.aspx"})

    monkeypatch.setattr(http, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(http, "_client", httpx.Client(transport=httpx.MockTransport(handler), follow_redirects=True))
    monkeypatch.setattr(mo_revisor, "POLITE_DELAY", 0)
    with pytest.raises(mo_revisor.Blocked):
        mo_revisor._get("https://revisor.mo.gov/main/OneSection.aspx", {"section": "1.010", "bid": 42})
    assert not [p for p in tmp_path.iterdir() if not p.name.startswith(".")]


def test_speeding_warning_raises_and_is_not_cached(tmp_path, monkeypatch):
    # before blocking, the site serves a warning page with 200 in place of the page asked for
    warning = "<p>Recent accesses are tracked over a thirty second interval.</p>"
    transport = httpx.MockTransport(lambda request: httpx.Response(200, text=warning))
    monkeypatch.setattr(http, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(http, "_client", httpx.Client(transport=transport))
    monkeypatch.setattr(mo_revisor, "POLITE_DELAY", 0)
    monkeypatch.setattr(mo_revisor, "WARNING_BACKOFF", (0, 0))
    with pytest.raises(mo_revisor.Warned):
        mo_revisor._get("https://revisor.mo.gov/main/OneChapter.aspx", {"chapter": "1"})
    assert not [p for p in tmp_path.iterdir() if not p.name.startswith(".")]


SECTION_URL = "https://revisor.mo.gov/main/OneSection.aspx"


def _serve(tmp_path, monkeypatch, answers: list[str]) -> list:
    """Serve `answers` in turn (the last one repeats); returns the requests made."""
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request.url)
        return httpx.Response(200, text=answers[min(len(calls), len(answers)) - 1])

    monkeypatch.setattr(http, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(http, "_client", httpx.Client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(mo_revisor, "POLITE_DELAY", 0)
    monkeypatch.setattr(mo_revisor.time, "sleep", lambda s: None)
    monkeypatch.setattr(mo_revisor, "pause_host", lambda host, s: None)
    return calls


def test_home_page_served_for_a_section_is_refused_and_not_cached(tmp_path, monkeypatch):
    # 161.415 bid 7908 once came back as the home page (table of contents), 200 and no redirect
    _serve(tmp_path, monkeypatch, [read("home_excerpt.html")])
    with pytest.raises(mo_revisor.Misserved):
        mo_revisor._get_stamped(
            SECTION_URL, {"section": "161.415", "bid": 7908}, backoff=(0,), check=mo_revisor._section_served
        )
    assert not [p for p in tmp_path.iterdir() if not p.name.startswith(".")]


def test_home_page_served_for_a_section_is_retried(tmp_path, monkeypatch):
    calls = _serve(tmp_path, monkeypatch, [read("home_excerpt.html"), read("section_1.010.html")])
    page, _ = mo_revisor._get_stamped(
        SECTION_URL, {"section": "1.010", "bid": 1}, backoff=(0,), check=mo_revisor._section_served
    )
    assert parse_section(page)["heading"]
    assert len(calls) == 2


def test_speeding_warning_backs_off_and_retries(tmp_path, monkeypatch):
    # a single warning (other traffic from the same IP counts) waits and retries instead of failing the load
    answers = ["<p>Recent accesses are tracked over a thirty second interval.</p>", "<html>the section</html>"]
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request.url)
        return httpx.Response(200, text=answers[min(len(calls), len(answers)) - 1])

    sleeps = []
    monkeypatch.setattr(http, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(http, "_client", httpx.Client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(mo_revisor, "POLITE_DELAY", 0)
    monkeypatch.setattr(mo_revisor, "WARNING_BACKOFF", (7, 11))
    monkeypatch.setattr(mo_revisor.time, "sleep", sleeps.append)
    assert mo_revisor._get("https://revisor.mo.gov/main/OneChapter.aspx", {"chapter": "1"}) == answers[1]
    assert len(calls) == 2
    assert sleeps == [7]


class FakeClock:
    """A shared wall clock that only moves when someone sleeps; sleeping is serialised like the real thing."""

    def __init__(self):
        self.now = 1000.0
        self.lock = threading.Lock()

    def time(self) -> float:
        return self.now

    monotonic = time  # never stepped back, unlike the wall clock tests move by hand

    def sleep(self, seconds: float) -> None:
        with self.lock:
            self.now += seconds


def test_throttle_keeps_requests_an_interval_apart_across_threads(tmp_path, monkeypatch):
    # two "shards" (each with its own loop) share the cache dir; on a fixed clock no two requests may start
    # closer than the interval, however they interleave
    monkeypatch.setattr(http, "CACHE_DIR", tmp_path)
    clock = FakeClock()
    starts, interval = [], 2.0

    def shard():
        for _ in range(6):
            with http.host_throttle(
                "revisor.mo.gov", interval, clock=clock.time, sleep=clock.sleep, monotonic=clock.monotonic
            ):
                starts.append(clock.time())

    threads = [threading.Thread(target=shard) for _ in range(3)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    starts.sort()
    assert len(starts) == 18
    gaps = [b - a for a, b in itertools.pairwise(starts)]
    assert min(gaps) >= interval
    assert starts[-1] - starts[0] == pytest.approx(interval * 17)  # and no slower than the interval either


def test_throttle_stamp_in_the_future_waits_at_most_one_interval(tmp_path, monkeypatch):
    monkeypatch.setattr(http, "CACHE_DIR", tmp_path)
    (tmp_path / ".throttle-h.last").write_text("9999999999.0")
    clock = FakeClock()
    with http.host_throttle("h", 2.0, clock=clock.time, sleep=clock.sleep, monotonic=clock.monotonic):
        assert clock.time() == 1002.0


def test_throttle_clock_stepped_back_mid_wait_waits_one_interval(tmp_path, monkeypatch):
    monkeypatch.setattr(http, "CACHE_DIR", tmp_path)
    (tmp_path / ".throttle-h.last").write_text("1000.0")
    wall = {"now": 1000.0}
    mono = {"now": 5.0}

    def sleep(seconds):
        assert seconds <= 2.0 and mono["now"] < 20, "stalled by the clock step"
        mono["now"] += seconds
        wall["now"] -= 3600  # NTP steps the wall clock back an hour while we sleep

    with http.host_throttle("h", 2.0, clock=lambda: wall["now"], sleep=sleep, monotonic=lambda: mono["now"]):
        assert mono["now"] == 7.0


def test_throttle_early_wake_still_waits_the_full_interval(tmp_path, monkeypatch):
    monkeypatch.setattr(http, "CACHE_DIR", tmp_path)
    (tmp_path / ".throttle-h.last").write_text("1000.0")
    clock = FakeClock()
    sleeps = []

    def early_sleep(seconds):  # wakes at half the requested time, like a coarse timer
        sleeps.append(seconds)
        clock.sleep(seconds / 2)

    with http.host_throttle("h", 2.0, clock=clock.time, sleep=early_sleep, monotonic=clock.monotonic):
        assert clock.time() >= 1002.0 - 1e-9
    assert len(sleeps) > 1


def test_throttle_across_real_processes(tmp_path):
    # three separate interpreters sharing a cache dir, real clock, short interval
    script = (
        "import sys, time\n"
        "from pathlib import Path\n"
        "from mogov import http\n"
        "http.CACHE_DIR = Path(sys.argv[1])\n"
        "for _ in range(4):\n"
        "    with http.host_throttle('h', 0.3):\n"
        "        print((Path(sys.argv[1]) / '.throttle-h.last').read_text(), flush=True)\n"
    )
    procs = [
        subprocess.Popen([sys.executable, "-c", script, str(tmp_path)], stdout=subprocess.PIPE, text=True)
        for _ in range(3)
    ]
    # the throttle's own recorded start times: reading time.time() after the fact adds scheduling jitter
    starts = sorted(float(line) for p in procs for line in p.communicate()[0].split())
    assert len(starts) == 12
    assert min(b - a for a, b in itertools.pairwise(starts)) >= 0.29


class _Added(list):
    def __init__(self):
        super().__init__()
        self.payloads = {}


def _loader_pages(monkeypatch, refused: set[str], n: int = 5):
    """Run mo_revisor.load on one chapter with sections 1.010, 1.020, ...; pages in `refused` get the warning."""
    sections = [(f"1.0{i}0", i) for i in range(1, n + 1)]
    added, fetched = _Added(), []
    added.checks = {}

    class Sink:
        counts: ClassVar[dict] = {}

        def __init__(self, *a, **k):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def add(self, table, key, payload, **k):
            added.append((table, key))
            added.payloads[(table, key)] = payload

    def fake_get(url, params=None, *, max_age=None, backoff=None, check=mo_revisor._not_blocked):
        added.checks[url.rsplit("/", 1)[-1]] = check
        if params and "section" in params:
            fetched.append(params["section"])
            if params["section"] in refused:
                raise mo_revisor.Warned("warning page")
        return "page", "2026-05-01T12:00:00+00:00"

    monkeypatch.setattr(mo_revisor.db, "JsonSink", Sink)
    monkeypatch.setattr(mo_revisor, "_get_stamped", fake_get)
    monkeypatch.setattr(mo_revisor, "_get", lambda *a, **k: fake_get(*a, **k)[0])
    monkeypatch.setattr(mo_revisor, "parse_toc", lambda page: [{"title": "I", "chapter": "1", "chapter_name": "x"}])
    monkeypatch.setattr(mo_revisor, "parse_repeals", lambda page: [])
    monkeypatch.setattr(mo_revisor, "parse_chapter", lambda page: sections)
    monkeypatch.setattr(mo_revisor, "parse_section", lambda page: {"html": "h"})
    monkeypatch.delenv("CLOUD_RUN_TASK_COUNT", raising=False)
    return added, fetched


def test_only_section_pages_must_carry_a_content_block(monkeypatch):
    added, _ = _loader_pages(monkeypatch, refused=set())
    mo_revisor.load(mo_revisor.db.UNSHARDED)
    assert added.checks["OneSection.aspx"] is mo_revisor._section_served
    assert {added.checks[page] for page in ("Home.aspx", "rx.aspx", "OneChapter.aspx")} == {mo_revisor._not_blocked}


def test_a_section_page_that_stays_refused_is_skipped_not_fatal(monkeypatch):
    added, fetched = _loader_pages(monkeypatch, refused={"1.020"})
    mo_revisor.load(mo_revisor.db.UNSHARDED)
    assert fetched == ["1.010", "1.020", "1.030", "1.040", "1.050"]
    assert [k for t, k in added if t == "mo_revisor_sections"] == ["1.010/1", "1.030/3", "1.040/4", "1.050/5"]


def test_consecutive_refused_section_pages_stop_the_load(monkeypatch):
    _added, fetched = _loader_pages(monkeypatch, refused={"1.020", "1.030", "1.040"})
    with pytest.raises(mo_revisor.Warned):
        mo_revisor.load(mo_revisor.db.UNSHARDED)
    assert fetched == ["1.010", "1.020", "1.030", "1.040"]


def test_alternating_refusals_stop_the_load_by_their_total(monkeypatch):
    # every other page refused: never 3 in a row, but 30 of 60 skipped is a warned IP, not missing pages
    refused = {f"1.0{i}0" for i in range(1, 61, 2)}
    _loader_pages(monkeypatch, refused=refused, n=60)
    with pytest.raises(RuntimeError, match="skipped 30 of 60"):
        mo_revisor.load(mo_revisor.db.UNSHARDED)


def test_a_few_scattered_refusals_are_tolerated_and_totalled(monkeypatch):
    refused = {f"1.0{i}0" for i in range(1, 100, 7)}  # 15 of 100, each followed by good pages
    added, _ = _loader_pages(monkeypatch, refused=refused, n=100)
    logged = []
    monkeypatch.setattr(mo_revisor.log, "info", lambda event, **kw: logged.append((event, kw)))
    mo_revisor.load(mo_revisor.db.UNSHARDED)
    assert len([k for t, k in added if t == "mo_revisor_sections"]) == 100 - len(refused)
    assert ("mo_revisor.sections_skipped", {"total": len(refused), "of": 100}) in logged


def test_a_warning_pauses_other_threads_requests_host_wide(tmp_path, monkeypatch):
    monkeypatch.setattr(http, "CACHE_DIR", tmp_path)
    clock = FakeClock()
    starts = []
    http.pause_host("revisor.mo.gov", 60, clock=clock.time)  # shard A was warned at t=1000

    def shard_b():  # shard B's next request, nothing else holding the lock
        with http.host_throttle("revisor.mo.gov", 2.0, clock=clock.time, sleep=clock.sleep, monotonic=clock.monotonic):
            starts.append(clock.time())

    t = threading.Thread(target=shard_b, daemon=True)
    t.start()
    t.join(timeout=10)
    assert not t.is_alive(), "shard B never got past the pause"
    assert starts == [pytest.approx(1060.0)]  # waited out the pause, no request in between
    with http.host_throttle("revisor.mo.gov", 2.0, clock=clock.time, sleep=clock.sleep, monotonic=clock.monotonic):
        assert clock.time() == 1062.0  # and the pause doesn't linger


def test_a_pause_stamp_far_in_the_future_is_capped(tmp_path, monkeypatch):
    monkeypatch.setattr(http, "CACHE_DIR", tmp_path)
    (tmp_path / ".throttle-h.pause").write_text("9999999999.0")  # clock was set back after a pause was written
    clock = FakeClock()
    with http.host_throttle("h", 2.0, clock=clock.time, sleep=clock.sleep, monotonic=clock.monotonic):
        assert clock.time() == 1000.0 + http.THROTTLE_MAX_PAUSE_S
    (tmp_path / ".throttle-h.pause").write_text("9999999999.0")
    http.pause_host("h", 60, clock=lambda: 1000.0)  # a fresh pause replaces the stale far one
    assert float((tmp_path / ".throttle-h.pause").read_text()) <= 1000.0 + http.THROTTLE_MAX_PAUSE_S


def test_pause_never_shortens_and_get_writes_it(tmp_path, monkeypatch):
    monkeypatch.setattr(http, "CACHE_DIR", tmp_path)
    http.pause_host("h", 100, clock=lambda: 1000.0)
    http.pause_host("h", 10, clock=lambda: 1000.0)
    assert float((tmp_path / ".throttle-h.pause").read_text()) == 1100.0


def test_get_pauses_the_whole_host_on_a_warning(monkeypatch):
    paused = []
    monkeypatch.setattr(mo_revisor, "pause_host", lambda host, s: paused.append((host, s)))
    monkeypatch.setattr(mo_revisor, "WARNING_BACKOFF", (7,))
    monkeypatch.setattr(mo_revisor.time, "sleep", lambda s: None)
    answers = iter([mo_revisor.Warned("w"), (b"ok", 0.0)])

    def fake_fetch(*a, **k):
        r = next(answers)
        if isinstance(r, Exception):
            raise r
        return r

    monkeypatch.setattr(mo_revisor, "fetch_stamped", fake_fetch)
    assert mo_revisor._get("https://revisor.mo.gov/main/x") == "ok"
    assert paused == [("revisor.mo.gov", 7)]


def test_throttle_raises_on_a_permanent_permission_error(tmp_path, monkeypatch):
    monkeypatch.setattr(http, "CACHE_DIR", tmp_path)
    monkeypatch.setattr(http.time, "sleep", lambda s: None)

    def deny(*a, **k):
        raise PermissionError("denied")

    monkeypatch.setattr(http.os, "open", deny)
    with pytest.raises(PermissionError), http.host_throttle("h", 1.0):
        pass


def test_more_than_one_cloud_run_task_is_refused(monkeypatch):
    _loader_pages(monkeypatch, refused=set())
    monkeypatch.setenv("CLOUD_RUN_TASK_COUNT", "3")
    with pytest.raises(RuntimeError, match="Cloud Run tasks"):
        mo_revisor.load(mo_revisor.db.UNSHARDED)


def test_chapter_links_are_read_as_markup_not_text():
    page = (
        "<html><body>"
        "<a class=\"v\" href='/main/PageSelect.aspx?section=1.010&bid=42'>single quotes, attribute first</a>"
        '<a href="/main/PageSelect.aspx?section=1.016&amp;bid=51044" title="t">extra attribute</a>'
        '<a href="/main/PageSelect.aspx?section=1.016&amp;bid=51044">duplicate</a>'
        '<!-- <a href="/main/PageSelect.aspx?section=9.999&amp;bid=1">commented out</a> -->'
        "<script>var x = '<a href=\"/main/PageSelect.aspx?section=8.888&amp;bid=2\">';</script>"
        '<a href="/main/PageSelect.aspx?section=2.010&amp;bid=abc">not a bid</a>'
        '<a href="/main/OneChapter.aspx?chapter=1">not a section</a>'
        "</body></html>"
    )
    assert parse_chapter(page) == [("1.010", 42), ("1.016", 51044)]


def test_toc_links_in_any_attribute_layout():
    page = (
        "<details><summary><span>I</span><span>TITLE</span></summary>"
        "<a class='x' href='/main/OneChapter.aspx?chapter=7'>7 Seven</a>"
        '<a href="/main/OneChapter.aspx?chapter=8&amp;x=1">other parameter</a>'
        "</details>"
    )
    assert parse_toc(page) == [{"title": "TITLE", "chapter": "7", "chapter_name": "Seven"}]


def test_repeal_rows_in_any_attribute_layout():
    page = (
        "<table>"
        '<tr class="r" style="width:100%;"><td><a href="/main/PageSelect.aspx?section=1.5&amp;bid=3">1.5</a></td>'
        "<td>(Repealed 1975)<span>(1/2/1975)</span></td></tr>"
        '<tr style="width:100%;"><td>no link</td><td>x</td></tr>'
        "</table><p id='xfer'>Transferred</p><table>"
        "<tr style='width:100%;'><td><a href='/main/PageSelect.aspx?section=2.5&bid=4'>2.5</a></td>"
        "<td>(Transferred; now 3.5)</td></tr></table>"
    )
    assert parse_repeals(page) == [
        {"kind": "repealed", "section": "1.5", "bid": 3, "note": "(Repealed 1975)", "date": "1/2/1975"},
        {"kind": "transferred", "section": "2.5", "bid": 4, "note": "(Transferred; now 3.5)", "date": None},
    ]


@pytest.mark.parametrize(
    "href",
    [
        "https://example.com/main/OneChapter.aspx?chapter=7",
        "http://revisor.mo.gov/main/OneChapter.aspx?chapter=7",
        "//example.com/main/OneChapter.aspx?chapter=7",
        "https:/main/OneChapter.aspx?chapter=7",  # a scheme with no host is still not a site-relative link
    ],
)
def test_links_to_other_hosts_are_not_followed(href):
    assert mo_revisor.chapter_link(href) is None
    assert (
        mo_revisor.section_link(href.replace("OneChapter", "PageSelect").replace("chapter=7", "section=1.5&bid=3"))
        is None
    )
    assert parse_toc(f"<details><summary><span>T</span></summary><a href='{href}'>7 Seven</a></details>") == []
    assert mo_revisor.chapter_link("/main/OneChapter.aspx?chapter=7") == "7"


def test_parser_never_touches_the_network():
    page = (
        '<!DOCTYPE html SYSTEM "http://example.invalid/x.dtd">'
        '<a href="/main/PageSelect.aspx?section=1.5&amp;bid=3">s</a>'
    )
    assert parse_chapter(page) == [("1.5", 3)]


def test_every_parse_uses_the_hardened_parser(monkeypatch):
    seen = []

    def spy(real):
        def wrapper(*args, **kwargs):
            seen.append(kwargs.get("parser"))
            return real(*args, **kwargs)

        return wrapper

    monkeypatch.setattr(lxml.html, "fromstring", spy(lxml.html.fromstring))
    monkeypatch.setattr(lxml.html, "fragment_fromstring", spy(lxml.html.fragment_fromstring))
    for func, name in [
        (parse_toc, "home_excerpt.html"),
        (parse_chapter, "chapter_1.html"),
        (parse_section, "section_1.010.html"),
        (parse_repeals, "rx_excerpt.html"),
    ]:
        seen.clear()
        func(read(name))
        assert seen, f"{func.__name__} no longer parses through lxml.html"
        assert all(parser is mo_revisor.PARSER for parser in seen), func.__name__


def test_loader_records_the_pages_fetched_at_in_the_section_payload(monkeypatch):
    added, _ = _loader_pages(monkeypatch, refused=set(), n=2)
    mo_revisor.load(mo_revisor.db.UNSHARDED)
    assert added.payloads[("mo_revisor_sections", "1.010/1")]["fetched_at"] == "2026-05-01T12:00:00+00:00"


def test_loader_records_the_repeals_pages_fetched_at_on_every_row(monkeypatch):
    added, _ = _loader_pages(monkeypatch, refused=set(), n=1)
    monkeypatch.setattr(
        mo_revisor, "parse_repeals", lambda page: [{"section": "9.1", "bid": 1}, {"section": "9.2", "bid": 2}]
    )
    mo_revisor.load(mo_revisor.db.UNSHARDED)
    assert [added.payloads[("mo_revisor_repeals", k)]["fetched_at"] for k in ("9.1/1", "9.2/2")] == [
        "2026-05-01T12:00:00+00:00"
    ] * 2


def _stamped_setup(tmp_path, monkeypatch):
    monkeypatch.setattr(http, "CACHE_DIR", tmp_path)
    hits = []

    def handler(request):
        hits.append(str(request.url))
        return httpx.Response(200, content=b"<html>page</html>")

    monkeypatch.setattr(http, "_client", httpx.Client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(mo_revisor, "POLITE_DELAY", 0)
    return hits


def test_fresh_fetch_is_stamped_with_the_time_it_was_fetched(tmp_path, monkeypatch):
    _stamped_setup(tmp_path, monkeypatch)
    before = datetime.now(UTC).replace(microsecond=0)
    _, fetched_at = mo_revisor._get_stamped("https://revisor.mo.gov/main/OneSection.aspx", {"section": "1.010"})
    after = datetime.now(UTC)
    assert before <= datetime.fromisoformat(fetched_at) <= after


def test_cache_hit_keeps_the_original_fetch_time_not_the_reuse_time(tmp_path, monkeypatch):
    hits = _stamped_setup(tmp_path, monkeypatch)
    url, params = "https://revisor.mo.gov/main/OneSection.aspx", {"section": "1.010"}
    mo_revisor._get_stamped(url, params, max_age=mo_revisor.SECTION_MAX_AGE)
    (entry,) = tmp_path.glob("*")
    now = datetime(2026, 10, 28, 12, 0, 0, tzinfo=UTC)
    long_ago = now - timedelta(days=30)
    # one fixed clock for the expiry check and the backdated mtime, so the test does not age out with the calendar
    monkeypatch.setattr(http, "time", SimpleNamespace(time=lambda: now.timestamp(), sleep=lambda s: None))
    os.utime(entry, (long_ago.timestamp(), long_ago.timestamp()))  # the page was fetched a month ago
    page, fetched_at = mo_revisor._get_stamped(url, params, max_age=mo_revisor.SECTION_MAX_AGE)
    assert len(hits) == 1  # served from the cache
    assert page == "<html>page</html>"
    assert fetched_at == long_ago.isoformat()


def test_expired_cache_entry_is_refetched_and_restamped(tmp_path, monkeypatch):
    hits = _stamped_setup(tmp_path, monkeypatch)
    url, params = "https://revisor.mo.gov/main/OneSection.aspx", {"section": "1.010"}
    mo_revisor._get_stamped(url, params, max_age=60)
    (entry,) = tmp_path.glob("*")
    os.utime(entry, (1_700_000_000, 1_700_000_000))  # older than max_age
    _, fetched_at = mo_revisor._get_stamped(url, params, max_age=60)
    assert len(hits) == 2
    assert datetime.fromisoformat(fetched_at).year >= 2026
