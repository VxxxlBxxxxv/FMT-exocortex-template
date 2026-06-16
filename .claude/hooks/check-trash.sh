#!/usr/bin/env bash
# SessionStart — verify a safe-delete CLI is available (safe-delete policy: never rm -rf).
# Non-blocking: prints a warning to context if missing, so the user can install it.
set -euo pipefail

has_safe_delete_cli() {
  command -v trash >/dev/null 2>&1 || \
    command -v trash-put >/dev/null 2>&1 || \
    command -v gio >/dev/null 2>&1
}

install_hint() {
  local os_id=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id="${ID:-} ${ID_LIKE:-}"
  fi

  if grep -qi microsoft /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then
    echo "sudo apt update && sudo apt install trash-cli"
  elif echo "$os_id" | grep -qiE 'ubuntu|debian'; then
    echo "sudo apt update && sudo apt install trash-cli"
  elif echo "$os_id" | grep -qiE 'arch|manjaro'; then
    echo "sudo pacman -S trash-cli"
  elif echo "$os_id" | grep -qiE 'fedora|rhel|centos'; then
    echo "sudo dnf install trash-cli"
  else
    echo "install trash-cli (or provide trash-put / gio trash)"
  fi
}

if ! has_safe_delete_cli; then
  echo "⚠️ safe-delete CLI не найден — политика безопасного удаления (вместо rm -rf) не работает. Установка: $(install_hint)" >&2
fi

exit 0
