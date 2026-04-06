#!/bin/bash
# Google Calendar MCP — подключение за 1 минуту
# Использует Shared OAuth App проекта IWE
#
# Usage:
#   bash setup/optional/setup-calendar.sh
#   bash setup/optional/setup-calendar.sh --account work
#
set -e

ACCOUNT="${1:-personal}"
if [ "$1" = "--account" ]; then
    ACCOUNT="${2:-personal}"
fi

# Workspace = parent of the script's directory (FMT-exocortex-template → workspace)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# If running from workspace root directly
if [ -f "$WORKSPACE_DIR/CLAUDE.md" ] && [ ! -d "$WORKSPACE_DIR/memory" ] 2>/dev/null; then
    WORKSPACE_DIR="$(dirname "$WORKSPACE_DIR")"
fi
# Use WORKSPACE_DIR from env if set, otherwise detect
WORKSPACE_DIR="${IWE_WORKSPACE:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

SECRETS_DIR="$WORKSPACE_DIR/.secrets"

echo "========================================"
echo "  Google Calendar для IWE"
echo "========================================"
echo ""
echo "Аккаунт: $ACCOUNT"
echo "Workspace: $WORKSPACE_DIR"
echo ""

# 1. Создать .secrets/ если нет
mkdir -p "$SECRETS_DIR"

# 2. OAuth credentials: из .exocortex.env или ручной путь
# Формат в .exocortex.env:  GCP_OAUTH_CREDENTIALS=/path/to/gcp-oauth.keys.json
ENV_FILE="$WORKSPACE_DIR/.exocortex.env"
CREDS_PATH="${GCP_OAUTH_CREDENTIALS:-}"

if [ -z "$CREDS_PATH" ] && [ -f "$ENV_FILE" ]; then
    CREDS_PATH=$(grep '^GCP_OAUTH_CREDENTIALS=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2-)
fi

if [ -n "$CREDS_PATH" ] && [ -f "$CREDS_PATH" ]; then
    cp "$CREDS_PATH" "$SECRETS_DIR/gcp-oauth.keys.json"
    echo "  ✓ OAuth credentials скопированы из $CREDS_PATH"
elif [ -f "$SECRETS_DIR/gcp-oauth.keys.json" ]; then
    echo "  ✓ OAuth credentials уже на месте (.secrets/gcp-oauth.keys.json)"
else
    echo "  ✗ OAuth credentials не найдены."
    echo ""
    echo "  Для настройки Google Calendar MCP нужен файл gcp-oauth.keys.json."
    echo "  Получить его можно двумя способами:"
    echo ""
    echo "  1. Создать свой OAuth App в Google Cloud Console:"
    echo "     https://console.cloud.google.com/apis/credentials"
    echo "     Скачать JSON → сохранить как: $SECRETS_DIR/gcp-oauth.keys.json"
    echo ""
    echo "  2. Указать путь к существующему файлу в .exocortex.env:"
    echo "     echo 'GCP_OAUTH_CREDENTIALS=/path/to/gcp-oauth.keys.json' >> $ENV_FILE"
    echo ""
    exit 1
fi

# 3. Проверить .gitignore
if [ -f "$WORKSPACE_DIR/.gitignore" ]; then
    if ! grep -q '.secrets/' "$WORKSPACE_DIR/.gitignore" 2>/dev/null; then
        echo '.secrets/' >> "$WORKSPACE_DIR/.gitignore"
        echo "  ✓ .secrets/ добавлен в .gitignore"
    fi
fi

# 4. Добавить MCP-сервер в .mcp.json
MCP_FILE="$WORKSPACE_DIR/.mcp.json"
if [ -f "$MCP_FILE" ]; then
    # Проверить, не добавлен ли уже
    if grep -q 'google-calendar' "$MCP_FILE" 2>/dev/null; then
        echo "  ✓ google-calendar уже в .mcp.json"
    else
        echo "  ⚠ Добавьте google-calendar в $MCP_FILE вручную:"
        echo '    "google-calendar": {'
        echo '      "command": "npx",'
        echo '      "args": ["-y", "@cocal/google-calendar-mcp"],'
        echo '      "env": {'
        echo "        \"GOOGLE_OAUTH_CREDENTIALS\": \"$SECRETS_DIR/gcp-oauth.keys.json\""
        echo '      }'
        echo '    }'
    fi
else
    cat > "$MCP_FILE" << MCPJSON
{
  "mcpServers": {
    "google-calendar": {
      "command": "npx",
      "args": ["-y", "@cocal/google-calendar-mcp"],
      "env": {
        "GOOGLE_OAUTH_CREDENTIALS": "$SECRETS_DIR/gcp-oauth.keys.json"
      }
    }
  }
}
MCPJSON
    echo "  ✓ .mcp.json создан"
fi

# 5. Запустить OAuth авторизацию
echo ""
echo "Сейчас откроется браузер для входа в Google."
echo "Войдите в свой аккаунт и нажмите «Разрешить»."
echo ""
echo "⚠ Google покажет предупреждение «This app isn't verified»."
echo "  Это нормально — нажмите «Advanced» → «Go to IWE MIM (unsafe)» → «Allow»."
echo "  Приложение безопасное, просто не проходило верификацию Google (не нужна до 100 пользователей)."
echo ""
read -p "Готовы? (Enter для продолжения) " -r

GOOGLE_OAUTH_CREDENTIALS="$SECRETS_DIR/gcp-oauth.keys.json" \
    npx -y @cocal/google-calendar-mcp auth --account "$ACCOUNT"

echo ""
echo "========================================"
echo "  Календарь подключён!"
echo "========================================"
echo ""
echo "Проверка:"
echo "  1. Перезапустите Claude Code (чтобы MCP подхватился)"
echo "  2. Скажите: «покажи мои события на сегодня»"
echo ""
