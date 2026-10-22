#!/usr/bin/env bash
set -euo pipefail

# Lightweight guardrail only. This is not a replacement for secret scanning
# across Git history or a dedicated scanner such as GitHub secret scanning.

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Security preflight must run inside a Git worktree." >&2
  exit 2
fi

found=0

# Scan tracked text files for common high-confidence credential formats.
# Print file names only to avoid copying any detected secret into Actions logs.
if git grep -I -l -E \
  'AIza[0-9A-Za-z_-]{35}|ya29\.[0-9A-Za-z_-]{20,}|gh[pousr]_[A-Za-z0-9_]{30,}|github_pat_[A-Za-z0-9_]{50,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----' \
  -- . ':!*.md' ':!*.example' ':!.gitignore'; then
  echo "::error::Potential credential pattern found in tracked source file(s). Remove/rotate them before release." >&2
  found=1
fi

# A local signing file should never be tracked in the repository.
if git ls-files | grep -E '(^|/)(local\.properties|key\.properties)$|\.(jks|keystore|p12|pfx|pem|key)$' >/dev/null; then
  echo "::error::A local configuration or signing-key file is tracked by Git. Remove it from the index and rotate exposed credentials." >&2
  git ls-files | grep -E '(^|/)(local\.properties|key\.properties)$|\.(jks|keystore|p12|pfx|pem|key)$' || true
  found=1
fi

if [[ "$found" -ne 0 ]]; then
  exit 1
fi

echo "Security preflight passed (common credential patterns and tracked local signing files). This is not a full security audit."
