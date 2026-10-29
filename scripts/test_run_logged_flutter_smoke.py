#!/usr/bin/env python3
"""Regression tests for bounded, streamed native smoke commands."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts" / "run_logged_flutter_smoke.py"


class LoggedSmokeRunnerTests(unittest.TestCase):
    def run_smoke(self, directory: Path, timeout: int, *command: str):
        log_path = directory / "smoke.log"
        summary_path = directory / "summary.md"
        result = subprocess.run(
            [
                sys.executable,
                str(RUNNER),
                str(log_path),
                str(summary_path),
                "Synthetic",
                str(timeout),
                *command,
            ],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        return result, log_path, summary_path

    def test_success_streams_and_retains_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            result, log_path, _ = self.run_smoke(
                Path(temporary), 5, sys.executable, "-c", "print(123)"
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("123", result.stdout)
            self.assertIn("123", log_path.read_text(encoding="utf-8"))

    def test_failure_is_reported_and_retained(self):
        with tempfile.TemporaryDirectory() as temporary:
            result, log_path, summary_path = self.run_smoke(
                Path(temporary), 5, sys.executable, "-c", "raise SystemExit(7)"
            )
            self.assertEqual(result.returncode, 7)
            self.assertTrue(log_path.exists())
            self.assertIn("Synthetic Flutter test failures", summary_path.read_text())

    @unittest.skipUnless(os.name == "posix", "requires POSIX process groups")
    def test_timeout_kills_child_that_keeps_output_pipe_open(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            child_pid_path = directory / "child.pid"
            child_code = "import time; time.sleep(30)"
            parent_code = (
                "import subprocess,sys; "
                "child=subprocess.Popen([sys.executable,'-c',sys.argv[1]]); "
                "open(sys.argv[2],'w').write(str(child.pid))"
            )
            result, log_path, summary_path = self.run_smoke(
                directory,
                1,
                sys.executable,
                "-c",
                parent_code,
                child_code,
                str(child_pid_path),
            )
            self.assertEqual(result.returncode, 124, result.stderr)
            log = log_path.read_text(encoding="utf-8")
            self.assertTrue(log.rstrip().endswith("[smoke-timeout] Synthetic smoke exceeded 1 seconds."))
            self.assertIn("smoke-timeout", summary_path.read_text(encoding="utf-8"))
            child_pid = int(child_pid_path.read_text(encoding="utf-8"))

            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                probe = subprocess.run(
                    ["ps", "-o", "stat=", "-p", str(child_pid)],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                state = probe.stdout.strip()
                if not state or state.startswith("Z"):
                    break
                time.sleep(0.05)
            else:
                self.fail(f"Smoke child process {child_pid} is still running.")


if __name__ == "__main__":
    unittest.main(verbosity=2)
