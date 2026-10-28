#!/usr/bin/env python3
"""Stream a Flutter smoke command to Actions while retaining its full output."""

from pathlib import Path
import subprocess
import sys


log_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
platform = sys.argv[3]
command = sys.argv[4:]
reporter = Path(__file__).with_name("report_flutter_test_failures.py")

with log_path.open("w", encoding="utf-8") as log_file:
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    assert process.stdout is not None
    for line in process.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        log_file.write(line)
        log_file.flush()
    return_code = process.wait()

if return_code != 0:
    subprocess.run(
        [sys.executable, str(reporter), str(log_path), str(summary_path), platform],
        check=False,
    )
sys.exit(return_code)
