#!/usr/bin/env python3
"""Validate UVM requirement traceability and coverage-goal metadata."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "verification" / "uvm_signoff.json"
SOURCE_FILES = (
    ROOT / "verification" / "uvm" / "cnn_uvm_pkg.sv",
    ROOT / "verification" / "uvm" / "cnn_uvm_tests_pkg.sv",
    ROOT / "verification" / "uvm" / "interfaces" / "cnn_axi_lite_if.sv",
    ROOT / "verification" / "uvm" / "interfaces" / "cnn_axis_if.sv",
    ROOT / "verification" / "uvm" / "interfaces" / "cnn_status_if.sv",
)
TARGETS = {"functional", "statement", "branch", "condition", "toggle", "assertion"}
ID_PATTERN = re.compile(r"^REQ-[A-Z]+-[0-9]{3}$")


def fail(message: str) -> None:
    raise ValueError(message)


def main() -> int:
    data = json.loads(MANIFEST.read_text(encoding="ascii"))
    if data.get("schema_version") != 1:
        fail("unsupported UVM signoff schema_version")

    targets = data.get("coverage_targets_percent", {})
    if set(targets) != TARGETS:
        fail(f"coverage targets must be exactly {sorted(TARGETS)}")
    for name, target in targets.items():
        if not isinstance(target, (int, float)) or not 0.0 < float(target) <= 100.0:
            fail(f"invalid {name} coverage target {target!r}")

    exclusions = data.get("exclusions")
    if not isinstance(exclusions, list):
        fail("exclusions must be a list")
    for exclusion in exclusions:
        if not all(exclusion.get(field) for field in ("id", "scope", "reason", "owner")):
            fail("each exclusion requires id, scope, reason, and owner")

    source = "\n".join(path.read_text(encoding="ascii") for path in SOURCE_FILES)
    test_symbols = set(re.findall(r"class\s+(cnn_uvm_[A-Za-z0-9_]+_test)\b", source))
    test_symbols.discard("cnn_uvm_base_test")
    assertion_symbols = set(re.findall(r"\b([ac]_[A-Za-z0-9_]+)\s*:\s*(?:assert|cover)\s+property", source))
    coverage_symbols = set(re.findall(r"\b([A-Za-z][A-Za-z0-9_]*)\s*:\s*(?:coverpoint|cross)\b", source))
    coverage_symbols.update(re.findall(r"covergroup\s+([A-Za-z][A-Za-z0-9_]*)", source))

    requirements = data.get("requirements")
    if not isinstance(requirements, list) or not requirements:
        fail("requirements must be a non-empty list")
    seen_ids: set[str] = set()
    for requirement in requirements:
        requirement_id = requirement.get("id", "")
        if not ID_PATTERN.fullmatch(requirement_id):
            fail(f"invalid requirement id {requirement_id!r}")
        if requirement_id in seen_ids:
            fail(f"duplicate requirement id {requirement_id}")
        seen_ids.add(requirement_id)
        if not requirement.get("description"):
            fail(f"{requirement_id} has no description")
        for field in ("tests", "assertions", "coverpoints"):
            if not requirement.get(field):
                fail(f"{requirement_id} has no {field} mapping")
        for test in requirement["tests"]:
            if test not in test_symbols:
                fail(f"{requirement_id} references unknown test {test}")
        for assertion in requirement["assertions"]:
            if assertion not in assertion_symbols:
                fail(f"{requirement_id} references unknown assertion {assertion}")
        for coverpoint in requirement["coverpoints"]:
            if coverpoint not in coverage_symbols and coverpoint not in assertion_symbols:
                fail(f"{requirement_id} references unknown coverpoint {coverpoint}")

    print(
        "PASS: UVM signoff manifest "
        f"requirements={len(requirements)} tests={len(test_symbols)} "
        f"assertions/covers={len(assertion_symbols)} targets={len(targets)}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
