# Прозрачная маршрутизация всего трафика через Tor (nftables).
# Использование: torproxy [команда]. Краткий список: torproxy help, руководство: torproxy guide.
# Без аргументов — интерактивное меню.
#
# Copyright (C) 2026 Isthsharius
# SPDX-License-Identifier: GPL-3.0-or-later
# Это свободная программа: её можно распространять и изменять на условиях
# GNU General Public License версии 3 или (по вашему выбору) любой более поздней.
# Распространяется БЕЗ КАКИХ-ЛИБО ГАРАНТИЙ. Подробности — в файле LICENSE.

# откуда загружен этот файл: нужно команде install
set -g __torproxy_self (path resolve (status filename))
set -g __torproxy_torrc /etc/tor/torrc
set -g __torproxy_begin '# --- torproxy transparent ---'
set -g __torproxy_end '# --- torproxy end ---'
set -g __torproxy_table torproxy
set -g __torproxy_timeout 90
set -g __torproxy_transport 9040
set -g __torproxy_dnsport 9053 # не 5353: его занимает mDNS systemd-resolved
set -g __torproxy_ctlport 9051
set -g __torproxy_version 0.3.0
set -g __torproxy_socksport 9050 # SocksPort по умолчанию: его не задаём, в Debian он в tor-service-defaults-torrc
set -g __torproxy_boot_unit torproxy-boot
set -g __torproxy_etc /etc/torproxy
set -g __torproxy_systemd_dir /etc/systemd/system
set -g __torproxy_leak_wait 6
set -g __torproxy_guard_interval 3
set -g __torproxy_auto_timeout 60 # bridges auto: сколько ждать один способ
set -g __torproxy_guard_unit torproxy-guard
set -g __torproxy_run /run/torproxy
set -g __torproxy_run_systemd /run/systemd/system

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

function torproxy --description 'Весь трафик через Tor: меню и команды (torproxy help)'
    switch "$argv[1]"
        case ''
            __torproxy_menu
        case on
            __torproxy_on $argv[2..]
        case off
            __torproxy_off $argv[2..]
        case browser
            __torproxy_browser
        case run
            __torproxy_run $argv[2..]
        case allow
            __torproxy_allow $argv[2..]
        case boot
            __torproxy_boot $argv[2..]
        case hide
            __torproxy_hide $argv[2..]
        case leaktest
            __torproxy_leaktest
        case doctor
            __torproxy_doctor
        case circuit
            __torproxy_circuit
        case watch
            __torproxy_watch
        case clean
            __torproxy_clean $argv[2..]
        case status
            __torproxy_status
        case newip
            __torproxy_newip
        case country
            __torproxy_country $argv[2]
        case exclude
            __torproxy_exclude $argv[2]
        case bridges
            __torproxy_bridges $argv[2..]
        case log
            sudo journalctl -fu $__torproxy_unit
        case version --version
            echo "torproxy $__torproxy_version ($__torproxy_platform: служба $__torproxy_unit, пользователь $__torproxy_user)"
        case help -h --help
            __torproxy_help
        case guide manual
            __torproxy_guide
        case install
            __torproxy_install
        case uninstall
            __torproxy_uninstall $argv[2..]
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

# Цвет с учётом соглашения NO_COLOR (no-color.org). Своя функция, а не подмена set_color:
# скрипт загружается в сессию пользователя и не должен менять её поведение.
function __torproxy_color
    test -n "$NO_COLOR"; and return 0
    set_color $argv
end

function __torproxy_say --argument-names color text
    echo "$(__torproxy_color $color)  $text$(__torproxy_color normal)"
end

function __torproxy_banner
    __torproxy_color magenta --bold
    echo '   ╭──────────────────────────────╮'
    echo '   │      🧅  T O R   P R O X Y     │'
    echo '   ╰──────────────────────────────╯'
    __torproxy_color normal
end

# Приветствие при запуске меню. В узком окне картинка не поместится: обычный заголовок.
function __torproxy_splash
    # «$(…)» в кавычках: без цвета __torproxy_color пуст, а пустой список стёр бы всю строку
    if set -q COLUMNS; and test "$COLUMNS" -lt 58
        __torproxy_banner
        return
    end
    set -l stem "$(__torproxy_color 7bc96f)"
    set -l skin "$(__torproxy_color --bold c792ea)"
    set -l core "$(__torproxy_color 9d6bd6)"
    set -l name "$(__torproxy_color --bold brwhite)"
    set -l dim "$(__torproxy_color brblack)"
    set -l off "$(__torproxy_color normal)"
    echo
    echo $stem'              )'$off
    echo $stem'             ('$off
    echo $skin'            .-"-.'$off
    echo $skin".'  "$core'|'$skin"  '."$off | string replace -r '^' '          '
    echo $skin'         /   '$core'/|\\'$skin'   \\'$off"       $name"'T O R   P R O X Y'$off
    echo $skin'        |   '$core'| | |'$skin'   |'$off"      $dim"'─────────────────'$off
    echo $skin'        |   '$core'| | |'$skin'   |'$off"      весь трафик через Tor"
    echo $skin'         \\   '$core'\\|/'$skin'   /'$off"       $dim"v$__torproxy_version$off
    echo $skin"          '._"$core'\\|/'$skin"_.'"$off
    echo
end

# Понятное название этапа подключения по метке из журнала Tor
function __torproxy_stage --argument-names tag
    switch "$tag"
        case 'conn_pt' 'conn_done_pt'
            echo "запускаю мост"
        case 'conn_proxy' 'conn_done_proxy' 'conn' 'conn_done'
            echo "соединяюсь с сетью Tor"
        case 'handshake' 'handshake_done' 'onehop_create'
            echo "рукопожатие"
        case 'requesting_status' 'loading_status' 'loading_keys'
            echo "загружаю список узлов"
        case 'requesting_descriptors' 'loading_descriptors' 'enough_dirinfo'
            echo "загружаю данные узлов"
        case 'ap_*'
            echo "соединяюсь с первым узлом"
        case 'circuit_create'
            echo "строю цепочку"
        case 'done'
            echo "готово"
    end
end

function __torproxy_bar --argument-names pct stage
    set -l w 30
    set -l n (math "floor($pct * $w / 100)")
    printf '\r  %s%s%s%s%s %3d%%' "$(__torproxy_color magenta)" "$(string repeat -n $n █)" \
        "$(__torproxy_color brblack)" "$(string repeat -n (math $w - $n) ░)" "$(__torproxy_color normal)" $pct
    # \e[K стирает хвост прошлой, более длинной подписи
    test -n "$stage"; and printf '  %s%s%s\e[K' "$(__torproxy_color brblack)" $stage "$(__torproxy_color normal)"
    return 0
end

function __torproxy_row --argument-names label value
    printf '  %s│%s %-16s %s\n' "$(__torproxy_color magenta)" "$(__torproxy_color normal)" $label $value
end

function __torproxy_help
    __torproxy_banner
    echo
    echo "  $(__torproxy_color --bold)torproxy$(__torproxy_color normal)                 интерактивное меню"
    echo "  $(__torproxy_color --bold)torproxy on$(__torproxy_color normal)              включить: весь трафик через Tor (--strict: и без доступа к локальной сети)"
    echo "  $(__torproxy_color --bold)torproxy off$(__torproxy_color normal)             выключить: обычный интернет (-y: без вопроса)"
    echo "  $(__torproxy_color --bold)torproxy status$(__torproxy_color normal)          статус, внешний IP и страна"
    echo "  $(__torproxy_color --bold)torproxy leaktest$(__torproxy_color normal)        проверка утечек: IP, DNS, UDP, IPv6, ICMP"
    echo "  $(__torproxy_color --bold)torproxy doctor$(__torproxy_color normal)          найти неполадку: зависимости, настройки, порты, часы"
    echo "  $(__torproxy_color --bold)torproxy circuit$(__torproxy_color normal)         схема цепочки: через какие страны идёт трафик"
    echo "  $(__torproxy_color --bold)torproxy watch$(__torproxy_color normal)           живая панель: IP, скорость, цепочка"
    echo "  $(__torproxy_color --bold)torproxy run программа$(__torproxy_color normal)   только эта программа через Tor, остальной трафик как был"
    echo "  $(__torproxy_color --bold)torproxy allow$(__torproxy_color normal)           исключения: адреса и интерфейсы мимо Tor (ослабляет защиту)"
    echo "  $(__torproxy_color --bold)torproxy browser$(__torproxy_color normal)         Tor Browser через системный Tor"
    echo "  $(__torproxy_color --bold)torproxy boot$(__torproxy_color normal)            защита с момента загрузки: on [--strict] | off"
    echo "  $(__torproxy_color --bold)torproxy hide$(__torproxy_color normal)            случайный MAC и скрытие имени компьютера: on | off"
    echo "  $(__torproxy_color --bold)torproxy clean файл$(__torproxy_color normal)      убрать метаданные из файлов (mat2)"
    echo "  $(__torproxy_color --bold)torproxy newip$(__torproxy_color normal)           новая цепочка Tor (новый IP)"
    echo "  $(__torproxy_color --bold)torproxy country de$(__torproxy_color normal)      страна выхода (de, nl, us…); 'any' — любая"
    echo "  $(__torproxy_color --bold)torproxy exclude ru,by$(__torproxy_color normal)   не выходить через эти страны; 'off' — снять запрет"
    echo "  $(__torproxy_color --bold)torproxy bridges$(__torproxy_color normal)         мосты: auto | snowflake | obfs4 | add | off"
    echo "  $(__torproxy_color --bold)torproxy log$(__torproxy_color normal)             журнал Tor в реальном времени"
    echo "  $(__torproxy_color --bold)torproxy install$(__torproxy_color normal)         установить этот файл для текущего пользователя"
    echo "  $(__torproxy_color --bold)torproxy uninstall$(__torproxy_color normal)       удалить программу и вернуть настройки (-y: без вопроса)"
    echo "  $(__torproxy_color --bold)torproxy guide$(__torproxy_color normal)           руководство пользователя"
    echo "  $(__torproxy_color --bold)torproxy version$(__torproxy_color normal)         версия и платформа (Arch / Debian, Ubuntu)"
end

# ---------- torrc ----------

# Наш блок в torrc между маркерами begin/end. Переписывается целиком при каждом вызове,
# чтобы исправления портов доходили до старых установок.
# Без опций страна и мосты сохраняются; --country КОД|any, --bridge СТРОКА (можно несколько), --no-bridges.
function __torproxy_torrc
    argparse 'country=' 'exclude=' 'bridge=+' no-bridges 'allow=' -- $argv; or return 1
    set -l torrc $__torproxy_torrc
    set -l country (__torproxy_exit_country)
    set -q _flag_country; and set country $_flag_country
    set -l exclude (__torproxy_exclude_current)
    set -q _flag_exclude; and set exclude (string split -n , -- $_flag_exclude)
    set -l allow (__torproxy_allow_current)
    set -q _flag_allow; and set allow (string split -n , -- $_flag_allow)
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
    if set -q exclude[1]
        set -a exit_lines "ExcludeExitNodes "(string join , -- '{'$exclude'}')
    end
    # Conflux строит запасные цепочки через выходы вне заданных стран (см. __torproxy_has_conflux)
    if set -q exit_lines[1]; and __torproxy_has_conflux
        set -a exit_lines 'ConfluxEnabled 0'
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
        (string replace -r '^' '# torproxy-allow ' -- $allow) \
        $__torproxy_end \
        | sudo tee -a $torrc >/dev/null
    __torproxy_pipefail $pipestatus; or begin
        __torproxy_say red "✘ Не удалось записать настройки в $torrc"
        return 1
    end
