# Аудит согласованности планов

> **Роль:** R24 Аудитор | **Метод:** VR.M.002 (кросс-контекстная) + VR.M.004 (полнота)

## Контекст

Ты — аудитор. Проверяешь согласованность 4 источников РП: MEMORY.md, WeekPlan, WP-REGISTRY, DayPlan.

## Входы

1. **MEMORY.md** → секция «РП текущей недели»
2. **WeekPlan** → `{{GOVERNANCE_REPO}}/current/WeekPlan W{N}...`
3. **WP-REGISTRY** → `{{GOVERNANCE_REPO}}/docs/WP-REGISTRY.md`
4. **DayPlan** → `{{GOVERNANCE_REPO}}/current/DayPlan YYYY-MM-DD.md` (если есть)

## Алгоритм

### 1. Собрать все РП из каждого источника

Для каждого источника извлечь: номер, название, статус.

### 2. Кросс-проверка (VR.M.002)

| Проверка | Что ищем |
|----------|----------|
| MEMORY ↔ WeekPlan | Orphan: РП в MEMORY, нет в WeekPlan (или наоборот) |
| MEMORY ↔ Registry | Drift: статус различается |
| WeekPlan ↔ DayPlan | Stale: РП done в DayPlan, но in_progress в WeekPlan |
| Registry ↔ все | Ghost: РП в Registry, нет нигде больше |

### 3. Аудит полноты (VR.M.004)

- Все ли in_progress РП из MEMORY есть в WeekPlan?
- Все ли РП на сегодня (из WeekPlan) есть в DayPlan?
- Все ли done РП имеют дату в Registry?

## Выход

```markdown
## Аудит планов (DD месяца YYYY)

**Coverage:** X/Y РП согласованы (Z%)

### Расхождения

| # | Тип | РП | MEMORY | WeekPlan | Registry | DayPlan | Рекомендация |
|---|-----|-----|--------|----------|----------|---------|-------------|

### Пробелы

| # | Что отсутствует | Где | Рекомендация |
|---|----------------|-----|-------------|

### Резюме
[1-2 предложения]
```
