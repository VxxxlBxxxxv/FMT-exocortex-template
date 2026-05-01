#!/bin/bash
# Генерирует update-manifest.json из текущего содержимого репо.
# Запускать перед релизом: bash generate-manifest.sh
#
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SCRIPT_DIR/update-manifest.json"

# Версия из CHANGELOG.md (первый ## [X.Y.Z])
VERSION=$(grep -m1 '^\#\# \[' "$SCRIPT_DIR/CHANGELOG.md" | sed 's/.*\[\(.*\)\].*/\1/')

if [ -z "$VERSION" ]; then
    echo "ERROR: Не удалось извлечь версию из CHANGELOG.md"
    exit 1
fi

echo "Генерация манифеста v$VERSION..."

# Файлы/директории, которые НЕ включаются в манифест обновлений
# seed/ — только при setup, README.md — пользователь кастомизирует,
# settings.local.json — персональный, .gitkeep — маркеры
EXCLUDE_PATTERNS=(
    "seed/"
    ".claude/settings.local.json"
    "generate-manifest.sh"
    "update-manifest.json"
    ".git/"
    ".DS_Store"
)

# Только корневой README.md (не roles/*/README.md и т.д.)
EXCLUDE_EXACT=(
    "README.md"
)

# Собираем файлы.
# Используем `git ls-files`, а не `find`: gitignored/untracked файлы
# (.exocortex.env, .claude.md.base, .claude/logs/) НЕ должны попадать в manifest —
# integration-contract-validator (manifest_paths) падает при их наличии.
FILES=()
while IFS= read -r rel; do
    # Проверяем исключения
    skip=false
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        case "$rel" in
            $pattern*|*/$pattern*) skip=true; break ;;
        esac
    done

    # Пропускаем .gitkeep
    [[ "$(basename "$rel")" == ".gitkeep" ]] && skip=true

    # Точные совпадения (корневой README.md)
    for exact in "${EXCLUDE_EXACT[@]}"; do
        [ "$rel" = "$exact" ] && { skip=true; break; }
    done

    $skip && continue
    FILES+=("$rel")
done < <(cd "$SCRIPT_DIR" && git ls-files | sort)

# Генерируем JSON
{
    echo '{'
    echo "  \"version\": \"$VERSION\","
    echo '  "description": "Манифест платформенных файлов FMT-exocortex-template. Используется update.sh для доставки обновлений.",'
    echo '  "files": ['

    last_idx=$(( ${#FILES[@]} - 1 ))
    for i in "${!FILES[@]}"; do
        f="${FILES[$i]}"
        comma=","
        [ "$i" -eq "$last_idx" ] && comma=""
        printf '    {"path": "%s"}%s\n' "$f" "$comma"
    done

    echo '  ]'
    echo '}'
} > "$MANIFEST"

echo "Готово: $MANIFEST"
echo "  Версия: $VERSION"
echo "  Файлов: ${#FILES[@]}"
echo ""
echo "Проверьте diff и закоммитьте:"
echo "  git diff update-manifest.json"
