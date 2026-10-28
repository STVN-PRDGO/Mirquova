#!/usr/bin/env python3
"""Publish concise Flutter test failure names to the GitHub check output."""

from pathlib import Path
import re
import sys


def escape_workflow_command(value: str) -> str:
    return (
        value.replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
        .replace(":", "%3A")
        .replace(",", "%2C")
    )


log_path, summary_path = map(Path, sys.argv[1:3])
platform = sys.argv[3] if len(sys.argv) > 3 else "Flutter"
lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
lines = [re.sub(r"\x1b\[[0-9;]*m", "", line) for line in lines]
failed = []
for line in lines:
    if re.search(r"\+\d+\s+-\d+:.*\[E\]", line):
        message = re.sub(r"^.*?\+\d+\s+-\d+:\s*", "", line).strip()
        if message not in failed:
            failed.append(message)

diagnostics = [
    line.strip()
    for line in lines
    if re.match(
        r"^\s*(Expected:|Actual:|Which:|Exception:|Bad state:|Error:|"
        r"Some tests failed\.|Test failed\.)",
        line,
    )
]
native_markers = [line.strip() for line in lines if "[native-pairing-smoke]" in line]

if not failed:
    failed = ["Flutter exited with failure; no expanded [E] test line was found."]

summary = [f"## {platform} Flutter test failures", ""]
for message in failed:
    print(
        f"::error title={platform} test failed::"
        f"{escape_workflow_command(message[:500])}"
    )
    summary.append(f"- {message}")
if diagnostics:
    summary.extend(["", "### Failure details", ""])
    summary.extend(f"- {line[:500]}" for line in diagnostics[:30])
if native_markers:
    summary.extend(["", "### Native smoke progress", ""])
    summary.extend(f"- {line[:500]}" for line in native_markers[-5:])
summary.append("")
with summary_path.open("a", encoding="utf-8") as summary_file:
    summary_file.write("\n".join(summary))
