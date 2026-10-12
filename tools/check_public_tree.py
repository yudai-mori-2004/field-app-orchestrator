#!/usr/bin/env python3
"""Reject tracked files that should not enter the public repository."""

from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys


MAX_TRACKED_BYTES = 2 * 1024 * 1024

FORBIDDEN_PARTS = {
    ".private",
    "artifacts",
    "experiments",
    "logs",
    "scratch",
    "screenshots",
    "tmp",
}

FORBIDDEN_SUFFIXES = {
    ".cer",
    ".heic",
    ".ipa",
    ".key",
    ".m4a",
    ".mobileprovision",
    ".mov",
    ".mp4",
    ".p12",
    ".p8",
    ".pem",
    ".provisionprofile",
    ".wav",
    ".xcarchive",
    ".xcresult",
    ".xctestrun",
}

CONTENT_PATTERNS = (
    (
        "private key",
        re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    ),
    ("GitHub token", re.compile(rb"(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})")),
    ("AWS access key", re.compile(rb"(?:AKIA|ASIA)[0-9A-Z]{16}")),
    ("OpenAI-style key", re.compile(rb"sk-(?:proj-)?[A-Za-z0-9_-]{20,}")),
    ("Google API key", re.compile(rb"AIza[0-9A-Za-z_-]{20,}")),
    ("Slack token", re.compile(rb"xox[baprs]-[A-Za-z0-9-]{10,}")),
    ("macOS user path", re.compile(rb"/Users/[A-Za-z0-9._-]+/")),
    ("Windows user path", re.compile(rb"[A-Za-z]:\\\\Users\\\\[A-Za-z0-9._ -]+\\\\")),
    ("Apple development team", re.compile(rb"DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}")),
    (
        "physical-device destination",
        re.compile(rb"-destination\s+['\"]?id=(?!<)[A-Za-z0-9-]{16,}"),
    ),
    (
        "personal email address",
        re.compile(rb"[A-Za-z0-9._%+-]+@(?:gmail|icloud|me|outlook|hotmail|yahoo)\.[A-Za-z]{2,}"),
    ),
)


def tracked_paths() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        check=True,
        stdout=subprocess.PIPE,
    )
    return [Path(raw.decode("utf-8", errors="surrogateescape")) for raw in result.stdout.split(b"\0") if raw]


def line_number(data: bytes, offset: int) -> int:
    return data.count(b"\n", 0, offset) + 1


def inspect(path: Path) -> list[str]:
    problems: list[str] = []
    lowered_parts = {part.lower() for part in path.parts}
    if lowered_parts & FORBIDDEN_PARTS or tuple(part.lower() for part in path.parts[:2]) == ("config", "local"):
        problems.append(f"{path}: local or diagnostic directory is tracked")

    lowered_name = path.name.lower()
    if lowered_name == ".env" or (lowered_name.startswith(".env.") and lowered_name != ".env.example"):
        problems.append(f"{path}: environment file is tracked")
    if any(lowered_name.endswith(suffix) for suffix in FORBIDDEN_SUFFIXES):
        problems.append(f"{path}: sensitive or diagnostic file type is tracked")

    if path.is_symlink():
        problems.append(f"{path}: symbolic links are not allowed in the public tree")
        return problems

    data = path.read_bytes()
    if len(data) > MAX_TRACKED_BYTES:
        problems.append(f"{path}: tracked file exceeds {MAX_TRACKED_BYTES} bytes")
    for label, pattern in CONTENT_PATTERNS:
        match = pattern.search(data)
        if match:
            problems.append(f"{path}:{line_number(data, match.start())}: possible {label}")
    return problems


def main() -> int:
    problems = [problem for path in tracked_paths() for problem in inspect(path)]
    if problems:
        print("Public-tree safety check failed:", file=sys.stderr)
        for problem in problems:
            print(f"- {problem}", file=sys.stderr)
        return 1
    print("Public-tree safety check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
