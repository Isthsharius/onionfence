# Проверка меню: выборы подставляются вместо fzf, ввод — из stdin.
source $DIR/lib.fish

set -g PICKS \
    '🔄  Новый IP (новая цепочка)' \
    '🌍  Страна выхода' 'nl   Нидерланды' \
    '🌍  Страна выхода' 'other  Ввести код вручную' \
    '📜  Журнал Tor (q — назад)' \
    '🔍  Проверить IP и страну' \
    '🌉  Мосты (обход блокировок Tor)' 'snowflake  Snowflake — встроенные, работают почти везде' \
    '🔒  Включить в строгом режиме (без локальной сети)' \
    '🟢  Включить Tor-режим' \
    '🛡️  Проверка утечек' \
    '🌐  Запустить Tor Browser' \
    '🕵️  Скрыть устройство в локальной сети' 'on   Случайный MAC, скрыть имя компьютера' \
    '🚀  Защита при загрузке' 'off  Обычная загрузка' \
    '🧹  Убрать метаданные из файла' \
    '🚫  Исключить страны' \
    '🗺️  Схема цепочки' \
    '📊  Живая панель' \
    '📖  Руководство пользователя (q — назад)' \
    '🩺  Найти неполадку' \
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
function __torproxy_on
    echo "on $argv" >>$T/menu.calls
end
function __torproxy_leaktest
    echo leaktest >>$T/menu.calls
end
function __torproxy_browser
    echo browser >>$T/menu.calls
end
function __torproxy_hide
    echo "hide $argv" >>$T/menu.calls
end
function __torproxy_boot
    echo "boot $argv" >>$T/menu.calls
end
function __torproxy_clean
    echo "clean $argv" >>$T/menu.calls
end
function __torproxy_exclude
    echo "exclude $argv" >>$T/menu.calls
end
function __torproxy_circuit
    echo circuit >>$T/menu.calls
end
function __torproxy_guide
    echo guide >>$T/menu.calls
end
function __torproxy_doctor
    echo doctor >>$T/menu.calls
end
function __torproxy_watch
    echo watch >>$T/menu.calls
end
function journalctl
    echo "journal $argv" >>$T/menu.calls
end

# Enter после newip, Enter после nl, код «ch» + Enter, (журнал без Enter), Enter после статуса и мостов
printf '\n\nch\n\n\n\n\n\n\n\n\n\n\'~/ф.jpg\'\n\nru,by\n\n\n\n' | __torproxy_menu >$T/menu.out 2>&1
t_eq "меню: выход по пустому выбору (Esc)" 0 $status
set -l calls (grep -v -- '--quick' $T/menu.calls | string trim)
t_eq "меню: действия в правильном порядке" \
    "newip|country nl|country ch|journal -u tor -n 300 -e|status|bridges snowflake|on --strict|on|leaktest|browser|hide on|boot off|clean $HOME/ф.jpg|exclude ru,by|circuit|watch|guide|doctor" (string join '|' $calls)
t_eq "меню: перед каждым экраном быстрый статус" 19 (grep -c -- '--quick' $T/menu.calls)
t_eq "меню: приветствие один раз, при запуске" 1 (grep -c 'весь трафик через Tor' $T/menu.out)
t_eq "меню: приветствие на первом экране" 1 (command head -12 $T/menu.out | grep -c 'весь трафик через Tor')
t_lacks "меню: нет ошибок read" "read:" (command cat $T/menu.out 2>/dev/null)