end

# Есть ли в этой версии Tor настройка ConfluxEnabled (с 0.4.8). Старый Tor с ней не запустится.
function __torproxy_has_conflux
    command tor --list-torrc-options 2>/dev/null | string match -q ConfluxEnabled
end

# Читает строки нашего блока torrc. Файл обычно доступен всем: sudo только если иначе нельзя,
# чтобы меню и быстрый статус не спрашивали пароль.
function __torproxy_torrc_sed --argument-names expr
    set -l range "/^$__torproxy_begin\$/,/^$__torproxy_end\$/"
    if test -r $__torproxy_torrc
        command sed -n "$range$expr" $__torproxy_torrc
    else
        sudo sed -n "$range$expr" $__torproxy_torrc
    end
end

function __torproxy_exit_country
    set -l c (__torproxy_torrc_sed "s/^ExitNodes {\(.*\)}/\1/p")
    test -n "$c"; and echo $c; or echo любая
end

# Коды исключённых стран, по одному в строке
function __torproxy_exclude_current
    __torproxy_torrc_sed "s/^ExcludeExitNodes //p" \
        | string replace -ra '[{}]' '' | string split -n ,
end

# Строки мостов из нашего блока (без слова Bridge)
function __torproxy_bridges_current
    __torproxy_torrc_sed "s/^Bridge //p"
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
    # исключения пользователя: DNS к ним всё равно идёт через Tor (правила DNS стоят раньше)
    set -l allow_nat
    set -l allow_filter
    for a in (__torproxy_allow_current)
        if string match -qr '^[0-9.]+(/\d+)?$' -- $a
            set -a allow_nat "ip daddr $a return comment \"torproxy-allow\""
            set -a allow_filter "ip daddr $a accept comment \"torproxy-allow\""
        else
            set -a allow_nat "oifname \"$a\" return comment \"torproxy-allow\""
            set -a allow_filter "oifname \"$a\" accept comment \"torproxy-allow\""
        end
    end
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
        $(string join \n -- $allow_nat)
        ip daddr $direct return
        meta nfproto ipv4 meta l4proto tcp redirect to :$__torproxy_transport
    }
    chain filter_out {
        type filter hook output priority 0; policy drop;
        meta skuid $tor_uid accept
        $lo_rule
        $lan_rule
        $(string join \n -- $allow_filter)
        udp sport 68 udp dport 67 accept
        # established не разрешаем: соединения, открытые до включения, не должны идти мимо Tor
        # всё прочее (UDP, ICMP, IPv6) — drop, чтобы не было утечек мимо Tor
    }
}"
end

function __torproxy_is_strict
    sudo nft list table inet $__torproxy_table 2>/dev/null | string match -q '*torproxy-strict*'
end

# Ждёт 100% в журнале Tor, рисуя полосу. Код: 0 — подключился, 1 — не успел, 2 — журнал не читается.
function __torproxy_wait_bootstrap --argument-names timeout started
    set -l pct 0
    set -l shown -1
    for i in (seq $timeout)
        set -l line (sudo journalctl -u $__torproxy_unit --since "$started" --no-pager -q | string match -r 'Bootstrapped \d+%.*' | tail -1)
        # string match без совпадений (Tor ещё не начал) — не ошибка, поэтому проверяем только journalctl
        test $pipestatus[1] -eq 0; or return 2
        set -l p (string match -rg 'Bootstrapped (\d+)%' -- "$line")
        test -n "$p"; and set pct $p
        set -l tag (string match -rg 'Bootstrapped \d+% \((\w+)\)' -- "$line")
        # вне терминала \\r не работает: каждый повтор был бы лишним мусором в журнале
        if test -t 1; or test $pct -ne $shown
            # подпись только в терминале: вне его достаточно процентов
            set -l stage
            test -t 1; and set stage (__torproxy_stage "$tag")
            __torproxy_bar $pct "$stage"
            set shown $pct
        end
        test $pct -eq 100; and return 0
        sleep 1
    end
    return 1
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
    __torproxy_clock_warn

    # через мосты (особенно snowflake) Tor подключается заметно дольше
    set -l timeout $__torproxy_timeout
    set -l bridges (__torproxy_bridges_current)
    set -q bridges[1]; and set timeout (math $timeout x 2)

    set -l started (date '+%Y-%m-%d %H:%M:%S')
    sudo systemctl restart $__torproxy_unit; or begin
        __torproxy_on_failed "Tor не запустился" $started
        return 1
    end
    echo "  Подключение к сети Tor..."
    __torproxy_wait_bootstrap $timeout $started
    set -l wait_rc $status
    echo
    if test $wait_rc -eq 2
        __torproxy_on_failed "Не удалось прочитать журнал Tor"
        return 1
    else if test $wait_rc -ne 0
        __torproxy_on_failed "Tor не подключился за $timeout секунд" $started
        return 1
    end

    # сторож не должен вернуть старую таблицу между удалением и созданием новой
    __torproxy_guard_stop
    sudo nft delete table inet $__torproxy_table 2>/dev/null
    __torproxy_rules $mode | sudo nft -f -; or begin
        __torproxy_say red "✘ Ошибка применения правил nftables"
        return 1
    end
    __torproxy_guard_start $mode
    resolvectl flush-caches 2>/dev/null

    __torproxy_say green "✔ Tor-режим ВКЛЮЧЁН. Перезапусти браузер и программы, открытые до включения."
    __torproxy_status
end

# Tor не поднялся. Если режим уже был включён, правила остаются: интернет закрыт, но без утечек.
function __torproxy_on_failed --argument-names reason started
    echo
    # журнал читаем до остановки: так в выборку не попадут сообщения о завершении
    set -l why
    if test -n "$started"
        set why (__torproxy_explain (sudo journalctl -u $__torproxy_unit --since "$started" --no-pager -q 2>/dev/null))
    end
    sudo systemctl stop $__torproxy_unit
    if sudo nft list table inet $__torproxy_table >/dev/null 2>&1
        __torproxy_say red "✘ $reason. Tor-режим остаётся включённым, поэтому интернет закрыт (torproxy off — вернуть обычный)"
    else
        __torproxy_say red "✘ $reason, правила НЕ применены (torproxy log)"
    end
    test -n "$why"; and __torproxy_say yellow "  Вероятная причина: $why"
end

# Переводит сообщения Tor в понятную причину. Порядок важен: сначала то, что не даёт Tor стартовать.
function __torproxy_explain
    if string match -qir 'Reading config failed|Failed to parse/validate config' -- $argv
        echo "ошибка в настройках Tor, подробности покажет torproxy doctor"
    else if string match -qir 'Could not bind|Address already in use' -- $argv
        echo "порт Tor занят другой программой, какой именно, покажет torproxy doctor"
    else if string match -qir 'Permission denied|apparmor' -- $argv
        echo "Tor не хватило прав (часто это AppArmor или права на каталог данных)"
    else if string match -qir 'Could not launch managed proxy|Managed proxy .*(?:fail|exit|terminat)|Pluggable Transport process terminated' -- $argv
        echo "не запустилась программа-транспорт для мостов"
    else if string match -qir 'clock|skew|not yet valid' -- $argv
        echo "неверные часы компьютера: исправь время и включи снова"
    else if string match -qir 'Network is unreachable|No route to host' -- $argv
        echo "нет подключения к сети"
    else if string match -qir 'Bootstrapped|Problem bootstrapping' -- $argv
        if test -n "$(__torproxy_bridges_current)"
            echo "мосты не отвечают: попробуй torproxy bridges auto или свои мосты от @GetBridgesBot"
        else
            echo "Tor, похоже, заблокирован в этой сети: попробуй torproxy bridges auto"
        end
    end
end

# Предупреждает, если система считает часы несинхронизированными: при большой ошибке Tor не подключится,
# а в Tor-режиме синхронизация по NTP заблокирована.
function __torproxy_clock_warn
    command -q timedatectl; or return 0
    if test "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = no
        __torproxy_say yellow "  ⚠ Часы не синхронизированы. Если Tor не подключится, сначала проверь время: timedatectl"
    end
end

# ---------- сторож правил ----------

# Сторож возвращает таблицу, если её стёрли (например, nftables.service делает flush ruleset):
# без него трафик молча пошёл бы напрямую, а пользователь считал бы, что он в Tor.
function __torproxy_guard_unit_text
    set -l nft (command -s nft; or echo /usr/bin/nft)
    set -l runtime $__torproxy_run/rules.nft
    set -l persistent $__torproxy_etc/rules.nft
    printf '%s\n' \
        '[Unit]' \
        'Description=torproxy: restore firewall rules if they are flushed' \
        'DefaultDependencies=no' \
        "After=local-fs.target $__torproxy_boot_unit.service" \
        'Before=shutdown.target' \
        'Conflicts=shutdown.target' \
        '' \
        '[Service]' \
        "ExecStart=/bin/sh -c 'while sleep $__torproxy_guard_interval; do $nft list table inet $__torproxy_table >/dev/null 2>&1 && continue; if [ -r $runtime ]; then f=$runtime; else f=$persistent; fi; $nft -f \$\$f && echo restored rules from \$\$f; done'" \
        'Restart=on-failure' \
        '' \
        '[Install]' \
        'WantedBy=sysinit.target'
end

# Запоминает действующие правила и запускает сторожа. Сбой не критичен: режим уже включён.
function __torproxy_guard_start --argument-names mode
    set -l ok 1
    sudo mkdir -p $__torproxy_run; or set ok 0
    __torproxy_rules $mode | sudo tee $__torproxy_run/rules.nft >/dev/null
    __torproxy_pipefail $pipestatus; or set ok 0
    __torproxy_guard_unit_text | sudo tee $__torproxy_run_systemd/$__torproxy_guard_unit.service >/dev/null
    __torproxy_pipefail $pipestatus; or set ok 0
    sudo systemctl daemon-reload; or set ok 0
    sudo systemctl start $__torproxy_guard_unit; or set ok 0
    if test $ok = 0
        __torproxy_say yellow "  ⚠ Не удалось запустить сторожа: если правила кто-то сотрёт, они не вернутся сами"
    end
end

