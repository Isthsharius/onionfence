# Прозрачная маршрутизация всего трафика через Tor (nftables).
# Использование: torproxy [on | off | status | newip | country [код] | bridges [режим] | log | help]
# Без аргументов — интерактивное меню.
#
# Copyright (C) 2026 Isthsharius
# SPDX-License-Identifier: GPL-3.0-or-later
# Это свободная программа: её можно распространять и изменять на условиях
# GNU General Public License версии 3 или (по вашему выбору) любой более поздней.
# Распространяется БЕЗ КАКИХ-ЛИБО ГАРАНТИЙ. Подробности — в файле LICENSE.

set -g __torproxy_torrc /etc/tor/torrc
set -g __torproxy_begin '# --- torproxy transparent ---'
set -g __torproxy_end '# --- torproxy end ---'
set -g __torproxy_table torproxy
set -g __torproxy_timeout 90
set -g __torproxy_transport 9040
set -g __torproxy_dnsport 9053 # не 5353: его занимает mDNS systemd-resolved
set -g __torproxy_ctlport 9051
set -g __torproxy_version 0.2.0
set -g __torproxy_socksport 9050 # SocksPort по умолчанию: его не задаём, в Debian он в tor-service-defaults-torrc
set -g __torproxy_boot_unit torproxy-boot
set -g __torproxy_etc /etc/torproxy
set -g __torproxy_systemd_dir /etc/systemd/system
set -g __torproxy_leak_wait 6

# Различия дистрибутивов. Debian/Ubuntu: настоящая служба — tor@default
# (tor.service там пустышка ExecStart=/bin/true), пользователь debian-tor,
# cookie в /run/tor. Аргумент root — префикс путей, нужен только тестам.
function __torproxy_detect --argument-names root
    if test -e "$root/usr/lib/systemd/system/tor@default.service"; or test -e "$root/lib/systemd/system/tor@default.service"
        set -g __torproxy_platform debian
        set -g __torproxy_unit tor@default
        set -g __torproxy_cookie /run/tor/control.authcookie
    else
        set -g __torproxy_platform arch
        set -g __torproxy_unit tor
        set -g __torproxy_cookie /var/lib/tor/control_auth_cookie
    end
    set -g __torproxy_user
    for u in tor debian-tor _tor
        if getent passwd $u >/dev/null
            set -g __torproxy_user $u
            break
        end
    end
end
__torproxy_detect

# Встроенные мосты Tor Browser
# (tor-browser-build: projects/tor-expert-bundle/pt_config.json, ноябрь 2026)
set -g __torproxy_builtin_snowflake \
    'snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn' \
    'snowflake 192.0.2.4:80 8838024498816A039FCBBAB14E6F40A0843051FA fingerprint=8838024498816A039FCBBAB14E6F40A0843051FA url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn'
set -g __torproxy_builtin_obfs4 \
    'obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMrr1BRiAW8IE9U5z27fQaYgOhX1UCmOpg2pFpoMvo6ZgQMzLsaTzzQNTlm7hNcb+Sg iat-mode=0' \
    'obfs4 209.148.46.65:443 74FAD13168806246602538555B5521A0383A1875 cert=ssH+9rP8dG2NLDN2XuFw63hIO/9MNNinLmxQDpVa+7kTOa9/m+tGWT1SmSYpQ9uTBGa6Hw iat-mode=0' \
    'obfs4 146.57.248.225:22 10A6CD36A537FCE513A322361547444B393989F0 cert=K1gDtDAIcUfeLqbstggjIw2rtgIKqdIhUlHp82XRqNSq/mtAjp1BIC9vHKJ2FAEpGssTPw iat-mode=0' \
    'obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMPW3vJxICfkMZNdkRrb63Zhl5j9dW3iRGiCx0A7mPhe5T2EDzQ35+Zw iat-mode=0' \
    'obfs4 51.222.13.177:80 5EDAC3B810E12B01F6FD8050D2FD3E277B289A08 cert=2uplIpLQ0q9+0qMFrK5pkaYRDOe460LL9WHBvatgkuRr/SL31wBOEupaMMJ6koRE6Ld0ew iat-mode=0' \
    'obfs4 212.83.43.95:443 BFE712113A72899AD685764B211FACD30FF52C31 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=1' \
    'obfs4 212.83.43.74:443 39562501228A4D5E27FCA4C0C81A01EE23AE3EE4 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=1'

function torproxy --description 'Весь трафик через Tor: меню / on / off / status / newip / country / log'
    switch "$argv[1]"
        case ''
            __torproxy_menu
        case on
            __torproxy_on $argv[2..]
        case off
            __torproxy_off $argv[2..]
        case browser
            __torproxy_browser
        case boot
            __torproxy_boot $argv[2..]
        case hide
            __torproxy_hide $argv[2..]
        case leaktest
            __torproxy_leaktest
        case clean
            __torproxy_clean $argv[2..]
        case status
            __torproxy_status
        case newip
            __torproxy_newip
        case country
            __torproxy_country $argv[2]
        case bridges
            __torproxy_bridges $argv[2..]
        case log
            sudo journalctl -fu $__torproxy_unit
        case version --version
            echo "torproxy $__torproxy_version ($__torproxy_platform: служба $__torproxy_unit, пользователь $__torproxy_user)"
        case help -h --help
            __torproxy_help
        case '*'
            __torproxy_help
            return 1
    end
end

# ---------- оформление ----------

# Аналог bash `set -o pipefail` (в fish его нет): вызывать как `__torproxy_pipefail $pipestatus`
# сразу после конвейера. Возвращает код первого упавшего звена, а не только последнего.
function __torproxy_pipefail
    for code in $argv
        test $code -ne 0; and return $code
    end
    return 0
end

function __torproxy_say --argument-names color text
    echo "$(set_color $color)  $text$(set_color normal)"
end

