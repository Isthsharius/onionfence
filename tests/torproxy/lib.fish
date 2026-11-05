# Общие функции тестов: проверки и заглушки системных команд.
# Ожидает переменные окружения: T (рабочий каталог теста), SRC (путь к torproxy.fish).

source $SRC
set -gx XDG_STATE_HOME $T/state # тесты не должны видеть настоящее состояние `torproxy hide`
# заглушки ниже рассчитаны на раскладку Arch; Debian/Ubuntu проверяются отдельно
set -g __torproxy_platform arch
set -g __torproxy_unit tor
set -g __torproxy_cookie /var/lib/tor/control_auth_cookie
# сторож в тестах не должен трогать настоящие /run и systemd
mkdir -p $T/run-sd
set -g __torproxy_run $T/run
set -g __torproxy_run_systemd $T/run-sd

# sed, а не string: builtin string внутри функции не читает канал, если у fish нет терминала
function nocolor
    # fish 3 на старых терминалах заканчивает цвет ещё и последовательностью ESC ( B
    command sed 's/\x1b\[[0-9;]*m//g; s/\x1b(B//g'
end

function __t_record --argument-names result name detail
    echo "$result $name" >>$T/results
    if test $result = PASS
        echo "$(set_color green)  ✔ $name$(set_color normal)"
    else
        echo "$(set_color red)  ✘ $name$(set_color normal)  $detail"
    end
end

function t_eq --argument-names name expected actual
    if test "$expected" = "$actual"
        __t_record PASS $name
    else
        __t_record FAIL $name "ожидалось «$expected», получено «$actual»"
    end
end

function t_has --argument-names name needle
    set -e argv[1..2]
    if string match -q -- "*$needle*" "$argv"
        __t_record PASS $name
    else
        __t_record FAIL $name "нет «$needle» в «$argv»"
        return 1
    end
end

function t_lacks --argument-names name needle
    set -e argv[1..2]
    if string match -q -- "*$needle*" "$argv"
        __t_record FAIL $name "лишнее «$needle» в «$argv»"
    else
        __t_record PASS $name
    end
end

function section
    echo
    echo "$(set_color --bold blue)■ $argv$(set_color normal)"
end

# ---------- заглушки ----------
# MOCK_SUDO_CACHED=0 — sudo -n «требует пароль»
# MOCK_BOOT          — проценты загрузки Tor, которые «покажет» journalctl
# MOCK_CHECK         — ответ check.torproject.org
# MOCK_NFT=record    — nft только записывает вызовы; иначе настоящий nft
# LIVE=1             — systemctl/journalctl/curl управляют настоящим Tor на тестовых портах

# MOCK_FAIL=tee|od   — эта команда под sudo «падает» (проверка pipefail)
function sudo
    test "$argv[1]" = -v; and return 0
    if test "$argv[1]" = -n
        set -e argv[1]
        test "$MOCK_SUDO_CACHED" = 0; and return 1
    end
    if test "$argv[1]" = "$MOCK_FAIL"
        test "$argv[1]" = tee; and command cat >/dev/null
        return 1
    end
    $argv
end

function __mock_tor_alive
    test -f $T/tor.pid; and kill -0 (command cat $T/tor.pid) 2>/dev/null
end

# Как systemd: ждём, пока Tor завершится. Иначе новый процесс не сможет занять порты
# старого и упадёт ещё до открытия журнала.
function __mock_tor_kill
    __mock_tor_alive; or return 0
    kill (command cat $T/tor.pid)
    for i in (seq 100)
        __mock_tor_alive; or return 0
        sleep 0.1
    end
    kill -9 (command cat $T/tor.pid)
end

function systemctl
    echo "systemctl $argv" >>$T/calls.log
    set -l alive 0
    if test "$LIVE" = 1
        __mock_tor_alive; and set alive 1
    else
        set alive (command cat $T/tor.state 2>/dev/null; or echo 0)
    end
    switch "$argv"
        case "-q is-active $__torproxy_unit"
            test $alive = 1
        case "is-active $__torproxy_unit"
            if test $alive = 1
                echo active
            else
                echo inactive
                return 3
            end
        case "restart $__torproxy_unit"
            test "$MOCK_RESTART_FAIL" = 1; and return 1
            if test "$LIVE" = 1
                __mock_tor_kill
                rm -f $T/tor.log
                # вывод отвязан, иначе (torproxy on | …) ждёт закрытия канала фоновым Tor
                tor -f $__torproxy_torrc --quiet </dev/null >/dev/null 2>&1 &
                echo $last_pid >$T/tor.pid
                disown
            else
                echo 1 >$T/tor.state
            end
        case "stop $__torproxy_unit"
            if test "$LIVE" = 1
                __mock_tor_kill
                rm -f $T/tor.pid
            else
                echo 0 >$T/tor.state
            end
        case "-q is-enabled $__torproxy_boot_unit"
            test -e $T/boot.enabled
        case "-q is-enabled $__torproxy_unit"
            test "$MOCK_TOR_ENABLED" = 1
        case "-q is-active $__torproxy_guard_unit"
            test -e $T/guard.active
        case "start $__torproxy_guard_unit"
            test "$MOCK_GUARD_FAIL" != 1; and touch $T/guard.active
        case "stop $__torproxy_guard_unit"
            rm -f $T/guard.active
        case 'enable *'
            test "$MOCK_ENABLE_FAIL" != 1
        case "reload $__torproxy_unit"
            test "$LIVE" = 1; and kill -HUP (command cat $T/tor.pid)
    end
end

function journalctl
    echo "journalctl $argv" >>$T/calls.log
    test "$MOCK_FAIL" = journalctl; and return 1
    if test "$LIVE" = 1
        command cat $T/tor.log 2>/dev/null
        true # как настоящий journalctl: нет записей — не ошибка
    else
        for p in $MOCK_BOOT
            echo "Tor[1]: Bootstrapped $p% (mock)"
        end
    end
end

function resolvectl
    echo "resolvectl $argv" >>$T/calls.log
end

function curl
    if test "$LIVE" = 1
        command curl --socks5-hostname 127.0.0.1:$LIVE_SOCKS $argv
        return
    end
    switch "$argv"
        case '*check.torproject.org*'
            printf '%s' $MOCK_CHECK
        case '*ipinfo.io*'
            echo '{"country":"DE","city":"Berlin"}'
    end
end

if test "$MOCK_NFT" = record
    function nft
        echo "nft $argv" >>$T/calls.log
        if contains -- -c $argv
            test "$MOCK_NFT_CHECK_FAIL" != 1
            return
        end
        if contains -- -f $argv
            command cat >$T/ruleset.nft
            test "$MOCK_NFT_FAIL" != 1
            return
        end
        test "$MOCK_RULES" = 1
    end
end
