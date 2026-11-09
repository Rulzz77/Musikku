#!/usr/bin/env bash
set -euo pipefail

# Scans tracked text files for concrete, high-confidence credential values.
# The patterns are assembled in Python so the scanner source does not match
# its own signature definitions. This is a guardrail, not a full Git-history scan.

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Security preflight must run inside a Git worktree." >&2
  exit 2
fi

python3 - <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path

# Assemble signatures from fragments to avoid matching the scanner's own code.
patterns = [
    ("Google API key", re.compile(("AI" + "za") + r"[0-9A-Za-z_-]{35}")),
    ("Google OAuth token", re.compile(("ya" + "29") + r"\.[0-9A-Za-z_-]{20,}")),
    ("GitHub token", re.compile(r"gh" + r"[pousr]_" + r"[A-Za-z0-9_]{30,}")),
    ("GitHub fine-grained token", re.compile("github" + r"_pat_[A-Za-z0-9_]{50,}")),
    ("AWS access key", re.compile("AK" + r"IA[0-9A-Z]{16}")),
    ("Slack token", re.compile("xo" + r"x[baprs]-[A-Za-z0-9-]{10,}")),
]
# Detect an actual multi-line PEM private-key block, not just a code regex or
# the text of a BEGIN marker in a security scanner.
pem = re.compile(
    r"-" * 5 + r"BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY" + r"-" * 5
    + r"\s*\n(?:[A-Za-z0-9+/=]{40,}\s*\n)+"
    + r"-" * 5 + r"END (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY" + r"-" * 5,
    re.MULTILINE,
)

try:
    raw = subprocess.check_output(["git", "ls-files", "-z"])
except subprocess.CalledProcessError:
    print("::error::Could not list tracked files with Git.", file=sys.stderr)
    sys.exit(2)

tracked = [p.decode("utf-8", "surrogateescape") for p in raw.split(b"\0") if p]
hits = []
local_config = []

for rel in tracked:
    posix = rel.replace("\\", "/")
    name = posix.rsplit("/", 1)[-1].lower()
    suffix = Path(posix).suffix.lower()

    if name in {"local.properties", "key.properties"} or suffix in {".jks", ".keystore", ".p12", ".pfx", ".pem", ".key"}:
        local_config.append(posix)

    # Documentation and explicit examples may describe credential formats;
    # generated/binary files are not source text and should not be tracked.
    if suffix in {".md", ".rst", ".adoc", ".example"} or name == ".gitignore":
        continue
    try:
        data = Path(rel).read_bytes()
    except (OSError, PermissionError):
        continue
    if b"\0" in data:
        continue
    text = data.decode("utf-8", "replace")

    for label, pattern in patterns:
        for match in pattern.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            hits.append((posix, line, label))
    for match in pem.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        hits.append((posix, line, "PEM private-key block"))

failed = False
seen = set()
for path, line, label in hits:
    item = (path, line, label)
    if item in seen:
        continue
    seen.add(item)
    print(f"::error file={path},line={line},title=Potential credential::{label} pattern detected; matched content is not printed.")
    failed = True

if local_config:
    for path in sorted(set(local_config)):
        print(f"::error file={path},title=Tracked local configuration or signing material::{path} should not be committed.")
    failed = True

if failed:
    print("Security preflight failed. Inspect the reported file/line locally; do not paste credential values into logs or chat.", file=sys.stderr)
    sys.exit(1)

print("Security preflight passed: no common concrete credential values or tracked local signing files detected.")
print("Note: this does not scan all Git history and is not a substitute for GitHub secret scanning/push protection.")
PY
