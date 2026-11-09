#!/usr/bin/env python3
"""Synchronize lib/app_info.dart with the version in pubspec.yaml.

Run after changing pubspec.yaml:
    python3 tool/sync_app_version.py
Check without writing:
    python3 tool/sync_app_version.py --check
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PUBSPEC = ROOT / "pubspec.yaml"
APP_INFO = ROOT / "lib" / "app_info.dart"
VERSION_LINE = re.compile(r"(?m)^version:\s*['\"]?([^\s'\"#]+)['\"]?\s*(?:#.*)?$")
NAME_PATTERN = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$")
BUILD_PATTERN = re.compile(r"^[0-9]+$")


def fail(message: str) -> int:
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail instead of modifying app_info.dart")
    parser.add_argument("--print-version", action="store_true", help="print normalized NAME+BUILD and exit")
    args = parser.parse_args()

    if not PUBSPEC.is_file() or not APP_INFO.is_file():
        return fail("Run this script from a MusikKu project that contains pubspec.yaml and lib/app_info.dart.")

    pubspec = PUBSPEC.read_text(encoding="utf-8")
    match = VERSION_LINE.search(pubspec)
    if not match:
        return fail("Could not read a version entry from pubspec.yaml.")

    version_spec = match.group(1)
    if version_spec.count("+") != 1:
        return fail("pubspec.yaml version must be NAME+BUILD, for example 5.0.9+93.")
    version_name, build_number = version_spec.split("+", 1)
    if not NAME_PATTERN.fullmatch(version_name) or not BUILD_PATTERN.fullmatch(build_number):
        return fail(f"Invalid version '{version_spec}'. Expected NAME+numeric BUILD, e.g. 5.0.9+93.")

    if args.print_version:
        print(f"{version_name}+{build_number}")
        return 0

    source = APP_INFO.read_text(encoding="utf-8")
    replacements = [
        (re.compile(r"(?m)^const String appVersion = '[^']*';$"), f"const String appVersion = '{version_name}';", "appVersion"),
        (re.compile(r"(?m)^const String appBuildNumber = '[^']*';$"), f"const String appBuildNumber = '{build_number}';", "appBuildNumber"),
    ]

    updated = source
    for pattern, replacement, label in replacements:
        updated, count = pattern.subn(lambda _m, r=replacement: r, updated, count=1)
        if count != 1:
            return fail(f"Expected exactly one declaration of {label} in lib/app_info.dart.")

    if updated == source:
        print(f"Version already synchronized: {version_name}+{build_number}")
        return 0

    if args.check:
        return fail(f"lib/app_info.dart is stale. Run: python3 tool/sync_app_version.py (expected {version_name}+{build_number}).")

    APP_INFO.write_text(updated, encoding="utf-8", newline="")
    print(f"Synchronized lib/app_info.dart to {version_name}+{build_number} from pubspec.yaml")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
