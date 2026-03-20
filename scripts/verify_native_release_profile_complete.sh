#!/usr/bin/env bash
# Tier A — native release profile completeness (docs/PROJECT_COMPLETION_STATEMENT.md).
# Runs: workflow/JSON contract, full repo verification without optional product benches, strength bar.
# Does NOT claim Tier B (full P0 self-host / P1+); see PROJECT_COMPLETION_ROADMAP.md.
# Propagates child exit codes (contract 11–17, release scripts, strength bar 1–12, etc.).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=============================================="
echo "  Native release profile completeness (Tier A)"
echo "  See docs/PROJECT_COMPLETION_STATEMENT.md"
echo "=============================================="

chmod +x \
  scripts/verify_required_github_status_checks_contract.sh \
  scripts/run_full_repo_verification.sh \
  scripts/verify_azl_strength_bar.sh \
  2>/dev/null || true

echo ""
echo "[1/3] Required GitHub status checks contract (workflow vs JSON)"
bash scripts/verify_required_github_status_checks_contract.sh

echo ""
echo "[2/3] Full repo verification (RUN_OPTIONAL_BENCHES=0)"
RUN_OPTIONAL_BENCHES=0 bash scripts/run_full_repo_verification.sh

echo ""
echo "[3/3] Strength bar (four pillars)"
bash scripts/verify_azl_strength_bar.sh

echo ""
echo "=============================================="
echo "  OK: Tier A — native release profile complete"
echo "  (Tier B roadmap may still be open — see docs/PROJECT_COMPLETION_ROADMAP.md)"
echo "=============================================="
