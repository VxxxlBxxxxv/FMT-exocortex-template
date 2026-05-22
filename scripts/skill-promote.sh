#!/usr/bin/env bash
# skill-promote.sh — промоция скилла в платформенный шаблон IWE (v2)
# see DP.SC.153, DP.ROLE.056
#
# Поток:
#   1. validate-skill.sh (gate: SKILL.md v2 обязателен)
#   2. Копирует <skill>/ → FMT/.claude/skills/<skill>/
#   3. Подстановки путей (HOME/IWE → env vars)
#   4. Устанавливает layer: L1 в FMT-копии SKILL.md
#   5. Регенерирует skills-catalog.yaml
#
# Использование:
#   bash skill-promote.sh <путь-к-папке-скилла> [--dry-run]

set -uo pipefail

SRC="${1:-}"
dry_run=false
[[ "${2:-}" == "--dry-run" ]] && dry_run=true

if [[ -z "$SRC" || ! -d "$SRC" ]]; then
    echo "Использование: $0 <путь-к-папке-скилла> [--dry-run]" >&2
    echo "Скилл = директория с SKILL.md внутри" >&2
    exit 1
fi

IWE="${IWE_WORKSPACE:-$HOME/IWE}"
FMT_DIR="${IWE_TEMPLATE:-$IWE/FMT-exocortex-template}"
GOV_REPO_AUTHOR="${IWE_GOVERNANCE_REPO:-DS-strategy}"
GOV_REPO_TMPL="DS-strategy"

skill_name=$(basename "$SRC")
DEST="$FMT_DIR/.claude/skills/$skill_name"

if [[ ! -f "$SRC/SKILL.md" ]]; then
    echo "❌ В папке нет SKILL.md — это не скилл?" >&2
    exit 1
fi

echo "🔄 Промоция скилла: $skill_name/"
echo "   Откуда: $SRC"
echo "   Куда:   $DEST"
echo ""

# ── Шаг 1. Валидация (gate) ──────────────────────────────────────────────────
VALIDATE_SCRIPT="$FMT_DIR/scripts/validate-skill.sh"
if [[ -f "$VALIDATE_SCRIPT" ]]; then
    echo "--- validate-skill.sh ---"
    skill_dir=$(dirname "$SRC/SKILL.md")
    if ! bash "$VALIDATE_SCRIPT" "$skill_name" --skills-dir "$(dirname "$SRC")" 2>&1; then
        echo "" >&2
        echo "❌ Промоция заблокирована: validate-skill.sh провалился." >&2
        echo "   Исправьте ошибки и повторите." >&2
        exit 1
    fi
    echo ""
else
    echo "⚠️  validate-skill.sh не найден — пропускаю валидацию (обновите FMT)"
fi

if $dry_run; then
    echo "--- dry-run: SKILL.md после подстановок + layer: L1 ---"
    sed \
        -e "s|$HOME/IWE|\${IWE:-\$HOME/IWE}|g" \
        -e "s|$HOME|\$HOME|g" \
        -e "s|$GOV_REPO_AUTHOR|\${IWE_GOVERNANCE_REPO:-$GOV_REPO_TMPL}|g" \
        -e "s|^layer: L3|layer: L1|" \
        "$SRC/SKILL.md"
    echo "--- конец ---"
    exit 0
fi

# ── Шаг 2. Копирование директории ────────────────────────────────────────────
mkdir -p "$DEST"
cp -r "$SRC"/. "$DEST/"

# ── Шаг 3. Подстановки путей + Шаг 4. layer: L1 ─────────────────────────────
tmp=$(mktemp)
sed \
    -e "s|$HOME/IWE|\${IWE:-\$HOME/IWE}|g" \
    -e "s|$HOME|\$HOME|g" \
    -e "s|$GOV_REPO_AUTHOR|\${IWE_GOVERNANCE_REPO:-$GOV_REPO_TMPL}|g" \
    -e "s|^layer: L3|layer: L1|" \
    "$DEST/SKILL.md" > "$tmp"
mv "$tmp" "$DEST/SKILL.md"

# Подстановки в .sh скрипты скилла
for f in "$DEST"/*.sh; do
    [[ -f "$f" ]] || continue
    tmp=$(mktemp)
    sed \
        -e "s|$HOME/IWE|\${IWE:-\$HOME/IWE}|g" \
        -e "s|$HOME|\$HOME|g" \
        -e "s|$GOV_REPO_AUTHOR|\${IWE_GOVERNANCE_REPO:-$GOV_REPO_TMPL}|g" \
        "$f" > "$tmp"
    mv "$tmp" "$f"
    chmod +x "$f"
done

echo "✅ Промотирован: FMT/.claude/skills/$skill_name/ (layer: L1)"

# ── Шаг 5. Регенерация каталога ──────────────────────────────────────────────
CATALOG_SCRIPT="$FMT_DIR/scripts/generate-skills-catalog.sh"
if [[ -f "$CATALOG_SCRIPT" ]]; then
    echo "🔄 Регенерация skills-catalog.yaml..."
    bash "$CATALOG_SCRIPT" 2>&1
fi

CHANGELOG_SCRIPT="$FMT_DIR/scripts/changelog-append.sh"
if [[ -f "$CHANGELOG_SCRIPT" ]]; then bash "$CHANGELOG_SCRIPT"; fi

echo ""
echo "Следующий шаг:"
echo "  cd $FMT_DIR && git add .claude/skills/$skill_name .claude/skills-catalog.yaml CHANGELOG.md"
echo "  git commit -m 'feat(WP-348): promote skill $skill_name to platform (L1)'"
