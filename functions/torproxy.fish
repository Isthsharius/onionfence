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
set -g __torproxy_version 0.1.0

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
            __torproxy_on
        case off
            __torproxy_off
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
    echo "  $(set_color --bold)torproxy on$(set_color normal)              включить: весь трафик через Tor"
    echo "  $(set_color --bold)torproxy off$(set_color normal)             выключить: обычный интернет"
    echo "  $(set_color --bold)torproxy status$(set_color normal)          статус, внешний IP и страна"
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

function __torproxy_on
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

    # Весь TCP -> TransPort, DNS -> DNSPort, остальное блокируется
    set -l tor_uid (id -u $__torproxy_user)
    set -l lan '{ 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }'
    sudo nft delete table inet $__torproxy_table 2>/dev/null
    echo "
table inet $__torproxy_table {
    chain nat_out {
        type nat hook output priority -100; policy accept;
        meta skuid $tor_uid return
        meta nfproto ipv4 udp dport 53 redirect to :$__torproxy_dnsport
        meta nfproto ipv4 tcp dport 53 redirect to :$__torproxy_transport
        meta nfproto ipv4 ip daddr 10.192.0.0/10 meta l4proto tcp redirect to :$__torproxy_transport
        ip daddr $lan return
        meta nfproto ipv4 meta l4proto tcp redirect to :$__torproxy_transport
    }
    chain filter_out {
        type filter hook output priority 0; policy drop;
        meta skuid $tor_uid accept
        oifname lo accept
        ip daddr $lan accept
        udp sport 68 udp dport 67 accept
        # established не разрешаем: соединения, открытые до включения, не должны идти мимо Tor
        # всё прочее (UDP, ICMP, IPv6) — drop, чтобы не было утечек мимо Tor
    }
}" | sudo nft -f -; or begin
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

function __torproxy_off
    sudo nft delete table inet $__torproxy_table 2>/dev/null
    sudo systemctl stop $__torproxy_unit
    resolvectl flush-caches 2>/dev/null
    __torproxy_say yellow "● Tor-режим ВЫКЛЮЧЕН, обычный интернет восстановлен."
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
    end

    echo "$(set_color magenta)"'  ╭──────────── статус ─────────────'"$(set_color normal)"
    __torproxy_row "Режим" $rules
    __torproxy_row "Служба Tor" (systemctl is-active $__torproxy_unit)
    __torproxy_row "Страна выхода" (__torproxy_exit_country)
    __torproxy_row "Мосты" (__torproxy_bridges_summary)

    if test "$argv[1]" != --quick
        __torproxy_row "Проверка" "$(set_color brblack)запрос к check.torproject.org…$(set_color normal)"
        set -l check (curl -s --max-time 20 https://check.torproject.org/api/ip)
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

    # смена мостов требует перезапуска Tor; если режим включён — переподключаемся
    if systemctl -q is-active $__torproxy_unit
        __torproxy_on
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
            '🔴  Выключить Tor-режим' \
            '🔍  Проверить IP и страну' \
            '🔄  Новый IP (новая цепочка)' \
            '🌍  Страна выхода' \
            '🌉  Мосты (обход блокировок Tor)' \
            '📜  Журнал Tor (q — назад)' \
            '🚪  Выход' | __torproxy_pick 'действие')

        switch "$choice"
            case '*Включить*'
                __torproxy_on
            case '*Выключить*'
                __torproxy_off
            case '*Проверить*'
                __torproxy_status
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
