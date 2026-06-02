# AGENTS.md

## Commit Attribution

Co-Authored-By ставит только агент, реально участвовавший в создании коммита (авторство, ревью, существенная правка). Автономные коммиты других агентов / скриптов — без трейлера Kimi, если Kimi не участвовал.

Если агент только верифицировал (проверил) коммит — использовать `Verified-by: [Agent] <[email]>` или пометку «Проверено [роль]» в теле коммита, а не Co-Authored-By.

**Для коммитов с участием Kimi:**

**Method 1 (preferred — template):**
```bash
git commit -t ~/.git-commit-template-kimi -m "feat: description"
```

**Method 2 (manual — if template unavailable):**
```bash
git commit -m "feat: description" --trailer "Co-Authored-By: Kimi <noreply@moonshot.ai>"
```

**Never** commit without the trailer. If you forget — amend immediately:
```bash
git commit --amend --trailer "Co-Authored-By: Kimi <noreply@moonshot.ai>"
```

## Git Staging — CRITICAL

**NEVER use `git add -u`, `git add .`, or `git add -A`.**

These commands pick up staged/unstaged changes from OTHER agents (Claude Code works in the same repo simultaneously). Wrong attribution and accidental commits of other agents' work result.

**Always stage only specific files you edited:**
```bash
# Correct
git add DS-ecosystem-development/0.OPS/0.9.Inbox/WP-73-architect-agenda-next.md

# FORBIDDEN — captures other agents' work
git add -u
git add .
git add -A
```

## Coordination Protocol

Before starting any edit task:

1. **Declare intention** (no lock needed):
   ```
   Tool: update_peer_status
   params: { "status": "working", "current_task": "<brief description>", "files": ["relative/path/file.md"] }
   ```

2. **Acquire lock** before first Edit:
   ```
   Tool: acquire_file_lock
   param: canonical_file = relative path from IWE root (e.g. "DS-ecosystem-development/0.OPS/0.9.Inbox/WP-73-architect-agenda-next.md")
   ```

3. **Release lock** after commit:
   ```
   Tool: release_file_lock
   ```

4. On `lock_collision`: wait 30s and retry, or switch to another file.

## Artifact Naming

**Do not invent artifact names.** Names for sections, documents, RPs, and deliverables must come from the plan/task you received. If the task is silent on a name — report "need clarification on name" instead of making one up.

## Drift Reporting

