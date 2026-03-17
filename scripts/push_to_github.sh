#!/usr/bin/env bash
# Run this from a machine with internet access to push AZL Language to GitHub.
set -e
cd "$(dirname "$0")/.."
echo "Pushing to origin main..."
if git push origin main --force-with-lease 2>&1; then
  echo "Done. Repo is live at: https://github.com/AZBCBA/AZL-Language"
else
  echo "If push was rejected (e.g. remote changed), run: git push origin main --force"
fi
