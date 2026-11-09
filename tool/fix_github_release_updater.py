#!/usr/bin/env python3
"""Fix MusikKu's updater allowlist after the GitHub repository was renamed.

Run from the root of the MusikKu Flutter project:
    python tool/fix_github_release_updater.py

The script only changes exact, expected URL/version strings and refuses to
silently overwrite an unknown/newer version.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path.cwd()
UPDATER = ROOT / "lib/services/app_update_service.dart"
ACTIVITY = ROOT / "android/app/src/main/kotlin/com/musikku/app/MainActivity.kt"
PUBSPEC = ROOT / "pubspec.yaml"
APP_INFO = ROOT / "lib/app_info.dart"
TARGET_VERSION = "5.0.50"
TARGET_BUILD = "28"
TARGET_SPEC = f"{TARGET_VERSION}+{TARGET_BUILD}"


def fail(message: str) -> int:
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def replace_once(data: bytes, old: bytes, new: bytes, label: str) -> bytes:
    if new in data:
        return data  # Already patched; idempotent, including dual-path allowlists.
    count = data.count(old)
    if count != 1:
        raise ValueError(
            f"Expected exactly one old occurrence for {label}, found {count}. "
            "No files have been written; inspect the current source first."
        )
    return data.replace(old, new, 1)


def patch_updater(data: bytes) -> bytes:
    replacements = [
        (b"static const String repository = 'flutter_application_5';",
         b"static const String repository = 'Musikku';",
         "repository constant"),
        (b"https://github.com/Rulzz77/flutter_application_5/releases",
         b"https://github.com/Rulzz77/Musikku/releases",
         "release page URL"),
        (b"https://api.github.com/repos/Rulzz77/flutter_application_5/releases/latest",
         b"https://api.github.com/repos/Rulzz77/Musikku/releases/latest",
         "latest release API URL"),
        (
            b"return uri.path.toLowerCase().startsWith(\n"
            b"        '/rulzz77/flutter_application_5/releases/download/',\n"
            b"      );",
            b"final path = uri.path.toLowerCase();\n"
            b"      // Accept the canonical repository path and the former alias.\n"
            b"      return path.startsWith('/rulzz77/musikku/releases/download/') ||\n"
            b"          path.startsWith('/rulzz77/flutter_application_5/releases/download/');",
            "download redirect allowlist"),
        (
            b"uri.path.toLowerCase().startsWith('/rulzz77/flutter_application_5/releases')",
            b"(uri.path.toLowerCase().startsWith('/rulzz77/musikku/releases') ||\n"
            b"            uri.path.toLowerCase().startsWith('/rulzz77/flutter_application_5/releases'))",
            "release page allowlist"),
        (
            b"uri.path.toLowerCase().startsWith('/rulzz77/flutter_application_5/releases/download/')",
            b"(uri.path.toLowerCase().startsWith('/rulzz77/musikku/releases/download/') ||\n"
            b"            uri.path.toLowerCase().startsWith('/rulzz77/flutter_application_5/releases/download/'))",
            "APK asset allowlist"),
    ]
    for old, new, label in replacements:
        data = replace_once(data, old, new, label)
    return data


def main() -> int:
    required = (UPDATER, ACTIVITY, PUBSPEC, APP_INFO)
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    if missing:
        return fail(
            "Run this script from the root of the MusikKu Flutter project. Missing: "
            + ", ".join(missing)
        )

    # Avoid downgrading a source tree that has advanced beyond the currently
    # published v5.0.49. A clean version bump is needed because release tags are
    # based on VERSION_NAME, not the build number.
    pubspec_data = PUBSPEC.read_bytes()
    version_match = re.search(rb"(?m)^version:\s*['\"]?([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)['\"]?\s*$", pubspec_data)
    if not version_match:
        return fail("Could not parse pubspec.yaml version. Expected NAME+BUILD, e.g. 5.0.49+27.")
    current_name = tuple(int(v) for v in version_match.group(1).decode().split('.'))
    current_build = int(version_match.group(2))
    target_name = tuple(int(v) for v in TARGET_VERSION.split('.'))
    if current_name > target_name:
        return fail(
            f"Current version {version_match.group(1).decode()} is newer than {TARGET_VERSION}. "
            "Patch the URLs only and choose a new, unused VERSION_NAME manually."
        )
    if current_name == target_name and current_build != int(TARGET_BUILD):
        return fail(
            f"pubspec.yaml already uses VERSION_NAME {TARGET_VERSION} with build {current_build}. "
            "Because the release tag is version-name based, select the next unused version manually."
        )

    try:
        updater_data = patch_updater(UPDATER.read_bytes())
        activity_data = replace_once(
            ACTIVITY.read_bytes(),
            b'https://github.com/Rulzz77/flutter_application_5/releases',
            b'https://github.com/Rulzz77/Musikku/releases',
            "MainActivity release page URL",
        )
    except ValueError as error:
        return fail(str(error))

    # If the project is below the next public release, advance it to the next
    # unused tag observed at patch creation time: v5.0.50 (build 28).
    if current_name < target_name:
        pubspec_data, count = re.subn(
            rb"(?m)^version:\s*[^\r\n]+$",
            f"version: {TARGET_SPEC}".encode(),
            pubspec_data,
            count=1,
        )
        if count != 1:
            return fail("Could not update the version line in pubspec.yaml.")
        app_info_data = APP_INFO.read_bytes()
        app_info_data, version_count = re.subn(
            rb"(?m)^const String appVersion = '[^']*';$",
            f"const String appVersion = '{TARGET_VERSION}';".encode(),
            app_info_data,
            count=1,
        )
        app_info_data, build_count = re.subn(
            rb"(?m)^const String appBuildNumber = '[^']*';$",
            f"const String appBuildNumber = '{TARGET_BUILD}';".encode(),
            app_info_data,
            count=1,
        )
        if version_count != 1 or build_count != 1:
            return fail("Could not synchronize version constants in lib/app_info.dart.")
    else:
        app_info_data = APP_INFO.read_bytes()
        # Ensure constants agree if the version was already set to the target.
        app_info_data, version_count = re.subn(
            rb"(?m)^const String appVersion = '[^']*';$",
            f"const String appVersion = '{TARGET_VERSION}';".encode(),
            app_info_data,
            count=1,
        )
        app_info_data, build_count = re.subn(
            rb"(?m)^const String appBuildNumber = '[^']*';$",
            f"const String appBuildNumber = '{TARGET_BUILD}';".encode(),
            app_info_data,
            count=1,
        )
        if version_count != 1 or build_count != 1:
            return fail("Could not synchronize version constants in lib/app_info.dart.")

    # Write only after every expected string and version has been validated.
    UPDATER.write_bytes(updater_data)
    ACTIVITY.write_bytes(activity_data)
    PUBSPEC.write_bytes(pubspec_data)
    APP_INFO.write_bytes(app_info_data)

    print("Fixed GitHub release updater URLs and allowlists.")
    print(f"Synchronized app version to {TARGET_SPEC}.")
    print("Changed files:")
    print("  lib/services/app_update_service.dart")
    print("  android/app/src/main/kotlin/com/musikku/app/MainActivity.kt")
    print("  pubspec.yaml")
    print("  lib/app_info.dart")
    print("\nNext: review changes, run flutter analyze, then build/publish a new release.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
