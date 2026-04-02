from __future__ import annotations

import csv
import re
import shutil
import sqlite3
import subprocess
from pathlib import Path

from app import config


RUN_ID_PATTERN = re.compile(r"Run ID:\s+([^\s]+)")


def stringify(cmd: list[str]) -> str:
    return " ".join(cmd)


def run_command(cmd: list[str], capture: bool = False) -> str:
    print(f"$ {stringify(cmd)}")
    if not capture:
        subprocess.run(cmd, check=True)
        return ""

    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert process.stdout is not None

    lines: list[str] = []
    for line in process.stdout:
        print(line, end="")
        lines.append(line)

    exit_code = process.wait()
    if exit_code != 0:
        raise subprocess.CalledProcessError(exit_code, cmd, output="".join(lines))
    return "".join(lines)


def docker_ruby(*args: str) -> list[str]:
    script, *rest = args
    return ["docker", "compose", "run", "--rm", "mcp-scanner", "ruby", f"app/ruby/{script}", *rest]


def sync_prefix(source_base: Path, latest_base: Path, suffixes: list[str]) -> None:
    latest_base.parent.mkdir(parents=True, exist_ok=True)
    for suffix in suffixes:
        source = source_base.with_suffix(suffix)
        if source.exists():
            shutil.copyfile(source, latest_base.with_suffix(suffix))


def newest_base(pattern: str) -> Path:
    matches = sorted(config.PROCESSED_DIR.glob(pattern), key=lambda path: path.stat().st_mtime, reverse=True)
    if not matches:
        raise FileNotFoundError(f"No files found for pattern: {pattern}")
    return matches[0].with_suffix("")


def latest_scan_run_id() -> str:
    if not config.DB_PATH.exists():
        raise FileNotFoundError(f"Scan database not found: {config.DB_PATH}")

    with sqlite3.connect(config.DB_PATH) as conn:
        row = conn.execute(
            "SELECT run_id FROM scans WHERE run_id IS NOT NULL AND run_id <> '' ORDER BY scanned_at DESC LIMIT 1"
        ).fetchone()
    if not row or not row[0]:
        raise RuntimeError("No scan run found in mcp_scans.db")
    return str(row[0])


def split_master_csv(input_csv: Path, active_output: Path, inactive_output: Path) -> tuple[int, int]:
    active_output.parent.mkdir(parents=True, exist_ok=True)
    inactive_output.parent.mkdir(parents=True, exist_ok=True)

    with input_csv.open("r", encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        headers = reader.fieldnames or []
        active_rows: list[dict[str, str]] = []
        inactive_rows: list[dict[str, str]] = []

        for row in reader:
            target = active_rows if row.get("website_active", "0").strip() == "1" else inactive_rows
            target.append(row)

    with active_output.open("w", encoding="utf-8", newline="") as target:
        writer = csv.DictWriter(target, fieldnames=headers)
        writer.writeheader()
        writer.writerows(active_rows)

    with inactive_output.open("w", encoding="utf-8", newline="") as target:
        writer = csv.DictWriter(target, fieldnames=headers)
        writer.writeheader()
        writer.writerows(inactive_rows)

    return len(active_rows), len(inactive_rows)
