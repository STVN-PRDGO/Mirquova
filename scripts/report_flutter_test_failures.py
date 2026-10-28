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
failure_details = []
for index, line in enumerate(lines):
    if re.search(r"\+\d+\s+-\d+:.*\[E\]", line):
        message = re.sub(r"^.*?\+\d+\s+-\d+:\s*", "", line).strip()
        if message not in failed:
            failed.append(message)
        context = []
        for following in lines[index + 1 : index + 16]:
            if re.search(r"\+\d+\s+-\d+:.*\[E\]", following):
                break
            if following.strip():
                context.append(following.strip())
            if len(context) >= 8:
                break
        if context:
            failure_details.append((message, "\n".join(context)))

diagnostics = [
    line.strip()
    for line in lines
    if re.match(
        r"^\s*(?:Expected:|Actual:|Which:|Exception:|Bad state:|Error:|"
        r"Some tests failed\.|Test failed\.)|.*(?:TimeoutExpired|timed out after)",
        line,
    )
]
native_markers = [line.strip() for line in lines if "[native-pairing-smoke]" in line]

if not failed:
    failed = ["Flutter exited with failure; no expanded [E] test line was found."]
if not failure_details:
    tail = [line.strip() for line in lines[-40:] if line.strip()]
else:
    tail = []

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
    for line in diagnostics[:30]:
        print(
            f"::error title={platform} test diagnostic::"
            f"{escape_workflow_command(line[:500])}"
        )
for message, context in failure_details[:10]:
    detail = f"{message}\n{context}"[:3000]
    print(
        f"::error title={platform} failure detail::"
        f"{escape_workflow_command(detail)}"
    )
    summary.extend(["", f"### {message}", "", context])
if tail:
    excerpt = "\n".join(tail)[:6000]
    print(
        f"::error title={platform} final test output::"
        f"{escape_workflow_command(excerpt)}"
    )
    summary.extend(["", "### Final test output", "", excerpt])
if native_markers:
    summary.extend(["", "### Native smoke progress", ""])
    summary.extend(f"- {line[:500]}" for line in native_markers[-5:])
    for line in native_markers[-5:]:
        print(
            f"::notice title={platform} smoke progress::"
            f"{escape_workflow_command(line[:500])}"
        )
summary.append("")
with summary_path.open("a", encoding="utf-8") as summary_file:
    summary_file.write("\n".join(summary))
