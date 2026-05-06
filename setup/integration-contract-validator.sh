#!/bin/bash
# integration-contract-validator.sh — детектор Spec↔State drift.
#
# # see VR.SC.006 (release-verification-protocol), VR.M.006 (5-layer verification, слой 1)
# # see AR.203 (release verification trigger)
#
# WP-273 R4.8 (proposal Евгения, Round 4 red-team). Закрывает 4-й системный корень:
# докуменация говорит А, код делает Б — нужен автоматический детектор расхождений
# до релиза.
#
# 12 детекторов:
#   1. manifest_paths    — пути из update-manifest.json существуют в дереве
#   2. seed_references   — protocol-*.md ссылки на seed/ существуют в seed/
#   3. extension_table   — extensions/README.md table ↔ реальное placement EXTENSION POINT в protocol-*/SKILL.md
#   4. hook_artifact     — .claude/hooks/*.sh не грепают TOOL_INPUT по artifact-именам (антипаттерн R4.5)
#   5. runner_readonly   — runners резолвят prompts/role.yaml/notify через $IWE_TEMPLATE (R5.1, 0.29.3)
#   6. install_failfast  — install.sh имеют grep '{{' check на PLIST_SRC (R5.2, 0.29.3)
#   7. prompts_python_coverage — нет hardcoded DS-strategy в prompts и .py (R6.1*, 0.29.5)
#   8. sed_placeholder_escape — substituted runners НЕ имеют bare {{X}} в sed (R6.1**, 0.29.6)
#   9. version_bump_consistency — code commit ПОСЛЕ manifest version bump = unreleased fix (issue #52, audit 0.29.29)
#  10. tracked_artifacts — .DS_Store/__pycache__/*.pyc в дереве + .gitignore coverage (issue #52)
#  11. memory_internal_refs — broken ссылки на memory/*.md из MEMORY.md/navigation.md (issue #52)
#  12. stat_portability — `stat -f` без `stat -c` fallback в той же функции = Linux mtime breakage (issue #52)
#
# Detectors #9-#12 — WARN-only (bootstrap-режим): сигналят, не блокируют CI.
# Promote в FAIL отдельным commit'ом после фикса underlying issues.
#
# Usage:
#   bash setup/integration-contract-validator.sh [--verbose]
#
# Exit:
#   0 — все детекторы PASS
#   1 — некорректные аргументы
#   N>1 — N drift-нарушений найдено

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$(dirname "$SCRIPT_DIR")"  # FMT-exocortex-template/
VERBOSE=false

# Detector regex'ы — shared source (0.29.19 DRY fix).
# shellcheck source=detector-regex.sh
. "$SCRIPT_DIR/detector-regex.sh"

while [ $# -gt 0 ]; do
    case "$1" in
        --verbose|-v) VERBOSE=true; shift ;;
        --help|-h)
            grep '^#' "$0" | head -22
            exit 0
            ;;
        *) echo "ERROR: Unknown arg: $1" >&2; exit 1 ;;
    esac
done

cd "$TEMPLATE_DIR"

VIOLATIONS=0
log() { echo "$@"; }
# SC2145 fix: используем $* (склеивает с IFS) внутри строки с literal-префиксом,
# чтобы не получать «mixes string and array» от shellcheck.
verbose() { if $VERBOSE; then echo "  $*"; fi; }

log "=== Integration Contract Validator (WP-273 R4.8) ==="
log ""