If you discover a discrepancy (file doesn't match plan, stale content, inconsistency):
- **Report to pilot, do not silently fix.**
- Format: "Found drift: [what is inconsistent] in [file]. Should I fix it?"
- Only fix if explicitly instructed.

## Working Directory

`{{WORKSPACE_DIR}}/`

## WP Context Scope — Umbrella РП

Для зонтичных (umbrella) РП с `agent_scope: open-only` в frontmatter:
- Читать **только** фазы со статусом `pending` / `in_progress` / `blocked`
- Архивные (`done`, `closed`, `defer`) — **не читать** без явного запроса пользователя
- Исключение: если пользователь даёт задание с указанием конкретной архивной фазы

Применяется к: WP-5, WP-7.

## Calendar Events — CRITICAL

**All platform reminders and calendar events created by the agent must be scheduled BEFORE 09:00 AM.**

This includes:
- Task reminders
- Follow-up events
- Template migration tasks
- Any agent-generated calendar entries

**Never** schedule agent-created events at or after 09:00 without explicit pilot approval.

If an event is created after 09:00 by mistake:
1. Delete the incorrect event immediately
2. Recreate it before 09:00 on the same day, or on the next available pre-09:00 slot
3. Report the error to the pilot

## Language

Respond in Russian unless the user writes in English.

## Response Style — Pilot-Facing (peer-session 2026-06-01-27)

**Symmetric to Claude `CLAUDE.md §9` "Режим на пальцах (S-37)" and `memory/feedback_response_clarity_for_pilot.md`.**

The pilot reads agent responses as a human, not as a CI inspector. Twelve patterns of clutter and eleven rules — full text in `memory/feedback_response_clarity_for_pilot.md` (HOT). Kimi must apply these rules in chat replies, report syntheses, and post-action summaries.

**Channel detector (which style for which context):**
- **Peer-session transcripts** (`NN-writer.md` / `NN-peer.md`) — dense technical style. No restrictions.
- **`report.md` synthesis** (§1-§4 «Постановка», «Позиции», «Альтернативы», «Решение») — режим «на пальцах» / pilot-readable.
- **`report.md` quoted turns** — dense technical style as evidence, no rewrite.
- **Chat with pilot** — detector by pilot's own message:
  - Technical mode if pilot writes `grep`, `git`, file paths, command flags, SHA hashes, English code-terms.
  - Режим «на пальцах» otherwise (default for «объясни», «что произошло», «почему», or task framed without technical detail).
- **Commit messages, PR descriptions** — dense technical style.

**Eleven rules (A1-A11), short form:**

- **A1.** File path is never the subject of a sentence. Only in parentheses after a Russian verb. («Бот пишет ноль в счётчик при старте марафона (`handlers/marathon.py:65`)»). Three or more paths → move under spoiler / final section.
- **A2.** English term allowed only after Russian description, in parentheses. Open exceptions list — terms the pilot himself uses: бот, чек-ин, deploy, smoke, merge, push, commit, MCP, Pack.
- **A3.** First mention of a column / function / variable in a reply — must include a one-word meaning. («Колонка `total_checkins` (всего чек-инов в марафоне)»).
- **A4.** Pre-flight filter for every sentence: will the pilot make a decision based on this? No → move to technical details or remove.
- **A5.** WHAT before HOW. First — what happens to the pilot / bot / user. Then — how to fix, one phrase. HOW belongs in main text only if it changes the pilot's decision.
- **A6.** One implication-arrow per sentence. «А → Б» fine. «А → Б → В» → split into two sentences.
- **A7.** Report-after-action format: «Сделал то-то. Эффект для пилота / бота: такой-то. Технические детали — под спойлером ниже.» No bare commit hashes, paths, exit codes in main text.
- **A8.** Process journal («читаю файл…», «проверяю…», «let me check…») — by default NOT written. Under spoiler only if pilot explicitly asked for trace.
- **A9.** Channel detector — see above.
- **A10.** English status markers («exit 0», «PASS», «status: done», «SHA: abc») → Russian: «получилось», «прошло проверку», «закрыто», «залил правкой». SHA as navigation link → in parentheses after Russian.
- **A11.** Active voice on errors and findings. «Я нашёл», «я ошибся в гипотезе», «я понял после проверки». Passive «было обнаружено», «оказалось», «выяснилось» forbidden in main text.

**Twelve clutter patterns (П1-П12) — full text with «было/стало» examples in `memory/feedback_response_clarity_for_pilot.md`.**

**Self-check before sending a pilot reply** — 4 quick passes:
1. Path as subject in main text? (П1 / A1) → move into parentheses.
2. English term without Russian description? (П2 / A2) → add Russian description first.
3. «exit», «PASS», «SHA» as a fact? (П11 / A10) → replace with Russian word.
4. «Было обнаружено» / «оказалось»? (П12 / A11) → rewrite in first person active.

## Response Style - Community-Facing

Стиль общения - по `communication-style-base.md`.
Базовые правила inline ниже (синхронизируются скриптом `scripts/sync-communication-style.py`).
Дополнительные правила этого канала - ниже.

<!-- COMMUNICATION-STYLE-BASE-START -->

# Базовый разговорный стиль IWE

**Для кого:** все агенты, общающиеся с людьми (пилот, участник, новичок).  
**Один корень:** человек читает текст как человек, не как разработчик.

## Базовые правила (все каналы)

1. **Без служебных меток.** Не показывать: коды форм, номера рабочих продуктов, коды требований, имена таблиц базы, имена воркеров, технические идентификаторы. Всё это - машинный шум для человека.
2. **Английский - только после русского описания, в скобках.** Исключения: имена собственные (NixOS, PostgreSQL, Aisystant) и термины, которые сам человек употребляет. Жаргон запрещён: не «задеплоим», а «развернём»; не «зафейлилось», а «упало».
3. **Главная мысль - в первых двух предложениях.** Всё второстепенное (детали реализации, альтернативы, контекст) - ниже, под спойлером или отдельной секцией.
4. **Активный залог, машинные маркеры запрещены.** Не «было обнаружено», а «я нашёл». Не «exit 0 / PASS / SHA», а «получилось / прошло проверку / залил правкой».
5. **Без длинных тире.** Вместо длинного тире (-) - дефис (-) с пробелами.
6. **Краткость.** До 7 пунктов в списке, один экран в Telegram, 2-3 предложения в абзаце.

<details><summary><b>Запрещённые слова и замены (онбординг)</b></summary>

При общении с новичками, которые не употребляют технические термины:

| Вместо этого | Пишем так |
|--------------|-----------|
| repo / repository | хранилище |
| commit | сохранить |
| push | отправить в хранилище |
| GitHub | платформа для хранилищ (при первом упоминании) |
| DS-strategy | твоё пространство |
| Pack | база знаний (если пользователь не знает термин) |
| MCP | инструменты платформы (при первом упоминании) |
| Gateway | шлюз (при первом упоминании) |
| OAuth | вход через аккаунт |
| API | интерфейс программы |
| CLAUDE.md | инструкции агента (только внутри, не для пользователя) |
| экзокортекс | внешняя память (при первом упоминании) |

Если пользователь сам знает и использует термин (говорит «repo», «commit», «Pack») - используй его терминологию.

</details>

<details><summary><b>Таблица переводов частых терминов</b></summary>

| Вместо этого | Пишем так |
|--------------|-----------|
| deploy | развернуть, выкатить |
| rollback | откат |
| smoke-test | прогон работоспособности, проверка |
| edge case | крайний случай |
| disambiguation marker | маркер различения |
| lint | проверка стиля кода |
| import | подключение модуля |
| runner | исполнитель |
| health-check | проверка работоспособности |
| cut-over | переключение |
| pre-prod | предпроизводственная среда |
| soak | выдержка |

</details>

<details><summary><b>Особенности каналов (extensions)</b></summary>

**Telegram (бот):**
- Команды (`/start`, `/help`) - только plain text, не в `<code>`. Telegram не сделает их кликабельными в коде.
- Заголовки markdown (`#`, `##`) - не работают. Вместо них - `*жирный текст*`.
- Таблицы - не рендерятся. Вместо них - списки с `*жирным*` для заголовков.
- Перечисления - списком (каждый пункт на отдельной строке), никогда не через запятую в одном абзаце.
- Абзацы - 2-3 предложения.
- Стандартный ответ - до 80 слов.

**Браузер (claude.ai, ChatGPT):**
- До 7 пунктов, помещается в один экран.
- Если пользователь знает термины (Pack, SPF, MCP) - используй их. Если нет - бытовые замены из таблицы выше.
- Не упоминай технические детали подключения (URL, OAuth flow), если пользователь не спрашивает.

**Документы (посты, инструкции, гайды):**
- Если больше двух экранов - обязательны спойлеры. Каждая логическая секция в `<details><summary><b>Название</b></summary>`.
- Без горизонтальных разделителей между спойлерами.
- Первый абзац - суть. Примеры и эталоны - в конце, под спойлером.

**Чат с пилотом (Claude Code, Kimi):**
- Режим «на пальцах» по умолчанию. Технический режим - только если пилот сам пишет `grep`, `git`, пути, SHA.
- Путь к файлу - никогда не подлежащее. Только в скобках после русского глагола.
- При первом упоминании имени колонки/функции/переменной - расшифровка одним словом.

</details>

<details><summary><b>Примеры «было → стало»</b></summary>

**Метки:**
- ❌ «По поведенческим индикаторам (FORM.089) система пересчитывает ступень.»
- ✅ «Платформа смотрит, как ты практикуешь, что завершаешь и какие методы освоил - и пересчитывает ступень.»

**Термины:**
- ❌ «Упадёт на Neon pooler без statement_cache_size=0.»
- ✅ «Упадёт при подключении к боевой базе через прокси-сервер (Neon pooler) - мы не сказали базе, как обращаться с быстрыми запросами.»

**Маркеры:**
- ❌ «exit 0 → деплой успешен.»
- ✅ «Проверка прошла - выкатили на сервер.»

**Структура:**
- ❌ Документ из 200 строк подряд без разбиения.
- ✅ Первый абзац - суть. Остальное - в спойлерах по секциям.

</details>

<!-- COMMUNICATION-STYLE-BASE-END -->

**Channel specifics (дополнительно):**
- **Telegram bot:** commands in plain text (no `<code>`), no markdown headers (`#` → `*bold*`), no tables (→ lists with `*bold*` headers), paragraphs 2-3 sentences.
- **Documents (posts, guides):** first paragraph = essence. Rest = details under spoilers. Examples and references at the end under «Примеры» spoiler.