function __torproxy_guard_stop
    sudo systemctl stop $__torproxy_guard_unit 2>/dev/null
    sudo rm -f $__torproxy_run/rules.nft $__torproxy_run_systemd/$__torproxy_guard_unit.service
    true
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
    __torproxy_guard_stop
    sudo systemctl daemon-reload
    sudo nft delete table inet $__torproxy_table 2>/dev/null
    sudo systemctl stop $__torproxy_unit
    resolvectl flush-caches 2>/dev/null
    __torproxy_say yellow "● Tor-режим ВЫКЛЮЧЕН, обычный интернет восстановлен."
    if systemctl -q is-enabled $__torproxy_boot_unit 2>/dev/null
        __torproxy_say yellow "  При следующей загрузке режим включится снова (torproxy boot off — отключить)"
    end
end

# ---------- исключения ----------

function __torproxy_allow_current
    __torproxy_torrc_sed "s/^# torproxy-allow //p"
end

# IPv4-адрес или сеть, которую разумно пропускать мимо Tor. Слишком широкая сеть отключила бы защиту.
function __torproxy_allow_valid_ip --argument-names value
    set -l m (string match -rg '^(\d+)\.(\d+)\.(\d+)\.(\d+)(?:/(\d+))?$' -- $value); or return 1
    for octet in $m[1..4]
        test $octet -le 255; or return 1
    end
    if set -q m[5]
        test $m[5] -ge 8 -a $m[5] -le 32; or return 1
    end
    return 0
end

# Применяет изменившиеся исключения: к работающему режиму и к правилам для загрузки
function __torproxy_allow_apply
    if sudo nft list table inet $__torproxy_table >/dev/null 2>&1
        set -l mode
        __torproxy_is_strict; and set mode strict
        __torproxy_guard_stop
        sudo nft delete table inet $__torproxy_table 2>/dev/null
        __torproxy_rules $mode | sudo nft -f -; or begin
            __torproxy_say red "✘ Ошибка применения правил nftables: режим снят, включи заново (torproxy on)"
            return 1
        end
        __torproxy_guard_start $mode
    end
    if sudo test -e $__torproxy_etc/rules.nft
        set -l mode
        sudo grep -q torproxy-strict $__torproxy_etc/rules.nft; and set mode strict
        __torproxy_rules $mode | sudo tee $__torproxy_etc/rules.nft >/dev/null
    end
    return 0
end

# torproxy allow [АДРЕС | ИНТЕРФЕЙС | del ЗНАЧЕНИЕ | off]
function __torproxy_allow --argument-names arg value
    set -l current (__torproxy_allow_current)
    switch "$arg"
        case ''
            if set -q current[1]
                __torproxy_say yellow "⚠ Мимо Tor идёт: "(string join ', ' -- $current)
            else
                __torproxy_say green "Исключений нет: весь трафик через Tor"
            end
            echo "  torproxy allow 100.64.0.0/10   адрес или сеть мимо Tor"
            echo "  torproxy allow tailscale0      сетевой интерфейс мимо Tor"
            echo "  torproxy allow del АДРЕС       убрать одно исключение"
            echo "  torproxy allow off             убрать все"
            return
        case off
            __torproxy_torrc --allow=; or return 1
            __torproxy_allow_apply; or return 1
            __torproxy_say green "✔ Исключений нет: весь трафик через Tor"
            return
        case del
            if not contains -- "$value" $current
                __torproxy_say red "✘ Такого исключения нет: $value"
                return 1
            end
            set -l left (string match -v -- "$value" $current)
            __torproxy_torrc --allow="$(string join , -- $left)"; or return 1
            __torproxy_allow_apply; or return 1
            __torproxy_say green "✔ Убрано: $value"
            return
    end

    if string match -qr '^[0-9.]+(/\d+)?$' -- $arg
        if not __torproxy_allow_valid_ip $arg
            __torproxy_say red "✘ Неверный адрес или слишком широкая сеть: $arg (нужна маска от /8 до /32)"
            return 1
        end
    else if not string match -qr '^[A-Za-z][A-Za-z0-9_.-]{0,14}$' -- $arg
        __torproxy_say red "✘ Не похоже на адрес или интерфейс: $arg"
        return 1
    else
        # через этот интерфейс идёт весь интернет: исключение отключило бы защиту целиком
        if contains -- $arg lo (ip route show default 2>/dev/null | string match -rg ' dev (\S+)')
            __torproxy_say red "✘ Через $arg идёт весь трафик: такое исключение отключило бы защиту"
            return 1
        end
        if command -q ip; and not ip link show $arg >/dev/null 2>&1
            __torproxy_say yellow "  ⚠ Интерфейса $arg сейчас нет: исключение сработает, когда он появится"
        end
    end
    if contains -- $arg $current
        __torproxy_say yellow "Уже в исключениях: $arg"
        return
    end
    __torproxy_torrc --allow="$(string join , -- $current $arg)"; or return 1
    __torproxy_allow_apply; or return 1
    __torproxy_say yellow "⚠ Теперь мимо Tor идёт: "(string join ', ' -- $current $arg)
    echo "  Этот трафик идёт напрямую, с твоего настоящего IP. DNS-запросы по-прежнему через Tor."
end

# ---------- одна программа через Tor ----------

set -g __torproxy_ns torproxy-run
set -g __torproxy_ns_host tprun0
set -g __torproxy_ns_peer tprun1
set -g __torproxy_ns_host_ip 172.31.250.1 # не 10.192.0.0/10: эту сеть Tor использует для DNS-подмены
set -g __torproxy_ns_peer_ip 172.31.250.2

# Правила хоста для пространства программы: из него есть только путь в Tor, всё прочее отбрасывается.
# route_localnet разрешает перенаправлять в 127.0.0.1, поэтому Tor не нужно слушать новый адрес.
function __torproxy_run_rules
    set -l h $__torproxy_ns_host
    echo "
table inet torproxy_run {
    chain nat_pre {
        type nat hook prerouting priority -100; policy accept;
        iifname \"$h\" meta nfproto ipv4 udp dport 53 dnat ip to 127.0.0.1:$__torproxy_dnsport
        iifname \"$h\" meta nfproto ipv4 tcp dport 53 dnat ip to 127.0.0.1:$__torproxy_transport
        iifname \"$h\" meta nfproto ipv4 meta l4proto tcp dnat ip to 127.0.0.1:$__torproxy_transport
    }
    chain filter_pre {
        type filter hook prerouting priority 0; policy accept;
        iifname \"$h\" ct status dnat accept
        iifname \"$h\" drop
    }
}"
end

# Сценарий от root: создаёт пространство, запускает программу, убирает всё после неё. Он целиком в одном
# процессе, чтобы уборка выполнилась и после Ctrl+C: fish при Ctrl+C бросил бы остаток функции.
# Параметры: uid gid ПЕРЕМЕННАЯ=ЗНАЧЕНИЕ… -- команда…
function __torproxy_run_script
    set -l ns $__torproxy_ns
    set -l h $__torproxy_ns_host
    set -l p $__torproxy_ns_peer
    set -l hip $__torproxy_ns_host_ip
    set -l pip $__torproxy_ns_peer_ip
    echo "
