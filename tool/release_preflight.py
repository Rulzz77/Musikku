#!/usr/bin/env python3
"""Offline static preflight for the MusikKu source bundle (not a Dart compiler)."""
from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
errors: list[str] = []
notes: list[str] = []
checks = 0


def check(condition: bool, success: str, failure: str) -> None:
    global checks
    checks += 1
    if condition:
        print(f"[PASS] {success}")
    else:
        errors.append(failure)
        print(f"[FAIL] {failure}")


pubspec_path = ROOT / "pubspec.yaml"
app_info_path = ROOT / "lib/app_info.dart"
manifest_path = ROOT / "android/app/src/main/AndroidManifest.xml"
network_path = ROOT / "android/app/src/main/res/xml/network_security_config.xml"
gradle_path = ROOT / "android/app/build.gradle.kts"

pubspec = pubspec_path.read_text(encoding="utf-8") if pubspec_path.exists() else ""
app_info = app_info_path.read_text(encoding="utf-8") if app_info_path.exists() else ""
version_match = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$", pubspec, re.M)
app_version_match = re.search(r"const String appVersion = '([^']+)';", app_info)
check(version_match is not None, "pubspec.yaml has a semantic version and build number", "pubspec.yaml version is missing or malformed")
check(app_version_match is not None, "app_info.dart declares appVersion", "lib/app_info.dart appVersion is missing")
if version_match and app_version_match:
    check(version_match.group(1) == app_version_match.group(1),
          "pubspec and app_info version names are synchronized",
          f"version mismatch: pubspec={version_match.group(1)} app_info={app_version_match.group(1)}")

asset = ROOT / "assets/icon/app_icon.png"
check(asset.is_file() and asset.stat().st_size > 0, "launcher icon asset exists", "assets/icon/app_icon.png is missing or empty")

# Ensure all relative Dart import/export/part paths point to a file in this project.
missing_refs: list[str] = []
for dart_file in sorted((ROOT / "lib").rglob("*.dart")) + sorted((ROOT / "test").rglob("*.dart")):
    try:
        source = dart_file.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        errors.append(f"could not decode Dart source: {dart_file.relative_to(ROOT)}")
        continue
    for match in re.finditer(r"^\s*(?:import|export|part)\s+['\"]([^'\"]+)['\"]", source, re.M):
        uri = match.group(1)
        if uri.startswith(("dart:", "package:")):
            continue
        target = (dart_file.parent / uri).resolve()
        if not target.is_file():
            missing_refs.append(f"{dart_file.relative_to(ROOT)} -> {uri}")
check(not missing_refs, "all relative Dart imports/exports/parts resolve", "missing Dart references: " + "; ".join(missing_refs[:8]))

# Parse all Android XML resources and manifests to catch malformed XML.
xml_files = sorted((ROOT / "android/app/src").rglob("*.xml"))
xml_errors: list[str] = []
for xml_file in xml_files:
    try:
        ET.parse(xml_file)
    except ET.ParseError as exc:
        xml_errors.append(f"{xml_file.relative_to(ROOT)}: {exc}")
check(bool(xml_files) and not xml_errors, f"parsed {len(xml_files)} Android XML files", "Android XML parse errors: " + "; ".join(xml_errors[:5]))

if manifest_path.exists():
    manifest_tree = ET.parse(manifest_path)
    manifest = manifest_tree.getroot()
    application = manifest.find("application")
    check(application is not None and application.get(ANDROID_NS + "networkSecurityConfig") == "@xml/network_security_config",
          "main manifest links network_security_config.xml", "main manifest does not link network_security_config.xml")
    check(application is not None and application.get(ANDROID_NS + "usesCleartextTraffic") == "false",
          "cleartext traffic is disabled in the manifest", "cleartext traffic is not explicitly disabled")
    permissions = {node.get(ANDROID_NS + "name"): node for node in manifest.findall("uses-permission")}
    check("android.permission.READ_MEDIA_AUDIO" in permissions,
          "READ_MEDIA_AUDIO is declared", "READ_MEDIA_AUDIO permission is missing")
    old_perm = permissions.get("android.permission.READ_EXTERNAL_STORAGE")
    check(old_perm is not None and old_perm.get(ANDROID_NS + "maxSdkVersion") == "32",
          "legacy storage permission is capped at API 32", "READ_EXTERNAL_STORAGE missing or lacks maxSdkVersion=32")
    if "android.permission.REQUEST_INSTALL_PACKAGES" in permissions:
        notes.append("REQUEST_INSTALL_PACKAGES remains because the app includes an in-app APK updater; remove it only if updater UI/native code is also removed.")
