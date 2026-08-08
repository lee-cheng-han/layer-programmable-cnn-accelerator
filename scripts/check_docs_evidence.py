#!/usr/bin/env python3
"""Check that README/result docs match the checked-in pre-board evidence."""

from __future__ import annotations

import re
import sys
from pathlib import Path


FLOW_REPORT = Path("docs/logs/pre_board_flow_report.md")
WARNING_REPORT = Path("docs/logs/pre_board_warning_budget.log")

SUMMARY_DOCS = [
    Path("README.md"),
    Path("docs/board_implementation.md"),
    Path("docs/performance_results.md"),
    Path("docs/synthesis_results.md"),
    Path("docs/case_study.md"),
]

STALE_PATTERNS = [
    "v2_image_to_image_architecture",
    "v2_top_implementation",
    "tb_cnn_accel_top_small",
    "6,355",
    "11.95%",
    "0.011 ns",
    "a ILA",
]


def require_match(pattern: str, text: str, source: Path) -> re.Match[str]:
    match = re.search(pattern, text, re.MULTILINE)
    if match is None:
        raise ValueError(f"{source}: could not find pattern: {pattern}")
    return match


def extract_flow_values() -> dict[str, str]:
    text = FLOW_REPORT.read_text()
    values = {
        "wns": require_match(r"\| WNS \| ([^|]+) ns \|", text, FLOW_REPORT).group(1).strip(),
        "whs": require_match(r"\| WHS \| ([^|]+) ns \|", text, FLOW_REPORT).group(1).strip(),
        "luts": require_match(r"\| Slice LUTs \| ([^|]+) \|", text, FLOW_REPORT).group(1).strip(),
        "regs": require_match(r"\| Slice Registers \| ([^|]+) \|", text, FLOW_REPORT).group(1).strip(),
        "lut_pct": require_match(r"\| Slice LUTs \| [^|]+ \| [^|]+ \| ([^|]+)% \|", text, FLOW_REPORT)
        .group(1)
        .strip(),
    }
    return values


def extract_warning_values() -> dict[str, str]:
    text = WARNING_REPORT.read_text()
    values = {
        "warnings": require_match(r"^Warnings: (\d+)$", text, WARNING_REPORT).group(1),
        "known": require_match(r"^Known warnings: (\d+)$", text, WARNING_REPORT).group(1),
        "unknown": require_match(r"^Unknown warnings: (\d+)$", text, WARNING_REPORT).group(1),
        "critical": require_match(r"^Critical warnings: (\d+)$", text, WARNING_REPORT).group(1),
        "errors": require_match(r"^Errors: (\d+)$", text, WARNING_REPORT).group(1),
    }
    return values


def comma_int(value: str) -> str:
    return f"{int(value.replace(',', '')):,}"


def check_doc(path: Path, needles: list[str], errors: list[str]) -> None:
    text = path.read_text()
    for needle in needles:
        if needle not in text:
            errors.append(f"{path}: missing expected evidence value `{needle}`")
    for stale in STALE_PATTERNS:
        if stale in text:
            errors.append(f"{path}: stale value/reference remains: `{stale}`")


def main() -> int:
    errors: list[str] = []

    for required in [FLOW_REPORT, WARNING_REPORT, *SUMMARY_DOCS]:
        if not required.exists():
            errors.append(f"missing required documentation file: {required}")

    if errors:
        for error in errors:
            print(error)
        return 1

    try:
        flow = extract_flow_values()
        warnings = extract_warning_values()
    except ValueError as exc:
        print(exc)
        return 1

    summary_needles = [
        comma_int(flow["luts"]),
        comma_int(flow["regs"]),
        f"{flow['lut_pct']}%",
        f"{flow['wns']} ns",
        f"{flow['whs']} ns",
    ]

    for doc in SUMMARY_DOCS:
        check_doc(doc, summary_needles, errors)

    warning_text = WARNING_REPORT.read_text()
    for key, expected in {
        "Warnings": warnings["warnings"],
        "Known warnings": warnings["known"],
        "Unknown warnings": warnings["unknown"],
        "Critical warnings": warnings["critical"],
        "Errors": warnings["errors"],
    }.items():
        if f"{key}: {expected}" not in warning_text:
            errors.append(f"{WARNING_REPORT}: missing `{key}: {expected}`")

    if errors:
        print("Documentation evidence check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    print("PASS: README/result docs match checked-in pre-board evidence.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
