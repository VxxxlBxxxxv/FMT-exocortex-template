# Спецификация реализации — Secondary-Model Adapter

> **see DP.SC.163, DP.ROLE.060** (Pack-digital-platform). Обещание и роль — там; здесь только технические контракты реализации.
> **Источник:** WP-72, ArchGate Ф4 (2026-06-04) → вариант A «ядро-политика + тонкие provider-драйверы».
> **Статус:** спецификация (до кода). Контракты ниже = acceptance-критерий MVP.
> **Целевой репозиторий реализации:** `scripts/` этого шаблона.

Адаптер вторичных моделей даёт единый контракт вызова любой не-первичной модели (Kimi, Codex CLI, Gemini, локальная) как напарника/писателя/ревьюера/верификатора. Архитектура: **одно ядро-политика** держит всю безопасность и контракт отказа; **тонкие provider-драйверы** отвечают только за транспорт к конкретному backend. Добавление модели = драйвер + строка реестра, ядро не меняется.

<details open>
<summary><b>1. Архитектура (вердикт ArchGate Ф4)</b></summary>

```
вызывающий скилл/агент
        │ stdin (промпт) + --model M --mode {peer|writer|reviewer|verifier} --add-dir DIR
        ▼
┌─────────────────────────────────────────────┐
│  secondary-model-adapter.sh  (ЯДРО-ПОЛИТИКА) │
│  1 load model-registry.yaml (fail-closed)    │
│  2 resolve trust (реестр = потолок, CLI ↓)   │
│  3 проверка allowed_modes                    │
│  4 size-guard (≤100MB / ≤5000 файлов)        │
│  5 .agentigore + PII фильтр → чистая копия    │  ← peer-adapter-filter.py
│  6 sandbox (env -i, cwd, mkstemp 0600,        │
│     realpath/symlink, trap cleanup)          │
│  ── ВСЁ выше строго ДО вызова модели ──        │
│  7 exec drivers/<provider>.sh (транспорт)     │
│  8 empty-guard · verdict-parse · timeout     │
│  9 audit-envelope (out-of-band) · exit-код    │
└─────────────────────────────────────────────┘
        │ env: SMA_MODEL_RESOLVED, SMA_CLEAN_DIRS, SMA_MODE, SMA_TRUST, SMA_SANDBOX_CWD
        ▼
   drivers/kimi.sh   drivers/claude.sh   drivers/<next>.sh   ← только транспорт
        │
        ▼
   stdout (ответ модели) + stderr (диагностика) + sidecar (audit-envelope)
```

**Что в ядре (одна точка контроля):** парсинг аргументов, реестр, trust, проверка режима, size-guard, фильтрация PII/.agentigore, sandbox, empty-guard, verdict-парсинг, timeout, audit-envelope, публичный exit-контракт, строка attribution.

**Что в драйвере (тонкий, только транспорт):** найти/запустить binary backend на УЖЕ очищенных директориях, прокинуть модель, stdin → stdout. Драйвер **не** делает фильтрацию, **не** трогает оригинальные директории, **не** ставит attribution, **не** пишет за пределы sandbox.

**Принцип (OwnerIntegrity):** security-логика существует в ОДНОМ месте. Драйвер, который дублирует фильтр или trust — нарушение контракта (вето на code-review).

</details>

<details>
<summary><b>2. Реестр моделей — model-registry.yaml (schema v1)</b></summary>

Расположение: `scripts/model-registry.yaml`. Загружается ядром. Незнакомая модель → **fail-closed** (exit 5).

```yaml
schema_version: 1

defaults:
  unknown_model: deny          # fail-closed: не в реестре → отказ, не «как недоверенная»
  max_add_dir_mb: 100
  max_add_dir_files: 5000
  max_content_scan_mb: 10
  turn_timeout_sec: 900        # 15 мин hard cut-off хода (DP.SC.162 v2)

models:
  kimi:
    provider: moonshot
    driver: drivers/kimi.sh
    binary_detect:             # порядок поиска бинаря (драйвер исполняет)
      - { env: KIMI_BIN }
      - { path: kimi }
      - { glob: "$HOME/.config/Code/User/globalStorage/moonshot-ai.kimi-code/bin/kimi/kimi" }
    version_pin: ">=1.0"       # сверка по `<binary> --version`; mismatch → exit 5
    trust: untrusted           # trusted | untrusted  (потолок доверия)
    aliases: [kimi-k2, k2]
    allowed_modes: [peer, reviewer, verifier, writer]
    capabilities: [1,2,3,4,6,8,9,10]   # классы DP.SC.163 §Capability surface
    network: allow             # информативно для аудита

  claude:
    provider: anthropic
    driver: drivers/claude.sh
    binary_detect:
      - { env: CLAUDE_BIN }
      - { path: claude }
    trust: trusted
    aliases: [sonnet, opus, haiku, claude-*]
    allowed_modes: [peer, reviewer, verifier, writer]
    capabilities: [1,2,3,4,5,6,7,8,9,10,11]
```