else:
    check(False, "main manifest exists", "main AndroidManifest.xml is missing")

if network_path.exists():
    network_text = network_path.read_text(encoding="utf-8")
    check("<base-config cleartextTrafficPermitted=\"false\"" in network_text,
          "network security config denies cleartext", "network_security_config.xml does not deny cleartext")
else:
    check(False, "network security config exists", "network_security_config.xml is missing")

gradle = gradle_path.read_text(encoding="utf-8") if gradle_path.exists() else ""
check("gradle.taskGraph.whenReady" in gradle and "releaseVariantInGraph" in gradle,
      "release signing guard checks the resolved Gradle task graph", "release signing guard is missing or incomplete")
check('signingConfig = signingConfigs.getByName("release")' in gradle,
      "release build explicitly uses the release signing config", "release signing config is not explicitly assigned")

radio_source = (ROOT / "lib/services/radio_service.dart").read_text(encoding="utf-8") if (ROOT / "lib/services/radio_service.dart").exists() else ""
check("required this.currentVideoId" in radio_source and "void Function(String message)? onError" in radio_source,
      "RadioService exposes public constructor parameter names", "RadioService constructor does not expose currentVideoId/onError")
check("required this._currentVideoId" not in radio_source and "this._onError," not in radio_source,
      "RadioService has no private named field-formal parameters", "private named field-formal constructor parameters remain")

required_tests = [
    ROOT / "test/services/queue_manager_test.dart",
    ROOT / "test/services/app_update_service_test.dart",
    ROOT / "test/services/radio_service_test.dart",
]
check(all(path.is_file() for path in required_tests), "queue, updater, and radio regression tests exist", "one or more expected regression test files are missing")

archive_candidates = ROOT.parent / "Audit_Archive/unused_source_candidates"
check(archive_candidates.is_dir() and len(list(archive_candidates.rglob("*.dart"))) >= 8,
      "legacy Dart candidates are retained outside active lib/", "legacy audit archive is missing or incomplete")

# A source ZIP should omit machine-local configuration, but a local developer may
# add these files before running this script. Warn instead of failing in that case.
if (ROOT / "android/key.properties").exists():
    notes.append("android/key.properties exists locally. Keep the signing config/keystore out of Git and public ZIPs.")
else:
    print("[PASS] production key.properties is absent from the clean source bundle")
    checks += 1
if (ROOT / "android/local.properties").exists():
    notes.append("android/local.properties exists locally. Keep this machine-specific path out of Git and public ZIPs.")
else:
    print("[PASS] machine-local local.properties is absent from the clean source bundle")
    checks += 1
gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8") if (ROOT / ".gitignore").exists() else ""
check("android/key.properties" in gitignore and "android/local.properties" in gitignore,
      ".gitignore excludes signing secrets and local SDK paths", ".gitignore does not protect key.properties/local.properties")

# Basic accidental-secret scan. This is heuristic and cannot prove that all secrets are absent.
scan_files = list((ROOT / "lib").rglob("*.dart")) + list((ROOT / "android/app/src/main/kotlin").rglob("*.kt"))
possible_secrets: list[str] = []
for source_file in scan_files:
    source_text = source_file.read_text(encoding="utf-8", errors="ignore")
    if re.search(r"AIza[0-9A-Za-z_-]{30,}", source_text) or "-----BEGIN PRIVATE KEY-----" in source_text or "-----BEGIN RSA PRIVATE KEY-----" in source_text:
        possible_secrets.append(str(source_file.relative_to(ROOT)))
check(not possible_secrets, "no obvious API key/private-key literal found in Dart/Kotlin source", "possible secret literal detected in: " + ", ".join(possible_secrets))

if notes:
    print("\nInformational notes:")
    for note in notes:
        print(f"[NOTE] {note}")

print(f"\nStatic preflight: {checks - len(errors)}/{checks} checks passed.")
print("This script does not replace `flutter test`, `flutter analyze`, or a real release build.")
if errors:
    print("\nBlockers:")
    for error in errors:
        print(f" - {error}")
    sys.exit(1)
sys.exit(0)