down() {
    nft delete table inet torproxy_run 2>/dev/null
    ip link del $h 2>/dev/null
    ip netns del $ns 2>/dev/null
    rm -f /etc/netns/$ns/resolv.conf
    rmdir /etc/netns/$ns 2>/dev/null
}
up() {
    ip netns list | grep -qw $ns && ip link show $h >/dev/null 2>&1 && return 0
    down
    set -e
    ip netns add $ns
    ip link add $h type veth peer name $p
    ip link set $p netns $ns
    sysctl -qw net.ipv6.conf.$h.disable_ipv6=1
    sysctl -qw net.ipv4.conf.$h.route_localnet=1
    sysctl -qw net.ipv4.conf.$h.rp_filter=0
    ip addr add $hip/30 dev $h
    ip link set $h up
    ip netns exec $ns sysctl -qw net.ipv6.conf.all.disable_ipv6=1
    ip -n $ns link set lo up
    ip -n $ns addr add $pip/30 dev $p
    ip -n $ns link set $p up
    ip -n $ns route add default via $hip
    nft -f - <<'RULES'
$(__torproxy_run_rules)
RULES
    mkdir -p /etc/netns/$ns
    echo 'nameserver $hip' >/etc/netns/$ns/resolv.conf
    set +e
}
if [ \"\$1\" = --stop ]; then
    pids=\$(ip netns pids $ns 2>/dev/null)
    [ -n \"\$pids\" ] && kill \$pids 2>/dev/null
    sleep 1
    pids=\$(ip netns pids $ns 2>/dev/null)
    [ -n \"\$pids\" ] && kill -9 \$pids 2>/dev/null
    down
    exit 0
fi
uid=\$1; gid=\$2; shift 2
if ! ( up ); then
    echo 'torproxy: не удалось создать сетевое пространство' >&2
    down
    exit 125
fi
trap : INT TERM
ip netns exec $ns sh -c '
    # Разрешение имён через локальные службы шло бы мимо сети пространства: прячем их сокеты
    for d in /run/systemd/resolve /run/nscd /var/run/nscd /run/avahi-daemon; do
        [ -d \"\$d\" ] && mount -t tmpfs tmpfs \"\$d\"
    done
    if [ -d /run/systemd/resolve ]; then
        echo \"nameserver $hip\" >/run/systemd/resolve/stub-resolv.conf
        echo \"nameserver $hip\" >/run/systemd/resolve/resolv.conf
    fi
    uid=\$1; gid=\$2; shift 2
    exec setpriv --reuid=\"\$uid\" --regid=\"\$gid\" --init-groups env \"\$@\"
' sh \"\$uid\" \"\$gid\" \"\$@\"
rc=\$?
[ -z \"\$(ip netns pids $ns 2>/dev/null)\" ] && down
exit \$rc"
end

# torproxy run [--force] программа [аргументы…] | torproxy run --stop
function __torproxy_run
    argparse -s force stop -- $argv; or return 1
    if set -q _flag_stop
        sudo sh -c (__torproxy_run_script | string collect) torproxy-run --stop
        __torproxy_say yellow "● Отдельное сетевое пространство закрыто, программы в нём завершены"
        return
    end
    if not set -q argv[1]
        echo "  torproxy run программа [аргументы]   только эта программа через Tor"
        echo "  torproxy run --force программа       запустить, даже если она уже открыта"
        echo "  torproxy run --stop                  завершить всё, что запущено так"
        return 1
    end
    for tool in ip setpriv nft
        if not command -q $tool
            __torproxy_say red "✘ Нужна программа $tool"
            return 1
        end
    end
    if test -z "$(command -s -- $argv[1])"
        __torproxy_say red "✘ Программа не найдена: $argv[1]"
        return 127
    end

    # Браузер и многие другие программы открывают окно в уже запущенной копии, а та работает мимо Tor
    set -l name (path basename -- $argv[1] | string sub -l 15)
    if not set -q _flag_force; and pgrep -xu (id -u) -- $name >/dev/null 2>&1
        __torproxy_say yellow "⚠ $name уже запущен. Новое окно может открыться в старой копии, а она работает МИМО Tor."
        if not test -t 0
            echo "  Закрой её или запусти с --force, если уверен, что программа создаст новую копию."
            return 1
        end
        read -P '  Запустить всё равно? [y/N] ' -l answer
        string match -qri '^[yд]' -- "$answer"; or return 1
    end

    # Tor нужен, но правила всей системы не включаем: в этом и смысл команды
    set -l started_tor 0
    if not systemctl -q is-active $__torproxy_unit
        __torproxy_torrc; or return 1
        echo "  Подключение к сети Tor..."
        set -l started (date '+%Y-%m-%d %H:%M:%S')
        sudo systemctl restart $__torproxy_unit; or begin
            __torproxy_on_failed "Tor не запустился" $started
            return 1
        end
        set -l timeout $__torproxy_timeout
        test -n "$(__torproxy_bridges_current)"; and set timeout (math $timeout x 2)
        __torproxy_wait_bootstrap $timeout $started
        set -l rc $status
        echo
        if test $rc -ne 0
            __torproxy_on_failed "Tor не подключился за $timeout секунд" $started
            return 1
        end
        set started_tor 1
    end

    set -l envs
    for v in DISPLAY WAYLAND_DISPLAY XAUTHORITY XDG_RUNTIME_DIR XDG_SESSION_TYPE XDG_CURRENT_DESKTOP DBUS_SESSION_BUS_ADDRESS PULSE_SERVER HOME USER LOGNAME PATH LANG LC_ALL TERM
        set -q $v; and set -a envs "$v=$$v"
    end
    sudo sh -c (__torproxy_run_script | string collect) torproxy-run (id -u) (id -g) $envs -- $argv
    set -l rc $status

    # Tor запускали мы и он больше никому не нужен: возвращаем как было
    if test $started_tor = 1
        if not sudo nft list table inet $__torproxy_table >/dev/null 2>&1; and not sudo ip netns pids $__torproxy_ns >/dev/null 2>&1
            sudo systemctl stop $__torproxy_unit
        end
    end
    return $rc
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
            __torproxy_clock_warn
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
            __torproxy_guard_unit_text | sudo tee $__torproxy_systemd_dir/$__torproxy_guard_unit.service >/dev/null
            __torproxy_pipefail $pipestatus; or begin
                __torproxy_say red "✘ Не удалось записать службу сторожа"
                return 1
            end
            sudo systemctl daemon-reload
            sudo systemctl enable $__torproxy_boot_unit $__torproxy_unit $__torproxy_guard_unit; or begin
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
            sudo systemctl disable $__torproxy_boot_unit $__torproxy_guard_unit 2>/dev/null
            sudo rm -f $__torproxy_systemd_dir/$__torproxy_guard_unit.service
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

# Ответ сайта проверки. Первое соединение после подключения Tor иногда сразу обрывается,
# поэтому быстрый обрыв повторяем. После таймаута не повторяем: команда висела бы минутами.
function __torproxy_check_ip
    for i in (seq 3)
        set -l started (date +%s)
        set -l reply (curl -s --max-time (__torproxy_check_timeout) https://check.torproject.org/api/ip)
        if test -n "$reply"
            printf '%s\n' $reply
            return 0
        end
        test (math (date +%s) - $started) -ge 10; and return 1
        test $i -lt 3; and sleep 2
    end
    return 1
end

# Одна строка отчёта leaktest; код возврата — результат проверки
function __torproxy_leak_row --argument-names ok name detail
    if test $ok = 1
        __torproxy_row $name "$(__torproxy_color green)✔$(__torproxy_color normal) $detail"
    else
        __torproxy_row $name "$(__torproxy_color red)✘$(__torproxy_color normal) $detail"
        return 1
    end
end

function __torproxy_leaktest
    set -l failed 0
    echo "$(__torproxy_color magenta)"'  ╭──────── проверка утечек ─────────'"$(__torproxy_color normal)"

    set -l ok 0
    sudo nft list table inet $__torproxy_table >/dev/null 2>&1; and set ok 1
    __torproxy_leak_row $ok "Правила" "таблица nftables"; or set failed (math $failed + 1)

    set ok 0
    systemctl -q is-active $__torproxy_unit; and set ok 1
    __torproxy_leak_row $ok "Служба Tor" $__torproxy_unit; or set failed (math $failed + 1)

    # адрес снаружи видит сам сайт проверки
    set -l check (__torproxy_check_ip)
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

    set -l allowed (__torproxy_allow_current)
    set -q allowed[1]; and __torproxy_row "Исключения" "$(__torproxy_color yellow)⚠$(__torproxy_color normal) мимо Tor идёт: "(string join ', ' -- $allowed)
    echo "$(__torproxy_color magenta)"'  ╰──────────────────────────────────'"$(__torproxy_color normal)"
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
    set -l rules "$(__torproxy_color red)● выключен$(__torproxy_color normal)"
    if not sudo $sudo_opts true 2>/dev/null
        set rules "$(__torproxy_color yellow)? нужен sudo (выбери «Проверить»)$(__torproxy_color normal)"
    else if sudo nft list table inet $__torproxy_table >/dev/null 2>&1
        set rules "$(__torproxy_color green)● ВКЛЮЧЁН$(__torproxy_color normal)"
        __torproxy_is_strict; and set rules "$(__torproxy_color green)● ВКЛЮЧЁН (строгий)$(__torproxy_color normal)"
    end

    echo "$(__torproxy_color magenta)"'  ╭──────────── статус ─────────────'"$(__torproxy_color normal)"
    __torproxy_row "Режим" $rules
    __torproxy_row "Служба Tor" (systemctl is-active $__torproxy_unit)
    __torproxy_row "Страна выхода" (__torproxy_exit_country)
    set -l excluded (__torproxy_exclude_current)
    set -q excluded[1]; and __torproxy_row "Исключены" (string join ', ' -- $excluded)
    set -l allowed (__torproxy_allow_current)
    set -q allowed[1]; and __torproxy_row "Мимо Tor" "$(__torproxy_color yellow)"(string join ', ' -- $allowed)"$(__torproxy_color normal)"
    __torproxy_row "Мосты" (__torproxy_bridges_summary)
    set -l boot выкл
    systemctl -q is-enabled $__torproxy_boot_unit 2>/dev/null; and set boot вкл
    __torproxy_row "При загрузке" $boot
    set -l hide выкл
    count (__torproxy_hide_dir)/* >/dev/null; and set hide вкл
    __torproxy_row "Скрытие" $hide

    if test "$argv[1]" != --quick
        __torproxy_row "Проверка" "$(__torproxy_color brblack)запрос к check.torproject.org…$(__torproxy_color normal)"
        set -l check (__torproxy_check_ip)
        set -l ip (echo $check | jq -r '.IP // empty' 2>/dev/null)
        if test -z "$ip"
            __torproxy_row "Внешний IP" "$(__torproxy_color red)нет ответа$(__torproxy_color normal)"
        else
            # страну спрашиваем у GeoIP самого Tor: ipinfo.io отвечает выходам Tor 403
            set -l geo
            if systemctl -q is-active $__torproxy_unit
                set geo (__torproxy_control "GETINFO ip-to-country/$ip" 2>/dev/null | string match -rg '^250-ip-to-country/.*=(\w+)$' | string upper)
            end
            test -n "$geo"; or set geo (curl -s --max-time 15 https://ipinfo.io/$ip/json | jq -r '[.country, .city] | map(select(. != null)) | join(", ")' 2>/dev/null)
            __torproxy_row "Внешний IP" "$ip $geo"
            if test "$(echo $check | jq -r .IsTor)" = true
                __torproxy_row "Через Tor" "$(__torproxy_color green)✔ да$(__torproxy_color normal)"
            else
                __torproxy_row "Через Tor" "$(__torproxy_color red)✘ нет$(__torproxy_color normal)"
            end
        end
    end
    echo "$(__torproxy_color magenta)"'  ╰──────────────────────────────────'"$(__torproxy_color normal)"
end

# Команды на ControlPort Tor (аутентификация cookie); печатает ответы Tor построчно
function __torproxy_control
    set -l cookie $__torproxy_cookie_cache
    if test -z "$cookie"
        sudo test -e $__torproxy_cookie; or return 2
        set cookie (sudo od -An -v -tx1 $__torproxy_cookie | string replace -ra '\s' '' | string join '')
        __torproxy_pipefail $pipestatus; or begin
            echo "не удалось прочитать $__torproxy_cookie" >&2
            return 2
        end
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
    if contains -- $cc (__torproxy_exclude_current)
        __torproxy_say red "✘ Страна $cc исключена, Tor не нашёл бы выхода (torproxy exclude off — снять запрет)"
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

# ---------- диагностика ----------

# Строка отчёта doctor: уровень ok | warn | fail; провалы считаются в __torproxy_doc_fails
function __torproxy_doc_row --argument-names level name detail
    switch $level
        case ok
            __torproxy_row $name "$(__torproxy_color green)✔$(__torproxy_color normal) $detail"
        case warn
            __torproxy_row $name "$(__torproxy_color yellow)⚠$(__torproxy_color normal) $detail"
        case fail
            __torproxy_row $name "$(__torproxy_color red)✘$(__torproxy_color normal) $detail"
            set -g __torproxy_doc_fails (math $__torproxy_doc_fails + 1)
    end
end

# Занят ли порт: протокол tcp | udp
function __torproxy_port_used --argument-names proto port
    set -l flag -t
    test $proto = udp; and set flag -u
    test -n "$(ss -Hln $flag "sport = :$port" 2>/dev/null)"
end

function __torproxy_doctor
    set -g __torproxy_doc_fails 0
    set -l pm "sudo pacman -S"
    test "$__torproxy_platform" = debian; and set pm "sudo apt install"
    echo "$(__torproxy_color magenta)"'  ╭──────── диагностика ─────────────'"$(__torproxy_color normal)"

    # программы
    for tool in tor nft curl jq socat ss systemctl
        if type -q $tool
            set -l detail установлен
            test $tool = tor; and set detail (tor --version 2>/dev/null | string match -rg 'version ([0-9.]+)')
            __torproxy_doc_row ok $tool "$detail"
        else
            __torproxy_doc_row fail $tool "нет: $pm $tool"
        end
    end
    if not type -q fzf
        __torproxy_doc_row warn fzf "нет: меню будет с номерами вместо стрелок"
    end
    set -l tor_ready 1
    type -q tor; or set tor_ready 0
    if test -z "$__torproxy_user"
        __torproxy_doc_row fail "Пользователь" "нет пользователя tor или debian-tor"
    end

    # транспорты для настроенных мостов
    set -l bridges (__torproxy_bridges_current)
    if set -q bridges[1]
        for tr in (string match -rg '^([a-z0-9_]+) ' -- $bridges | sort -u)
            if test -n "$(__torproxy_pt_binary $tr)"
                __torproxy_doc_row ok "Мосты $tr" "транспорт на месте"
            else
                __torproxy_doc_row fail "Мосты $tr" (__torproxy_pt_hint $tr)
            end
        end
    end

    # настройки: Tor сам проверяет итоговый файл
    if test $tor_ready = 1
        set -l defaults
        test -r /usr/share/tor/tor-service-defaults-torrc; and set defaults --defaults-torrc /usr/share/tor/tor-service-defaults-torrc
        set -l verify (sudo tor $defaults --verify-config -f $__torproxy_torrc 2>&1)
        if test $status -eq 0
            __torproxy_doc_row ok "Настройки" "Tor принимает $__torproxy_torrc"
        else
            set -l first (string match -ri '.*\[(?:warn|err)\].*' -- $verify)[1]
            __torproxy_doc_row fail "Настройки" "Tor отвергает $__torproxy_torrc: $first"
        end
    end

    # служба и порты
    set -l active 0
    systemctl -q is-active $__torproxy_unit; and set active 1
    set -l rules 0
    sudo nft list table inet $__torproxy_table >/dev/null 2>&1; and set rules 1
    for entry in "tcp $__torproxy_transport TransPort" "udp $__torproxy_dnsport DNSPort" "tcp $__torproxy_ctlport ControlPort"
        set -l e (string split ' ' -- $entry)
        set -l used 0
        __torproxy_port_used $e[1] $e[2]; and set used 1
        if test $active = 1 -a $used = 0
            __torproxy_doc_row fail $e[3] "порт $e[2] не слушается: Tor ещё запускается или настройки не применились"
        else if test $active = 0 -a $used = 1
            __torproxy_doc_row fail $e[3] "порт $e[2] занят другой программой: sudo ss -lntup | grep $e[2]"
        else if test $active = 1
            __torproxy_doc_row ok $e[3] "порт $e[2] слушается"
        else
            __torproxy_doc_row ok $e[3] "порт $e[2] свободен"
        end
    end

    # согласованность
    if test $rules = 1 -a $active = 0
        __torproxy_doc_row fail "Интернет" "закрыт: правила есть, а Tor не запущен. torproxy on или torproxy off"
    else if test $rules = 1
        __torproxy_doc_row ok "Режим" "включён"
        if systemctl -q is-active $__torproxy_guard_unit
            __torproxy_doc_row ok "Сторож" "вернёт правила, если их сотрут"
        else
            __torproxy_doc_row warn "Сторож" "не запущен: стёртые правила не вернутся сами (torproxy on запустит его)"
        end
    else if test $active = 1
        __torproxy_doc_row warn "Режим" "Tor работает, но трафик идёт напрямую (torproxy on)"
    else
        __torproxy_doc_row ok "Режим" "выключен"
    end
    if test $active = 1
        if set -l reply (__torproxy_control 'GETINFO status/bootstrap-phase' 2>/dev/null); and string match -q '*PROGRESS=100*' -- "$reply"
            __torproxy_doc_row ok "Подключение" "Tor подключён к сети"
        else if string match -q '*BOOTSTRAP*' -- "$reply"
            __torproxy_doc_row warn "Подключение" "Tor ещё подключается"
        else
            __torproxy_doc_row fail "ControlPort" "Tor не отвечает или отверг cookie"
        end
    end

    set -l allowed (__torproxy_allow_current)
    set -q allowed[1]; and __torproxy_doc_row warn "Исключения" "мимо Tor идёт: "(string join ', ' -- $allowed)

    # часы
    if command -q timedatectl
        switch "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)"
            case yes
                __torproxy_doc_row ok "Часы" "синхронизированы"
            case no
                if test $rules = 1
                    __torproxy_doc_row warn "Часы" "не синхронизируются: в Tor-режиме NTP закрыт. Это норма, пока время не разойдётся сильно"
                else
                    __torproxy_doc_row warn "Часы" "не синхронизированы: при большой ошибке Tor не подключится"
                end
        end
    end

    # если Tor не работает, журнал обычно уже называет причину
    if test $active = 0
        set -l why (__torproxy_explain (sudo journalctl -u $__torproxy_unit -n 100 --no-pager -q 2>/dev/null))
        test -n "$why"; and __torproxy_doc_row warn "Прошлый запуск" $why
    end

    echo "$(__torproxy_color magenta)"'  ╰──────────────────────────────────'"$(__torproxy_color normal)"
    if test $__torproxy_doc_fails -eq 0
        __torproxy_say green "✔ Неполадок не найдено"
    else
        __torproxy_say red "✘ Неполадок: $__torproxy_doc_fails"
        return 1
    end
end

# ---------- установка ----------

# Запускатель для любых оболочек. Текст совпадает с bin/torproxy: один файл ставится и без него.
function __torproxy_launcher_text
    printf '%s\n' \
        '#!/usr/bin/env -S fish --no-config' \
        '# Запуск torproxy из любой оболочки: сам код лежит в functions/torproxy.fish.' \
        '# SPDX-License-Identifier: GPL-3.0-or-later' \
        '' \
        'set -l self (path resolve (status filename))' \
        'for f in (path dirname $self)/../functions/torproxy.fish \\' \
        '        (path dirname $self)/../share/fish/vendor_functions.d/torproxy.fish \\' \
        '        /usr/share/fish/vendor_functions.d/torproxy.fish \\' \
        '        $HOME/.config/fish/functions/torproxy.fish' \
        '    if test -r $f' \
        '        source $f' \
        '        torproxy $argv' \
        '        exit $status' \
        '    end' \
        'end' \
        'echo "torproxy: не найден torproxy.fish" >&2' \
        'exit 127'
end

function __torproxy_install
    set -l config $HOME/.config/fish
    test -n "$XDG_CONFIG_HOME"; and set config $XDG_CONFIG_HOME/fish
    set -l target $config/functions/torproxy.fish
    set -l bin $HOME/.local/bin
    mkdir -p (path dirname $target) $bin; or return 1

    # из своего же каталога копировать нечего: это повторная установка
    if test "$__torproxy_self" != "$(path resolve $target)"
        command cp -- $__torproxy_self $target; or begin
            __torproxy_say red "✘ Не удалось записать $target"
            return 1
        end
    end
    __torproxy_launcher_text >$bin/torproxy; and chmod 755 $bin/torproxy; or begin
        __torproxy_say red "✘ Не удалось записать $bin/torproxy"
        return 1
    end

    # автодополнение есть только в полной версии, один файл работает и без него
    set -l completion (path dirname $__torproxy_self)/../completions/torproxy.fish
    set -l completion_target $config/completions/torproxy.fish
    if test -r $completion
        mkdir -p (path dirname $completion_target)
        if test "$(path resolve $completion)" != "$(path resolve $completion_target)"
            command cp -- $completion $completion_target
        end
    end

    __torproxy_say green "✔ torproxy $__torproxy_version установлен"
    if not contains -- $bin $PATH
        echo
        __torproxy_say yellow "  Каталог $bin не в PATH, поэтому в bash и zsh команды может не быть. Добавь его:"
        echo "    bash:  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
        echo "    zsh:   echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
        echo "    В fish это не нужно."
    end
    echo
    echo "  Открой новый терминал и проверь: torproxy doctor"
    echo "  Руководство: torproxy guide. Если нет интернета: torproxy off"
end

function __torproxy_uninstall
    argparse y/yes -- $argv; or return 1
    if not set -q _flag_yes
        if not test -t 0
            __torproxy_say red "✘ Нужно подтверждение: torproxy uninstall -y"
            return 1
        end
        echo "  Будут выключены Tor-режим и защита при загрузке, возвращены настройки сети,"
        echo "  убран блок из $__torproxy_torrc и удалены файлы программы. Tor останется."
        read -P '  Удалить? [y/N] ' -l answer
        string match -qri '^[yд]' -- "$answer"; or return 1
    end

    # Сначала всё, что держит систему в изменённом виде: пока файлы на месте, это ещё можно отменить
    if test -e $__torproxy_systemd_dir/$__torproxy_boot_unit.service
        __torproxy_boot off; or __torproxy_say yellow "  ⚠ Не удалось снять защиту при загрузке"
    end
    if command -q ip; and sudo ip netns list 2>/dev/null | string match -q "$__torproxy_ns*"
        __torproxy_run --stop
    end
    __torproxy_off -y
    if count (__torproxy_hide_dir)/* >/dev/null
        __torproxy_hide off; or __torproxy_say yellow "  ⚠ Настройки сети не возвращены: они сохранены в "(__torproxy_hide_dir)
    end
    if sudo grep -qxF -- $__torproxy_end $__torproxy_torrc
        sudo sed -i "/^$__torproxy_begin\$/,/^$__torproxy_end\$/d" $__torproxy_torrc
        or __torproxy_say yellow "  ⚠ Не удалось убрать блок из $__torproxy_torrc"
    end

    set -l config $HOME/.config/fish
    test -n "$XDG_CONFIG_HOME"; and set config $XDG_CONFIG_HOME/fish
    rm -f $config/functions/torproxy.fish $config/completions/torproxy.fish $HOME/.local/bin/torproxy
    __torproxy_say green "✔ torproxy удалён, Tor и остальные программы не тронуты"
    test -e $__torproxy_torrc.bak-torproxy; and echo "  Копия настроек до первого запуска: $__torproxy_torrc.bak-torproxy"
    echo "  Если ставили пакетом: sudo pacman -R torproxy"
    echo "  В открытых терминалах команда останется до их закрытия."
end

# ---------- руководство ----------

# Текст руководства: строка «# Заголовок» станет заголовком, остальное выводится как есть
function __torproxy_guide_text
    echo '# Руководство пользователя torproxy '$__torproxy_version
    echo '
torproxy направляет весь TCP-трафик и DNS компьютера через сеть Tor, а всё
остальное (UDP, ICMP, IPv6) блокирует, чтобы ничего не ушло мимо Tor.

# Быстрый старт

  torproxy            открыть меню
  torproxy on         включить Tor-режим
  torproxy status     убедиться: «Через Tor ✔ да»
  torproxy off        выключить и вернуть обычный интернет

После включения перезапусти браузер и программы, открытые раньше: их старые
соединения обрываются. Команды просят пароль sudo, он нужен для настройки
файрвола и службы Tor.

# Меню

Команда torproxy без аргументов открывает меню. Пункт выбирается стрелками
и Enter (без fzf — номером), Esc закрывает меню. Сверху виден текущий статус.

# Основные команды

  on                  включить Tor-режим
  on --strict         то же, но закрыть и доступ к локальной сети (кроме DHCP)
  off                 выключить; спросит, если через Tor работают программы
  off -y              выключить без вопроса
  status              режим, служба, страна, мосты, внешний IP
  newip               новая цепочка; Tor делает это не чаще раза в 10 секунд
  log                 журнал Tor в реальном времени, Ctrl+C — выход
  version             версия и определившаяся система
  help                краткий список команд
  guide               это руководство

# Наблюдение

  circuit             схема: через какие страны и узлы идёт трафик
  watch               живая панель: IP, скорость, цепочки и путь
                      клавиши: q — выход, n — новый IP
  leaktest            проверка утечек: IP, DNS, UDP, IPv6, ICMP
  doctor              найти неполадку: программы, настройки, порты, часы

Разные сайты идут по разным цепочкам, поэтому circuit показывает последнюю
открытую. Если соединений нет, будет показана готовая цепочка без сайта.

# Страны

  country de          выходить в интернет через Германию (код из двух букв)
  country any         любая страна
  exclude ru,by       никогда не выходить через эти страны
  exclude off         снять запрет

Страна применяется сразу. Нельзя выбрать исключённую страну и исключить
выбранную. С ограничением по странам отключается Conflux (разделение трафика
по цепочкам): его цепочки не соблюдают эти настройки. Скорость может немного
снизиться. Редкая страна с малым числом узлов может работать медленно или
не подключаться совсем.

# Мосты: если Tor заблокирован

Мосты помогают, когда провайдер блокирует Tor, и скрывают от него сам факт
использования Tor. Для них нужна программа-транспорт: lyrebird-proxy в Arch,
obfs4proxy и snowflake-client в Debian и Ubuntu.

  bridges auto        подобрать рабочий способ: напрямую, obfs4, snowflake
  bridges auto --no-direct    то же, но не подключаться без мостов
  bridges snowflake   встроенные Snowflake: работают почти везде, но медленно
  bridges obfs4       встроенные obfs4: быстрые, но их адреса часто блокируют
  bridges add         добавить свои: Telegram @GetBridgesBot
                      или bridges.torproject.org
  bridges off         без мостов

Если нужно скрыть использование Tor от провайдера, бери --no-direct: обычный
auto сначала пробует подключиться напрямую. Свои мосты обычно надёжнее
встроенных.

# Одна программа через Tor

  run программа       только эта программа идёт через Tor, остальное как было
  run --force прог.   запустить, даже если она уже открыта
  run --stop          завершить всё, что запущено этой командой

Tor-режим включать не нужно, а Tor запустится сам. Программа получает отдельную
сетевую среду, из которой есть только путь в Tor, поэтому обойти его не может,
даже если игнорирует настройки прокси.

Важно: браузер и многие программы открывают окно в уже запущенной копии, а она
работает МИМО Tor. Закрой её заранее или укажи новый профиль. Файлы, DBus и
другие локальные службы программе по-прежнему доступны. Если Ctrl+C прервал
запуск, Tor может остаться работать: torproxy off его остановит.

# Исключения: мимо Tor

  allow               показать исключения
  allow 100.64.0.0/10 пустить адрес или сеть напрямую
  allow tailscale0    пустить сетевой интерфейс напрямую
  allow del АДРЕС     убрать одно исключение
  allow off           убрать все

Это ослабляет защиту: такой трафик идёт с настоящего IP. DNS-запросы всё равно
идут через Tor, поэтому DNS из Tailscale и похожих программ может не работать.
Нельзя исключить интерфейс, через который идёт весь интернет, и сети шире /8.
Исключения видны в status, leaktest и doctor.

# Анонимность

  browser             Tor Browser через системный Tor, без двойного Tor
  boot on             правила включаются при загрузке, ещё до появления сети
  boot on --strict    то же в строгом режиме
  boot off            обычная загрузка
  hide on             случайный MAC, имя компьютера не передаётся в сеть
  hide off            вернуть прежние настройки сети
  clean файл…         убрать метаданные (GPS, автор, камера): рядом появится
                      файл.cleaned.расширение, исходный файл не меняется

hide требует NetworkManager и переподключает сеть, а сети с привязкой по MAC
могут не пустить. clean требует mat2 и не убирает то, что видно на самом фото.

# Что скрипт не решит

Скрипт закрывает технические утечки. Выдать тебя могут и другие вещи:

  - вход в свои аккаунты сразу раскрывает, кто ты;
  - обычный браузер узнаётся по отпечатку и кукам, для этого нужен browser;
  - программа, оставшаяся открытой после off, продолжит сессию с настоящего IP;
  - остаются манера письма и время активности;
  - вредоносная программа на компьютере узнает, кто ты, и в Tor-режиме.

В Tor-режиме не работают UDP-сервисы: игры, звонки, QUIC, VPN и синхронизация
времени. Трафик Docker и виртуальных машин не перехватывается.

# Сторож правил

Пока режим включён, служба torproxy-guard каждые 3 секунды проверяет таблицу
файрвола и возвращает её, если её стёрли: например, перезапуск nftables.service
очищает все правила. Запрет снимается только командой torproxy off.

# Если что-то не работает

Начни с torproxy doctor: он проверит программы, настройки, порты и часы.

  Нет интернета
      torproxy off вернёт обычный интернет. Так бывает, если Tor упал или при
      включённом boot не подключился: правила намеренно закрывают выход.

  Tor не подключается
      torproxy log покажет причину. Tor заблокирован: torproxy bridges auto.
      Застрял в самом начале: проверь время на компьютере, при сильно неверных
      часах Tor не подключается, а в Tor-режиме NTP заблокирован.

  Страна не меняется
      В этой стране могло не оказаться подходящего узла: попробуй другую или
      torproxy country any. Проверить: torproxy status.

  Сайт не открывается или просит капчу
      Сайты часто блокируют узлы выхода Tor: torproxy newip даст другой.

  Внешний IP: нет ответа
      Сайт проверки не ответил. Повтори torproxy status или выполни leaktest.

  «Для мостов … нет программы-транспорта»
      Установи программу, название которой указано в сообщении.

# Установка и удаление

  install             установить этот файл для текущего пользователя
  uninstall           выключить всё, вернуть настройки и удалить программу
  uninstall -y        то же без вопроса

Подробная инструкция для разных случаев лежит в файле INSTALL.md: с GitHub,
из папки или архива, из одного файла, из пакета.

# Настройки вывода

  NO_COLOR=1 torproxy status      вывод без цвета (стандарт no-color.org)

# Файлы

  /etc/tor/torrc                  настройки в блоке между метками torproxy
  /etc/tor/torrc.bak-torproxy     копия файла до первого изменения
  /etc/torproxy/                  правила для запуска при загрузке
  ~/.local/state/torproxy/hide/   прежние настройки сети для hide off

Правила файрвола лежат в отдельной таблице nftables inet torproxy. torproxy off
удаляет только её, другие правила не затрагиваются.'
end

# torproxy guide: в терминале листается, в файл и конвейер выводится чистым текстом
function __torproxy_guide
    if not test -t 1
        __torproxy_guide_text | string replace -r '^# ' ''
        return
    end
    set -l bold "$(__torproxy_color --bold magenta)"
    set -l off "$(__torproxy_color normal)"
    set -l text (__torproxy_guide_text | string replace -r '^# (.*)$' "$bold\$1$off")
    if command -q less
        # текст всегда в UTF-8: без этого в локали C less показал бы кириллицу как <D0><A0>
        printf '%s\n' $text | env LESSCHARSET=utf-8 less -R -P ' стрелки — прокрутка, q — назад '
    else
        printf '%s\n' $text
    end
end

# ---------- схема цепочки и панель ----------

# Цепочки и соединения Tor, по одной записи в строке
function __torproxy_circuit_lines
    __torproxy_control 'GETINFO circuit-status' 'GETINFO stream-status' 2>/dev/null \
        | string replace -r '^250[-+](?:circuit|stream)-status=' ''
    __torproxy_pipefail $pipestatus
end

# Цепочки, по которым ходит обычный трафик: без служебных и внутренних
function __torproxy_circuit_usable
    for line in (string match -r '^\d+ BUILT .*' -- $argv)
        string match -rq ' PURPOSE=(?:GENERAL|CONFLUX_LINKED)\b' -- $line; or continue
        string match -rq 'IS_INTERNAL|ONEHOP_TUNNEL' -- $line; and continue
        echo $line
    end
end

# Цепочка для показа: 1-я строка — путь, 2-я — сайт (если по ней что-то открыто).
# Сначала последнее открытое соединение, иначе последняя готовая цепочка.
function __torproxy_circuit_pick
    set -l usable (__torproxy_circuit_usable $argv)
    set -q usable[1]; or return 1
    set -l streams (string match -r '^\d+ SUCCEEDED [1-9]\d* \S+' -- $argv)
    if set -q streams[1]
        for stream in $streams[-1..1]
            set -l f (string split ' ' -- $stream)
            for line in $usable
                if test (string split -f1 ' ' -- $line) = $f[3]
                    string split -f3 ' ' -- $line
                    # имя приходит из сети: в терминал пускаем только безопасные символы
                    string replace -r ':\d+$' '' -- $f[4] | string replace -ra '[^[:alnum:]._:-]' ''
                    return 0
                end
            end
        end
    end
    string split -f3 ' ' -- $usable[-1]
end

# Флаг страны из символов-указателей Unicode
function __torproxy_flag --argument-names cc
    set -l letters (string split '' abcdefghijklmnopqrstuvwxyz)
    set -l a (contains -i -- (string sub -l1 -- $cc) $letters)
    set -l b (contains -i -- (string sub -s2 -l1 -- $cc) $letters)
    if test -z "$a" -o -z "$b"
        echo 🌐
        return
    end
    printf "$(printf '\\\\U%08X\\\\U%08X' (math 0x1F1E5 + $a) (math 0x1F1E5 + $b))"
    echo
end

# Страна узла по отпечатку. Запоминаем: панель спрашивает об одних и тех же узлах.
function __torproxy_hop_country --argument-names fp
    set -l var __torproxy_cc_$fp
    if not set -q $var
        set -l ip (__torproxy_control "GETINFO ns/id/$fp" 2>/dev/null | string match -r '^r .*' | string split ' ')[7]
        set -l cc
        test -n "$ip"; and set cc (__torproxy_control "GETINFO ip-to-country/$ip" 2>/dev/null | string match -rg '^250-ip-to-country/.*=([a-z]{2})$')
        # неудачу не запоминаем: это мог быть разовый сбой связи (и мосты, о которых Tor молчит)
        if test -z "$cc"
            echo '??'
            return
        end
        set -g $var $cc
    end
    echo $$var
end

# «Ты ──▶ 🇩🇪 DE ──▶ … ──▶ сайт»
function __torproxy_chain --argument-names path target
    set -l parts Ты
    for hop in (string split , -- $path)
        set -l fp (string match -rg '^\$([0-9A-F]{40})' -- $hop)
        set -l cc (__torproxy_hop_country $fp)
        set -a parts (__torproxy_flag $cc)" "(string upper -- $cc)
    end
    test -n "$target"; or set target сайт
    set -a parts (string shorten -m28 -- $target)
    string join ' ──▶ ' -- $parts
end

function __torproxy_circuit
    if not systemctl -q is-active $__torproxy_unit
        __torproxy_say red "✘ Tor не запущен (torproxy on)"
        return 1
    end
    set -l lines (__torproxy_circuit_lines)
    if test $status -ne 0
        __torproxy_say red "✘ Нет связи с Tor через ControlPort"
        return 1
    end
    set -l usable (__torproxy_circuit_usable $lines)
    set -l picked (__torproxy_circuit_pick $lines)
    if not set -q picked[1]
        __torproxy_say yellow "Tor ещё не построил цепочек, подожди немного"
        return 1
    end
    echo
    set -l chain (__torproxy_chain $picked[1] "$picked[2]")
    __torproxy_color --bold
    echo "  $chain"
    __torproxy_color normal
    echo
    set -l hops (string split , -- $picked[1])
    set -l bridges (__torproxy_bridges_current)
    for i in (seq (count $hops))
        set -l nick (string match -rg '~(\w+)$' -- $hops[$i])
        test -n "$nick"; or set nick '(без имени)'
        if test $i -eq 1
            if set -q bridges[1]
                __torproxy_row мост "$nick — видит твой IP, но не сайт"
            else
                __torproxy_row вход "$nick — видит твой IP, но не сайт"
            end
        else if test $i -eq (count $hops)
            __torproxy_row выход "$nick — видит сайт, но не тебя"
        else
            __torproxy_row середина "$nick — не видит ни тебя, ни сайт"
        end
    end
    echo
    if set -q picked[2]
        echo "  Разные сайты идут по разным цепочкам (всего: "(count $usable)"). Показана последняя открытая."
    else
        echo "  Открытых соединений нет, показана готовая цепочка (всего: "(count $usable)")."
    end
end

# Мини-график из значений
function __torproxy_spark
    set -l blocks ▁ ▂ ▃ ▄ ▅ ▆ ▇ █
    set -l max 0
    for v in $argv
        test $v -gt $max; and set max $v
    end
    set -l out
    for v in $argv
        if test $max -eq 0
            set -a out $blocks[1]
        else
            set -a out $blocks[(math "1 + floor($v * 7 / $max)")]
        end
    end
    string join '' -- $out
end

function __torproxy_rate --argument-names n
    if test $n -lt 1024
        echo "$n Б/с"
    else if test $n -lt 1048576
        echo (math -s1 $n / 1024)" КБ/с"
    else
        echo (math -s1 $n / 1048576)" МБ/с"
    end
end

function __torproxy_duration --argument-names s
    printf '%02d:%02d:%02d\n' (math "floor($s / 3600)") (math "floor($s / 60) % 60") (math "$s % 60")
end

# IP спрашиваем в фоне: сайт может отвечать десятки секунд, а панель не должна замирать
function __torproxy_watch_ip_start
    set -g __torproxy_w_ip_pid
    command curl -s --max-time (__torproxy_check_timeout) https://check.torproject.org/api/ip >$__torproxy_w_ip_file 2>/dev/null </dev/null &
    set -g __torproxy_w_ip_pid $last_pid
    disown
end

# Если запрос завершился, забирает ответ. Следующий запрос: через 5 минут, а после неудачи через 5 секунд.
function __torproxy_watch_ip_poll
    if test -n "$__torproxy_w_ip_pid"; and kill -0 $__torproxy_w_ip_pid 2>/dev/null
        return
    end
    set -l now (date +%s)
    if test -n "$__torproxy_w_ip_pid"
        set -g __torproxy_w_ip_pid
        set -l check (command cat $__torproxy_w_ip_file 2>/dev/null)
        set -l ip (echo $check | jq -r '.IP // empty' 2>/dev/null)
        if test -n "$ip"
            set -l cc (__torproxy_control "GETINFO ip-to-country/$ip" 2>/dev/null | string match -rg '^250-ip-to-country/.*=([a-z]{2})$')
            set -g __torproxy_w_ip $ip
            set -g __torproxy_w_ip_cc (string upper -- "$cc")
            set -g __torproxy_w_istor (echo $check | jq -r .IsTor 2>/dev/null)
            set -g __torproxy_w_ip_next (math $now + 300)
        else
            set -g __torproxy_w_ip_next (math $now + 5)
        end
    end
    test $now -ge $__torproxy_w_ip_next; and __torproxy_watch_ip_start
end

# Один кадр панели из состояния __torproxy_w_*
function __torproxy_watch_frame
    set -l width 30
    if set -q COLUMNS; and test "$COLUMNS" -lt 60
        set width 12
    end
    echo "$(__torproxy_color magenta --bold)"'  ╭─ T O R   P R O X Y ─────'"$(__torproxy_color normal) $__torproxy_w_mode"
    if test -z "$__torproxy_w_alive"
        __torproxy_row Tor "$(__torproxy_color red)нет связи$(__torproxy_color normal) (torproxy on)"
    else
        set -l ip "$(__torproxy_color brblack)запрос…$(__torproxy_color normal)"
        if test -n "$__torproxy_w_ip"
            set ip "$__torproxy_w_ip $__torproxy_w_ip_cc"
            if test "$__torproxy_w_istor" = true
                set ip "$ip  $(__torproxy_color green)✔ через Tor$(__torproxy_color normal)"
            else
                set ip "$ip  $(__torproxy_color red)✘ не через Tor$(__torproxy_color normal)"
            end
        end
        __torproxy_row "Внешний IP" $ip
        # в график идут только последние значения, сколько помещается
        set -l from (math "max(1, "(count $__torproxy_w_down)" - $width + 1)")
        set -l down_graph (__torproxy_spark $__torproxy_w_down[$from..-1])
        set -l up_graph (__torproxy_spark $__torproxy_w_up[$from..-1])
        __torproxy_row "↓ "(__torproxy_rate $__torproxy_w_down[-1]) "$(__torproxy_color magenta)$down_graph$(__torproxy_color normal)"
        __torproxy_row "↑ "(__torproxy_rate $__torproxy_w_up[-1]) "$(__torproxy_color cyan)$up_graph$(__torproxy_color normal)"
        __torproxy_row Цепочек "$__torproxy_w_circuits"
        __torproxy_row Работает (__torproxy_duration $__torproxy_w_uptime)
        test -n "$__torproxy_w_chain"; and __torproxy_row Путь $__torproxy_w_chain
    end
    test -n "$__torproxy_w_msg"; and __torproxy_row "" "$(__torproxy_color yellow)$__torproxy_w_msg$(__torproxy_color normal)"
    echo "$(__torproxy_color magenta)"'  ╰─'"$(__torproxy_color normal) q — выход, n — новый IP"
end

# Опрос Tor для следующего кадра
function __torproxy_watch_update
    set -l reply (__torproxy_control 'GETINFO traffic/read' 'GETINFO traffic/written' 'GETINFO uptime' 2>/dev/null)
    set -l read (string match -rg '^250-traffic/read=(\d+)$' -- $reply)
    set -l written (string match -rg '^250-traffic/written=(\d+)$' -- $reply)
    set -l uptime (string match -rg '^250-uptime=(\d+)$' -- $reply)
    if test -z "$read" -o -z "$written"
        set -g __torproxy_w_alive
        # Tor перезапущен: у него новый cookie. Пароль здесь спрашивать нельзя, отсюда sudo -n.
        set -l cookie (sudo -n od -An -v -tx1 $__torproxy_cookie 2>/dev/null | string replace -ra '\s' '' | string join '')
        test -n "$cookie"; and set -g __torproxy_cookie_cache $cookie
        set -g __torproxy_w_prev
        return
    end
    set -g __torproxy_w_alive 1
    set -g __torproxy_w_uptime $uptime
    set -l now (date +%s.%N)
    set -l down 0
    set -l up 0
    if set -q __torproxy_w_prev[3]
        set -l dt (math "max($now - $__torproxy_w_prev[1], 0.05)")
        # счётчики сбрасываются при перезапуске Tor: отрицательной скорости не бывает
        set down (math "floor(max($read - $__torproxy_w_prev[2], 0) / $dt)")
        set up (math "floor(max($written - $__torproxy_w_prev[3], 0) / $dt)")
    end
    set -g __torproxy_w_prev $now $read $written
    set -a __torproxy_w_down $down
    set -a __torproxy_w_up $up
    # храним только то, что видно на экране
    set -q __torproxy_w_down[61]; and set -e __torproxy_w_down[1]
    set -q __torproxy_w_up[61]; and set -e __torproxy_w_up[1]

    # цепочки меняются редко, а запрос дороже: раз в 5 кадров
    set -g __torproxy_w_tick (math $__torproxy_w_tick + 1)
    if test (math "$__torproxy_w_tick % 5") -eq 1
        set -l lines (__torproxy_circuit_lines)
        set -g __torproxy_w_circuits (count (__torproxy_circuit_usable $lines))
        set -l picked (__torproxy_circuit_pick $lines)
        set -g __torproxy_w_chain
        set -q picked[1]; and set -g __torproxy_w_chain (__torproxy_chain $picked[1] "$picked[2]")
        set -g __torproxy_w_mode "$(__torproxy_color yellow)режим неизвестен$(__torproxy_color normal)"
        if set -l rules (sudo -n nft list table inet $__torproxy_table 2>/dev/null)
            set -g __torproxy_w_mode "$(__torproxy_color green)● включён$(__torproxy_color normal)"
            string match -q '*torproxy-strict*' -- "$rules"; and set -g __torproxy_w_mode "$(__torproxy_color green)● включён, строгий$(__torproxy_color normal)"
        else if sudo -n true 2>/dev/null
            set -g __torproxy_w_mode "$(__torproxy_color yellow)● Tor работает, но трафик идёт напрямую$(__torproxy_color normal)"
        end
    end
end

function __torproxy_watch_reset
    set -g __torproxy_w_alive
    set -g __torproxy_w_prev
    set -g __torproxy_w_down
    set -g __torproxy_w_up
    set -g __torproxy_w_tick 0
    set -g __torproxy_w_ip
    set -g __torproxy_w_ip_cc
    set -g __torproxy_w_istor
    set -g __torproxy_w_ip_pid
    set -g __torproxy_w_ip_next 0
    set -g __torproxy_w_circuits 0
    set -g __torproxy_w_chain
    set -g __torproxy_w_msg
    set -g __torproxy_w_mode
end

function __torproxy_watch
    if not systemctl -q is-active $__torproxy_unit
        __torproxy_say red "✘ Tor не запущен (torproxy on)"
        return 1
    end
    # спросить пароль можно только сейчас, пока терминал в обычном режиме
    sudo -v; or return 1
    set -l cookie (sudo od -An -v -tx1 $__torproxy_cookie 2>/dev/null | string replace -ra '\s' '' | string join '')
    if test -z "$cookie"
        __torproxy_say red "✘ Не удалось прочитать $__torproxy_cookie"
        return 1
    end
    set -g __torproxy_cookie_cache $cookie
    __torproxy_watch_reset

    # не терминал: один кадр, без управляющих последовательностей
    if not test -t 0; or not test -t 1
        __torproxy_watch_update
        __torproxy_watch_frame
        set -e __torproxy_cookie_cache
        return
    end

    set -g __torproxy_w_ip_file (mktemp)
    set -l saved (stty -g)
    # -isig: Ctrl+C приходит обычной клавишей, иначе fish прервал бы функцию и терминал остался бы сломан
    if not stty -echo -icanon -isig min 0 time 10 2>/dev/null
        __torproxy_say red "✘ Не удалось настроить терминал"
        rm -f $__torproxy_w_ip_file
        set -e __torproxy_cookie_cache
        return 1
    end
    printf '\e[?1049h\e[?25l\e[2J'
    set -l eol (printf '\e[K')
    while true
        __torproxy_watch_update
        __torproxy_watch_ip_poll
        printf '\e[H'
        __torproxy_watch_frame | string replace -r '$' $eol
        printf '\e[J'
        set -g __torproxy_w_msg
        set -l key (dd bs=1 count=1 2>/dev/null | od -An -tx1 | string trim)
        switch "$key"
            case 71 51 03 1b # q, Q, Ctrl+C, Esc
                break
            case 6e 4e # n, N
                __torproxy_newip >/dev/null 2>&1
                set -g __torproxy_w_msg "Новая цепочка запрошена"
                set -g __torproxy_w_ip_next 0
                set -g __torproxy_w_tick 0
        end
    end
    printf '\e[?25h\e[?1049l'
    stty $saved
    test -n "$__torproxy_w_ip_pid"; and kill $__torproxy_w_ip_pid 2>/dev/null
    rm -f $__torproxy_w_ip_file
    set -e __torproxy_cookie_cache
end

# Сменить страну в работающем Tor сразу: SETCONF и закрыть цепочки через старую страну.
# CLOSECIRCUIT, в отличие от NEWNYM, не ограничен «раз в 10 секунд».
function __torproxy_apply_country --argument-names cc
    set -l conf 'RESETCONF ExitNodes StrictNodes'
    test $cc != any; and set conf "SETCONF ExitNodes=\"{$cc}\" StrictNodes=1"
    set -l excl 'RESETCONF ExcludeExitNodes'
    set -l codes (__torproxy_exclude_current)
    set -q codes[1]; and set excl "SETCONF ExcludeExitNodes=\""(string join , -- '{'$codes'}')"\""
    set -l cmds $conf $excl
    if __torproxy_has_conflux
        if test $cc != any; or set -q codes[1]
            set -a cmds 'SETCONF ConfluxEnabled=0'
        else
            set -a cmds 'RESETCONF ConfluxEnabled'
        end
    end
    set -l reply (__torproxy_control $cmds 'GETINFO circuit-status' 2>/dev/null); or return 1
    # 250 OK на AUTHENTICATE, каждую настройку и GETINFO
    test (count (string match '250 OK' -- $reply)) -ge (math (count $cmds) + 2); or return 1
    # единственная цепочка приходит в одной строке с заголовком 250-circuit-status=
    set -l ids (string replace -r '^250[-+]circuit-status=' '' -- $reply | string match -rg '^(\d+) (?:LAUNCHED|BUILT|GUARD_WAIT|EXTENDED) ')
    set -q ids[1]; and __torproxy_control (string replace -r '^' 'CLOSECIRCUIT ' -- $ids) >/dev/null 2>&1
    return 0
end

# torproxy exclude [ru,by | off]: страны, через которые нельзя выходить в интернет
function __torproxy_exclude --argument-names arg
    set -l current (__torproxy_exclude_current)
    if test -z "$arg"
        set -l shown нет
        set -q current[1]; and set shown (string join ', ' -- $current)
        __torproxy_say yellow "Исключённые страны: $shown"
        echo "  torproxy exclude ru,by   не выходить через эти страны"
        echo "  torproxy exclude off     снять запрет"
        return
    end
    set -l codes
    if test "$arg" != off
        set codes (string lower -- $arg | string split -n ,)
        for c in $codes
            if not string match -qr '^[a-z]{2}$' -- $c
                __torproxy_say red "✘ Нужны двухбуквенные коды через запятую (ru,by) или off"
                return 1
            end
        end
        if contains -- (__torproxy_exit_country) $codes
            __torproxy_say red "✘ Страна "(__torproxy_exit_country)" сейчас выбрана для выхода: сначала torproxy country any"
            return 1
        end
    end
    __torproxy_torrc --exclude="$(string join , -- $codes)"; or return 1
    if set -q codes[1]
        __torproxy_say green "✔ Выход запрещён через: "(string join ', ' -- $codes)
    else
        __torproxy_say yellow "● Запрет на страны снят"
    end
    if systemctl -q is-active $__torproxy_unit
        set -l cc (__torproxy_exit_country)
        contains -- $cc любая; and set cc any
        if not __torproxy_apply_country $cc
            sudo systemctl reload $__torproxy_unit
            __torproxy_say yellow "  Tor применит это к новым соединениям в течение ~10 секунд"
        end
    end
end

# torproxy bridges auto [--no-direct]: пробует способы подключения по очереди и оставляет первый рабочий.
# Правила nftables не трогает: Tor выходит в сеть сам, остальной трафик в это время закрыт, как и был.
function __torproxy_bridges_auto
    argparse no-direct -- $argv; or return 1
    set -l saved (__torproxy_bridges_current)
    set -l was_active 0
    systemctl -q is-active $__torproxy_unit; and set was_active 1

    set -l ways obfs4 snowflake
    set -q _flag_no_direct; or set ways direct $ways
    set -l found
    for way in $ways
        set -l timeout $__torproxy_auto_timeout
        set -l args --no-bridges
        switch $way
            case obfs4
                set args --bridge=$__torproxy_builtin_obfs4
            case snowflake
                set args --bridge=$__torproxy_builtin_snowflake
                # snowflake сначала ищет добровольца, ему нужно больше времени
                set timeout (math $timeout x 2)
        end
        if test $way != direct; and test -z "$(__torproxy_pt_binary $way)"
            __torproxy_say yellow "  $way пропущен: "(__torproxy_pt_hint $way)
            continue
        end
        echo "  Пробую: $way (до $timeout с)"
        __torproxy_torrc $args; or return 1
        set -l started (date '+%Y-%m-%d %H:%M:%S')
        sudo systemctl restart $__torproxy_unit; or continue
        __torproxy_wait_bootstrap $timeout $started
        set -l rc $status
        echo
        if test $rc -eq 0
            set found $way
            break
        end
        test $rc -eq 2; and __torproxy_say red "✘ Не удалось прочитать журнал Tor"
    end

    if test -z "$found"
        # настройки возвращаем: ни один способ не лучше прежнего
        set -l args --no-bridges
        set -q saved[1]; and set args --bridge=$saved
        __torproxy_torrc $args; or return 1
        if test $was_active = 1
            sudo systemctl restart $__torproxy_unit
        else
            sudo systemctl stop $__torproxy_unit
        end
        __torproxy_say red "✘ Ни один способ не подключился. Настройки мостов не изменены."
        echo "  Свои мосты обычно работают лучше: Telegram @GetBridgesBot, затем torproxy bridges add"
        return 1
    end

    __torproxy_say green "✔ Работает: $found. Мосты: "(__torproxy_bridges_summary)
    if test $was_active = 1
        set -l opts
        __torproxy_is_strict; and set opts --strict
        __torproxy_on $opts
    else
        # проба не должна оставлять Tor работающим: режим включает только torproxy on
        sudo systemctl stop $__torproxy_unit
        echo "  Включить Tor-режим: torproxy on"
    end
end

# torproxy bridges [auto | snowflake | obfs4 | add [СТРОКА…] | off]
function __torproxy_bridges --argument-names mode
    set -l lines
    switch "$mode"
        case ''
            __torproxy_say yellow "Мосты сейчас: "(__torproxy_bridges_summary)
            echo "  torproxy bridges auto        подобрать рабочий способ (--no-direct: не пробовать без мостов)"
            echo "  torproxy bridges snowflake   встроенные Snowflake — работают почти везде, но медленнее"
            echo "  torproxy bridges obfs4       встроенные obfs4 — быстрые, но их адреса часто блокируют"
            echo "  torproxy bridges add         свои мосты: Telegram @GetBridgesBot или bridges.torproject.org"
            echo "  torproxy bridges off         без мостов"
            return
        case auto
            __torproxy_bridges_auto $argv[2..]
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
            __torproxy_say red "✘ Неизвестный режим: $mode (auto | snowflake | obfs4 | add | off)"
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
    set -l greeted
    while true
        clear
        if test -z "$greeted"
            __torproxy_splash
            set greeted 1
        else
            __torproxy_banner
        end
        __torproxy_status --quick
        echo
        set -l choice (printf '%s\n' \
            '🟢  Включить Tor-режим' \
            '🔒  Включить в строгом режиме (без локальной сети)' \
            '🔴  Выключить Tor-режим' \
            '🔍  Проверить IP и страну' \
            '🛡️  Проверка утечек' \
            '🩺  Найти неполадку' \
            '🗺️  Схема цепочки' \
            '📊  Живая панель' \
            '🌐  Запустить Tor Browser' \
            '🎯  Запустить одну программу через Tor' \
            '🔄  Новый IP (новая цепочка)' \
            '🌍  Страна выхода' \
            '🚫  Исключить страны' \
            '🔓  Исключения: мимо Tor' \
            '🌉  Мосты (обход блокировок Tor)' \
            '🕵️  Скрыть устройство в локальной сети' \
            '🚀  Защита при загрузке' \
            '🧹  Убрать метаданные из файла' \
            '📜  Журнал Tor (q — назад)' \
            '📖  Руководство пользователя (q — назад)' \
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
            case '*неполадку*'
                __torproxy_doctor
            case '*Схема*'
                __torproxy_circuit
            case '*панель*'
                __torproxy_watch
                continue
            case '*одну программу*'
                read -P '  Команда (например, curl https://example.com): ' -t -l cmd
                # read -t оставляет кавычки в словах
                set -q cmd[1]; and __torproxy_run (string unescape -- $cmd)
            case '*Исключения*'
                __torproxy_allow
                read -P '  Адрес или интерфейс (del АДРЕС — убрать, off — все, Enter — назад): ' -t -l a
                set -q a[1]; and __torproxy_allow $a
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
            case '*Исключить*'
                read -P '  Коды через запятую (ru,by) или off: ' -l codes
                test -n "$codes"; and __torproxy_exclude $codes
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
                    'auto       Подобрать автоматически' \
                    'snowflake  Snowflake — встроенные, работают почти везде' \
                    'obfs4      obfs4 — встроенные, быстрые, но часто заблокированы' \
                    'add        Добавить свои (Telegram @GetBridgesBot)' \
                    'off        Без мостов' \
                    | __torproxy_pick 'мосты')
                set m (string split -f1 ' ' -- $m)
                test -n "$m"; and __torproxy_bridges $m
            case '*Руководство*'
                __torproxy_guide
                continue
            case '*Журнал*'
                # pager вместо -f: Ctrl+C в fish прервал бы всё меню
                sudo journalctl -u $__torproxy_unit -n 300 -e
                continue
            case '*'
                return
        end
        echo
        read -P "$(__torproxy_color brblack)"'  Enter — назад в меню'"$(__torproxy_color normal)" -l __pause
    end
end
