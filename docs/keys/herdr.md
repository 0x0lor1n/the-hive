# herdr: клавиши (тег 2, агенты)

Бинды повторяют tmux на теге 1 (см. [tmux.md](tmux.md)): одна и та же рука
работает в обоих мультиплексорах. Источник истины: `herdrConfig.keys` в
`cells/workstation/home/dev/agents.nix`. foot шлёт `Ctrl+Shift+*` как CSI-u
(`cells/workstation/home/default.nix`), поэтому эти аккорды доходят до herdr.
Полный список активных биндов внутри herdr: `prefix` `?`.

Один агент живёт в одном workspace. Табы не используются.

## Агенты

| Клавиши | Что |
|---|---|
| `Ctrl+Shift+Enter` | новый агент. fuzzel спрашивает тип (hermes / claude / opencode), потом директорию: первая строка = cwd текущего pane, дальше cwd других pane и zoxide. Enter, Enter = такой же агент здесь |
| `Ctrl+Shift+Backspace` | убить агента. fuzzel со списком workspaces и статусом агента: выбрал строку, workspace закрыт. Строка `✕ close N workspaces without an agent` закрывает только workspaces без агента |
| `Ctrl+↑` / `Ctrl+↓` | предыдущий / следующий агент |
| `Shift+Enter` | перенос строки в промпте hermes/claude (через патч `HERDR_ENV` в hermes) |

## Workspaces

| Клавиши | Что |
|---|---|
| `Ctrl+,` / `Ctrl+.` | предыдущий / следующий workspace |
| `Alt+1..9` | перейти к workspace N |
| `Ctrl+Shift+Q` | закрыть текущий workspace (с подтверждением; Esc возвращает туда, откуда вызвал) |
| `prefix` `w` | пикер workspaces (navigate mode, `j`/`k`, Esc выход) |
| `prefix` `g` | goto: поиск по workspaces/агентам |
| `prefix` `Shift+W` | переименовать workspace |

## Panes

| Клавиши | Что |
|---|---|
| `Ctrl+←` / `Ctrl+→` | фокус на pane слева / справа |
| `Ctrl+Shift+W` | закрыть pane |
| `Ctrl+Shift+F` | zoom pane / обратно |
| `Ctrl+Shift+←↑↓→` | resize pane |
| `prefix` `v` / `prefix` `-` | split вправо / вниз |
| `prefix` `[` | copy mode (vi-клавиши, `v` выделение, `y` копировать) |
| `prefix` `e` | открыть scrollback pane в `$EDITOR` |

## Прочее (дефолты herdr)

`prefix` = `Ctrl+Shift+B`, как в tmux.

| Клавиши | Что |
|---|---|
| `prefix` `?` | справка по всем биндам |
| `prefix` `b` | показать / скрыть сайдбар |
| `prefix` `o` | перейти к источнику последнего уведомления |
| `prefix` `Shift+R` | перечитать config.toml |
| `prefix` `q` | detach (агенты продолжают работать в `herdr-server`) |

`Ctrl+N` / `Ctrl+P` здесь не забиндены: внутри агентов это история промпта.

## Сессии

`herdr-server.service` живёт дольше сессии dwl. `~/.config/herdr` в persist,
поэтому после reboot workspaces и имена агентов восстанавливаются, а
hermes/claude/opencode поднимаются через `--resume <id>`. Процессы reboot не
переживают, восстанавливается беседа агента.
