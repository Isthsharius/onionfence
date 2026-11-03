# Общие функции тестов: проверки и заглушки системных команд.
# Ожидает переменные окружения: T (рабочий каталог теста), SRC (путь к torproxy.fish).

source $SRC

# sed, а не string: builtin string внутри функции не читает канал, если у fish нет терминала
function nocolor
    command sed 's/\x1b\[[0-9;]*m//g'
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

function systemctl
    echo "systemctl $argv" >>$T/calls.log
    set -l alive 0
    if test "$LIVE" = 1
        __mock_tor_alive; and set alive 1
    else
        set alive (command cat $T/tor.state 2>/dev/null; or echo 0)
    end
    switch "$argv"
        case '-q is-active tor'
            test $alive = 1
        case 'is-active tor'
            if test $alive = 1
                echo active
            else
                echo inactive
                return 3
            end
        case 'restart tor'
            test "$MOCK_RESTART_FAIL" = 1; and return 1
            if test "$LIVE" = 1
                __mock_tor_alive; and kill (command cat $T/tor.pid)
                rm -f $T/tor.log
                # вывод отвязан, иначе (torproxy on | …) ждёт закрытия канала фоновым Tor
                tor -f $__torproxy_torrc --quiet </dev/null >/dev/null 2>&1 &
                echo $last_pid >$T/tor.pid
                disown
            else
                echo 1 >$T/tor.state
            end
        case 'stop tor'
            if test "$LIVE" = 1
                __mock_tor_alive; and kill (command cat $T/tor.pid)
                rm -f $T/tor.pid
            else
                echo 0 >$T/tor.state
            end
        case 'reload tor'
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
        if contains -- -f $argv
            command cat >$T/ruleset.nft
            test "$MOCK_NFT_FAIL" != 1
            return
        end
        test "$MOCK_RULES" = 1
    end
end