**Правила реестра:**
- `allowed_modes` модели = пересечение её `capabilities` с лестницей режимов DP.SC.163 §Capability surface. Модель без класса 4 (tool use) не получает `writer`. Валидатор реестра проверяет это при загрузке.
- `trust` в реестре = **потолок**. CLI-флаг `--trust untrusted` может только **понизить** (доверенную модель прогнать как недоверенную), никогда не повысить.
- Защита реестра: файл под code-owner/подписью; ядро игнорирует попытку переопределить путь реестра через env без явного флага (защита от подмены — §6 поверхность config).

</details>

<details>
<summary><b>3. Интерфейс provider-драйвера</b></summary>

Драйвер — тонкий скрипт `scripts/drivers/<provider>.sh`, вызывается ядром **после** всех проверок безопасности. Контракт «ядро → драйвер»:

**Вход драйверу (env, выставляет ядро):**
| Переменная | Значение |
|---|---|
| `SMA_MODEL_RESOLVED` | конкретный backend-идентификатор модели (после нормализации алиаса) |
| `SMA_CLEAN_DIRS` | NUL-разделённый список УЖЕ очищенных директорий (только их можно отдавать модели) |
| `SMA_MODE` | `peer` / `writer` / `reviewer` / `verifier` |
| `SMA_TRUST` | `trusted` / `untrusted` (итоговый, после понижения) |
| `SMA_SANDBOX_CWD` | директория-песочница, в которой драйвер обязан запускать backend |
| stdin | промпт (ядро передаёт как есть) |

**Выход драйвера ядру:**
| Канал | Содержимое |
|---|---|
| stdout | ответ модели (markdown), без добавленной attribution |
| stderr | диагностика backend (auth/network/quota) |
| exit | `0` ok · `1` пустой ответ · `7` binary не найден/backend недоступен · `9` timeout (если драйвер сам ловит) · прочее → ядро нормализует |

**Обязанности драйвера (только транспорт):** найти binary по `binary_detect`, сверить `version_pin`, запустить backend на `SMA_CLEAN_DIRS` в `SMA_SANDBOX_CWD`, отдать stdin, вернуть stdout/stderr/exit.

**Запрещено драйверу:** фильтрация контекста, чтение оригинальных `--add-dir`, запись вне `SMA_SANDBOX_CWD`, эмиссия attribution, повышение trust, сетевые действия сверх вызова backend.

</details>

<details>
<summary><b>4. Контракт результата по режиму (role-result contracts)</b></summary>

Закрывает открытый вопрос DP.SC.163 «проверяемый контракт результата на режим».

| Режим | Контракт вывода | Проверка ядром |
|---|---|---|
| `peer` | свободная markdown-критика | нет (только attribution + envelope) |
| `reviewer` | список замечаний; рекомендованный формат строки `severity · file · note` | нет жёсткой; envelope фиксирует `mode=reviewer` |
| `writer` | артефакт (markdown) | непустой вывод; attribution `Co-Authored-By` обязателен |
| `verifier` | **первая непустая строка** = `ВЕРДИКТ: прошло \| не прошло \| неопределённо`, далее обоснование | ядро парсит вердикт → `envelope.verdict`; нераспознан → `verdict=неопределённо` + warn в stderr (exit 0, ответ есть) |

Вердикт верификатора — единственный режим с машиночитаемым контрактом; остальные свободны по форме, но всегда сопровождаются out-of-band attribution от ядра.

</details>

<details>
<summary><b>5. Публичный exit-контракт v1</b></summary>

Единый для всех моделей (инвариант 3 DP.SC.163). Колонка «владелец» = слой, который выставляет код.