function __torproxy_banner
    set_color magenta --bold
    echo '   ╭──────────────────────────────╮'
    echo '   │      🧅  T O R   P R O X Y     │'
    echo '   ╰──────────────────────────────╯'
    set_color normal
end

function __torproxy_bar --argument-names pct
    set -l w 30
    set -l n (math "floor($pct * $w / 100)")
    printf '\r  %s%s%s%s%s %3d%%' "$(set_color magenta)" "$(string repeat -n $n █)" \
        "$(set_color brblack)" "$(string repeat -n (math $w - $n) ░)" "$(set_color normal)" $pct
end

function __torproxy_row --argument-names label value
    printf '  %s│%s %-16s %s\n' "$(set_color magenta)" "$(set_color normal)" $label $value
end

function __torproxy_help
    __torproxy_banner
    echo
    echo "  $(set_color --bold)torproxy$(set_color normal)                 интерактивное меню"
    echo "  $(set_color --bold)torproxy on$(set_color normal)              включить: весь трафик через Tor (--strict: и без доступа к локальной сети)"
    echo "  $(set_color --bold)torproxy off$(set_color normal)             выключить: обычный интернет (-y: без вопроса)"
    echo "  $(set_color --bold)torproxy status$(set_color normal)          статус, внешний IP и страна"
    echo "  $(set_color --bold)torproxy leaktest$(set_color normal)        проверка утечек: IP, DNS, UDP, IPv6, ICMP"
    echo "  $(set_color --bold)torproxy browser$(set_color normal)         Tor Browser через системный Tor"
    echo "  $(set_color --bold)torproxy boot$(set_color normal)            защита с момента загрузки: on [--strict] | off"
    echo "  $(set_color --bold)torproxy hide$(set_color normal)            случайный MAC и скрытие имени компьютера: on | off"
    echo "  $(set_color --bold)torproxy clean файл$(set_color normal)      убрать метаданные из файлов (mat2)"
    echo "  $(set_color --bold)torproxy newip$(set_color normal)           новая цепочка Tor (новый IP)"
    echo "  $(set_color --bold)torproxy country de$(set_color normal)      страна выхода (de, nl, us…); 'any' — любая"
    echo "  $(set_color --bold)torproxy bridges$(set_color normal)         мосты: snowflake | obfs4 | add | off"
    echo "  $(set_color --bold)torproxy log$(set_color normal)             журнал Tor в реальном времени"
    echo "  $(set_color --bold)torproxy version$(set_color normal)         версия и платформа (Arch / Debian, Ubuntu)"
end

# ---------- torrc ----------

# Наш блок в torrc между маркерами begin/end. Переписывается целиком при каждом вызове,
# чтобы исправления портов доходили до старых установок.
# Без опций страна и мосты сохраняются; --country КОД|any, --bridge СТРОКА (можно несколько), --no-bridges.
function __torproxy_torrc
    argparse 'country=' 'bridge=+' no-bridges -- $argv; or return 1
    set -l torrc $__torproxy_torrc
    set -l country (__torproxy_exit_country)
    set -q _flag_country; and set country $_flag_country
    set -l bridges (__torproxy_bridges_current)
    set -q _flag_no_bridges; and set bridges
    set -q _flag_bridge; and set bridges $_flag_bridge

    # каждому типу мостов нужна программа-транспорт; проверяем до того, как трогать torrc
    set -l bridge_lines
    if set -q bridges[1]
        set bridge_lines 'UseBridges 1'
        for tr in (string match -rg '^([a-z0-9_]+) ' -- $bridges | sort -u)
            set -l bin (__torproxy_pt_binary $tr)
            if test -z "$bin"
                __torproxy_say red "✘ Для мостов $tr нет программы-транспорта: "(__torproxy_pt_hint $tr)
                return 1
            end
            set -a bridge_lines "ClientTransportPlugin $tr exec $bin"
        end
        set -a bridge_lines (string replace -r '^' 'Bridge ' -- $bridges)
    end

    test -e $torrc.bak-torproxy; or sudo cp $torrc $torrc.bak-torproxy
    if sudo grep -qxF -- $__torproxy_end $torrc
        sudo sed -i "/^$__torproxy_begin\$/,/^$__torproxy_end\$/d" $torrc
    else if sudo grep -qxF -- $__torproxy_begin $torrc
        # первая версия блока: без end-маркера, 4 строки
        sudo sed -i "/^$__torproxy_begin\$/,+4d" $torrc
    end

    set -l exit_lines
    if not contains -- $country any любая
        set exit_lines "ExitNodes {$country}" 'StrictNodes 1'
    end
    printf '%s\n' \
        $__torproxy_begin \
        'VirtualAddrNetworkIPv4 10.192.0.0/10' \
        'AutomapHostsOnResolve 1' \
        "TransPort 127.0.0.1:$__torproxy_transport IsolateClientAddr IsolateClientProtocol IsolateDestAddr IsolateDestPort" \
        "DNSPort 127.0.0.1:$__torproxy_dnsport" \
        "ControlPort 127.0.0.1:$__torproxy_ctlport" \
        'CookieAuthentication 1' \
        $exit_lines \
        $bridge_lines \
        $__torproxy_end \
        | sudo tee -a $torrc >/dev/null
    __torproxy_pipefail $pipestatus; or begin
        __torproxy_say red "✘ Не удалось записать настройки в $torrc"
        return 1
    end
end

function __torproxy_exit_country
    set -l c (sudo sed -n "/^$__torproxy_begin\$/,/^$__torproxy_end\$/s/^ExitNodes {\(.*\)}/\1/p" $__torproxy_torrc)
    test -n "$c"; and echo $c; or echo любая
end

# Строки мостов из нашего блока (без слова Bridge)
function __torproxy_bridges_current
    sudo sed -n "/^$__torproxy_begin\$/,/^$__torproxy_end\$/s/^Bridge //p" $__torproxy_torrc
end