# === Detector 1: manifest paths existence ===
log "[1/12] manifest_paths — пути из update-manifest.json в дереве..."
if [ -f update-manifest.json ] && command -v python3 >/dev/null 2>&1; then
    MISSING=$(python3 -c "
import json, os
with open('update-manifest.json') as f:
    data = json.load(f)
for entry in data.get('files', []):
    p = entry.get('path') if isinstance(entry, dict) else entry
    if p and not os.path.isfile(p):
        print(p)
")
    if [ -n "$MISSING" ]; then
        log "  ❌ FAIL: manifest содержит пути, отсутствующие в дереве:"
        echo "$MISSING" | sed 's/^/      /'
        COUNT=$(echo "$MISSING" | wc -l | tr -d ' ')
        VIOLATIONS=$((VIOLATIONS + COUNT))
    else
        log "  ✅ PASS"
    fi
else
    log "  ⊘ SKIP (нет update-manifest.json или python3)"
fi
log ""

# === Detector 2: seed references in protocols ===
log "[2/12] seed_references — protocol-*.md ссылки на seed/ существуют..."
SEED_REFS_VIOLATIONS=0
if [ -d seed ]; then
    while IFS= read -r ref; do
        # ref like "seed/strategy/decisions/" or "seed/strategy/docs/Strategy.md"
        rel="${ref%/}"
        if [ ! -e "$rel" ]; then
            log "  ❌ Reference: '$ref' не существует в дереве"
            verbose "    upstream of seed/strategy/: $(ls seed/strategy/ 2>/dev/null | tr '\n' ' ')"
            SEED_REFS_VIOLATIONS=$((SEED_REFS_VIOLATIONS + 1))
        fi
    done < <(grep -hoE 'seed/[a-z][a-z/_-]*' memory/protocol-*.md 2>/dev/null | sort -u | grep -vE '\.\.\.$|/$' || true)

    if [ "$SEED_REFS_VIOLATIONS" -eq 0 ]; then
        log "  ✅ PASS"
    else
        log "  ❌ FAIL ($SEED_REFS_VIOLATIONS violations)"
        VIOLATIONS=$((VIOLATIONS + SEED_REFS_VIOLATIONS))
    fi
else
    log "  ⊘ SKIP (нет seed/)"
fi
log ""

# === Detector 3: extension table ↔ real EXTENSION POINT placement ===
log "[3/12] extension_table — extensions/README.md table ↔ EXTENSION POINT в protocol-*.md/SKILL.md..."
EXT_VIOLATIONS=0
if [ -f extensions/README.md ]; then
    # Parse extension table from README.md: lines like "| protocol-close | checks | ..."
    declare_table=$(grep -E '^\|\s*`?[a-z][a-z-]*`?\s*\|\s*`?[a-z]+`?\s*\|' extensions/README.md 2>/dev/null | head -20 || true)

    # Find actual EXTENSION POINT references in protocols/skills.
    # WP-273 R6 fix (Round 5 sub-agent assessment): regex терминировался на первом
    # backtick — пропускал EP'ы где в строке несколько backtick'ов (например
    # "ДО `git commit` проверить `extensions/X.md`"). Расширили: ищем
    # `extensions/X.md` отдельным regex, без зависимости от «EXTENSION POINT».
    real_eps=$(grep -hroE 'extensions/[a-z-]+\.[a-z]+\.md' \
        memory/protocol-*.md .claude/skills/*/SKILL.md \
        .claude/skills/*/scripts/*.sh 2>/dev/null | sort -u || true)

    # For each entry in declared_table, check that it's loaded somewhere
    while IFS= read -r line; do
        proto=$(echo "$line" | awk -F'|' '{gsub(/[` ]/, "", $2); print $2}')
        hook=$(echo "$line" | awk -F'|' '{gsub(/[` ]/, "", $3); print $3}')
        [ -z "$proto" ] && continue
        [ -z "$hook" ] && continue
        expected="extensions/${proto}.${hook}.md"
        if ! echo "$real_eps" | grep -q "^${expected}$"; then
            log "  ⚠ Table declared $expected, но EXTENSION POINT не найден в protocols/skills"
            EXT_VIOLATIONS=$((EXT_VIOLATIONS + 1))
        fi
    done <<< "$declare_table"

    if [ "$EXT_VIOLATIONS" -eq 0 ]; then
        log "  ✅ PASS"
    else
        log "  ⚠ WARN ($EXT_VIOLATIONS таблица-vs-код расхождений)"
        # extension table — это документация контракта, не критический drift
    fi
else
    log "  ⊘ SKIP (нет extensions/README.md)"
fi
log ""

# === Detector 4: hook trigger pattern (hooks-design.md принцип) ===
log "[4/12] hook_artifact — hooks не грепают TOOL_INPUT (R4.5 антипаттерн)..."
HOOK_VIOLATIONS=0
if [ -d .claude/hooks ]; then
    while IFS= read -r f; do
        # WP-273 R6 fix (Round 5 sub-agent assessment): уточнили regex до
        # КОНКРЕТНОГО антипаттерна (R4.5) — grep'ать TOOL_INPUT по artifact-именам
        # (DayPlan, WeekPlan, day-close, day-open). Раньше ловили любой grep TOOL_INPUT,
        # включая легитимный gating «это git commit вообще?» — false positive.
        if grep -qE 'TOOL_INPUT.*\|.*grep[^|]*(DayPlan|WeekPlan|day-close|day-open|week-close|week-open)' "$f" 2>/dev/null; then
            log "  ⚠ $f: grep TOOL_INPUT по artifact-именам (нарушает hooks-design.md, использовать staged-files)"
            HOOK_VIOLATIONS=$((HOOK_VIOLATIONS + 1))
        fi
    done < <(find .claude/hooks -name "*.sh" -type f 2>/dev/null)

    if [ "$HOOK_VIOLATIONS" -eq 0 ]; then
        log "  ✅ PASS"
    else
        log "  ⚠ WARN ($HOOK_VIOLATIONS hooks)"
        # WARN, не FAIL — есть валидные case'ы (debug logging)
    fi
else
    log "  ⊘ SKIP (нет .claude/hooks/)"
fi
log ""

# === Detector 5: runner read-only references resolve correctly (R5.1 regression) ===
log "[5/12] runner_readonly — runners резолвят prompts/role.yaml/notify через \$IWE_TEMPLATE..."
RUNNER_VIOLATIONS=0
# Антипаттерн (Round 5 R5.1): PROMPTS_DIR="\$REPO_DIR/prompts" без fallback на \$IWE_TEMPLATE.
# Runner работает только если все read-only данные дублированы в runtime.
for runner in roles/strategist/scripts/strategist.sh roles/extractor/scripts/extractor.sh; do
    [ -f "$runner" ] || continue
    if ! grep -q 'IWE_TEMPLATE.*roles/.*prompts' "$runner" 2>/dev/null; then
        log "  ⚠ $runner: PROMPTS_DIR не резолвится через \$IWE_TEMPLATE (antipattern R5.1)"
        RUNNER_VIOLATIONS=$((RUNNER_VIOLATIONS + 1))
    fi
done
# scheduler.sh: проверка ROLES_DIR_TEMPLATE для role.yaml lookup
if [ -f roles/synchronizer/scripts/scheduler.sh ]; then
    if ! grep -q 'ROLES_DIR_TEMPLATE.*IWE_TEMPLATE' roles/synchronizer/scripts/scheduler.sh 2>/dev/null; then
        log "  ⚠ scheduler.sh: role.yaml lookup не использует \$IWE_TEMPLATE (R5.1)"
        RUNNER_VIOLATIONS=$((RUNNER_VIOLATIONS + 1))
    fi
fi
if [ "$RUNNER_VIOLATIONS" -eq 0 ]; then
    log "  ✅ PASS"
else
    log "  ❌ FAIL ($RUNNER_VIOLATIONS runners без правильного \$IWE_TEMPLATE-резолва)"
    VIOLATIONS=$((VIOLATIONS + RUNNER_VIOLATIONS))
fi
log ""

# === Detector 6: install.sh fail-fast при literal {{...}} в plist (R5.2 regression) ===
log "[6/12] install_failfast — install.sh имеют grep '{{' check на PLIST_SRC..."
FAILFAST_VIOLATIONS=0
for install_sh in roles/strategist/install.sh roles/extractor/install.sh roles/synchronizer/install.sh; do
    [ -f "$install_sh" ] || continue
    # Антипаттерн: install.sh без grep на плейсхолдеры → может скопировать
    # plist с literal {{IWE_RUNTIME}} в ~/Library/LaunchAgents/.
    if ! grep -qE "grep -qE? '\\\\\{\\\\\{|grep -qE? '\{\{" "$install_sh" 2>/dev/null; then
        log "  ⚠ $install_sh: нет fail-fast grep на {{...}} в plist (antipattern R5.2)"
        FAILFAST_VIOLATIONS=$((FAILFAST_VIOLATIONS + 1))
    fi
done
if [ "$FAILFAST_VIOLATIONS" -eq 0 ]; then
    log "  ✅ PASS"
else
    log "  ❌ FAIL ($FAILFAST_VIOLATIONS install.sh без fail-fast)"
    VIOLATIONS=$((VIOLATIONS + FAILFAST_VIOLATIONS))
fi
log ""

# === Detector 7: prompts + python coverage (R6.1* regression — мой smoke test пропустил) ===
log "[7/12] prompts_python_coverage — нет hardcoded DS-strategy в prompts и .py..."
COVERAGE_VIOLATIONS=0
# Python scripts: должны читать GOVERNANCE_REPO из env, не хардкодить
while IFS= read -r py; do
    [ -f "$py" ] || continue
    # Антипаттерн: Path с literal "DS-strategy" без чтения env
    if grep -qE '"DS-strategy"|/DS-strategy[/"]' "$py" 2>/dev/null; then
        # Допустимо если читает GOVERNANCE_REPO из env (значит fallback default)
        if ! grep -qE 'IWE_GOVERNANCE_REPO|GOVERNANCE_REPO' "$py" 2>/dev/null; then
            log "  ⚠ $py: hardcoded DS-strategy без чтения GOVERNANCE_REPO env"
            COVERAGE_VIOLATIONS=$((COVERAGE_VIOLATIONS + 1))
        fi
    fi
done < <(find roles -name '*.py' -type f 2>/dev/null)

# Prompts: не должны иметь bare DS-strategy/, должны использовать {{GOVERNANCE_REPO}}
while IFS= read -r prompt; do
    [ -f "$prompt" ] || continue
    # Hits: bare 'DS-strategy/' или ' DS-strategy ' или '`DS-strategy`' или '`DS-strategy/'
    # WP-279 fix: расширен паттерн — ранее пропускал `DS-strategy/path` (backtick+slash).
    # 0.29.19 DRY fix: regex source — setup/detector-regex.sh ($DETECTOR_07_REGEX).
    if grep -qE "$DETECTOR_07_REGEX" "$prompt" 2>/dev/null; then
        # Game допустима если параллельно есть {{GOVERNANCE_REPO}} (миграционная стадия)
        log "  ⚠ $prompt: bare DS-strategy без {{GOVERNANCE_REPO}}"
        COVERAGE_VIOLATIONS=$((COVERAGE_VIOLATIONS + 1))
    fi
done < <(find roles -name 'prompts' -type d 2>/dev/null | xargs -I{} find {} -name '*.md' -type f 2>/dev/null)

if [ "$COVERAGE_VIOLATIONS" -eq 0 ]; then
    log "  ✅ PASS"
else
    log "  ❌ FAIL ($COVERAGE_VIOLATIONS prompts/.py с hardcoded DS-strategy)"
    VIOLATIONS=$((VIOLATIONS + COVERAGE_VIOLATIONS))
fi
log ""

# === Detector 8: bare {{...}} в sed-выражениях substituted-runners (R6.1**, 0.29.6) ===
log "[8/12] sed_placeholder_escape — substituted runners НЕ имеют bare {{X}} в sed (build-runtime подменит)..."
SED_VIOLATIONS=0
# Парсим overlay-реестр: substituted-файлы из реестра проверяем на bare {{X}} в sed-выражениях.
# Антипаттерн (R6.1**): sed -e "s|{{X}}|val|" в substituted runner'е → build-runtime подменит {{X}} → sed broken.
# Правильно: использовать escape (через bash переменные _o='{''{', _c='}''}', либо вынести в helper).
while IFS= read -r path; do
    [ -f "$path" ] || continue
    case "$path" in *.sh)
        # Ищем sed -e "s|{{X}}|...|" — это bare placeholder в substituted-файле = регрессия R6.1**.
        if grep -qE 'sed.*-e.*"s\|\{\{[A-Z_]+\}\}\|' "$path" 2>/dev/null; then
            log "  ⚠ $path: bare {{X}} в sed-выражении (R6.1** antipattern, build-runtime подменит литерал)"
            SED_VIOLATIONS=$((SED_VIOLATIONS + 1))
        fi
        ;;
    esac
done < <(awk '/^substituted:/,/^[a-z_]+:/' .claude/runtime-overlay.yaml 2>/dev/null | grep -oE '^\s+- .*' | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/[[:space:]]*#.*//')

if [ "$SED_VIOLATIONS" -eq 0 ]; then
    log "  ✅ PASS"
else
    log "  ❌ FAIL ($SED_VIOLATIONS substituted runners с bare {{X}} sed)"
    VIOLATIONS=$((VIOLATIONS + SED_VIOLATIONS))
fi
log ""

# === Detector 9: version_bump_consistency (issue #52, audit 0.29.29) ===
# Если был code-commit ПОСЛЕ последнего bump'а update-manifest.json — значит fix
# не released. update.sh у пилотов не подтянет изменения, потому что версия не
# поменялась. Срабатывает на: 75e1819 (fix Scout) после 4f0277f (manifest 0.29.29).
log "[9/12] version_bump_consistency — code commits после manifest bump = unreleased fix..."
BUMP_VIOLATIONS=0
if [ -d .git ] && command -v git >/dev/null 2>&1; then
    LAST_MANIFEST_BUMP=$(git log -1 --format=%H -- update-manifest.json 2>/dev/null || echo "")
    if [ -n "$LAST_MANIFEST_BUMP" ]; then
        # Считаем commits, изменившие code/scripts/hooks/skills/memory ПОСЛЕ manifest bump'а.
        # Исключаем самые manifest и CHANGELOG (release-housekeeping commits).
        UNRELEASED=$(git log --oneline "$LAST_MANIFEST_BUMP..HEAD" -- \
            .claude/ scripts/ setup/ roles/ memory/ 2>/dev/null \
            | grep -vE 'CHANGELOG|update-manifest' || true)
        if [ -n "$UNRELEASED" ]; then
            COUNT=$(echo "$UNRELEASED" | wc -l | tr -d ' ')
            log "  ⚠ WARN: $COUNT code commits после manifest bump $LAST_MANIFEST_BUMP — нужен version bump"
            verbose "    $(echo "$UNRELEASED" | head -3)"
            BUMP_VIOLATIONS="$COUNT"
        fi
    fi
    if [ "$BUMP_VIOLATIONS" -eq 0 ]; then
        log "  ✅ PASS"
    fi
    # WARN, не FAIL — release-process сигнал, не drift в коде. Не блокирует CI на feature-веткак.
else
    log "  ⊘ SKIP (нет .git или git недоступен)"
fi
log ""

# === Detector 10: tracked_artifacts (issue #52, audit 0.29.29) ===
# .DS_Store/__pycache__/*.pyc/*.swp в tracked-files = шум на пилотах + версионная
# несовместимость bytecode'а. Также проверяем покрытие .gitignore.
log "[10/12] tracked_artifacts — .DS_Store/__pycache__/*.pyc/*.swp в дереве + .gitignore..."
ARTIFACT_VIOLATIONS=0
if [ -d .git ] && command -v git >/dev/null 2>&1; then
    # Tracked OS/IDE/build artifacts
    TRACKED_ARTIFACTS=$(git ls-files 2>/dev/null \
        | grep -E '(^|/)\.DS_Store$|(^|/)Thumbs\.db$|(^|/)__pycache__/|\.pyc$|\.swp$|(^|/)\.idea/' \
        || true)
    if [ -n "$TRACKED_ARTIFACTS" ]; then
        log "  ❌ Tracked artifacts (шум для пилотов):"
        echo "$TRACKED_ARTIFACTS" | sed 's/^/      /'
        ARTIFACT_VIOLATIONS=$(echo "$TRACKED_ARTIFACTS" | wc -l | tr -d ' ')
    fi

    # .gitignore coverage check
    if [ -f .gitignore ]; then
        for p in '.DS_Store' '__pycache__' '*.pyc' '*.swp'; do
            # Pattern должен присутствовать как самостоятельная строка (не в комментарии)
            if ! grep -qE "^${p}$|^/${p}$|^\*\*/${p}$" .gitignore 2>/dev/null; then
                log "  ⚠ $p не в .gitignore"
                ARTIFACT_VIOLATIONS=$((ARTIFACT_VIOLATIONS + 1))
            fi
        done
    fi

    if [ "$ARTIFACT_VIOLATIONS" -eq 0 ]; then
        log "  ✅ PASS"
    else
        log "  ⚠ WARN ($ARTIFACT_VIOLATIONS artifact-нарушений) — promote в FAIL после фикса"
    fi
    # WARN, не FAIL — initial bootstrap detector. Promote в FAIL отдельным commit'ом
    # после очистки .DS_Store + расширения .gitignore.
else
    log "  ⊘ SKIP (нет .git)"
fi
log ""

# === Detector 11: memory_internal_refs (issue #52, audit 0.29.29) ===
# memory/MEMORY.md и memory/navigation.md содержат таблицу ссылок на memory/*.md.
# Битые ссылки = свежий пилот после setup.sh видит broken-навигацию.
log "[11/12] memory_internal_refs — ссылки memory/*.md из MEMORY/navigation указывают на существующее..."
REFS_VIOLATIONS=0
if [ -d memory ]; then
    BROKEN_REFS=$(grep -hoE '`memory/[a-z0-9_-]+\.md`?' memory/MEMORY.md memory/navigation.md 2>/dev/null \
        | tr -d '`' \
        | sort -u \
        | while IFS= read -r p; do
            [ -f "$p" ] || echo "$p"
        done)
    if [ -n "$BROKEN_REFS" ]; then
        log "  ⚠ Broken memory refs (WARN — promote в FAIL после фикса):"
        echo "$BROKEN_REFS" | sed 's/^/      /'
    else
        log "  ✅ PASS"
    fi
    # WARN, не FAIL — bootstrap detector.
else
    log "  ⊘ SKIP (нет memory/)"
fi
log ""

# === Detector 12: stat_portability (issue #52, audit 0.29.29) ===
# `stat -f` (BSD/macOS) без `stat -c` (GNU/Linux) fallback в той же функции = молча
# возвращает мусор на Linux. Симптом найден в scripts/iwe-drift.sh:74 — функция
# dir_newest_mtime_days_ago даёт абсурдные значения, /audit-installation skill
# показывает фантомные drift-warnings.
log "[12/12] stat_portability — stat -f без cross-platform fallback в той же функции..."
STAT_VIOLATIONS=0
while IFS= read -r f; do
    [ -f "$f" ] || continue
    # Для каждой строки `stat -f` проверяем, есть ли `stat -c` либо `Darwin`/`uname`
    # check в окне ±5 строк (одна функция). Skip self (validator-meta references).
    case "$f" in
        ./setup/integration-contract-validator.sh) continue ;;
    esac
    # grep -n "$f" выдаёт `lineno:content` (без имени файла, потому что grep
    # принимает один файл). Поэтому первое поле IFS=: — это lineno, а не file.
    while IFS=: read -r lineno _rest; do
        case "${lineno:-}" in
            ''|*[!0-9]*) continue ;;
        esac
        if [ "$lineno" -gt 5 ]; then
            start=$((lineno - 5))
        else
            start=1
        fi
        end=$((lineno + 5))
        if ! sed -n "${start},${end}p" "$f" 2>/dev/null | grep -qE 'stat -c|Darwin|uname[^|]*Darwin|case.*Darwin'; then
            log "  ❌ $f:$lineno — stat -f без stat -c fallback в окрестности (Linux mtime breakage)"
            STAT_VIOLATIONS=$((STAT_VIOLATIONS + 1))
        fi
    done < <(grep -nE 'stat -f' "$f" 2>/dev/null)
done < <(find . -name '*.sh' -type f -not -path '*/.git/*' 2>/dev/null)

if [ "$STAT_VIOLATIONS" -eq 0 ]; then
    log "  ✅ PASS"
else
    log "  ⚠ WARN ($STAT_VIOLATIONS stat -f без fallback) — promote в FAIL после фикса"
fi
# WARN, не FAIL — bootstrap detector. Promote в FAIL после добавления `|| stat -c %Y`
# fallback в iwe-drift.sh:74 и memory-bleed.sh:158.
log ""

# === Verdict ===
log "=================================================="
if [ "$VIOLATIONS" -eq 0 ]; then
    log "  ✅ Integration contracts: PASS"
    log "=================================================="
    exit 0
else
    log "  ❌ Integration contracts: $VIOLATIONS violations"
    log "=================================================="
    exit "$VIOLATIONS"
fi
