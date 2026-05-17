#!/usr/bin/env bash
# script-promote.sh — промоция личного скрипта в платформенный шаблон IWE
#
# Поток: личная папка/<script> → подстановки → FMT/scripts/<script>
# Личные константы заменяются на параметры среды (env vars).
#
# Использование:
#   bash script-promote.sh <путь-к-скрипту> [--dry-run]
#
# Примеры:
#   bash script-promote.sh ~/IWE/DS-strategy/scripts/my-tool.sh --dry-run
#   bash script-promote.sh ~/IWE/DS-strategy/scripts/my-tool.sh

set -uo pipefail

SRC="${1:-}"
dry_run=false
[[ "${2:-}" == "--dry-run" ]] && dry_run=true

if [[ -z "$SRC" || ! -f "$SRC" ]]; then
    echo "Использование: $0 <путь-к-скрипту> [--dry-run]" >&2
    echo "Пример: $0 ~/IWE/\$GOV_REPO/scripts/my-tool.sh" >&2
    exit 1
fi

IWE="${IWE_WORKSPACE:-$HOME/IWE}"
FMT_DIR="${IWE_TEMPLATE:-$IWE/FMT-exocortex-template}"
GOV_REPO_AUTHOR="${IWE_GOVERNANCE_REPO:-DS-strategy}"
GOV_REPO_TMPL="DS-strategy"

fname=$(basename "$SRC")
DEST="$FMT_DIR/scripts/$fname"
VALIDATOR="$FMT_DIR/scripts/validate-fmt-scripts.sh"

echo "🔄 Промоция: $fname"
echo "   Откуда: $SRC"
echo "   Куда:   $DEST"
echo ""

# Подстановки: личные константы → параметры среды
# Порядок важен: сначала длинный путь ($HOME/IWE), потом короткий ($HOME)
result=$(sed \
    -e "s|$HOME/IWE|\${IWE:-\$HOME/IWE}|g" \
    -e "s|$HOME|\$HOME|g" \
    -e "s|$GOV_REPO_AUTHOR|\${IWE_GOVERNANCE_REPO:-$GOV_REPO_TMPL}|g" \
    "$SRC")

if $dry_run; then
    echo "--- dry-run: результат после подстановок ---"
    printf '%s\n' "$result"
    echo "--- конец ---"
    exit 0
fi

# Валидация результата через временный файл
tmp_dir=$(mktemp -d)
tmp_file="$tmp_dir/$fname"
printf '%s\n' "$result" > "$tmp_file"
chmod +x "$tmp_file"

if [[ -f "$VALIDATOR" ]]; then
    if ! bash "$VALIDATOR" "$tmp_dir" 2>&1; then
        rm -rf "$tmp_dir"
        echo "" >&2
        echo "❌ После подстановок остались личные хардкоды." >&2
        echo "   Используй --dry-run для просмотра и исправь вручную." >&2
        exit 1
    fi
fi

# Smoke-тест: запустить в изолированном env с шаблонными переменными
# Цель: убедиться что скрипт не падает с exit 1 при чужом окружении
# Используем --help или пустой запуск — ожидаем exit 0 или exit 1 только от validation
echo "   smoke-test с шаблонным окружением..."
smoke_result=0
env -i \
    HOME="/tmp/iwe-smoke-user" \
    IWE="/tmp/iwe-smoke-user/IWE" \
    IWE_GOVERNANCE_REPO="DS-strategy" \
    PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin" \
    bash "$tmp_file" --help > /dev/null 2>&1 || smoke_result=$?

# exit 0 = OK, exit 1 = validation error (приемлемо — скрипт без аргументов)
# exit 127 = команда не найдена (зависимость сломана) — блокер
if [[ $smoke_result -eq 127 ]]; then
    rm -rf "$tmp_dir"
    echo "❌ Smoke-тест: exit 127 — скрипт не может запуститься в чужом окружении." >&2
    echo "   Проверь зависимости (python3, jq, и т.п.) и абсолютные пути." >&2
    exit 1
fi
echo "   smoke-test: OK (exit $smoke_result)"

# Скопировать в FMT
cp "$tmp_file" "$DEST"
chmod +x "$DEST"
rm -rf "$tmp_dir"

echo ""
echo "✅ Промотирован: FMT/scripts/$fname"

# Обновить [Unreleased] в CHANGELOG
CHANGELOG_SCRIPT="$FMT_DIR/scripts/changelog-append.sh"
if [[ -f "$CHANGELOG_SCRIPT" ]]; then bash "$CHANGELOG_SCRIPT"; fi

echo "Следующий шаг:"
echo "  cd $FMT_DIR && git add scripts/$fname CHANGELOG.md && git commit -m 'feat: promote $fname to platform'"