# Кратко для статуса: «нет» или «snowflake ×2, obfs4 ×1»
function __torproxy_bridges_summary
    set -l bridges (__torproxy_bridges_current)
    if not set -q bridges[1]
        echo нет
        return
    end
    set -l types
    for b in $bridges
        set -l t (string match -rg '^([a-z0-9_]+) ' -- $b); or set t обычные
        set -a types $t
    end
    for t in (printf '%s\n' $types | sort -u)
        echo "$t ×"(count (string match -- $t $types))
    end | string join ', '
end

# Путь к программе-транспорту. lyrebird умеет obfs4, webtunnel, meek_lite и snowflake;
# obfs4proxy — только obfs4 и meek_lite. На Debian/Ubuntu AppArmor разрешает Tor
# запускать obfs4proxy и snowflake-client, но не lyrebird, поэтому они там первые.
function __torproxy_pt_binary --argument-names transport
    set -l candidates
    switch $transport
        case obfs4 meek_lite
            set candidates lyrebird obfs4proxy
        case webtunnel
            set candidates lyrebird webtunnel-client
        case snowflake
            set candidates lyrebird snowflake-client
        case conjure
            set candidates conjure-client
    end
    test "$__torproxy_platform" = debian; and set candidates $candidates[-1..1]
    for c in $candidates
        command -s $c; and return
    end
    return 1
end

# Как установить транспорт для мостов этого типа
function __torproxy_pt_hint --argument-names transport
    if test "$__torproxy_platform" = debian
        switch $transport
            case obfs4 meek_lite
                echo "sudo apt install obfs4proxy"
            case snowflake
                echo "sudo apt install snowflake-client"
            case '*'
                echo "в стабильных Debian/Ubuntu пакета для $transport нет, используйте obfs4 или snowflake"
        end
    else
        echo "paru -S lyrebird-proxy"
    end
end

# Строка моста: [транспорт] IP:порт [параметры]; префикс «Bridge » допускается
function __torproxy_bridge_normalize --argument-names line
    set line (string trim -- $line | string replace -r '^Bridge\s+' '' | string replace -ra '\s+' ' ')
    string match -qr '^([a-z0-9_]+ )?(\d{1,3}(\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]):\d{1,5}( [^ #]+)*$' -- $line
    or return 1
    echo $line
end

# ---------- команды ----------

# Правила nftables: весь TCP -> TransPort, DNS -> DNSPort, остальное блокируется.
# Аргумент strict: локальная сеть тоже закрыта, кроме DHCP.
function __torproxy_rules --argument-names mode
    set -l tor_uid (id -u $__torproxy_user)
    set -l lan '{ 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }'
    set -l direct $lan
    set -l lo_rule 'oifname lo accept'
    set -l lan_rule "ip daddr $lan accept"
    if test "$mode" = strict
        set direct 127.0.0.0/8
        set lo_rule 'oifname lo accept comment "torproxy-strict"'
        # после redirect файрвол ещё видит прежний интерфейс, поэтому одного oifname lo мало
        set lan_rule "ip daddr $direct accept"
    end
    echo "
table inet $__torproxy_table {
    chain nat_out {
        type nat hook output priority -100; policy accept;
        meta skuid $tor_uid return
        meta nfproto ipv4 udp dport 53 redirect to :$__torproxy_dnsport
        meta nfproto ipv4 tcp dport 53 redirect to :$__torproxy_transport
        meta nfproto ipv4 ip daddr 10.192.0.0/10 meta l4proto tcp redirect to :$__torproxy_transport
        ip daddr $direct return
        meta nfproto ipv4 meta l4proto tcp redirect to :$__torproxy_transport
    }
    chain filter_out {
        type filter hook output priority 0; policy drop;
        meta skuid $tor_uid accept
        $lo_rule
        $lan_rule
        udp sport 68 udp dport 67 accept
        # established не разрешаем: соединения, открытые до включения, не должны идти мимо Tor
        # всё прочее (UDP, ICMP, IPv6) — drop, чтобы не было утечек мимо Tor
    }
}"
end

function __torproxy_is_strict
    sudo nft list table inet $__torproxy_table 2>/dev/null | string match -q '*torproxy-strict*'
end

function __torproxy_on
    argparse strict -- $argv; or return 1
    set -l mode
    set -q _flag_strict; and set mode strict
    __torproxy_banner
    if test -z "$__torproxy_user"
        __torproxy_say red "✘ Tor не установлен (нет пользователя tor/debian-tor): sudo pacman -S tor или sudo apt install tor"
        return 1
    end
    __torproxy_torrc; or return 1

    # через мосты (особенно snowflake) Tor подключается заметно дольше
    set -l timeout $__torproxy_timeout
    set -l bridges (__torproxy_bridges_current)
    set -q bridges[1]; and set timeout (math $timeout x 2)

    set -l started (date '+%Y-%m-%d %H:%M:%S')
    sudo systemctl restart $__torproxy_unit; or begin
        __torproxy_on_failed "Tor не запустился"
        return 1
    end
    echo "  Подключение к сети Tor..."
    set -l pct 0
    for i in (seq $timeout)
        set -l p (sudo journalctl -u $__torproxy_unit --since "$started" --no-pager -q | string match -rg 'Bootstrapped (\d+)%' | tail -1)
        # string match без совпадений (Tor ещё не начал) — не ошибка, поэтому проверяем только journalctl
        if test $pipestatus[1] -ne 0
            __torproxy_on_failed "Не удалось прочитать журнал Tor"
            return 1
        end
        test -n "$p"; and set pct $p
        __torproxy_bar $pct
        test $pct -eq 100; and break
        sleep 1
    end
    echo
    if test $pct -ne 100
        __torproxy_on_failed "Tor не подключился за $timeout секунд"
        return 1
    end

    sudo nft delete table inet $__torproxy_table 2>/dev/null
    __torproxy_rules $mode | sudo nft -f -; or begin
        __torproxy_say red "✘ Ошибка применения правил nftables"
        return 1
    end
    resolvectl flush-caches 2>/dev/null

    __torproxy_say green "✔ Tor-режим ВКЛЮЧЁН. Перезапусти браузер и программы, открытые до включения."
    __torproxy_status
