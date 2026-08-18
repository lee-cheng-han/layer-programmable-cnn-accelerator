#!/usr/bin/env python3
"""Summarize measured XSim code and functional coverage."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


CODE_LABELS = ("statement", "branch", "condition", "toggle")


def parse_code_dashboard(path: Path) -> dict[str, float]:
    text = path.read_text(encoding="utf-8")
    match = re.search(
        r"<td class='dashTable'>([0-9.]+)</td>\s*"
        r"<td class='dashTable'>([0-9.]+)</td>\s*"
        r"<td class='dashTable'>([0-9.]+)</td>\s*"
        r"<td class='dashTable'>([0-9.]+)</td>",
        text,
    )
    if match is None:
        raise ValueError(f"coverage scores not found in {path}")
    return dict(zip(CODE_LABELS, map(float, match.groups()), strict=True))


def parse_functional_report(path: Path) -> float:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"Coverage Score\s*:,\s*([0-9.]+)", text)
    if match is None:
        raise ValueError(f"functional coverage score not found in {path}")
    return float(match.group(1))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--coverage-root", type=Path, required=True)
    parser.add_argument(
        "--manifest", type=Path, default=Path("verification/uvm_signoff.json")
    )
    parser.add_argument(
        "--require-targets",
        action="store_true",
        help="return failure unless every declared coverage target is met",
    )
    args = parser.parse_args()

    report_root = args.coverage_root / "report"
    code_report = report_root / "code" / "codeCoverageReport" / "dashboard.html"
    if not code_report.is_file():
        code_report = report_root / "codeCoverageReport" / "dashboard.html"
    functional_report = (
        report_root
        / "functional"
        / "functionalCoverageReport"
        / "xcrg_func_cov_report.txt"
    )
    if not functional_report.is_file():
        functional_report = (
            args.coverage_root
            / "report-functional"
            / "functionalCoverageReport"
            / "xcrg_func_cov_report.txt"
        )
    scores = {"functional": parse_functional_report(functional_report)}
    if code_report.is_file():
        scores.update(parse_code_dashboard(code_report))
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    targets = manifest["coverage_targets_percent"]
    results = {
        name: {
            "measured": round(value, 4),
            "target": targets.get(name),
            "met": targets.get(name) is None or value >= targets[name],
        }
        for name, value in scores.items()
    }
    for name in CODE_LABELS:
        if name not in results:
            results[name] = {
                "measured": None,
                "target": targets[name],
                "met": False,
                "status": "unmeasured",
                "note": "The merged code database exists, but xcrg did not emit its HTML report.",
            }
    assertion_target = targets["assertion"]
    results["assertion"] = {
        "measured": None,
        "target": assertion_target,
        "met": False,
        "status": "unmeasured",
        "note": "Assertion failures are checked by the campaign, but assertion coverage was not emitted by xcrg.",
    }
    output = {
        "tool": "Vivado Simulator 2025.2",
        "campaign_cases": len(
            list((args.coverage_root / "databases" / "xsim.covdb").glob("*"))
        ),
        "results": results,
        "all_targets_met": all(result["met"] for result in results.values()),
    }
    output_path = args.coverage_root / "coverage_summary.json"
    output_path.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    for name in ("functional", *CODE_LABELS):
        result = results[name]
        if result["measured"] is None:
            print(
                f"UNMEASURED: {name} coverage has no xcrg score "
                f"(target={result['target']:.2f}%)"
            )
            continue
        status = "PASS" if result["met"] else "GAP"
        print(
            f"{status}: {name} measured={result['measured']:.2f}% "
            f"target={result['target']:.2f}%"
        )
    print(
        "UNMEASURED: assertion coverage has no xcrg score "
        f"(target={assertion_target:.2f}%)"
    )
    print(f"Wrote {output_path}")
    if args.require_targets and not output["all_targets_met"]:
        print("ERROR: U5 coverage targets are not closed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
