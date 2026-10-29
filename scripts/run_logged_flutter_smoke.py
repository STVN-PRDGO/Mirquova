#!/usr/bin/env python3
"""Run a bounded Flutter smoke command, stream its log, and report failures."""

from pathlib import Path
import os
import queue
import signal
import subprocess
import sys
import threading
import time


log_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
platform = sys.argv[3]
timeout_seconds = float(sys.argv[4])
command = sys.argv[5:]
if not command:
    raise SystemExit("A smoke command is required.")
reporter = Path(__file__).with_name("report_flutter_test_failures.py")
output: queue.Queue[str | None] = queue.Queue()


with log_path.open("w", encoding="utf-8") as log_file:
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
        start_new_session=(os.name == "posix"),
    )
    assert process.stdout is not None

    def forward_output() -> None:
        try:
            for line in process.stdout:
                output.put(line)
        finally:
            output.put(None)

    reader = threading.Thread(target=forward_output, daemon=True)
    reader.start()
    deadline = time.monotonic() + timeout_seconds
    timed_out = False
    stream_ended = False

    while True:
        if stream_ended and process.poll() is not None:
            break
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            timed_out = True
            break
        try:
            line = output.get(timeout=min(remaining, 0.5))
        except queue.Empty:
            if process.poll() is not None and not reader.is_alive():
                break
            continue
        if line is None:
            stream_ended = True
            continue
        sys.stdout.write(line)
        sys.stdout.flush()
        log_file.write(line)
        log_file.flush()

    if timed_out:
        grace_deadline = time.monotonic() + 5
        if os.name == "posix":
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        else:
            process.terminate()
        try:
            process.wait(timeout=max(0, grace_deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            if os.name == "posix":
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            else:
                process.kill()
            process.wait()
        if os.name == "posix":
            while time.monotonic() < grace_deadline:
                try:
                    os.killpg(process.pid, 0)
                except ProcessLookupError:
                    break
                time.sleep(0.05)
            else:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
    return_code = process.wait()
    reader.join(timeout=5)

if timed_out:
    while True:
        try:
            line = output.get_nowait()
        except queue.Empty:
            break
        if line is not None:
            sys.stdout.write(line)
            sys.stdout.flush()
            with log_path.open("a", encoding="utf-8") as log_file:
                log_file.write(line)
    message = f"[smoke-timeout] {platform} smoke exceeded {timeout_seconds:g} seconds.\n"
    sys.stderr.write(message)
    with log_path.open("a", encoding="utf-8") as log_file:
        log_file.write(message)
    return_code = 124
if return_code != 0:
    subprocess.run(
        [sys.executable, str(reporter), str(log_path), str(summary_path), platform],
        check=False,
    )
sys.exit(return_code)
