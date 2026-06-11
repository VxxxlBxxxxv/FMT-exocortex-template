# Каталог скиллов IWE

> Автогенерировано `scripts/generate-catalogs.py` · 2026-06-07 · НЕ редактировать вручную.
> Источник: `.claude/skills/*/SKILL.md`. Скилл вызывается командой `/<id>`.

| Скилл | Что делает |
|-------|------------|
| `/agent-fault` | Регистрация косяка агента в системе учёта WP-316 L1. Без LLM — детерминированный скрипт. |
| `/apply-captures` | Разбор extraction-reports со status pending-review — решение R15 (accept/reject/defer), запись в Pack, обновл… |
| `/archgate` | Оценка архитектурного решения по 7 характеристикам ЭМОГССБ (v3 — профиль без агрегатного балла, conjunctive s… |
| `/audit-docs` | Аудит документации репо: детекция drift'а между кодом и docs, отчёт coverage по категориям. Запускается вручн… |
| `/audit-installation` | Аудит пользовательской инсталляции IWE. Запускает scripts/iwe-audit.sh + MCP healthcheck + smoke-test ритуала… |
| `/bottleneck-pick` | Скилл IWE — см. тело файла |
| `/check-secret` | Проверка фрагмента текста на возможные секреты (API keys, tokens, passwords) ПЕРЕД отправкой в чат / коммитом… |
| `/consent` | Управление consent в learning.tracking_consent — opt-in / opt-out / status / revoke. Обязательное условие для… |
| `/day-close` | Протокол закрытия дня (Day Close). Алиас для /run-protocol close day — симметрия с /day-open. |
| `/day-open` | Протокол открытия дня (Day Open). Собирает вчерашние коммиты, issues, заметки, календарь, бота QA, Scout, мир… |
| `/decompose` | Декомпозиция деятельности на этапы с физическими артефактами и чеклистами приёмки. Детектор разрывов. Использ… |
| `/diagnose-iwe` | Диагностика ступени мастерства (Диагност R28, FORM.089 §6.1) прямо в VS Code / claude.ai. До 5 вопросов, ~5 м… |
| `/discovery-session` | — |
| `/extend` | Каталог расширяемости IWE: что можно настроить, какие extension points существуют, какие параметры доступны,… |
| `/fpf` | Загрузка применимых принципов для задачи из иерархии Pack → SPF → FPF. Используй когда нужно найти релевантны… |
| `/iwe-bug-report` | Сообщить об ошибке или проблеме платформы IWE. Создаёт GitHub issue в FMT-exocortex-template. |
| `/iwe-rules-review` | Еженедельное ревью культуры работы IWE (элемент 14 — Эволюция системы). Запускается при Week Close. |
| `/iwe-update` | Обновление IWE с объяснением изменений. Агент вызывает update.sh, парсит CHANGELOG, объясняет что изменилось,… |
| `/ke` | Knowledge Extraction — извлечение и маршрутизация знания на рубеже работы. Используй когда обнаружен паттерн,… |
| `/kimi-peer-writer` | Peer-сессия DP.SC.154 где Kimi = писатель, Claude = напарник. Запускается простой фразой. Включает ОРЗ Openin… |
| `/lesson-close` | Закрыть занятие, открытое скиллом /lesson. Финализирует workbook/YYYY-MM-DD.md (frontmatter status, метаданны… |
| `/month-close` | Протокол закрытия месяца (Month Close). Стадия 7 каскада ВДВ v9 (PD.METHOD.008). Запускается в первый Пн меся… |
| `/org-dev` | | |
| `/pack-creator` | | |
| `/pack-new` | Создание нового Pack — guided flow по SPF: выбор домена, имя Pack, scaffold структуры, дорожная карта наполне… |
| `/peer-conversation` | Многотуровый диалог писателя (Claude) с напарником (Kimi) по задаче пилота (DP.SC.154). Ведёт turn-loop, обна… |
| `/personal-guide-render` | Собирает (или пересобирает) персональное руководство в УЖЕ существующем репо `personal-guide` (плоское имя, о… |
| `/personal-guide-start` | Bootstrap-обёртка — создаёт пустой репо `personal-guide` под аккаунтом пилота (плоское имя, без логина в назв… |
| `/platform-bottleneck` | Alias для /bottleneck-pick --layer platform. Deprecated — используйте /bottleneck-pick напрямую. |
| `/run-protocol` | Пошаговое выполнение протокола ОРЗ с обязательной отметкой каждого шага. Предотвращает пропуск шагов (включая… |
| `/setup-wakatime` | Настройка WakaTime time-tracking для Claude Code и VS Code |
| `/strategy-session` | Стратегическая сессия — диспетчер. День-0 (нет Strategy.md/WeekPlan) → initial flow (цели, неудовлетворённост… |
| `/think` | ADI-цикл структурированного рассуждения (Abduction-Deduction-Induction-Audit-Decide). Используй для сложных р… |
| `/transcribe` | Транскрипция аудио/видео файлов через MLX Whisper (Apple Silicon). Использование: /transcribe path/to/file.mp3 |
| `/verify` | Верификация артефакта по эталону из Pack. Загружает роль VR.R.001 (Верификатор) с context isolation — проверя… |
| `/w-reflection` | Записать W-рефлексию (мировоззренческий слот RCS) в learning.w_reflections. Используется Диагностом R28 (MIM.… |
| `/week-close` | Протокол закрытия недели (Week Close). Ретро 7 дней + carry-over в новую неделю + платформенные шаги (бэкап,… |
| `/week-close-pilot` | Скилл IWE — см. тело файла |
| `/wp-new` | Создание нового рабочего продукта (РП) с записью в 5 мест атомарно. Используй когда появляется новая задача,… |

_Всего скиллов: 39_

