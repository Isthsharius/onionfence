# Проверка меню: выборы подставляются вместо fzf, ввод — из stdin.
source $DIR/lib.fish

set -g PICKS \
    '🔄  Новый IP (новая цепочка)' \
    '🌍  Страна выхода' 'nl   Нидерланды' \
    '🌍  Страна выхода' 'other  Ввести код вручную' \
    '📜  Журнал Tor (q — назад)' \
    '🔍  Проверить IP и страну' \
    '🌉  Мосты (обход блокировок Tor)' 'snowflake  Snowflake — встроенные, работают почти везде' \
    ''

function __torproxy_pick
    echo $PICKS[1]
    set -e PICKS[1]
end
function clear
end
function __torproxy_newip
    echo newip >>$T/menu.calls
end
function __torproxy_country
    echo "country $argv" >>$T/menu.calls
end
function __torproxy_status
    echo "status $argv" >>$T/menu.calls
end
function __torproxy_bridges
    echo "bridges $argv" >>$T/menu.calls
end
function journalctl
    echo "journal $argv" >>$T/menu.calls
end

# Enter после newip, Enter после nl, код «ch» + Enter, (журнал без Enter), Enter после статуса и мостов
printf '\n\nch\n\n\n\n' | __torproxy_menu >$T/menu.out 2>&1
t_eq "меню: выход по пустому выбору (Esc)" 0 $status
set -l calls (grep -v -- '--quick' $T/menu.calls | string trim)
t_eq "меню: действия в правильном порядке" \
    "newip|country nl|country ch|journal -u tor -n 300 -e|status|bridges snowflake" (string join '|' $calls)
t_eq "меню: перед каждым экраном быстрый статус" 7 (grep -c -- '--quick' $T/menu.calls)
t_lacks "меню: нет ошибок read" "read:" (command cat $T/menu.out 2>/dev/null)