end

# Tor не поднялся. Если режим уже был включён, правила остаются: интернет закрыт, но без утечек.
function __torproxy_on_failed --argument-names reason
    echo
    sudo systemctl stop $__torproxy_unit
    if sudo nft list table inet $__torproxy_table >/dev/null 2>&1
        __torproxy_say red "✘ $reason. Tor-режим остаётся включённым, поэтому интернет закрыт (torproxy off — вернуть обычный)"
    else
        __torproxy_say red "✘ $reason, правила НЕ применены (torproxy log)"
    end
end

# Имена программ с соединениями наружу (свои процессы: чужие ss без root не называет).
# В Tor-режиме все такие соединения идут через Tor.
function __torproxy_online_apps
    for line in (ss -Htnp state established 2>/dev/null)
        set -l peer (string split -n ' ' -- $line)[4]
        string match -qr '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|\[::1\]|\[::ffff:127\.|\[fe80)' -- $peer; and continue
        string match -rg 'users:\(\("([^"]+)"' -- $line
    end | sort -u | string match -v -r '^(tor|lyrebird|obfs4proxy|snowflake-client)$'
end

function __torproxy_off
    argparse y/yes -- $argv; or return 1
    # Программа, которая переживёт выключение, продолжит ту же сессию уже с настоящего IP
    # и свяжет его с Tor. Поэтому предупреждаем до снятия правил, а не после.
    if sudo nft list table inet $__torproxy_table >/dev/null 2>&1
        set -l apps (__torproxy_online_apps)
        if set -q apps[1]
            __torproxy_say yellow "⚠ Через Tor сейчас работают: "(string join ', ' -- $apps)
            echo "  Останутся открытыми — продолжат те же сессии (куки, аккаунты) уже с настоящего IP"
            echo "  и свяжут его с тем, что ты делал через Tor. Лучше закрыть их до выключения."
            if not set -q _flag_yes; and isatty stdin
                read -P '  Выключить всё равно? [y/N] ' -l answer
                if not string match -qri '^[yд]' -- "$answer"
                    __torproxy_say yellow "Отменено, Tor-режим остаётся включённым"
                    return 1
                end
            end
        end
    end
    sudo nft delete table inet $__torproxy_table 2>/dev/null
    sudo systemctl stop $__torproxy_unit
    resolvectl flush-caches 2>/dev/null
    __torproxy_say yellow "● Tor-режим ВЫКЛЮЧЕН, обычный интернет восстановлен."
    if systemctl -q is-enabled $__torproxy_boot_unit 2>/dev/null
        __torproxy_say yellow "  При следующей загрузке режим включится снова (torproxy boot off — отключить)"
    end
end

# ---------- анонимность ----------

# Tor Browser через системный Tor: свой Tor он не запускает, иначе трафик шёл бы через Tor дважды.
function __torproxy_browser_binary
    command -s tor-browser; and return
    for f in $HOME/.local/share/torbrowser/tbb/*/tor-browser*/Browser/start-tor-browser $HOME/tor-browser*/Browser/start-tor-browser
        if test -x $f
            echo $f
            return
        end
    end
    # при первом запуске скачает и проверит Tor Browser
    command -s torbrowser-launcher
end

function __torproxy_browser
    if not systemctl -q is-active $__torproxy_unit
        __torproxy_say red "✘ Tor не запущен (torproxy on)"
        return 1
    end
    set -l bin (__torproxy_browser_binary)
    if test -z "$bin"
        set -l pm "sudo pacman -S"
        test "$__torproxy_platform" = debian; and set pm "sudo apt install"
        __torproxy_say red "✘ Tor Browser не найден: $pm torbrowser-launcher"
        return 1
    end
    env TOR_SKIP_LAUNCH=1 TOR_PROVIDER=none TOR_SOCKS_HOST=127.0.0.1 TOR_SOCKS_PORT=$__torproxy_socksport \
        setsid -f $bin </dev/null >/dev/null 2>&1
    or begin
        __torproxy_say red "✘ Не удалось запустить $bin"
        return 1
    end
    __torproxy_say green "✔ Tor Browser запускается через системный Tor (порт $__torproxy_socksport)"
end

# Служба загружает правила раньше сети. Как и у nftables.service: DefaultDependencies=no и
# sysinit.target. After=nftables.service — его «flush ruleset» иначе стёр бы нашу таблицу.
function __torproxy_boot_unit_text
    set -l nft (command -s nft; or echo /usr/bin/nft)
    printf '%s\n' \
        '[Unit]' \
        'Description=torproxy: block traffic outside Tor from early boot' \
        'DefaultDependencies=no' \
        'After=local-fs.target nftables.service' \
        'Before=network-pre.target shutdown.target' \
        'Wants=network-pre.target' \
        'Conflicts=shutdown.target' \
        '' \
        '[Service]' \
        'Type=oneshot' \
        'RemainAfterExit=yes' \
        "ExecStartPre=-$nft delete table inet $__torproxy_table" \
        "ExecStart=$nft -f $__torproxy_etc/rules.nft" \
        '' \
        '[Install]' \
        'WantedBy=sysinit.target'
end

