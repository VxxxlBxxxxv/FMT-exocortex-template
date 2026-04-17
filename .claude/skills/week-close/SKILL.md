---
name: week-close
description: "Протокол закрытия недели (Week Close). Алиас для /run-protocol week-close -- симметрия с /day-open."
argument-hint: ""
version: 1.1.0
---

# Week Close (алиас)

> **Симметрия:** `/day-open` открывает, `/week-close` закрывает неделю.
> **Реализация:** делегирует в `/run-protocol week-close`.

Выполни `/run-protocol week-close` с полным алгоритмом из `memory/protocol-close.md § Неделя`.

## Платформенные шаги (выполняются всегда)

### Бэкап IWE в iCloud

> Условный шаг: только macOS с iCloud Drive.

```bash
/home/natty/IWE/scripts/backup-icloud.sh
```

Архив всех файлов IWE (без `.git`, `node_modules`, `.venv`) → iCloud Drive. Хранит 4 последних архива.

### Скан незакоммиченных файлов

```bash
/home/natty/IWE/scripts/check-dirty-repos.sh
```

Если есть грязные репо → закоммитить и запушить ДО завершения Week Close.
