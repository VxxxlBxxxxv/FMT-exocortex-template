#!/bin/bash
# backup-icloud.sh — Бэкап IWE в iCloud Drive (без .git, node_modules, .venv)
# Использование: ./scripts/backup-icloud.sh
# Хранит последние 4 архива, удаляет старые.
# Платформа: macOS с iCloud Drive.

set -euo pipefail

IWE_DIR="${WORKSPACE_DIR:-$HOME/IWE}"
ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/IWE-backups"
DATE=$(date +%Y%m%d-%H%M)
ARCHIVE="IWE-backup-${DATE}.tar.gz"
MAX_BACKUPS=4

# Проверка iCloud
if [ ! -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]; then
    echo "❌ iCloud Drive не найден. Убедитесь что iCloud Drive включён в System Settings."
    exit 1
fi

# Создать папку в iCloud если нет
mkdir -p "$ICLOUD_DIR"

echo "📦 Создаю архив $ARCHIVE..."
tar --exclude='.git' \
    --exclude='node_modules' \
    --exclude='.venv' \
    --exclude='__pycache__' \
    --exclude='_backups' \
    --exclude='.DS_Store' \
    -czf "$ICLOUD_DIR/$ARCHIVE" \
    -C "$(dirname "$IWE_DIR")" "$(basename "$IWE_DIR")/"

SIZE=$(du -h "$ICLOUD_DIR/$ARCHIVE" | cut -f1)
echo "✅ Архив создан: $ICLOUD_DIR/$ARCHIVE ($SIZE)"

# Удалить старые архивы (оставить последние MAX_BACKUPS)
cd "$ICLOUD_DIR"
TOTAL=$(ls -1 IWE-backup-*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
if [ "$TOTAL" -gt "$MAX_BACKUPS" ]; then
    TO_DELETE=$((TOTAL - MAX_BACKUPS))
    ls -1t IWE-backup-*.tar.gz | tail -n "$TO_DELETE" | while read old; do
        echo "🗑  Удаляю старый: $old"
        rm "$old"
    done
fi

echo "📊 Текущие бэкапы в iCloud:"
ls -lh IWE-backup-*.tar.gz 2>/dev/null