| Exit | Условие | Фаза | Владелец | Гарантия при отказе |
|---|---|---|---|---|
| 0 | OK, непустой ответ | post | ядро | ответ в stdout |
| 1 | модель вызвана, вернула пусто | post | ядро (по сигналу драйвера) | инфра ок, семантика пуста |
| 2 | ошибка `.agentigore`-фильтра | pre | ядро | модель не вызвана |
| 3 | **PII Hard Block** | pre | ядро | модель не вызвана, PII-файл не скопирован |
| 4 | `--add-dir` >100MB / >5000 файлов | pre | ядро | модель не вызвана |
| 5 | модель/версия не в реестре (**fail-closed**) | pre | ядро | модель не вызвана |
| 6 | режим запрещён для trust-profile | pre | ядро | модель не вызвана |
| 7 | binary не найден / backend недоступен | pre | драйвер | инфра-ошибка, контекст не утёк |
| 8 | нарушение sandbox (path-traversal/symlink) | pre | ядро | модель не вызвана |
| **9** | **timeout/отмена хода (>turn_timeout_sec)** | post | ядро | процесс убит, sandbox очищен |

> Код **9** расширяет таблицу DP.SC.163 §Exceptions (там 0–8). При реализации — backport строки в DP.SC.163, чтобы не разъехались (OwnerIntegrity). Версия контракта: `exit-contract/1`; изменение кодов = major-bump.

</details>

<details>
<summary><b>6. Безопасность §Б — поверхность × митигация × failure-test</b></summary>

Решение пилота (2026-06-04): **митигация** — закрытие всех 9 поверхностей = acceptance-критерий MVP. Каждая строка обязана иметь проходящий failure-test до merge.

| # | Поверхность | Угроза | Митигация в ядре | Failure-test (acceptance) |
|---|---|---|---|---|
| 1 | **stdin** (промпт) | PII/секрет в payload → недоверенной модели | вне охвата фильтра по контракту; trust-политика + документированная граница; caller-ответственность | тест: промпт с секретом → envelope помечает `stdin_unfiltered=true`, граница задокументирована |
| 2 | **env** | секреты окружения наследует дочерний процесс | `env -i` + явный allowlist passthrough (PATH, HOME, backend-token по реестру) перед exec драйвера | тест: подложить `SECRET_X` в env → его нет в окружении backend |
| 3 | **tmp** | world-readable /tmp, предсказуемые имена, TOCTOU | `mktemp -d` 0700 + `mkstemp` 0600, выделенный корень, `trap cleanup EXIT INT TERM` | тест: проверить права 0600/0700; после выхода tmp удалён |
| 4 | **stderr** | секрет/PII backend в stderr → лог | перехват stderr ядром, скраб known-pattern перед проксированием, не эхоить сырьём в audit | тест: backend пишет `sk-...` в stderr → в логе редактировано |
| 5 | **cwd** | запуск в корне репо = доступ ко всем файлам через относительные пути | `SMA_SANDBOX_CWD` = tmp-песочница; только `SMA_CLEAN_DIRS` в allowlist | тест: backend пытается читать `../secret` → недоступно |
| 6 | **config** | подмена `model-registry.yaml`, env-override пути, неприпиненная версия | реестр из фиксированного пути; env-override только с явным флагом; `version_pin` сверка; fail-closed | тест: подмена пути реестра через env без флага → игнор; неизвестная версия → exit 5 |
| 7 | **logs** | сырьё с PII в audit-envelope | envelope хранит **только метаданные** (модель/режим/счётчики/exit), НЕ payload; attribution от ядра | тест: envelope не содержит текста ответа модели |
| 8 | **symlink** | symlink в allowlist-дир на `/etc`/секреты | `peer-adapter-filter.py` уже: `os.walk(followlinks=False)` + `islink` skip + realpath-guard; ядро повторно резолвит realpath границы | тест: symlink на `/etc/passwd` в `--add-dir` → пропущен, не скопирован |
| 9 | **crash cleanup** | падение оставляет tmp/полузапись attribution | `trap` cleanup на всех сигналах; атомарная запись envelope (tmp+rename); empty-guard отделяет «нет ответа» от «пусто» | тест: kill -9 драйвера → trap чистит tmp; envelope не полузаписан |

**Failure-test matrix (отдельный smoke):** unknown model (5), binary missing (7), empty output (1), PII block (3), size guard (4), mode denied (6), sandbox escape (8), timeout (9), pre-fail НЕ вызывает модель (инвариант 2), env-scrub (поверхность 2), tmp-perms (3), envelope-no-payload (7).

</details>

<details>
<summary><b>7. Audit-envelope v1 (out-of-band)</b></summary>

