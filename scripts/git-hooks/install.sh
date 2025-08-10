#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

HOOKS_DIR=".git/hooks"
mkdir -p "$HOOKS_DIR"

cat > "$HOOKS_DIR/pre-push" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "🔎 Running pre-push checks..."
scripts/check_no_placeholders.sh
scripts/run_all_tests.sh
echo "✅ Pre-push checks passed"
EOF

chmod +x "$HOOKS_DIR/pre-push"
echo "✅ Git hooks installed"