# torproxy boot [on [--strict] | off]
function __torproxy_boot --argument-names action
    set -l service $__torproxy_systemd_dir/$__torproxy_boot_unit.service
    switch "$action"
        case ''
            if systemctl -q is-enabled $__torproxy_boot_unit 2>/dev/null
                __torproxy_say green "Защита при загрузке включена"
            else
                __torproxy_say yellow "Защита при загрузке выключена"
            end
            echo "  torproxy boot on [--strict]   с момента загрузки весь трафик только через Tor"
            echo "  torproxy boot off             обычная загрузка"
        case on
            argparse strict -- $argv[2..]; or return 1
            set -l mode
            set -q _flag_strict; and set mode strict
            if test -z "$__torproxy_user"
                __torproxy_say red "✘ Tor не установлен"
                return 1
            end
            __torproxy_torrc; or return 1
            sudo mkdir -p $__torproxy_etc; or return 1
            __torproxy_rules $mode | sudo tee $__torproxy_etc/rules.nft >/dev/null
            __torproxy_pipefail $pipestatus; or begin
                __torproxy_say red "✘ Не удалось записать $__torproxy_etc/rules.nft"
                return 1
            end
            # ошибка в правилах при загрузке оставила бы систему без защиты: проверяем сейчас
            if not sudo nft -c -f $__torproxy_etc/rules.nft
                __torproxy_say red "✘ nftables не принял правила, защита не включена"
                return 1
            end
            # запоминаем, включал ли Tor сам пользователь, чтобы off вернул всё как было.
            # Только при первом on: при повторном Tor уже включён нами.
            if not test -e $service; and systemctl -q is-enabled $__torproxy_unit 2>/dev/null
                sudo touch $__torproxy_etc/tor-was-enabled
            end
            __torproxy_boot_unit_text | sudo tee $service >/dev/null
            __torproxy_pipefail $pipestatus; or begin
                __torproxy_say red "✘ Не удалось записать $service"
                return 1
            end
            sudo systemctl daemon-reload
            sudo systemctl enable $__torproxy_boot_unit $__torproxy_unit; or begin
                __torproxy_say red "✘ Не удалось включить службы"
                return 1
            end
            __torproxy_say green "✔ Защита включится со следующей загрузки"
            echo "  Если Tor при загрузке не подключится, интернета не будет: torproxy off вернёт его."
        case off
            # защита не включалась: автозапуск Tor настроен не нами, его не трогаем
            if not test -e $service
                __torproxy_say yellow "Защита при загрузке и так выключена"
                return 0
            end
            sudo systemctl disable $__torproxy_boot_unit 2>/dev/null
            sudo test -e $__torproxy_etc/tor-was-enabled; or sudo systemctl disable $__torproxy_unit
            sudo rm -f $service
            sudo rm -rf $__torproxy_etc
            sudo systemctl daemon-reload
            __torproxy_say yellow "● Защита при загрузке выключена (текущий режим не изменён)"
        case '*'
            __torproxy_say red "✘ Неизвестное действие: $action (on | off)"
            return 1
    end
end

function __torproxy_hide_dir
    if test -n "$XDG_STATE_HOME"
        echo $XDG_STATE_HOME/torproxy/hide
    else
        echo $HOME/.local/state/torproxy/hide
    end
end

# Активные подключения Wi-Fi и Ethernet: «uuid:тип»
function __torproxy_hide_conns
    nmcli -t -f UUID,TYPE connection show --active | string match -r '^.*:(?:802-11-wireless|802-3-ethernet)$'
end

