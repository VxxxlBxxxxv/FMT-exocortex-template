---
name: fpf
description: Загрузка применимых принципов для задачи из иерархии Pack → SPF → FPF. Используй когда нужно найти релевантные принципы перед принятием решения.
argument-hint: "<запрос или тема>"
---

# Загрузка принципов

Запрос: $ARGUMENTS

## Fallback Chain

```
Pack (предметное) → SPF (корректность) → FPF (первые принципы)
```

## Алгоритм

1. **Классифицируй запрос:**
   - Предметное знание (архитектура, домен, сервис) → source_type=pack
   - Форма, процесс, корректность → source=SPF
   - Базовые различения, первые принципы → source=FPF

2. **Ищи через knowledge-mcp:**
   - `knowledge-mcp search(query="<запрос>", source_type="pack")` -- по всем Pack
   - `knowledge-mcp search(query="<запрос>", source="SPF")` -- по SPF
   - `knowledge-mcp search(query="<запрос>", source="FPF")` -- по FPF
   - Если первый уровень не дал результатов -- спускайся по fallback chain

3. **Если knowledge-mcp недоступен** (нет в `/mcp`):
   - Pack: читай файлы `PACK-*/pack/` через Glob + Read
   - SPF: читай `SPF/docs/` через Glob + Read
   - FPF: читай `FPF/Readme.md` (обзор) или ищи через Grep по `FPF/`

4. **Покажи** релевантные принципы с пояснением, как они применимы к задаче. Включай ссылку на источник (github_url из результата поиска или путь к файлу).
