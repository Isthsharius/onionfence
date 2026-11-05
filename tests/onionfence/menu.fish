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
    '🎯  Запустить одну программу через Tor' \
    '🔓  Исключения: мимо Tor' \
    '🧼  Чистый запуск программы' \
    '⏱️  Смена цепочки по таймеру' \
    '🚨  Экстренное отключение' \
    '── Наблюдение ──' \
    '🕐  Сверить часы через Tor' \
    ''

function __onionfence_pick
    echo $PICKS[1]
    set -e PICKS[1]
end
function clear
end
function __onionfence_newip
    echo newip >>$T/menu.calls
end
function __onionfence_rotate
    echo "rotate $argv" >>$T/menu.calls
end
function __onionfence_timesync
    echo timesync >>$T/menu.calls
end
function __onionfence_panic
    echo panic >>$T/menu.calls
end
function __onionfence_country
    echo "country $argv" >>$T/menu.calls
end
function __onionfence_status
    echo "status $argv" >>$T/menu.calls
end
function __onionfence_bridges
    echo "bridges $argv" >>$T/menu.calls
end
function __onionfence_on
    echo "on $argv" >>$T/menu.calls
end
function __onionfence_leaktest
    echo leaktest >>$T/menu.calls
end
function __onionfence_browser
    echo browser >>$T/menu.calls
end
function __onionfence_hide
    echo "hide $argv" >>$T/menu.calls
end
function __onionfence_boot
    echo "boot $argv" >>$T/menu.calls
end
function __onionfence_clean
    echo "clean $argv" >>$T/menu.calls
end
function __onionfence_exclude
    echo "exclude $argv" >>$T/menu.calls
end
function __onionfence_circuit
    echo circuit >>$T/menu.calls
end
function __onionfence_guide
    echo guide >>$T/menu.calls
end
function __onionfence_doctor
    echo doctor >>$T/menu.calls
end
function __onionfence_run
    echo "run $argv" >>$T/menu.calls
end
function __onionfence_allow
    echo "allow $argv" >>$T/menu.calls
end
function __onionfence_watch
    echo watch >>$T/menu.calls
end
function journalctl
    echo "journal $argv" >>$T/menu.calls
end

# Enter после newip, Enter после nl, код «ch» + Enter, (журнал без Enter), Enter после статуса и мостов
printf '\n\nch\n\n\n\n\n\n\n\n\n\n\'~/ф.jpg\'\n\nru,by\n\n\n\ncurl \'https://a b\'\n\n192.0.2.1\n\nfirefox -x\n\n10m\n\n\n\n' | __onionfence_menu >$T/menu.out 2>&1
t_eq "меню: выход по пустому выбору (Esc)" 0 $status
set -l calls (grep -v -- '--quick' $T/menu.calls | string trim)
t_eq "меню: действия в правильном порядке" \
    "newip|country nl|country ch|journal -u tor -n 300 -e|status|bridges snowflake|on --strict|on|leaktest|browser|hide on|boot off|clean $HOME/ф.jpg|exclude ru,by|circuit|watch|guide|doctor|run curl https://a b|allow|allow 192.0.2.1|run --fresh firefox -x|rotate|rotate 10m|panic|timesync" (string join '|' $calls)
t_eq "меню: перед каждым экраном быстрый статус" 26 (grep -c -- '--quick' $T/menu.calls)
t_eq "меню: приветствие один раз, при запуске" 1 (grep -c 'Весь трафик устройства через TOR' $T/menu.out)
t_eq "меню: приветствие на первом экране" 1 (command head -12 $T/menu.out | grep -c 'Весь трафик устройства через TOR')
t_lacks "меню: нет ошибок read" "read:" (command cat $T/menu.out 2>/dev/null)
