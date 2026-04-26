# Capture Detectors

> **Dispatcher:** [../hooks/capture-bus.sh](../hooks/capture-bus.sh)
> **Registry:** [../config/capture-detectors.sh](../config/capture-detectors.sh)

## Контракт интерфейса

Детектор — исполняемый скрипт (shell по умолчанию), который:

1. **Input** — читает JSON из stdin (harness hook input): `tool_name`, `tool_input`, `tool_response`, `cwd`, `session_id`, `hook_event_name`.
2. **Output** — либо пустой stdout (событие не обнаружено), либо ровно одна строка JSON:
  ```json
  {
    "event_type": "agent_incident",
    "payload": { ... },
    "repo_ctx": { "target_repo_hint": "/abs/path" }
  }
  ```
3. **Exit** — `0` всегда (независимо от наличия события). Ненулевой exit = ошибка, dispatcher логирует `detector_error` и продолжает.

## Правила

- **Один детектор = одно событие за вызов.** Нужно больше — либо два детектора, либо второе событие на следующем tool call.
- **`repo_ctx.target_repo_hint` обязателен.** Детектор сам определяет целевой репо (через `tool_input.file_path`, `cwd`, или контекст сессии). Если не может определить однозначно — эмитит пустой stdout, не угадывает. Writer отклонит запись без hint'а (нет fallback).
- **Rule-based по умолчанию.** `cost_class: free` — регексы, string match, конкретные условия. `cost_class: llm` — вызовы LLM-as-judge, отключены по умолчанию.
- **Latency ≤30ms на вызов.** Детектор работает на каждом PostToolUse. Бюджет шины ≤150ms для 4-5 активных детекторов.

## Добавить новый детектор

1. Скопировать `detector_incident.sh` как шаблон.
2. Заменить логику в теле — оставить структуру (input parse → detection → emit/skip).
3. Зарегистрировать в `config/capture-detectors.sh`:
  ```bash
  "NAME|.claude/detectors/detector_NAME.sh|EVENT_TYPE|free|true|PostToolUse,Stop"
  ```
4. `chmod +x` на новый детектор.
5. Если `event_type` новый — добавить routing в `lib/capture_writer.sh` (case-statement) и в spec §4.3.
6. Запустить dry-run (см. ниже) прежде чем enable=true.

## Dry-run

Тест детектора без записи в incident-log:

```bash
echo '{
  "hook_event_name": "PostToolUse",
  "tool_name": "Write",
  "tool_input": {"file_path": "/Users/.../IWE/<governance-repo>/random-file.md"},
  "cwd": "/Users/.../IWE/<governance-repo>"
}' | .claude/detectors/detector_incident.sh
```

Ожидание: stdout содержит JSON event (если матчится) или пусто.

## Отладка

Все срабатывания и ошибки — в `.claude/logs/capture_log.jsonl`:

```bash
tail -f ~/IWE/.claude/logs/capture_log.jsonl | jq .
```

Статусы:
- `fired` — событие записано в целевой репо
- `skip` — детектор отработал, событие не обнаружено
- `detector_error` — детектор упал (exit != 0 или stderr)
- `writer_reject` — writer отклонил запись (target_repo_unresolved, unknown_event_type, …)
