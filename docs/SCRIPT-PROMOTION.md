# Промоция скрипта: L3 (author) → L1 (universal)

> Процесс переноса скрипта из авторской зоны (`WORKSPACE/scripts/`) в FMT-шаблон
> (`FMT-exocortex-template/scripts/`), откуда `update.sh` доставит его всем пилотам.
> Источник: WP-5 #12, DP.KR.001 §5.6.

## Когда промотировать

Промоция уместна, если скрипт:
- работает в авторском IWE ≥2 недели без серьёзных правок
- имеет универсальную ценность (не привязан к личным данным автора)
- параметризуем через `WORKSPACE_DIR` + `params.yaml` (или env-переменные)

Не промотируется:
- скрипт, ссылающийся на личные репозитории (например, governance-репо автора)
- одноразовый скрипт без планов повторного запуска
- скрипт с авторскими константами, которые нельзя вынести в параметр

## 7-шаговый процесс

### Шаг 1. Проверить коллизии

```bash
~/IWE/FMT-exocortex-template/scripts/check-script-collisions.sh
```

Если скрипт с таким же именем уже в FMT — разобрать коллизию: merge (оставить
одну версию) или rename (если нужны обе функции). Без этого шага промоция
сломает поведение у пилотов, у которых скрипт уже есть.

### Шаг 2. Параметризовать авторские константы

| Авторская константа | Универсальный паттерн |
|---------------------|-----------------------|
| `$HOME/IWE` | `${WORKSPACE_DIR:-$HOME/IWE}` |
| `$HOME/IWE/PACK-personal` | `params.yaml` → пользовательский ключ |
| Личные пути (governance, knowledge-index) | `params.yaml` параметр + graceful skip если пусто |
| WakaTime CLI путь | `${WAKATIME_CLI:-$HOME/.wakatime/wakatime-cli}` |
| FMT путь | `${FMT_PATH:-${WORKSPACE_DIR}/FMT-exocortex-template}` |

Правило: скрипт читает параметры из `${WORKSPACE_DIR}/params.yaml`. Если
обязательный параметр отсутствует — выводит сообщение и `exit 0` (не fail).

### Шаг 3. Добавить параметр в FMT/params.yaml

Если скрипт требует нового параметра — добавить в `FMT-exocortex-template/params.yaml`
с дефолтом (обычно пустая строка) + комментарием, объясняющим назначение.

### Шаг 4. Скопировать в FMT

```bash
cp WORKSPACE/scripts/my-script.sh FMT-exocortex-template/scripts/my-script.sh
chmod +x FMT-exocortex-template/scripts/my-script.sh
```

### Шаг 5. Зарегистрировать в update-manifest.json

Добавить запись в `FMT-exocortex-template/update-manifest.json`:

```json
{
  "path": "scripts/my-script.sh"
}
```

Список упорядочен лексикографически по `path` — вставлять в правильную позицию.

### Шаг 6. Обновить версию манифеста и CHANGELOG

В `update-manifest.json` поднять `version` (semver: новый скрипт = minor bump).
В `CHANGELOG.md` добавить запись с этой версией.

Pre-commit hook `.githooks/pre-commit` проверяет согласованность версий
manifest ↔ CHANGELOG — без bump-а коммит будет заблокирован.

### Шаг 7. Smoke-test и коммит

```bash
# Smoke-test 1: скрипт работает без params.yaml (graceful skip)
bash FMT-exocortex-template/scripts/my-script.sh

# Smoke-test 2: с params.yaml — выполняет ожидаемое действие
WORKSPACE_DIR=/tmp/test-iwe bash FMT-exocortex-template/scripts/my-script.sh

cd FMT-exocortex-template
git add scripts/my-script.sh params.yaml update-manifest.json CHANGELOG.md
git commit -m "feat: promote my-script.sh from staging"
git push
```

## Удаление автора-версии (после промоции)

Если скрипт **не имеет** дополнительной авторской логики поверх универсальной —
удалить из `WORKSPACE/scripts/`. Следующий `update.sh` доставит FMT-версию
обратно в `WORKSPACE/scripts/` — единая точка истины.

Если у автора есть **дополнительная логика** (например, обёртка с авторскими
аргументами) — переименовать авторскую версию, чтобы избежать коллизии после
прихода универсальной.

## Откат

`git revert` коммита промоции + следующий `update.sh` у пилотов вернёт прежнее
состояние. Параметр в `params.yaml` остаётся (без вреда, неиспользуем).

## Связь с правилами

- **DP.KR.001 §5.6** — классификация скриптов как исполнителей ролей
- **DP.D.048** — Script ≠ Agent (детерминированный flow)
- **DP.D.049** — Log ≠ Incident ≠ State file (артефакты исполнения)
- **§9 CLAUDE.md** — авторский режим (`params.yaml: author_mode: true`)
- **Extensions Gate** — пользовательская кастомизация только через `extensions/`
