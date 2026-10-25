import os
import subprocess
import sys


def test_module_entry_point_shuts_down_once():
    env = {**os.environ, "MOGOV_METRICS_CONSOLE": "1", "PYTHONUTF8": "1"}
    proc = subprocess.run(
        [
            sys.executable,
            "-c",
            "import sys, runpy; sys.argv=['mogov','list']; runpy.run_module('mogov.cli', run_name='__main__')",
        ],
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, proc.stderr
    assert "can only be called once" not in proc.stderr


def test_shutdown_is_idempotent_and_still_flushes(monkeypatch):
    from mogov import obs

    calls = []

    class Provider:
        def shutdown(self):
            calls.append("shutdown")

    monkeypatch.setattr(obs.metrics, "get_meter_provider", lambda: Provider())
    monkeypatch.setattr(obs, "_shut_down", False)
    obs.shutdown()
    obs.shutdown()
    assert calls == ["shutdown"]
