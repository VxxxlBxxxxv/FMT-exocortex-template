#!/usr/bin/env bash
# validate-fmt-scripts.sh — проверка FMT/scripts/ на личные хардкоды
# Запускается автоматически из template-sync.sh и вручную при подозрении.
#
# Использование:
#   bash validate-fmt-scripts.sh [scripts-dir]
#
# Что проверяет:
#   1. Абсолютный домашний путь пользователя (/Users/<name> или /home/<name>)
#   2. Голое имя авторского governance-репо без ${VAR:-default} защиты

set -uo pipefail

SCRIPTS_DIR="${1:-$(dirname "$0")}"
AUTHOR_HOME="${HOME}"
AUTHOR_GOV_REPO="${IWE_GOVERNANCE_REPO:-DS-strategy}"

errors=0
checked=0

for f in "$SCRIPTS_DIR"/*.sh "$SCRIPTS_DIR"/*.py; do
    [[ -f "$f" ]] || continue
    fname=$(basename "$f")
    # Не проверять сам себя
    [[ "$fname" == "validate-fmt-scripts.sh" ]] && continue
    checked=$((checked + 1))

    # Проверка 1: абсолютный личный путь (resolved $HOME, не переменная)
    if grep -qF "$AUTHOR_HOME" "$f" 2>/dev/null; then
        echo "  ❌ $fname: содержит '$AUTHOR_HOME'" >&2
        grep -nF "$AUTHOR_HOME" "$f" | head -3 | sed 's/^/     /' >&2
        errors=$((errors + 1))
    fi

    # Проверка 2: голое имя авторского governance-репо (без env-var fallback)
    # Допустимо: ${IWE_GOVERNANCE_REPO:-DS-strategy} или GOV_REPO="${...:-DS-strategy}"
    # Запрещено: буквальное имя governance-репо вне fallback-паттерна в исполняемых строках
    # Комментарии (#) пропускаются — документация не влияет на поведение
    if grep -q "$AUTHOR_GOV_REPO" "$f" 2>/dev/null; then
        bad_lines=$(grep -n "$AUTHOR_GOV_REPO" "$f" \
            | grep -v '^\s*#\|^[0-9]*:\s*#' \
            | grep -v '\${[^}]*:-' || true)
        if [[ -n "$bad_lines" ]]; then
            echo "  ❌ $fname: '$AUTHOR_GOV_REPO' без env fallback в коде" >&2
            echo "$bad_lines" | head -3 | sed 's/^/     /' >&2
            errors=$((errors + 1))
        fi
    fi
done

if [[ $checked -eq 0 ]]; then
    echo "validate-fmt-scripts: нет файлов для проверки в $SCRIPTS_DIR"
    exit 0
fi

if [[ $errors -eq 0 ]]; then
    echo "✅ validate-fmt-scripts: $checked файлов проверено, личных хардкодов нет"
    exit 0
else
    echo "❌ validate-fmt-scripts: $errors нарушений в $checked файлах — исправить до коммита в FMT" >&2
    exit 1
fi