# torproxy hide [on | off]. Меняет профили NetworkManager; прежние значения хранятся в файле,
# чтобы off вернул их точно. Имя компьютера уходит через DHCP, mDNS и LLMNR.
function __torproxy_hide --argument-names action
    set -l dir (__torproxy_hide_dir)
    switch "$action"
        case ''
            if count $dir/* >/dev/null
                __torproxy_say green "Устройство скрыто: случайный MAC, имя компьютера не передаётся"
            else
                __torproxy_say yellow "Скрытие выключено"
            end
            echo "  torproxy hide on    случайный MAC и скрытие имени от локальной сети (сеть переподключится)"
            echo "  torproxy hide off   вернуть как было"
            return
        case on off
            if not type -q nmcli
                __torproxy_say red "✘ Нужен NetworkManager (nmcli)"
                return 1
            end
        case '*'
            __torproxy_say red "✘ Неизвестное действие: $action (on | off)"
            return 1
    end

    if test $action = on
        set -l conns (__torproxy_hide_conns)
        if not set -q conns[1]
            __torproxy_say red "✘ Нет активного подключения Wi-Fi или Ethernet"
            return 1
        end
        mkdir -p $dir; or return 1
        echo "  Сеть переподключится, IP-адрес в локальной сети может смениться."
        for conn in $conns
            set -l parts (string split : -- $conn)
            set -l uuid $parts[1]
            set -l mac_prop $parts[2].cloned-mac-address
            set -l props $mac_prop ipv4.dhcp-send-hostname ipv6.dhcp-send-hostname connection.mdns connection.llmnr
            # значения сохраняем один раз: повторный on не должен затереть настоящие
            if not test -e $dir/$uuid
                for p in $props
                    echo "$p=$(nmcli -g $p connection show $uuid)"
                end >$dir/$uuid
            end
            sudo nmcli connection modify $uuid $mac_prop random ipv4.dhcp-send-hostname no \
                ipv6.dhcp-send-hostname no connection.mdns no connection.llmnr no
            and sudo nmcli connection up $uuid >/dev/null
            or begin
                __torproxy_say red "✘ Не удалось применить настройки (torproxy hide off — вернуть как было)"
                return 1
            end
        end
        __torproxy_say green "✔ MAC случайный, имя компьютера локальной сети не передаётся"
    else
        set -l active (nmcli -t -f UUID connection show --active)
        for f in $dir/*
            set -l uuid (path basename $f)
            set -l args
            for line in (command cat $f)
                set -l kv (string split -m1 = -- $line)
                set -a args $kv[1] "$kv[2]"
            end
            if not sudo nmcli connection modify $uuid $args
                __torproxy_say red "✘ Не удалось вернуть настройки подключения $uuid (сохранены в $f)"
                return 1
            end
            contains -- $uuid $active; and sudo nmcli connection up $uuid >/dev/null
            rm -f $f
        end
        __torproxy_say yellow "● Настройки сети возвращены"
    end
end

# Сколько ждать ответа сайта проверки: через мосты (особенно snowflake) запросы идут намного дольше
function __torproxy_check_timeout
    set -l bridges (__torproxy_bridges_current)
    set -q bridges[1]; and echo 60; or echo 30
end

# Одна строка отчёта leaktest; код возврата — результат проверки
function __torproxy_leak_row --argument-names ok name detail
    if test $ok = 1
        __torproxy_row $name "$(set_color green)✔$(set_color normal) $detail"
    else
        __torproxy_row $name "$(set_color red)✘$(set_color normal) $detail"
        return 1
    end
end

function __torproxy_leaktest
    set -l failed 0
    echo "$(set_color magenta)"'  ╭──────── проверка утечек ─────────'"$(set_color normal)"

    set -l ok 0
    sudo nft list table inet $__torproxy_table >/dev/null 2>&1; and set ok 1
    __torproxy_leak_row $ok "Правила" "таблица nftables"; or set failed (math $failed + 1)

    set ok 0
    systemctl -q is-active $__torproxy_unit; and set ok 1
    __torproxy_leak_row $ok "Служба Tor" $__torproxy_unit; or set failed (math $failed + 1)

    # адрес снаружи видит сам сайт проверки
    set -l check (curl -s --max-time (__torproxy_check_timeout) https://check.torproject.org/api/ip)
    set -l ip (echo $check | jq -r '.IP // "нет ответа"' 2>/dev/null)
    test -n "$ip"; or set ip "нет ответа"
    set ok 0
    test "$(echo $check | jq -r .IsTor 2>/dev/null)" = true; and set ok 1
    __torproxy_leak_row $ok "Внешний IP" $ip; or set failed (math $failed + 1)

    # 192.0.2.1 — адрес из документации, DNS там нет: ответ может прийти только от Tor
    set -l reply (printf '\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01' \
        | socat -t$__torproxy_leak_wait - UDP:192.0.2.1:53 2>/dev/null | od -An -tx1)
    set ok 0
    test -n "$reply"; and set ok 1
    __torproxy_leak_row $ok "DNS" "запросы перехватывает Tor"; or set failed (math $failed + 1)

    # отправка должна упасть: файрвол не выпускает UDP и IPv6 мимо Tor
    set ok 1
    printf x | socat -t0.2 - UDP:198.51.100.1:443 >/dev/null 2>&1; and set ok 0
    __torproxy_leak_row $ok "UDP" "мимо Tor не выходит"; or set failed (math $failed + 1)

    set ok 1
    printf x | socat -t0.2 - 'UDP6:[2001:db8::1]:443' >/dev/null 2>&1; and set ok 0
    __torproxy_leak_row $ok "IPv6" "мимо Tor не выходит"; or set failed (math $failed + 1)

    if command -q ping
        set ok 1
        ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; and set ok 0
        __torproxy_leak_row $ok "ICMP" "ping мимо Tor не выходит"; or set failed (math $failed + 1)
    end

    echo "$(set_color magenta)"'  ╰──────────────────────────────────'"$(set_color normal)"
    if test $failed -eq 0
        __torproxy_say green "✔ Утечек не найдено"
    else
        __torproxy_say red "✘ Проблем: $failed"
        return 1
    end
end

# Убирает метаданные (GPS, автор, модель камеры): рядом появляется файл.cleaned.расширение
function __torproxy_clean
    if not set -q argv[1]
        echo "  torproxy clean файл…   убрать метаданные: рядом появится файл.cleaned.расширение"
        return 1
    end
    if not type -q mat2
        set -l pm "sudo pacman -S"
        test "$__torproxy_platform" = debian; and set pm "sudo apt install"
        __torproxy_say red "✘ Нужна программа mat2: $pm mat2"
        return 1
    end
    set -l failed 0
    for f in $argv
        if not test -f "$f"
            __torproxy_say red "✘ Нет такого файла: $f"
            set failed 1
            continue
        end
        if mat2 -- $f
            __torproxy_say green "✔ "(string replace -r '(\.[^./]+)$' '.cleaned$1' -- $f)
        else
            __torproxy_say red "✘ mat2 не смог обработать: $f"
            set failed 1
        end
    end
    __torproxy_say yellow "  Исходные файлы не тронуты. Текст и лица на самих фото mat2 не убирает."
    test $failed -eq 0
end

# С аргументом --quick не делает сетевых запросов и не спрашивает пароль (для меню)
function __torproxy_status
    # в быстром режиме не спрашиваем пароль, только используем закэшированный sudo
    set -l sudo_opts
    test "$argv[1]" = --quick; and set sudo_opts -n
    set -l rules "$(set_color red)● выключен$(set_color normal)"
    if not sudo $sudo_opts true 2>/dev/null
        set rules "$(set_color yellow)? нужен sudo (выбери «Проверить»)$(set_color normal)"
    else if sudo nft list table inet $__torproxy_table >/dev/null 2>&1
        set rules "$(set_color green)● ВКЛЮЧЁН$(set_color normal)"
        __torproxy_is_strict; and set rules "$(set_color green)● ВКЛЮЧЁН (строгий)$(set_color normal)"
    end

    echo "$(set_color magenta)"'  ╭──────────── статус ─────────────'"$(set_color normal)"
    __torproxy_row "Режим" $rules
    __torproxy_row "Служба Tor" (systemctl is-active $__torproxy_unit)
    __torproxy_row "Страна выхода" (__torproxy_exit_country)
    __torproxy_row "Мосты" (__torproxy_bridges_summary)
    set -l boot выкл
    systemctl -q is-enabled $__torproxy_boot_unit 2>/dev/null; and set boot вкл
    __torproxy_row "При загрузке" $boot
    set -l hide выкл
    count (__torproxy_hide_dir)/* >/dev/null; and set hide вкл
    __torproxy_row "Скрытие" $hide

    if test "$argv[1]" != --quick
        __torproxy_row "Проверка" "$(set_color brblack)запрос к check.torproject.org…$(set_color normal)"
        set -l check (curl -s --max-time (__torproxy_check_timeout) https://check.torproject.org/api/ip)
        set -l ip (echo $check | jq -r '.IP // empty' 2>/dev/null)
        if test -z "$ip"
            __torproxy_row "Внешний IP" "$(set_color red)нет ответа$(set_color normal)"
        else
            # страну спрашиваем у GeoIP самого Tor: ipinfo.io отвечает выходам Tor 403
            set -l geo
            if systemctl -q is-active $__torproxy_unit
                set geo (__torproxy_control "GETINFO ip-to-country/$ip" 2>/dev/null | string match -rg '^250-ip-to-country/.*=(\w+)$' | string upper)
            end
            test -n "$geo"; or set geo (curl -s --max-time 15 https://ipinfo.io/$ip/json | jq -r '[.country, .city] | map(select(. != null)) | join(", ")' 2>/dev/null)
            __torproxy_row "Внешний IP" "$ip $geo"
            if test "$(echo $check | jq -r .IsTor)" = true
                __torproxy_row "Через Tor" "$(set_color green)✔ да$(set_color normal)"
            else
                __torproxy_row "Через Tor" "$(set_color red)✘ нет$(set_color normal)"
            end
        end
    end
    echo "$(set_color magenta)"'  ╰──────────────────────────────────'"$(set_color normal)"
end

# Команды на ControlPort Tor (аутентификация cookie); печатает ответы Tor построчно
function __torproxy_control
    sudo test -e $__torproxy_cookie; or return 2
    set -l cookie (sudo od -An -v -tx1 $__torproxy_cookie | string replace -ra '\s' '' | string join '')
    __torproxy_pipefail $pipestatus; or begin
        echo "не удалось прочитать $__torproxy_cookie" >&2
        return 2
    end
    set -l reply (printf '%s\r\n' "AUTHENTICATE $cookie" $argv QUIT | socat -t2 - TCP:127.0.0.1:$__torproxy_ctlport 2>/dev/null)
    __torproxy_pipefail $pipestatus; or begin
        echo "ControlPort 127.0.0.1:$__torproxy_ctlport не отвечает" >&2
        return 3
    end
    string trim -- $reply
end

function __torproxy_newip
    if not systemctl -q is-active $__torproxy_unit
        __torproxy_say red "✘ Tor не запущен (torproxy on)"
        return 1
    end
    if not sudo test -e $__torproxy_cookie
        __torproxy_say red "✘ Нет ControlPort — выполни torproxy on заново, чтобы обновить настройки Tor"
        return 1
    end
    set -l reply (__torproxy_control 'SIGNAL NEWNYM' 2>&1)
    if test (count (string match '250 OK' -- $reply)) -ge 2
        __torproxy_say green "✔ Новая цепочка запрошена — новые соединения пойдут через другой IP (Tor делает это не чаще раза в 10 секунд)"
    else
        __torproxy_say red "✘ Новый IP не получен: $reply"
        return 1
    end
end

function __torproxy_country --argument-names cc
    if test -z "$cc"
        __torproxy_say yellow "Страна выхода сейчас: "(__torproxy_exit_country)
        echo "  Укажи код: torproxy country de  (или any — любая)"
        return
    end
    set cc (string lower -- $cc)
    if test "$cc" != any; and not string match -qr '^[a-z]{2}$' -- $cc
        __torproxy_say red "✘ Нужен двухбуквенный код страны (de, nl, us, ch…) или any"
        return 1
    end

    __torproxy_torrc --country $cc; or return 1
    __torproxy_say green "✔ Страна выхода: "(__torproxy_exit_country)

    if systemctl -q is-active $__torproxy_unit; and not __torproxy_apply_country $cc
        # без ControlPort: перечитать torrc; старые цепочки доживут до NEWNYM (до 10 секунд)
        sudo systemctl reload $__torproxy_unit
        __torproxy_say yellow "  Tor применит это к новым соединениям в течение ~10 секунд"
    end
end

# Сменить страну в работающем Tor сразу: SETCONF и закрыть цепочки через старую страну.
# CLOSECIRCUIT, в отличие от NEWNYM, не ограничен «раз в 10 секунд».
function __torproxy_apply_country --argument-names cc
    set -l conf 'RESETCONF ExitNodes StrictNodes'
    test $cc != any; and set conf "SETCONF ExitNodes=\"{$cc}\" StrictNodes=1"
    set -l reply (__torproxy_control $conf 'GETINFO circuit-status' 2>/dev/null); or return 1
    # 250 OK на AUTHENTICATE, SETCONF и GETINFO
    test (count (string match '250 OK' -- $reply)) -ge 3; or return 1
    set -l ids (string match -rg '^(\d+) (?:LAUNCHED|BUILT|GUARD_WAIT|EXTENDED) ' -- $reply)
    set -q ids[1]; and __torproxy_control (string replace -r '^' 'CLOSECIRCUIT ' -- $ids) >/dev/null 2>&1
    return 0
end

# torproxy bridges [snowflake | obfs4 | add [СТРОКА…] | off]
function __torproxy_bridges --argument-names mode
    set -l lines
    switch "$mode"
        case ''
            __torproxy_say yellow "Мосты сейчас: "(__torproxy_bridges_summary)
            echo "  torproxy bridges snowflake   встроенные Snowflake — работают почти везде, но медленнее"
            echo "  torproxy bridges obfs4       встроенные obfs4 — быстрые, но их адреса часто блокируют"
            echo "  torproxy bridges add         свои мосты: Telegram @GetBridgesBot или bridges.torproject.org"
            echo "  torproxy bridges off         без мостов"
            return
        case off
            __torproxy_torrc --no-bridges; or return 1
        case snowflake
            set lines $__torproxy_builtin_snowflake
        case obfs4
            set lines $__torproxy_builtin_obfs4
        case add
            set -l input $argv[2..]
            if not set -q input[1]
                echo "  Вставь строки мостов (каждая с новой строки), в конце — пустая строка:"
                while read -P '  мост › ' -l line
                    test -n "$line"; or break
                    set -a input $line
                end
            end
            if not set -q input[1]
                __torproxy_say yellow "Ничего не добавлено"
                return 1
            end
            for line in $input
                set -l b (__torproxy_bridge_normalize $line)
                if test -z "$b"
                    __torproxy_say red "✘ Не похоже на строку моста: $line"
                    return 1
                end
                set -a lines $b
            end
            # свои мосты добавляются к уже настроенным, без повторов
            set lines (printf '%s\n' (__torproxy_bridges_current) $lines | awk '!seen[$0]++')
        case '*'
            __torproxy_say red "✘ Неизвестный режим: $mode (snowflake | obfs4 | add | off)"
            return 1
    end

    if set -q lines[1]
        set -l args
        for b in $lines
            set -a args --bridge $b
        end
        __torproxy_torrc $args; or return 1
    end
    __torproxy_say green "✔ Мосты: "(__torproxy_bridges_summary)

    # смена мостов требует перезапуска Tor; если режим включён — переподключаемся в том же режиме
    if systemctl -q is-active $__torproxy_unit
        set -l opts
        __torproxy_is_strict; and set opts --strict
        __torproxy_on $opts
    end
end

# ---------- меню ----------

function __torproxy_pick --argument-names prompt
    # читает варианты из stdin; fzf, если есть, иначе нумерованный список
    if command -q fzf
        fzf --height=~15 --reverse --border=rounded --prompt="$prompt › " \
            --color='border:magenta,prompt:magenta,pointer:magenta' --no-info
    else
        set -l items (command cat)
        for i in (seq (count $items))
            echo "  $i) $items[$i]" >/dev/tty
        end
        read -P "  $prompt › " -l n </dev/tty
        string match -qr '^\d+$' -- $n; and test $n -ge 1 -a $n -le (count $items); and echo $items[$n]
    end
end

function __torproxy_menu
    while true
        clear
        __torproxy_banner
        __torproxy_status --quick
        echo
        set -l choice (printf '%s\n' \
            '🟢  Включить Tor-режим' \
            '🔒  Включить в строгом режиме (без локальной сети)' \
            '🔴  Выключить Tor-режим' \
            '🔍  Проверить IP и страну' \
            '🛡️  Проверка утечек' \
            '🌐  Запустить Tor Browser' \
            '🔄  Новый IP (новая цепочка)' \
            '🌍  Страна выхода' \
            '🌉  Мосты (обход блокировок Tor)' \
            '🕵️  Скрыть устройство в локальной сети' \
            '🚀  Защита при загрузке' \
            '🧹  Убрать метаданные из файла' \
            '📜  Журнал Tor (q — назад)' \
            '🚪  Выход' | __torproxy_pick 'действие')

        switch "$choice"
            case '*строгом*'
                __torproxy_on --strict
            case '*Включить*'
                __torproxy_on
            case '*Выключить*'
                __torproxy_off
            case '*Проверить*'
                __torproxy_status
            case '*утечек*'
                __torproxy_leaktest
            case '*Tor Browser*'
                __torproxy_browser
            case '*Скрыть*'
                set -l a (printf '%s\n' 'on   Случайный MAC, скрыть имя компьютера' 'off  Вернуть как было' | __torproxy_pick 'скрытие')
                set a (string split -f1 ' ' -- $a)
                test -n "$a"; and __torproxy_hide $a
            case '*загрузке*'
                set -l a (printf '%s\n' 'on   Весь трафик через Tor с момента загрузки' 'off  Обычная загрузка' | __torproxy_pick 'загрузка')
                set a (string split -f1 ' ' -- $a)
                test -n "$a"; and __torproxy_boot $a
            case '*метаданные*'
                read -P '  Путь к файлу: ' -l f
                # read не раскрывает ~, а при перетаскивании файла терминал добавляет кавычки
                set f (string trim -c " '\"" -- $f | string replace -r '^~(?=/|$)' $HOME)
                test -n "$f"; and __torproxy_clean $f
            case '*Новый IP*'
                __torproxy_newip
            case '*Страна*'
                set -l c (printf '%s\n' \
                    'any  Любая (по умолчанию)' 'de   Германия' 'nl   Нидерланды' 'ch   Швейцария' \
                    'se   Швеция' 'fi   Финляндия' 'fr   Франция' 'gb   Великобритания' \
                    'us   США' 'ca   Канада' 'jp   Япония' 'other  Ввести код вручную' \
                    | __torproxy_pick 'страна')
                set c (string split -f1 ' ' -- $c)
                if test "$c" = other
                    read -P '  Код страны (2 буквы): ' c
                end
                test -n "$c"; and __torproxy_country $c
            case '*Мосты*'
                set -l m (printf '%s\n' \
                    'snowflake  Snowflake — встроенные, работают почти везде' \
                    'obfs4      obfs4 — встроенные, быстрые, но часто заблокированы' \
                    'add        Добавить свои (Telegram @GetBridgesBot)' \
                    'off        Без мостов' \
                    | __torproxy_pick 'мосты')
                set m (string split -f1 ' ' -- $m)
                test -n "$m"; and __torproxy_bridges $m
            case '*Журнал*'
                # pager вместо -f: Ctrl+C в fish прервал бы всё меню
                sudo journalctl -u $__torproxy_unit -n 300 -e
                continue
            case '*'
                return
        end
        echo
        read -P "$(set_color brblack)"'  Enter — назад в меню'"$(set_color normal)" -l __pause
    end
end
