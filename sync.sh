#!/usr/bin/env bash
# sync.sh — локальный запуск синхронизации (Linux / macOS)
# Использование: ./sync.sh [путь к корню репо]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${1:-$SCRIPT_DIR}"

echo "=== sync_index ==="
echo "Корень репо: $REPO_ROOT"
echo

# Проверяем python3
if ! command -v python3 &>/dev/null; then
  echo "[ERROR] python3 не найден. Установите Python 3.9+"
  exit 1
fi

python3 "$SCRIPT_DIR/scripts/sync_index.py" "$REPO_ROOT"