Attribution и метаданные эмитит **ядро**, не доверяя stdout модели (инвариант 5 DP.SC.163). Sidecar JSON: путь `$SMA_AUDIT_FILE` или дефолт `$TMPDIR/sma-audit-<ts>.json`; атомарная запись (tmp+rename).

```json
{
  "schema": "sma-audit/1",
  "ts": "2026-06-04T12:00:00Z",
  "model_alias": "kimi",
  "model_resolved": "kimi-k2",
  "provider": "moonshot",
  "binary_version": "1.2.3",
  "mode": "peer",
  "trust": "untrusted",
  "add_dirs_requested": ["/path/a"],
  "add_dirs_clean": ["/tmp/sma-xxxx/a"],
  "filtered_out_count": 3,
  "size_guard": { "mb": 12, "files": 240 },
  "stdin_unfiltered": true,
  "exit": 0,
  "duration_ms": 8400,
  "verdict": null,
  "attribution": "Co-Authored-By: Kimi <kimi@moonshot.local>"
}
```

**Запрещено в envelope:** текст промпта, текст ответа модели (поверхность 7 — logs). Только метаданные и счётчики.

</details>

<details>
<summary><b>8. Объём MVP и обратная совместимость</b></summary>

**MVP (один высокоэнергетический слот):**
1. `scripts/secondary-model-adapter.sh` — ядро-политика (все 9 шагов из §1).
2. `scripts/drivers/kimi.sh` — драйвер недоверенной модели (транспорт).
3. `scripts/drivers/claude.sh` — драйвер доверенной модели (тонкий проброс).
4. `scripts/model-registry.yaml` — kimi + claude.
5. Переиспользовать `scripts/peer-adapter-filter.py` как есть (фильтр уже закрывает поверхности 8, частично 1).
6. Smoke + failure-test matrix (§6).

**Обратная совместимость (без слома вызывающих скиллов):** `kimi-peer-adapter.sh` и `claude-peer-adapter.sh` остаются как **тонкие wrapper'ы**, вызывающие ядро:
- `kimi-peer-adapter.sh "$@"` → `secondary-model-adapter.sh --model kimi --mode peer "$@"`
- `claude-peer-adapter.sh "$@"` → `secondary-model-adapter.sh --model claude --mode peer "$@"`

Скиллы `peer-conversation`, `kimi-peer-writer` не трогаются — контракт stdin→stdout сохранён.

</details>

<details>
<summary><b>9. Разрешение открытых вопросов DP.SC.163</b></summary>

| Открытый вопрос (DP.SC.163) | Решение в спеке |
|---|---|
| Стрим vs буфер | **буфер**: все проверки строго pre-call (фильтр завершается до вызова); stdout буферизуется ядром для empty-guard и verdict-parse |
| Таймауты / зависший CLI | `turn_timeout_sec` (дефолт 900 = 15 мин, DP.SC.162 v2); ядро оборачивает драйвер в `timeout`; превышение → kill + exit 9 + cleanup |
| Версионирование контракта | три независимых версии: `exit-contract/1`, `sma-audit/1`, реестр `schema_version: 1`; breaking → major-bump |
| Машиночитаемый статус отдельно от stdout | exit-код + sidecar envelope; stdout = только ответ модели |
| Проверяемый контракт результата на режим | §4: verifier обязан вернуть строку `ВЕРДИКТ:`; остальные свободны |
| Лимиты stdout/токенов | size-guard на вход (есть); на выход — envelope фиксирует `duration_ms`; жёсткий лимит вывода — defer до наблюдаемой проблемы (YAGNI) |

</details>

<details>
<summary><b>10. Acceptance-чеклист спеки → перед кодом</b></summary>

- [ ] `model-registry.yaml` schema v1 — реализована загрузка + fail-closed + version_pin.
- [ ] Интерфейс драйвера — env-контракт зафиксирован, kimi/claude драйверы пишут только транспорт.
- [ ] Role-result contracts — verifier-вердикт парсится, прочие режимы свободны.
- [ ] Exit-контракт v1 — все коды 0–9, backport кода 9 в DP.SC.163.
- [ ] Все 9 поверхностей §Б — митигация + проходящий failure-test.
- [ ] Audit-envelope v1 — только метаданные, attribution от ядра, без payload.
- [ ] Обратная совместимость — старые адаптеры = wrapper'ы, скиллы не сломаны.
- [ ] Smoke + failure-test matrix зелёные.
- [ ] OwnerIntegrity: `DP.ROLE.060` зарегистрирован в `02-domain-entities/02A-roles.md`; backport exit-9 в DP.SC.163.

</details>
