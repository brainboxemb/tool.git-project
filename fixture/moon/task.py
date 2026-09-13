#!/usr/bin/env python3
"""Tiny cross-platform producer used only by the Moon owner regression test."""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "fixture" / "moon"
OUT = FIXTURE / "out"
EVIDENCE = OUT / "evidence"
STATE = FIXTURE / ".executions"

OUT.mkdir(parents=True, exist_ok=True)
EVIDENCE.mkdir(parents=True, exist_ok=True)
STATE.mkdir(parents=True, exist_ok=True)

source = (FIXTURE / "input.txt").read_text(encoding="utf-8").strip()
revision = subprocess.run(
    ["git", "rev-parse", "HEAD"],
    cwd=ROOT,
    check=True,
    text=True,
    capture_output=True,
).stdout.strip()

payload = f"revision={revision}\ninput={source}\n"
(OUT / "artifact.txt").write_text(payload, encoding="utf-8")
(EVIDENCE / "execution.log").write_text(
    "fixture producer executed\n" + payload,
    encoding="utf-8",
)

counter = STATE / "count.txt"
count = int(counter.read_text(encoding="utf-8")) if counter.exists() else 0
counter.write_text(f"{count + 1}\n", encoding="utf-8")
