# tmux: клавиши (тег 1)

Источник истины: `dotfiles/tmux/config.conf` (live-симлинк из
`cells/deck/homeModules/tmux.nix`). `prefix` = `Ctrl+Shift+B`. Почти всё
висит без prefix. Mouse выключен, copy mode на vi-клавишах.

## Panes

| Клавиши | Что |
|---|---|
| `Ctrl+Shift+Enter` | новый pane в cwd текущего (то же, что `Super+Shift+Enter`) |
| `Ctrl+Shift+W` | закрыть pane |
| `Ctrl+←↑↓→` | фокус на pane в этом направлении |
| `Ctrl+N` / `Ctrl+P` | следующий / предыдущий pane (в vim/fzf/sk уходит в программу) |
| `Ctrl+Shift+N` / `Ctrl+Shift+P` | поменять pane со следующим / предыдущим |
| `Ctrl+Enter` | поменять pane с master (верхний левый) |
| `Ctrl+Shift+←↑↓→` | resize на 4 клетки |
| `Ctrl+Shift+F` | zoom pane / обратно |
| `Ctrl+Alt+Enter` | вынести pane в отдельное окно |
| `Ctrl+Alt+G` | pane с шеллом через proxychains (промпт `ghost@`) |
| `Ctrl+F4` | показать номера pane |
| `Ctrl+Shift+F4` | номера pane, потом цифра = поменяться с ним |
| `prefix` `p` | fuzzy-выбор pane с превью (sk) |
| `prefix` `y` / `Y` | синхронный ввод во все pane вкл / выкл |

## Окна и сессии

| Клавиши | Что |
|---|---|
| `Ctrl+Shift+T` | новое окно в cwd текущего |
| `Ctrl+Shift+Q` | закрыть окно (спрашивает, если pane больше одного) |
| `Ctrl+,` / `Ctrl+.` | предыдущее / следующее окно |
| `Ctrl+Shift+<` / `Ctrl+Shift+>` | подвинуть окно влево / вправо |
| `Alt+1..9` | перейти к окну N |
| `prefix` `s` | sesh: выбор сессии (`^a` все, `^t` tmux, `^g` конфиги, `^x` zoxide, `^f` поиск, `^d` убить) |
| `prefix` `L` | предыдущая сессия |
| `prefix` `Ctrl+S` / `prefix` `Ctrl+R` | resurrect: сохранить / восстановить вручную (continuum и так сохраняет каждые 15 минут) |

## Лейауты

Дефолт повторяет dwl: широкое окно = main-vertical, портретное = main-horizontal.

| Клавиши | Что |
|---|---|
| `Ctrl+Shift+L`, затем `v` / `h` / `t` / `f` | main-vertical / main-horizontal / tiled / zoom |

## Scrollback и copy

| Клавиши | Что |
|---|---|
| `Ctrl+Shift+PgUp` / `PgDn` | страница истории вверх / вниз (в vim/less уходит в программу) |
| `Ctrl+Shift+Home` / `End` | в начало / конец истории |
| `Ctrl+Shift+K` | очистить экран и историю |
| `v` / `Ctrl+V` / `y` | copy mode: выделение / прямоугольник / скопировать в буфер |
| `Ctrl+Shift+F5` | перечитать tmux.conf |
