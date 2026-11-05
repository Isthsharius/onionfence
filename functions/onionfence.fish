# Прозрачная маршрутизация всего трафика через Tor (nftables).
# Использование: onionfence [команда]. Краткий список: onionfence help, руководство: onionfence guide.
# Без аргументов — интерактивное меню.
#
# Copyright (C) 2026 Isthsharius
# SPDX-License-Identifier: GPL-3.0-or-later
# Это свободная программа: её можно распространять и изменять на условиях
# GNU General Public License версии 3 или (по вашему выбору) любой более поздней.
# Распространяется БЕЗ КАКИХ-ЛИБО ГАРАНТИЙ. Подробности — в файле LICENSE.

# откуда загружен этот файл: нужно команде install
set -g __onionfence_self (path resolve (status filename))
set -g __onionfence_torrc /etc/tor/torrc
set -g __onionfence_begin '# --- onionfence transparent ---'
set -g __onionfence_end '# --- onionfence end ---'
set -g __onionfence_table onionfence
set -g __onionfence_timeout 90
set -g __onionfence_transport 9040
set -g __onionfence_dnsport 9053 # не 5353: его занимает mDNS systemd-resolved
set -g __onionfence_ctlport 9051
set -g __onionfence_version 0.3.0
set -g __onionfence_socksport 9050 # SocksPort по умолчанию: его не задаём, в Debian он в tor-service-defaults-torrc
set -g __onionfence_boot_unit onionfence-boot
set -g __onionfence_etc /etc/onionfence
set -g __onionfence_systemd_dir /etc/systemd/system
set -g __onionfence_leak_wait 6
# старое имя программы: нужно, чтобы перенести настройки (см. __onionfence_migrate)
set -g __onionfence_old_etc /etc/torproxy
set -g __onionfence_old_dns /etc/torproxy-dns
set -g __onionfence_old_run /run/torproxy
set -g __onionfence_guard_interval 3
set -g __onionfence_auto_timeout 60 # bridges auto: сколько ждать один способ
set -g __onionfence_guard_unit onionfence-guard
set -g __onionfence_rotate_unit onionfence-rotate
set -g __onionfence_aur_helpers paru yay pamac
set -g __onionfence_panic_table onionfence_panic
set -g __onionfence_run /run/onionfence
set -g __onionfence_run_systemd /run/systemd/system
set -g __onionfence_dropin_root /etc/systemd/system
set -g __onionfence_tor_dns_dir /etc/onionfence-dns
set -g __onionfence_resolve_dir /run/systemd/resolve
set -g __onionfence_bridge_dns 9.9.9.9 1.1.1.1 8.8.8.8

# Различия дистрибутивов. Debian/Ubuntu: настоящая служба — tor@default
# (tor.service там пустышка ExecStart=/bin/true), пользователь debian-tor,
# cookie в /run/tor. Аргумент root — префикс путей, нужен только тестам.
function __onionfence_detect --argument-names root
    if test -e "$root/usr/lib/systemd/system/tor@default.service"; or test -e "$root/lib/systemd/system/tor@default.service"
        set -g __onionfence_platform debian
        set -g __onionfence_unit tor@default
        set -g __onionfence_cookie /run/tor/control.authcookie
    else
        set -g __onionfence_platform arch
        set -g __onionfence_unit tor
        set -g __onionfence_cookie /var/lib/tor/control_auth_cookie
    end
    set -g __onionfence_user
    for u in tor debian-tor _tor
        if getent passwd $u >/dev/null
            set -g __onionfence_user $u
            break
        end
    end
end
__onionfence_detect

# Встроенные мосты Tor Browser
# (tor-browser-build: projects/tor-expert-bundle/pt_config.json, ноябрь 2026)
set -g __onionfence_builtin_snowflake \
    'snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn' \
    'snowflake 192.0.2.4:80 8838024498816A039FCBBAB14E6F40A0843051FA fingerprint=8838024498816A039FCBBAB14E6F40A0843051FA url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn'
set -g __onionfence_builtin_obfs4 \
    'obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMrr1BRiAW8IE9U5z27fQaYgOhX1UCmOpg2pFpoMvo6ZgQMzLsaTzzQNTlm7hNcb+Sg iat-mode=0' \
    'obfs4 209.148.46.65:443 74FAD13168806246602538555B5521A0383A1875 cert=ssH+9rP8dG2NLDN2XuFw63hIO/9MNNinLmxQDpVa+7kTOa9/m+tGWT1SmSYpQ9uTBGa6Hw iat-mode=0' \
    'obfs4 146.57.248.225:22 10A6CD36A537FCE513A322361547444B393989F0 cert=K1gDtDAIcUfeLqbstggjIw2rtgIKqdIhUlHp82XRqNSq/mtAjp1BIC9vHKJ2FAEpGssTPw iat-mode=0' \
    'obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMPW3vJxICfkMZNdkRrb63Zhl5j9dW3iRGiCx0A7mPhe5T2EDzQ35+Zw iat-mode=0' \
    'obfs4 51.222.13.177:80 5EDAC3B810E12B01F6FD8050D2FD3E277B289A08 cert=2uplIpLQ0q9+0qMFrK5pkaYRDOe460LL9WHBvatgkuRr/SL31wBOEupaMMJ6koRE6Ld0ew iat-mode=0' \
    'obfs4 212.83.43.95:443 BFE712113A72899AD685764B211FACD30FF52C31 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=1' \
    'obfs4 212.83.43.74:443 39562501228A4D5E27FCA4C0C81A01EE23AE3EE4 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=1'

function onionfence --description 'Весь трафик через Tor: меню и команды (onionfence help)'
    # справке, версии и установке старые настройки не мешают, остальным командам нужно единое состояние
    switch "$argv[1]"
        case help -h --help version --version guide manual install
        case '*'
            __onionfence_migrate; or return 1
    end
    switch "$argv[1]"
        case ''
            __onionfence_menu
        case on
            __onionfence_on $argv[2..]
        case off
            __onionfence_off $argv[2..]
        case browser
            __onionfence_browser
        case run
            __onionfence_run $argv[2..]
        case allow
            __onionfence_allow $argv[2..]
        case boot
            __onionfence_boot $argv[2..]
        case hide
            __onionfence_hide $argv[2..]
        case leaktest
            __onionfence_leaktest
        case doctor
            __onionfence_doctor
        case circuit
            __onionfence_circuit
        case watch
            __onionfence_watch
        case clean
            __onionfence_clean $argv[2..]
        case status
            __onionfence_status
        case newip
            __onionfence_newip $argv[2..]
        case panic
            __onionfence_panic $argv[2..]
        case country
            __onionfence_country $argv[2]
        case exclude
            __onionfence_exclude $argv[2]
        case bridges
            __onionfence_bridges $argv[2..]
        case log
            sudo journalctl -fu $__onionfence_unit
        case version --version
            echo "onionfence $__onionfence_version ($__onionfence_platform: служба $__onionfence_unit, пользователь $__onionfence_user)"
        case help -h --help
            __onionfence_help
        case guide manual
            __onionfence_guide
        case install
            __onionfence_install
        case uninstall
            __onionfence_uninstall $argv[2..]
        case '*'
            __onionfence_help
            return 1
    end
end

# ---------- оформление ----------

# Аналог bash `set -o pipefail` (в fish его нет): вызывать как `__onionfence_pipefail $pipestatus`
# сразу после конвейера. Возвращает код первого упавшего звена, а не только последнего.
function __onionfence_pipefail
    for code in $argv
        test $code -ne 0; and return $code
    end
    return 0
end

# Цвет с учётом соглашения NO_COLOR (no-color.org). Своя функция, а не подмена set_color:
# скрипт загружается в сессию пользователя и не должен менять её поведение.
function __onionfence_color
    test -n "$NO_COLOR"; and return 0
    # единая палитра: рамки и заголовки одного цвета, зелёный, жёлтый и красный только для состояний
    switch "$argv[1]"
        case frame
            set_color magenta
        case title
            set_color --bold magenta
        case dim
            set_color brblack
        case '*'
            set_color $argv
    end
end

function __onionfence_say --argument-names color text
    echo "$(__onionfence_color $color)  $text$(__onionfence_color normal)"
end

function __onionfence_banner
    # внутренняя ширина 30; эмодзи занимает две клетки, поэтому строка записана вручную
    set -l version_line (printf '%-30s' "           v$__onionfence_version")
    __onionfence_color title
    echo '   ╭──────────────────────────────╮'
    echo '   │     🧅  O N I O N F E N C E  │'
    echo "   │$version_line│"
    echo '   ╰──────────────────────────────╯'
    __onionfence_color normal
end

# Приветствие при запуске меню. В узком окне картинка не поместится: обычный заголовок.
function __onionfence_splash
    if set -q COLUMNS; and test "$COLUMNS" -lt 60
        __onionfence_banner
        return
    end
    # луковица проявляется слоями, только в настоящем терминале; отключается ONIONFENCE_NO_ANIMATION=1
    set -l art (__onionfence_splash_art)
    if test -t 1; and test -z "$ONIONFENCE_NO_ANIMATION" -a -z "$NO_COLOR"
        for line in $art
            echo $line
            sleep 0.05
        end
    else
        printf '%s\n' $art
    end
end

function __onionfence_splash_art
    # «$(…)» в кавычках: без цвета цветовая команда пуста, а пустой список стёр бы всю строку
    set -l stem "$(__onionfence_color 7bc96f)"
    set -l skin "$(__onionfence_color --bold c792ea)"
    set -l core "$(__onionfence_color 9d6bd6)"
    set -l name "$(__onionfence_color --bold brwhite)"
    set -l dim "$(__onionfence_color dim)"
    set -l off "$(__onionfence_color normal)"
    echo
    echo $stem'              )'$off
    echo $stem'             ('$off
    echo $skin'            .-"-.'$off
    echo $skin".'  "$core'|'$skin"  '."$off | string replace -r '^' '          '
    echo $skin'         /   '$core'/|\\'$skin'   \\'$off"       $name"'O N I O N F E N C E'$off
    echo $skin'        |   '$core'| | |'$skin'   |'$off"      $dim"'───────────────────'$off
    echo $skin'        |   '$core'| | |'$skin'   |'$off"      Весь трафик устройства через TOR"
    echo $skin'         \\   '$core'\\|/'$skin'   /'$off"       $dim"v$__onionfence_version$off
    echo $skin"          '._"$core'\\|/'$skin"_.'"$off
    echo
end

# Понятное название этапа подключения по метке из журнала Tor
function __onionfence_stage --argument-names tag
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

# Полоса без управляющих символов: для панели и итогов
function __onionfence_bar_text --argument-names pct width
    test -n "$width"; or set width 20
    set -l n (math "floor($pct * $width / 100)")
    printf '%s%s%s%s%s' "$(__onionfence_color frame)" "$(string repeat -n $n █)" \
        "$(__onionfence_color dim)" "$(string repeat -n (math $width - $n) ░)" "$(__onionfence_color normal)"
end

# Итог проверки: полоса и «9 из 9»
function __onionfence_summary --argument-names ok total
    test $total -gt 0; or return 0
    set -l bar (__onionfence_bar_text (math "floor($ok * 100 / $total)"))
    echo "  $bar $ok из $total проверок в порядке"
end

function __onionfence_bar --argument-names pct stage
    set -l w 30
    set -l n (math "floor($pct * $w / 100)")
    printf '\r  %s%s%s%s%s %3d%%' "$(__onionfence_color frame)" "$(string repeat -n $n █)" \
        "$(__onionfence_color dim)" "$(string repeat -n (math $w - $n) ░)" "$(__onionfence_color normal)" $pct
    # \e[K стирает хвост прошлой, более длинной подписи
    test -n "$stage"; and printf '  %s%s%s\e[K' "$(__onionfence_color dim)" $stage "$(__onionfence_color normal)"
    return 0
end

function __onionfence_row --argument-names label value
    printf '  %s│%s %-16s %s\n' "$(__onionfence_color frame)" "$(__onionfence_color normal)" $label $value
end

function __onionfence_help
    __onionfence_banner
    echo
    echo "  $(__onionfence_color --bold)onionfence$(__onionfence_color normal)                 интерактивное меню"
    echo "  $(__onionfence_color --bold)onionfence on$(__onionfence_color normal)              включить: весь трафик через Tor (--strict: и без доступа к локальной сети)"
    echo "  $(__onionfence_color --bold)onionfence off$(__onionfence_color normal)             выключить: обычный интернет (-y: без вопроса)"
    echo "  $(__onionfence_color --bold)onionfence status$(__onionfence_color normal)          статус, внешний IP и страна"
    echo "  $(__onionfence_color --bold)onionfence leaktest$(__onionfence_color normal)        проверка утечек: IP, DNS, UDP, IPv6, ICMP"
    echo "  $(__onionfence_color --bold)onionfence doctor$(__onionfence_color normal)          найти неполадку: зависимости, настройки, порты, часы"
    echo "  $(__onionfence_color --bold)onionfence circuit$(__onionfence_color normal)         схема цепочки: через какие страны идёт трафик"
    echo "  $(__onionfence_color --bold)onionfence watch$(__onionfence_color normal)           живая панель: IP, скорость, цепочка"
    echo "  $(__onionfence_color --bold)onionfence run программа$(__onionfence_color normal)   только эта программа через Tor; --fresh — с чистым временным домашним каталогом"
    echo "  $(__onionfence_color --bold)onionfence allow$(__onionfence_color normal)           исключения: адреса и интерфейсы мимо Tor (ослабляет защиту)"
    echo "  $(__onionfence_color --bold)onionfence browser$(__onionfence_color normal)         Tor Browser через системный Tor"
    echo "  $(__onionfence_color --bold)onionfence boot$(__onionfence_color normal)            защита с момента загрузки: on [--strict] | off"
    echo "  $(__onionfence_color --bold)onionfence hide$(__onionfence_color normal)            случайный MAC и скрытие имени компьютера: on | off"
    echo "  $(__onionfence_color --bold)onionfence clean файл$(__onionfence_color normal)      убрать метаданные из файлов (mat2)"
    echo "  $(__onionfence_color --bold)onionfence newip$(__onionfence_color normal)           новая цепочка Tor; --every 10m — менять по таймеру, off — снять"
    echo "  $(__onionfence_color --bold)onionfence panic$(__onionfence_color normal)           экстренно закрыть сеть и программы; panic off — снять"
    echo "  $(__onionfence_color --bold)onionfence country de$(__onionfence_color normal)      страна выхода (de, nl, us…); 'any' — любая"
    echo "  $(__onionfence_color --bold)onionfence exclude ru,by$(__onionfence_color normal)   не выходить через эти страны; 'off' — снять запрет"
    echo "  $(__onionfence_color --bold)onionfence bridges$(__onionfence_color normal)         мосты: auto | snowflake | obfs4 | add | off"
    echo "  $(__onionfence_color --bold)onionfence log$(__onionfence_color normal)             журнал Tor в реальном времени"
    echo "  $(__onionfence_color --bold)onionfence install$(__onionfence_color normal)         установить этот файл для текущего пользователя"
    echo "  $(__onionfence_color --bold)onionfence uninstall$(__onionfence_color normal)       удалить программу и вернуть настройки (-y: без вопроса)"
    echo "  $(__onionfence_color --bold)onionfence guide$(__onionfence_color normal)           руководство пользователя"
    echo "  $(__onionfence_color --bold)onionfence version$(__onionfence_color normal)         версия и платформа (Arch / Debian, Ubuntu)"
end

# ---------- torrc ----------

# Наш блок в torrc между маркерами begin/end. Переписывается целиком при каждом вызове,
# чтобы исправления портов доходили до старых установок.
# Без опций страна и мосты сохраняются; --country КОД|any, --bridge СТРОКА (можно несколько), --no-bridges.
function __onionfence_torrc
    argparse 'country=' 'exclude=' 'bridge=+' no-bridges 'allow=' -- $argv; or return 1
    set -l torrc $__onionfence_torrc
    set -l country (__onionfence_exit_country)
    set -q _flag_country; and set country $_flag_country
    set -l exclude (__onionfence_exclude_current)
    set -q _flag_exclude; and set exclude (string split -n , -- $_flag_exclude)
    set -l allow (__onionfence_allow_current)
    set -q _flag_allow; and set allow (string split -n , -- $_flag_allow)
    set -l bridges (__onionfence_bridges_current)
    set -q _flag_no_bridges; and set bridges
    set -q _flag_bridge; and set bridges $_flag_bridge

    # каждому типу мостов нужна программа-транспорт; проверяем до того, как трогать torrc
    set -l bridge_lines
    if set -q bridges[1]
        set bridge_lines 'UseBridges 1'
        for tr in (string match -rg '^([a-z0-9_]+) ' -- $bridges | sort -u)
            set -l bin (__onionfence_pt_binary $tr)
            if test -z "$bin"
                __onionfence_say red "✘ Для мостов $tr нет программы-транспорта: "(__onionfence_pt_hint $tr)
                return 1
            end
            set -a bridge_lines "ClientTransportPlugin $tr exec $bin"
        end
        set -a bridge_lines (string replace -r '^' 'Bridge ' -- $bridges)
    end

    test -e $torrc.bak-onionfence; or sudo cp $torrc $torrc.bak-onionfence
    if sudo grep -qxF -- $__onionfence_end $torrc
        sudo sed -i "/^$__onionfence_begin\$/,/^$__onionfence_end\$/d" $torrc
    else if sudo grep -qxF -- $__onionfence_begin $torrc
        # первая версия блока: без end-маркера, 4 строки
        sudo sed -i "/^$__onionfence_begin\$/,+4d" $torrc
    end

    set -l exit_lines
    if not contains -- $country any любая
        set exit_lines "ExitNodes {$country}" 'StrictNodes 1'
    end
    if set -q exclude[1]
        set -a exit_lines "ExcludeExitNodes "(string join , -- '{'$exclude'}')
    end
    # Conflux строит запасные цепочки через выходы вне заданных стран (см. __onionfence_has_conflux)
    if set -q exit_lines[1]; and __onionfence_has_conflux
        set -a exit_lines 'ConfluxEnabled 0'
    end
    printf '%s\n' \
        $__onionfence_begin \
        'VirtualAddrNetworkIPv4 10.192.0.0/10' \
        'AutomapHostsOnResolve 1' \
        "TransPort 127.0.0.1:$__onionfence_transport IsolateClientAddr IsolateClientProtocol IsolateDestAddr IsolateDestPort" \
        "DNSPort 127.0.0.1:$__onionfence_dnsport" \
        "ControlPort 127.0.0.1:$__onionfence_ctlport" \
        'CookieAuthentication 1' \
        $exit_lines \
        $bridge_lines \
        (string replace -r '^' '# onionfence-allow ' -- $allow) \
        $__onionfence_end \
        | sudo tee -a $torrc >/dev/null
    __onionfence_pipefail $pipestatus; or begin
        __onionfence_say red "✘ Не удалось записать настройки в $torrc"
        return 1
    end
    __onionfence_tor_dropin_sync
end

# ---------- настройки службы Tor ----------
#
# 1. Транспорту мостов нужен DNS: Snowflake ищет брокера по имени. Пока правила включены, DNS системы идёт
#    в Tor, а Tor ждёт мост: замкнутый круг. Поэтому службе Tor даём свой resolv.conf и прячем сокет
#    systemd-resolved, через который glibc иначе пошла бы в тот же круг. Правила выпускают пользователя Tor
#    напрямую, а всем остальным программам DNS по-прежнему доступен только через Tor.
# 2. При загрузке Tor не должен стартовать раньше сети: после неудачной первой попытки Snowflake
#    долго не пробует снова.
function __onionfence_tor_dropin_path
    echo $__onionfence_dropin_root/$__onionfence_unit.service.d/onionfence.conf
end

function __onionfence_tor_dropin_text --argument-names bridges boot
    if test "$boot" = 1
        printf '%s\n' \
            '[Unit]' \
            'Wants=network-online.target NetworkManager-wait-online.service' \
            'After=network-online.target NetworkManager-wait-online.service' \
            ''
    end
    if test "$bridges" = 1
        echo '[Service]'
        # если resolv.conf ссылается внутрь каталога resolved, подмены каталога достаточно
        if not string match -q "$__onionfence_resolve_dir/*" -- (path resolve /etc/resolv.conf)
            echo "BindReadOnlyPaths=$__onionfence_tor_dns_dir/resolv.conf:/etc/resolv.conf"
        end
        test -d $__onionfence_resolve_dir; and echo "BindReadOnlyPaths=$__onionfence_tor_dns_dir/resolve:$__onionfence_resolve_dir"
    end
    return 0
end

function __onionfence_tor_dropin_remove
    set -l file (__onionfence_tor_dropin_path)
    sudo test -e $file; or return 0
    sudo rm -f $file
    sudo rmdir (path dirname $file) 2>/dev/null
    sudo rm -f $__onionfence_tor_dns_dir/resolv.conf $__onionfence_tor_dns_dir/resolve/resolv.conf $__onionfence_tor_dns_dir/resolve/stub-resolv.conf
    sudo rmdir $__onionfence_tor_dns_dir/resolve $__onionfence_tor_dns_dir 2>/dev/null
    sudo systemctl daemon-reload
    return 0
end

# Приводит настройки службы Tor в соответствие с мостами и защитой при загрузке
function __onionfence_tor_dropin_sync
    set -l bridges 0
    test -n "$(__onionfence_bridges_current)"; and set bridges 1
    set -l boot 0
    test -e $__onionfence_systemd_dir/$__onionfence_boot_unit.service; and set boot 1
    if test $bridges = 0 -a $boot = 0
        __onionfence_tor_dropin_remove
        return
    end

    set -l text (__onionfence_tor_dropin_text $bridges $boot | string collect)
    set -l file (__onionfence_tor_dropin_path)
    set -l ok 1
    if test $bridges = 1
        set -l dns (printf 'nameserver %s\n' $__onionfence_bridge_dns; echo 'options timeout:3 attempts:2')
        sudo mkdir -p $__onionfence_tor_dns_dir/resolve; or set ok 0
        printf '%s\n' $dns | sudo tee $__onionfence_tor_dns_dir/resolv.conf $__onionfence_tor_dns_dir/resolve/resolv.conf $__onionfence_tor_dns_dir/resolve/stub-resolv.conf >/dev/null
        __onionfence_pipefail $pipestatus; or set ok 0
    end
    if test "$text" != "$(command cat $file 2>/dev/null | string collect)"
        sudo mkdir -p (path dirname $file); or set ok 0
        printf '%s\n' $text | sudo tee $file >/dev/null
        __onionfence_pipefail $pipestatus; or set ok 0
        sudo systemctl daemon-reload; or set ok 0
    end
    if test $ok = 0
        __onionfence_say yellow "  ⚠ Не удалось настроить службу Tor: при включённых правилах мосты могут не подключиться"
    end
    return 0
end

# Есть ли в этой версии Tor настройка ConfluxEnabled (с 0.4.8). Старый Tor с ней не запустится.
function __onionfence_has_conflux
    command tor --list-torrc-options 2>/dev/null | string match -q ConfluxEnabled
end

# Читает строки нашего блока torrc. Файл обычно доступен всем: sudo только если иначе нельзя,
# чтобы меню и быстрый статус не спрашивали пароль.
function __onionfence_torrc_sed --argument-names expr
    set -l range "/^$__onionfence_begin\$/,/^$__onionfence_end\$/"
    if test -r $__onionfence_torrc
        command sed -n "$range$expr" $__onionfence_torrc
    else
        sudo sed -n "$range$expr" $__onionfence_torrc
    end
end

function __onionfence_exit_country
    set -l c (__onionfence_torrc_sed "s/^ExitNodes {\(.*\)}/\1/p")
    test -n "$c"; and echo $c; or echo любая
end

# Коды исключённых стран, по одному в строке
function __onionfence_exclude_current
    __onionfence_torrc_sed "s/^ExcludeExitNodes //p" \
        | string replace -ra '[{}]' '' | string split -n ,
end

# Строки мостов из нашего блока (без слова Bridge)
function __onionfence_bridges_current
    __onionfence_torrc_sed "s/^Bridge //p"
end

# Кратко для статуса: «нет» или «snowflake ×2, obfs4 ×1»
function __onionfence_bridges_summary
    set -l bridges (__onionfence_bridges_current)
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
function __onionfence_pt_binary --argument-names transport
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
    test "$__onionfence_platform" = debian; and set candidates $candidates[-1..1]
    for c in $candidates
        command -s $c; and return
    end
    return 1
end

# Как установить транспорт для мостов этого типа
function __onionfence_pt_hint --argument-names transport
    if test "$__onionfence_platform" = debian
        switch $transport
            case obfs4 meek_lite
                echo "sudo apt install obfs4proxy"
            case snowflake
                echo "sudo apt install snowflake-client"
            case '*'
                echo "в стабильных Debian/Ubuntu пакета для $transport нет, используйте obfs4 или snowflake"
        end
    else
        # lyrebird в AUR: на Manjaro его обычно ставит pamac, на Arch — paru или yay
        for helper in $__onionfence_aur_helpers
            if type -q $helper
                switch $helper
                    case pamac
                        echo "pamac build lyrebird-proxy"
                    case '*'
                        echo "$helper -S lyrebird-proxy"
                end
                return
            end
        end
        echo "paru -S lyrebird-proxy"
    end
end

# Строка моста: [транспорт] IP:порт [параметры]; префикс «Bridge » допускается
function __onionfence_bridge_normalize --argument-names line
    set line (string trim -- $line | string replace -r '^Bridge\s+' '' | string replace -ra '\s+' ' ')
    string match -qr '^([a-z0-9_]+ )?(\d{1,3}(\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]):\d{1,5}( [^ #]+)*$' -- $line
    or return 1
    echo $line
end

# ---------- команды ----------

# Правила nftables: весь TCP -> TransPort, DNS -> DNSPort, остальное блокируется.
# Аргумент strict: локальная сеть тоже закрыта, кроме DHCP.
function __onionfence_rules --argument-names mode
    set -l tor_uid (id -u $__onionfence_user)
    set -l lan '{ 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }'
    set -l direct $lan
    set -l lo_rule 'oifname lo accept'
    set -l lan_rule "ip daddr $lan accept"
    # исключения пользователя: DNS к ним всё равно идёт через Tor (правила DNS стоят раньше)
    set -l allow_nat
    set -l allow_filter
    for a in (__onionfence_allow_current)
        if string match -qr '^[0-9.]+(/\d+)?$' -- $a
            set -a allow_nat "ip daddr $a return comment \"onionfence-allow\""
            set -a allow_filter "ip daddr $a accept comment \"onionfence-allow\""
        else
            set -a allow_nat "oifname \"$a\" return comment \"onionfence-allow\""
            set -a allow_filter "oifname \"$a\" accept comment \"onionfence-allow\""
        end
    end
    if test "$mode" = strict
        set direct 127.0.0.0/8
        set lo_rule 'oifname lo accept comment "onionfence-strict"'
        # после redirect файрвол ещё видит прежний интерфейс, поэтому одного oifname lo мало
        set lan_rule "ip daddr $direct accept"
    end
    echo "
table inet $__onionfence_table {
    chain nat_out {
        type nat hook output priority -100; policy accept;
        meta skuid $tor_uid return
        meta nfproto ipv4 udp dport 53 redirect to :$__onionfence_dnsport
        meta nfproto ipv4 tcp dport 53 redirect to :$__onionfence_transport
        meta nfproto ipv4 ip daddr 10.192.0.0/10 meta l4proto tcp redirect to :$__onionfence_transport
        $(string join \n -- $allow_nat)
        ip daddr $direct return
        meta nfproto ipv4 meta l4proto tcp redirect to :$__onionfence_transport
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

function __onionfence_is_strict
    sudo nft list table inet $__onionfence_table 2>/dev/null | string match -q '*onionfence-strict*'
end

# Ждёт 100% в журнале Tor, рисуя полосу. Код: 0 — подключился, 1 — не успел, 2 — журнал не читается.
function __onionfence_wait_bootstrap --argument-names timeout started
    set -l pct 0
    set -l shown -1
    for i in (seq $timeout)
        set -l line (sudo journalctl -u $__onionfence_unit --since "$started" --no-pager -q | string match -r 'Bootstrapped \d+%.*' | tail -1)
        # string match без совпадений (Tor ещё не начал) — не ошибка, поэтому проверяем только journalctl
        test $pipestatus[1] -eq 0; or return 2
        set -l p (string match -rg 'Bootstrapped (\d+)%' -- "$line")
        test -n "$p"; and set pct $p
        set -l tag (string match -rg 'Bootstrapped \d+% \((\w+)\)' -- "$line")
        # вне терминала \\r не работает: каждый повтор был бы лишним мусором в журнале
        if test -t 1; or test $pct -ne $shown
            # подпись только в терминале: вне его достаточно процентов
            set -l stage
            test -t 1; and set stage (__onionfence_stage "$tag")
            __onionfence_bar $pct "$stage"
            set shown $pct
        end
        test $pct -eq 100; and return 0
        sleep 1
    end
    return 1
end

function __onionfence_on
    argparse strict -- $argv; or return 1
    set -l mode
    set -q _flag_strict; and set mode strict
    if __onionfence_panic_active
        __onionfence_say red "✘ Сейчас действует экстренное отключение: сначала onionfence panic off"
        return 1
    end
    __onionfence_banner
    if test -z "$__onionfence_user"
        __onionfence_say red "✘ Tor не установлен (нет пользователя tor/debian-tor): sudo pacman -S tor или sudo apt install tor"
        return 1
    end
    __onionfence_torrc; or return 1
    __onionfence_clock_warn

    # через мосты (особенно snowflake) Tor подключается заметно дольше
    set -l timeout $__onionfence_timeout
    set -l bridges (__onionfence_bridges_current)
    set -q bridges[1]; and set timeout (math $timeout x 2)

    set -l started (date '+%Y-%m-%d %H:%M:%S')
    sudo systemctl restart $__onionfence_unit; or begin
        __onionfence_on_failed "Tor не запустился" $started
        return 1
    end
    echo "  Подключение к сети Tor..."
    __onionfence_wait_bootstrap $timeout $started
    set -l wait_rc $status
    echo
    if test $wait_rc -eq 2
        __onionfence_on_failed "Не удалось прочитать журнал Tor"
        return 1
    else if test $wait_rc -ne 0
        __onionfence_on_failed "Tor не подключился за $timeout секунд" $started
        return 1
    end

    # сторож не должен вернуть старую таблицу между удалением и созданием новой
    __onionfence_guard_stop
    sudo nft delete table inet $__onionfence_table 2>/dev/null
    __onionfence_rules $mode | sudo nft -f -; or begin
        __onionfence_say red "✘ Ошибка применения правил nftables"
        return 1
    end
    __onionfence_guard_start $mode
    resolvectl flush-caches 2>/dev/null

    __onionfence_say green "✔ Tor-режим ВКЛЮЧЁН. Перезапусти браузер и программы, открытые до включения."
    __onionfence_status
end

# Tor не поднялся. Если режим уже был включён, правила остаются: интернет закрыт, но без утечек.
function __onionfence_on_failed --argument-names reason started
    echo
    # журнал читаем до остановки: так в выборку не попадут сообщения о завершении
    set -l why
    if test -n "$started"
        set why (__onionfence_explain (sudo journalctl -u $__onionfence_unit --since "$started" --no-pager -q 2>/dev/null))
    end
    sudo systemctl stop $__onionfence_unit
    if sudo nft list table inet $__onionfence_table >/dev/null 2>&1
        __onionfence_say red "✘ $reason. Tor-режим остаётся включённым, поэтому интернет закрыт (onionfence off — вернуть обычный)"
    else
        __onionfence_say red "✘ $reason, правила НЕ применены (onionfence log)"
    end
    test -n "$why"; and __onionfence_say yellow "  Вероятная причина: $why"
end

# Переводит сообщения Tor в понятную причину. Порядок важен: сначала то, что не даёт Tor стартовать.
function __onionfence_explain
    if string match -qir 'Reading config failed|Failed to parse/validate config' -- $argv
        echo "ошибка в настройках Tor, подробности покажет onionfence doctor"
    else if string match -qir 'Could not bind|Address already in use' -- $argv
        echo "порт Tor занят другой программой, какой именно, покажет onionfence doctor"
    else if string match -qir 'Permission denied|apparmor' -- $argv
        echo "Tor не хватило прав (часто это AppArmor или права на каталог данных)"
    else if string match -qir 'broker failure.*(?:lookup|name resolution)' -- $argv
        echo "мост не смог найти своего брокера по имени: проверь сеть или выбери другие мосты (onionfence bridges auto)"
    else if string match -qir 'Could not launch managed proxy|Managed proxy .*(?:fail|exit|terminat)|Pluggable Transport process terminated' -- $argv
        echo "не запустилась программа-транспорт для мостов"
    else if string match -qir 'clock|skew|not yet valid' -- $argv
        echo "неверные часы компьютера: исправь время и включи снова"
    else if string match -qir 'Network is unreachable|No route to host' -- $argv
        echo "нет подключения к сети"
    else if string match -qir 'Bootstrapped|Problem bootstrapping' -- $argv
        if test -n "$(__onionfence_bridges_current)"
            echo "мосты не отвечают: попробуй onionfence bridges auto или свои мосты от @GetBridgesBot"
        else
            echo "Tor, похоже, заблокирован в этой сети: попробуй onionfence bridges auto"
        end
    end
end

# Предупреждает, если система считает часы несинхронизированными: при большой ошибке Tor не подключится,
# а в Tor-режиме синхронизация по NTP заблокирована.
function __onionfence_clock_warn
    command -q timedatectl; or return 0
    if test "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = no
        __onionfence_say yellow "  ⚠ Часы не синхронизированы. Если Tor не подключится, сначала проверь время: timedatectl"
    end
end

# ---------- сторож правил ----------

# Сторож возвращает таблицу, если её стёрли (например, nftables.service делает flush ruleset):
# без него трафик молча пошёл бы напрямую, а пользователь считал бы, что он в Tor.
function __onionfence_guard_unit_text
    set -l nft (command -s nft; or echo /usr/bin/nft)
    set -l runtime $__onionfence_run/rules.nft
    set -l persistent $__onionfence_etc/rules.nft
    printf '%s\n' \
        '[Unit]' \
        'Description=onionfence: restore firewall rules if they are flushed' \
        'DefaultDependencies=no' \
        "After=local-fs.target $__onionfence_boot_unit.service" \
        'Before=shutdown.target' \
        'Conflicts=shutdown.target' \
        '' \
        '[Service]' \
        "ExecStart=/bin/sh -c 'while sleep $__onionfence_guard_interval; do $nft list table inet $__onionfence_table >/dev/null 2>&1 && continue; if [ -r $runtime ]; then f=$runtime; else f=$persistent; fi; $nft -f \$\$f && echo restored rules from \$\$f; done'" \
        'Restart=on-failure' \
        '' \
        '[Install]' \
        'WantedBy=sysinit.target'
end

# Запоминает действующие правила и запускает сторожа. Сбой не критичен: режим уже включён.
function __onionfence_guard_start --argument-names mode
    set -l ok 1
    sudo mkdir -p $__onionfence_run; or set ok 0
    __onionfence_rules $mode | sudo tee $__onionfence_run/rules.nft >/dev/null
    __onionfence_pipefail $pipestatus; or set ok 0
    __onionfence_guard_unit_text | sudo tee $__onionfence_run_systemd/$__onionfence_guard_unit.service >/dev/null
    __onionfence_pipefail $pipestatus; or set ok 0
    sudo systemctl daemon-reload; or set ok 0
    sudo systemctl start $__onionfence_guard_unit; or set ok 0
    if test $ok = 0
        __onionfence_say yellow "  ⚠ Не удалось запустить сторожа: если правила кто-то сотрёт, они не вернутся сами"
    end
end

function __onionfence_guard_stop
    sudo systemctl stop $__onionfence_guard_unit 2>/dev/null
    sudo rm -f $__onionfence_run/rules.nft $__onionfence_run_systemd/$__onionfence_guard_unit.service
    true
end

# Имена программ с соединениями наружу (свои процессы: чужие ss без root не называет).
# В Tor-режиме все такие соединения идут через Tor.
function __onionfence_online_apps
    for line in (ss -Htnp state established 2>/dev/null)
        set -l peer (string split -n ' ' -- $line)[4]
        string match -qr '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|\[::1\]|\[::ffff:127\.|\[fe80)' -- $peer; and continue
        string match -rg 'users:\(\("([^"]+)"' -- $line
    end | sort -u | string match -v -r '^(tor|lyrebird|obfs4proxy|snowflake-client)$'
end

function __onionfence_off
    argparse y/yes -- $argv; or return 1
    # Программа, которая переживёт выключение, продолжит ту же сессию уже с настоящего IP
    # и свяжет его с Tor. Поэтому предупреждаем до снятия правил, а не после.
    if sudo nft list table inet $__onionfence_table >/dev/null 2>&1
        set -l apps (__onionfence_online_apps)
        if set -q apps[1]
            __onionfence_say yellow "⚠ Через Tor сейчас работают: "(string join ', ' -- $apps)
            echo "  Останутся открытыми — продолжат те же сессии (куки, аккаунты) уже с настоящего IP"
            echo "  и свяжут его с тем, что ты делал через Tor. Лучше закрыть их до выключения."
            if not set -q _flag_yes; and isatty stdin
                read -P '  Выключить всё равно? [y/N] ' -l answer
                if not string match -qri '^[yд]' -- "$answer"
                    __onionfence_say yellow "Отменено, Tor-режим остаётся включённым"
                    return 1
                end
            end
        end
    end
    __onionfence_guard_stop
    sudo systemctl stop $__onionfence_rotate_unit 2>/dev/null
    sudo systemctl daemon-reload
    sudo nft delete table inet $__onionfence_panic_table 2>/dev/null
    sudo nft delete table inet $__onionfence_table 2>/dev/null
    sudo systemctl stop $__onionfence_unit
    resolvectl flush-caches 2>/dev/null
    __onionfence_say yellow "● Tor-режим ВЫКЛЮЧЕН, обычный интернет восстановлен."
    if systemctl -q is-enabled $__onionfence_boot_unit 2>/dev/null
        __onionfence_say yellow "  При следующей загрузке режим включится снова (onionfence boot off — отключить)"
    end
end

# ---------- исключения ----------

function __onionfence_allow_current
    __onionfence_torrc_sed "s/^# onionfence-allow //p"
end

# IPv4-адрес или сеть, которую разумно пропускать мимо Tor. Слишком широкая сеть отключила бы защиту.
function __onionfence_allow_valid_ip --argument-names value
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
function __onionfence_allow_apply
    if sudo nft list table inet $__onionfence_table >/dev/null 2>&1
        set -l mode
        __onionfence_is_strict; and set mode strict
        __onionfence_guard_stop
        sudo nft delete table inet $__onionfence_table 2>/dev/null
        __onionfence_rules $mode | sudo nft -f -; or begin
            __onionfence_say red "✘ Ошибка применения правил nftables: режим снят, включи заново (onionfence on)"
            return 1
        end
        __onionfence_guard_start $mode
    end
    if sudo test -e $__onionfence_etc/rules.nft
        set -l mode
        sudo grep -q onionfence-strict $__onionfence_etc/rules.nft; and set mode strict
        __onionfence_rules $mode | sudo tee $__onionfence_etc/rules.nft >/dev/null
    end
    return 0
end

# onionfence allow [АДРЕС | ИНТЕРФЕЙС | del ЗНАЧЕНИЕ | off]
function __onionfence_allow --argument-names arg value
    set -l current (__onionfence_allow_current)
    switch "$arg"
        case ''
            if set -q current[1]
                __onionfence_say yellow "⚠ Мимо Tor идёт: "(string join ', ' -- $current)
            else
                __onionfence_say green "Исключений нет: весь трафик через Tor"
            end
            echo "  onionfence allow 100.64.0.0/10   адрес или сеть мимо Tor"
            echo "  onionfence allow tailscale0      сетевой интерфейс мимо Tor"
            echo "  onionfence allow del АДРЕС       убрать одно исключение"
            echo "  onionfence allow off             убрать все"
            return
        case off
            __onionfence_torrc --allow=; or return 1
            __onionfence_allow_apply; or return 1
            __onionfence_say green "✔ Исключений нет: весь трафик через Tor"
            return
        case del
            if not contains -- "$value" $current
                __onionfence_say red "✘ Такого исключения нет: $value"
                return 1
            end
            set -l left (string match -v -- "$value" $current)
            __onionfence_torrc --allow="$(string join , -- $left)"; or return 1
            __onionfence_allow_apply; or return 1
            __onionfence_say green "✔ Убрано: $value"
            return
    end

    if string match -qr '^[0-9.]+(/\d+)?$' -- $arg
        if not __onionfence_allow_valid_ip $arg
            __onionfence_say red "✘ Неверный адрес или слишком широкая сеть: $arg (нужна маска от /8 до /32)"
            return 1
        end
    else if not string match -qr '^[A-Za-z][A-Za-z0-9_.-]{0,14}$' -- $arg
        __onionfence_say red "✘ Не похоже на адрес или интерфейс: $arg"
        return 1
    else
        # через этот интерфейс идёт весь интернет: исключение отключило бы защиту целиком
        if contains -- $arg lo (ip route show default 2>/dev/null | string match -rg ' dev (\S+)')
            __onionfence_say red "✘ Через $arg идёт весь трафик: такое исключение отключило бы защиту"
            return 1
        end
        if command -q ip; and not ip link show $arg >/dev/null 2>&1
            __onionfence_say yellow "  ⚠ Интерфейса $arg сейчас нет: исключение сработает, когда он появится"
        end
    end
    if contains -- $arg $current
        __onionfence_say yellow "Уже в исключениях: $arg"
        return
    end
    __onionfence_torrc --allow="$(string join , -- $current $arg)"; or return 1
    __onionfence_allow_apply; or return 1
    __onionfence_say yellow "⚠ Теперь мимо Tor идёт: "(string join ', ' -- $current $arg)
    echo "  Этот трафик идёт напрямую, с твоего настоящего IP. DNS-запросы по-прежнему через Tor."
end

# ---------- одна программа через Tor ----------

set -g __onionfence_ns onionfence-run
set -g __onionfence_ns_host ofrun0
set -g __onionfence_ns_peer ofrun1
set -g __onionfence_ns_host_ip 172.31.250.1 # не 10.192.0.0/10: эту сеть Tor использует для DNS-подмены
set -g __onionfence_ns_peer_ip 172.31.250.2

# Правила хоста для пространства программы: из него есть только путь в Tor, всё прочее отбрасывается.
# route_localnet разрешает перенаправлять в 127.0.0.1, поэтому Tor не нужно слушать новый адрес.
function __onionfence_run_rules
    set -l h $__onionfence_ns_host
    echo "
table inet onionfence_run {
    chain nat_pre {
        type nat hook prerouting priority -100; policy accept;
        iifname \"$h\" meta nfproto ipv4 udp dport 53 dnat ip to 127.0.0.1:$__onionfence_dnsport
        iifname \"$h\" meta nfproto ipv4 tcp dport 53 dnat ip to 127.0.0.1:$__onionfence_transport
        iifname \"$h\" meta nfproto ipv4 meta l4proto tcp dnat ip to 127.0.0.1:$__onionfence_transport
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
# Параметры: uid gid fresh(0|1) домашний_каталог xauthority ПЕРЕМЕННАЯ=ЗНАЧЕНИЕ… команда… (без «--»: env принял бы его за имя программы)
function __onionfence_run_script
    set -l ns $__onionfence_ns
    set -l h $__onionfence_ns_host
    set -l p $__onionfence_ns_peer
    set -l hip $__onionfence_ns_host_ip
    set -l pip $__onionfence_ns_peer_ip
    echo "
down() {
    nft delete table inet onionfence_run 2>/dev/null
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
$(__onionfence_run_rules)
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
uid=\$1; gid=\$2; fresh=\$3; home=\$4; xauth=\$5; shift 5
if ! ( up ); then
    echo 'onionfence: не удалось создать сетевое пространство' >&2
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
    uid=\$1; gid=\$2; fresh=\$3; home=\$4; xauth=\$5; shift 5
    # Чистый запуск: вместо домашнего каталога пустой каталог в памяти, он исчезнет вместе с программой
    if [ \"\$fresh\" = 1 ]; then
        saved=
        if [ -n \"\$xauth\" ] && [ -r \"\$xauth\" ]; then
            saved=\$(mktemp)
            cp \"\$xauth\" \"\$saved\"
        fi
        if ! mount -t tmpfs -o mode=700,uid=\"\$uid\",gid=\"\$gid\" tmpfs \"\$home\"; then
            echo \"onionfence: не удалось создать чистый домашний каталог\" >&2
            exit 125
        fi
        if [ -n \"\$saved\" ]; then
            case \"\$xauth\" in
                \"\$home\"/*) install -D -o \"\$uid\" -g \"\$gid\" -m 600 \"\$saved\" \"\$xauth\" ;;
            esac
            rm -f \"\$saved\"
        fi
        install -d -o \"\$uid\" -g \"\$gid\" -m 700 \"\$home/.tmp\"
        cd \"\$home\" || exit 125
    fi
    exec setpriv --reuid=\"\$uid\" --regid=\"\$gid\" --init-groups env \"\$@\"
' sh \"\$uid\" \"\$gid\" \"\$fresh\" \"\$home\" \"\$xauth\" \"\$@\"
rc=\$?
[ -z \"\$(ip netns pids $ns 2>/dev/null)\" ] && down
exit \$rc"
end

# onionfence run [--force] [--fresh] программа [аргументы…] | onionfence run --stop
function __onionfence_run
    argparse -s force stop fresh -- $argv; or return 1
    if set -q _flag_stop
        sudo sh -c (__onionfence_run_script | string collect) onionfence-run --stop
        __onionfence_say yellow "● Отдельное сетевое пространство закрыто, программы в нём завершены"
        return
    end
    if not set -q argv[1]
        echo "  onionfence run программа [аргументы]   только эта программа через Tor"
        echo "  onionfence run --force программа       запустить, даже если она уже открыта"
        echo "  onionfence run --fresh программа       с пустым домашним каталогом в памяти: всё исчезнет после закрытия"
        echo "  onionfence run --stop                  завершить всё, что запущено так"
        return 1
    end
    for tool in ip setpriv nft
        if not command -q $tool
            __onionfence_say red "✘ Нужна программа $tool"
            return 1
        end
    end
    if test -z "$(command -s -- $argv[1])"
        __onionfence_say red "✘ Программа не найдена: $argv[1]"
        return 127
    end

    set -l fresh 0
    if set -q _flag_fresh
        set fresh 1
        # каталог будет закрыт пустым: программа оттуда просто не запустится
        if string match -q "$HOME/*" -- (command -s -- $argv[1])
            __onionfence_say red "✘ Программа лежит в домашнем каталоге, а при --fresh он скрыт: укажи другую программу"
            return 1
        end
    end

    # Браузер и многие другие программы открывают окно в уже запущенной копии, а та работает мимо Tor
    set -l name (path basename -- $argv[1] | string sub -l 15)
    if not set -q _flag_force; and pgrep -xu (id -u) -- $name >/dev/null 2>&1
        __onionfence_say yellow "⚠ $name уже запущен. Новое окно может открыться в старой копии, а она работает МИМО Tor."
        if not test -t 0
            echo "  Закрой её или запусти с --force, если уверен, что программа создаст новую копию."
            return 1
        end
        read -P '  Запустить всё равно? [y/N] ' -l answer
        string match -qri '^[yд]' -- "$answer"; or return 1
    end

    # Tor нужен, но правила всей системы не включаем: в этом и смысл команды
    set -l started_tor 0
    if not systemctl -q is-active $__onionfence_unit
        __onionfence_torrc; or return 1
        echo "  Подключение к сети Tor..."
        set -l started (date '+%Y-%m-%d %H:%M:%S')
        sudo systemctl restart $__onionfence_unit; or begin
            __onionfence_on_failed "Tor не запустился" $started
            return 1
        end
        set -l timeout $__onionfence_timeout
        test -n "$(__onionfence_bridges_current)"; and set timeout (math $timeout x 2)
        __onionfence_wait_bootstrap $timeout $started
        set -l rc $status
        echo
        if test $rc -ne 0
            __onionfence_on_failed "Tor не подключился за $timeout секунд" $started
            return 1
        end
        set started_tor 1
    end

    set -l envs
    for v in DISPLAY WAYLAND_DISPLAY XAUTHORITY XDG_RUNTIME_DIR XDG_SESSION_TYPE XDG_CURRENT_DESKTOP DBUS_SESSION_BUS_ADDRESS PULSE_SERVER HOME USER LOGNAME PATH LANG LC_ALL TERM
        set -q $v; and set -a envs "$v=$$v"
    end
    test $fresh = 1; and set -a envs "TMPDIR=$HOME/.tmp"
    sudo sh -c (__onionfence_run_script | string collect) onionfence-run (id -u) (id -g) $fresh $HOME "$XAUTHORITY" $envs $argv
    set -l rc $status
    if test $fresh = 1
        __onionfence_say yellow "  Временный домашний каталог исчезнет, когда закроются все программы этого запуска"
    end

    # Tor запускали мы и он больше никому не нужен: возвращаем как было
    if test $started_tor = 1
        if not sudo nft list table inet $__onionfence_table >/dev/null 2>&1; and not sudo ip netns pids $__onionfence_ns >/dev/null 2>&1
            sudo systemctl stop $__onionfence_unit
        end
    end
    return $rc
end

# ---------- анонимность ----------

# Tor Browser через системный Tor: свой Tor он не запускает, иначе трафик шёл бы через Tor дважды.
function __onionfence_browser_binary
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

function __onionfence_browser
    if not systemctl -q is-active $__onionfence_unit
        __onionfence_say red "✘ Tor не запущен (onionfence on)"
        return 1
    end
    set -l bin (__onionfence_browser_binary)
    if test -z "$bin"
        set -l pm "sudo pacman -S"
        test "$__onionfence_platform" = debian; and set pm "sudo apt install"
        __onionfence_say red "✘ Tor Browser не найден: $pm torbrowser-launcher"
        return 1
    end
    env TOR_SKIP_LAUNCH=1 TOR_PROVIDER=none TOR_SOCKS_HOST=127.0.0.1 TOR_SOCKS_PORT=$__onionfence_socksport \
        setsid -f $bin </dev/null >/dev/null 2>&1
    or begin
        __onionfence_say red "✘ Не удалось запустить $bin"
        return 1
    end
    __onionfence_say green "✔ Tor Browser запускается через системный Tor (порт $__onionfence_socksport)"
end

# Служба загружает правила раньше сети. Как и у nftables.service: DefaultDependencies=no и
# sysinit.target. After=nftables.service — его «flush ruleset» иначе стёр бы нашу таблицу.
function __onionfence_boot_unit_text
    set -l nft (command -s nft; or echo /usr/bin/nft)
    printf '%s\n' \
        '[Unit]' \
        'Description=onionfence: block traffic outside Tor from early boot' \
        'DefaultDependencies=no' \
        'After=local-fs.target nftables.service' \
        'Before=network-pre.target shutdown.target' \
        'Wants=network-pre.target' \
        'Conflicts=shutdown.target' \
        '' \
        '[Service]' \
        'Type=oneshot' \
        'RemainAfterExit=yes' \
        "ExecStartPre=-$nft delete table inet $__onionfence_table" \
        "ExecStart=$nft -f $__onionfence_etc/rules.nft" \
        '' \
        '[Install]' \
        'WantedBy=sysinit.target'
end

# onionfence boot [on [--strict] | off]
function __onionfence_boot --argument-names action
    set -l service $__onionfence_systemd_dir/$__onionfence_boot_unit.service
    switch "$action"
        case ''
            if systemctl -q is-enabled $__onionfence_boot_unit 2>/dev/null
                __onionfence_say green "Защита при загрузке включена"
            else
                __onionfence_say yellow "Защита при загрузке выключена"
            end
            echo "  onionfence boot on [--strict]   с момента загрузки весь трафик только через Tor"
            echo "  onionfence boot off             обычная загрузка"
        case on
            argparse strict -- $argv[2..]; or return 1
            set -l mode
            set -q _flag_strict; and set mode strict
            if test -z "$__onionfence_user"
                __onionfence_say red "✘ Tor не установлен"
                return 1
            end
            __onionfence_torrc; or return 1
            __onionfence_clock_warn
            sudo mkdir -p $__onionfence_etc; or return 1
            __onionfence_rules $mode | sudo tee $__onionfence_etc/rules.nft >/dev/null
            __onionfence_pipefail $pipestatus; or begin
                __onionfence_say red "✘ Не удалось записать $__onionfence_etc/rules.nft"
                return 1
            end
            # ошибка в правилах при загрузке оставила бы систему без защиты: проверяем сейчас
            if not sudo nft -c -f $__onionfence_etc/rules.nft
                __onionfence_say red "✘ nftables не принял правила, защита не включена"
                return 1
            end
            # запоминаем, включал ли Tor сам пользователь, чтобы off вернул всё как было.
            # Только при первом on: при повторном Tor уже включён нами.
            if not test -e $service; and systemctl -q is-enabled $__onionfence_unit 2>/dev/null
                sudo touch $__onionfence_etc/tor-was-enabled
            end
            __onionfence_boot_unit_text | sudo tee $service >/dev/null
            __onionfence_pipefail $pipestatus; or begin
                __onionfence_say red "✘ Не удалось записать $service"
                return 1
            end
            __onionfence_guard_unit_text | sudo tee $__onionfence_systemd_dir/$__onionfence_guard_unit.service >/dev/null
            __onionfence_pipefail $pipestatus; or begin
                __onionfence_say red "✘ Не удалось записать службу сторожа"
                return 1
            end
            __onionfence_tor_dropin_sync
            sudo systemctl daemon-reload
            sudo systemctl enable $__onionfence_boot_unit $__onionfence_unit $__onionfence_guard_unit; or begin
                __onionfence_say red "✘ Не удалось включить службы"
                return 1
            end
            __onionfence_say green "✔ Защита включится со следующей загрузки"
            echo "  Если Tor при загрузке не подключится, интернета не будет: onionfence off вернёт его."
        case off
            # защита не включалась: автозапуск Tor настроен не нами, его не трогаем
            if not test -e $service
                __onionfence_say yellow "Защита при загрузке и так выключена"
                return 0
            end
            sudo systemctl disable $__onionfence_boot_unit $__onionfence_guard_unit 2>/dev/null
            sudo rm -f $__onionfence_systemd_dir/$__onionfence_guard_unit.service
            sudo test -e $__onionfence_etc/tor-was-enabled; or sudo systemctl disable $__onionfence_unit
            sudo rm -f $service
            sudo rm -rf $__onionfence_etc
            __onionfence_tor_dropin_sync
            sudo systemctl daemon-reload
            __onionfence_say yellow "● Защита при загрузке выключена (текущий режим не изменён)"
        case '*'
            __onionfence_say red "✘ Неизвестное действие: $action (on | off)"
            return 1
    end
end

function __onionfence_hide_dir
    if test -n "$XDG_STATE_HOME"
        echo $XDG_STATE_HOME/onionfence/hide
    else
        echo $HOME/.local/state/onionfence/hide
    end
end

# Активные подключения Wi-Fi и Ethernet: «uuid:тип»
function __onionfence_hide_conns
    nmcli -t -f UUID,TYPE connection show --active | string match -r '^.*:(?:802-11-wireless|802-3-ethernet)$'
end

# onionfence hide [on | off]. Меняет профили NetworkManager; прежние значения хранятся в файле,
# чтобы off вернул их точно. Имя компьютера уходит через DHCP, mDNS и LLMNR.
function __onionfence_hide --argument-names action
    set -l dir (__onionfence_hide_dir)
    switch "$action"
        case ''
            if count $dir/* >/dev/null
                __onionfence_say green "Устройство скрыто: случайный MAC, имя компьютера не передаётся"
            else
                __onionfence_say yellow "Скрытие выключено"
            end
            echo "  onionfence hide on    случайный MAC и скрытие имени от локальной сети (сеть переподключится)"
            echo "  onionfence hide off   вернуть как было"
            return
        case on off
            if not type -q nmcli
                __onionfence_say red "✘ Нужен NetworkManager (nmcli)"
                return 1
            end
        case '*'
            __onionfence_say red "✘ Неизвестное действие: $action (on | off)"
            return 1
    end

    if test $action = on
        set -l conns (__onionfence_hide_conns)
        if not set -q conns[1]
            __onionfence_say red "✘ Нет активного подключения Wi-Fi или Ethernet"
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
                __onionfence_say red "✘ Не удалось применить настройки (onionfence hide off — вернуть как было)"
                return 1
            end
        end
        __onionfence_say green "✔ MAC случайный, имя компьютера локальной сети не передаётся"
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
                __onionfence_say red "✘ Не удалось вернуть настройки подключения $uuid (сохранены в $f)"
                return 1
            end
            contains -- $uuid $active; and sudo nmcli connection up $uuid >/dev/null
            rm -f $f
        end
        __onionfence_say yellow "● Настройки сети возвращены"
    end
end

# Сколько ждать ответа сайта проверки: через мосты (особенно snowflake) запросы идут намного дольше
function __onionfence_check_timeout
    set -l bridges (__onionfence_bridges_current)
    set -q bridges[1]; and echo 60; or echo 30
end

# Ответ сайта проверки. Первое соединение после подключения Tor иногда сразу обрывается,
# поэтому быстрый обрыв повторяем. После таймаута не повторяем: команда висела бы минутами.
function __onionfence_check_ip
    for i in (seq 3)
        set -l started (date +%s)
        set -l reply (curl -s --max-time (__onionfence_check_timeout) https://check.torproject.org/api/ip)
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
function __onionfence_leak_row --argument-names ok name detail
    set -g __onionfence_leak_total (math $__onionfence_leak_total + 1)
    if test $ok = 1
        __onionfence_row $name "$(__onionfence_color green)✔$(__onionfence_color normal) $detail"
    else
        __onionfence_row $name "$(__onionfence_color red)✘$(__onionfence_color normal) $detail"
        return 1
    end
end

function __onionfence_leaktest
    set -g __onionfence_leak_total 0
    set -l failed 0
    echo "$(__onionfence_color frame)"'  ╭──────── проверка утечек ─────────'"$(__onionfence_color normal)"

    set -l ok 0
    sudo nft list table inet $__onionfence_table >/dev/null 2>&1; and set ok 1
    __onionfence_leak_row $ok "Правила" "таблица nftables"; or set failed (math $failed + 1)

    set ok 0
    systemctl -q is-active $__onionfence_unit; and set ok 1
    __onionfence_leak_row $ok "Служба Tor" $__onionfence_unit; or set failed (math $failed + 1)

    # адрес снаружи видит сам сайт проверки
    set -l check (__onionfence_check_ip)
    set -l ip (echo $check | jq -r '.IP // "нет ответа"' 2>/dev/null)
    test -n "$ip"; or set ip "нет ответа"
    set ok 0
    test "$(echo $check | jq -r .IsTor 2>/dev/null)" = true; and set ok 1
    __onionfence_leak_row $ok "Внешний IP" $ip; or set failed (math $failed + 1)

    # 192.0.2.1 — адрес из документации, DNS там нет: ответ может прийти только от Tor
    set -l reply (printf '\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01' \
        | socat -t$__onionfence_leak_wait - UDP:192.0.2.1:53 2>/dev/null | od -An -tx1)
    set ok 0
    test -n "$reply"; and set ok 1
    __onionfence_leak_row $ok "DNS" "запросы перехватывает Tor"; or set failed (math $failed + 1)

    # отправка должна упасть: файрвол не выпускает UDP и IPv6 мимо Tor
    set ok 1
    printf x | socat -t0.2 - UDP:198.51.100.1:443 >/dev/null 2>&1; and set ok 0
    __onionfence_leak_row $ok "UDP" "мимо Tor не выходит"; or set failed (math $failed + 1)

    set ok 1
    printf x | socat -t0.2 - 'UDP6:[2001:db8::1]:443' >/dev/null 2>&1; and set ok 0
    __onionfence_leak_row $ok "IPv6" "мимо Tor не выходит"; or set failed (math $failed + 1)

    if command -q ping
        set ok 1
        ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; and set ok 0
        __onionfence_leak_row $ok "ICMP" "ping мимо Tor не выходит"; or set failed (math $failed + 1)
    end

    set -l allowed (__onionfence_allow_current)
    set -q allowed[1]; and __onionfence_row "Исключения" "$(__onionfence_color yellow)⚠$(__onionfence_color normal) мимо Tor идёт: "(string join ', ' -- $allowed)
    echo "$(__onionfence_color frame)"'  ╰──────────────────────────────────'"$(__onionfence_color normal)"
    __onionfence_summary (math $__onionfence_leak_total - $failed) $__onionfence_leak_total
    if test $failed -eq 0
        __onionfence_say green "✔ Утечек не найдено"
    else
        __onionfence_say red "✘ Проблем: $failed"
        return 1
    end
end

# Убирает метаданные (GPS, автор, модель камеры): рядом появляется файл.cleaned.расширение
function __onionfence_clean
    if not set -q argv[1]
        echo "  onionfence clean файл…   убрать метаданные: рядом появится файл.cleaned.расширение"
        return 1
    end
    if not type -q mat2
        set -l pm "sudo pacman -S"
        test "$__onionfence_platform" = debian; and set pm "sudo apt install"
        __onionfence_say red "✘ Нужна программа mat2: $pm mat2"
        return 1
    end
    set -l failed 0
    for f in $argv
        if not test -f "$f"
            __onionfence_say red "✘ Нет такого файла: $f"
            set failed 1
            continue
        end
        if mat2 -- $f
            __onionfence_say green "✔ "(string replace -r '(\.[^./]+)$' '.cleaned$1' -- $f)
        else
            __onionfence_say red "✘ mat2 не смог обработать: $f"
            set failed 1
        end
    end
    __onionfence_say yellow "  Исходные файлы не тронуты. Текст и лица на самих фото mat2 не убирает."
    test $failed -eq 0
end

# С аргументом --quick не делает сетевых запросов и не спрашивает пароль (для меню)
function __onionfence_status
    # в быстром режиме не спрашиваем пароль, только используем закэшированный sudo
    set -l sudo_opts
    test "$argv[1]" = --quick; and set sudo_opts -n
    set -l rules "$(__onionfence_color red)● выключен$(__onionfence_color normal)"
    if not sudo $sudo_opts true 2>/dev/null
        set rules "$(__onionfence_color yellow)? нужен sudo (выбери «Проверить»)$(__onionfence_color normal)"
    else if sudo nft list table inet $__onionfence_table >/dev/null 2>&1
        set rules "$(__onionfence_color green)● ВКЛЮЧЁН$(__onionfence_color normal)"
        __onionfence_is_strict; and set rules "$(__onionfence_color green)● ВКЛЮЧЁН (строгий)$(__onionfence_color normal)"
    end

    # главное видно сразу, подробности ниже
    set -l sudo_ok 0
    sudo $sudo_opts true 2>/dev/null; and set sudo_ok 1
    set -l headline "$(__onionfence_color --bold yellow)? Статус неизвестен: нужен пароль sudo$(__onionfence_color normal)"
    if test $sudo_ok = 1
        if sudo nft list table inet $__onionfence_panic_table >/dev/null 2>&1
            set headline "$(__onionfence_color --bold red)■ СЕТЬ ЗАКРЫТА: экстренное отключение (onionfence panic off)$(__onionfence_color normal)"
        else if sudo nft list table inet $__onionfence_table >/dev/null 2>&1
            if systemctl -q is-active $__onionfence_unit
                set headline "$(__onionfence_color --bold green)● ЗАЩИЩЕНО · весь трафик через Tor$(__onionfence_color normal)"
            else
                set headline "$(__onionfence_color --bold yellow)■ СЕТЬ ЗАКРЫТА: Tor не запущен (onionfence on или off)$(__onionfence_color normal)"
            end
        else
            set headline "$(__onionfence_color --bold red)○ НЕ ЗАЩИЩЕНО · обычный интернет$(__onionfence_color normal)"
        end
    end
    echo "  $headline"
    echo "$(__onionfence_color frame)"'  ╭──────────── статус ─────────────'"$(__onionfence_color normal)"
    __onionfence_row "Режим" $rules
    __onionfence_row "Служба Tor" (systemctl is-active $__onionfence_unit)
    __onionfence_row "Страна выхода" (__onionfence_exit_country)
    set -l excluded (__onionfence_exclude_current)
    set -q excluded[1]; and __onionfence_row "Исключены" (string join ', ' -- $excluded)
    set -l allowed (__onionfence_allow_current)
    set -q allowed[1]; and __onionfence_row "Мимо Tor" "$(__onionfence_color yellow)"(string join ', ' -- $allowed)"$(__onionfence_color normal)"
    __onionfence_row "Мосты" (__onionfence_bridges_summary)
    set -l rotate (__onionfence_rotate_current)
    test -n "$rotate"; and __onionfence_row "Смена цепочки" "каждые $rotate"
    set -l boot выкл
    systemctl -q is-enabled $__onionfence_boot_unit 2>/dev/null; and set boot вкл
    __onionfence_row "При загрузке" $boot
    set -l hide выкл
    count (__onionfence_hide_dir)/* >/dev/null; and set hide вкл
    __onionfence_row "Скрытие" $hide

    if test "$argv[1]" != --quick
        __onionfence_row "Проверка" "$(__onionfence_color dim)запрос к check.torproject.org…$(__onionfence_color normal)"
        set -l check (__onionfence_check_ip)
        set -l ip (echo $check | jq -r '.IP // empty' 2>/dev/null)
        if test -z "$ip"
            __onionfence_row "Внешний IP" "$(__onionfence_color red)нет ответа$(__onionfence_color normal)"
        else
            # страну спрашиваем у GeoIP самого Tor: ipinfo.io отвечает выходам Tor 403
            set -l geo
            if systemctl -q is-active $__onionfence_unit
                set geo (__onionfence_control "GETINFO ip-to-country/$ip" 2>/dev/null | string match -rg '^250-ip-to-country/.*=(\w+)$' | string upper)
            end
            test -n "$geo"; or set geo (curl -s --max-time 15 https://ipinfo.io/$ip/json | jq -r '[.country, .city] | map(select(. != null)) | join(", ")' 2>/dev/null)
            __onionfence_row "Внешний IP" "$ip $geo"
            if test "$(echo $check | jq -r .IsTor)" = true
                __onionfence_row "Через Tor" "$(__onionfence_color green)✔ да$(__onionfence_color normal)"
            else
                __onionfence_row "Через Tor" "$(__onionfence_color red)✘ нет$(__onionfence_color normal)"
            end
        end
    end
    echo "$(__onionfence_color frame)"'  ╰──────────────────────────────────'"$(__onionfence_color normal)"
end

# Команды на ControlPort Tor (аутентификация cookie); печатает ответы Tor построчно
function __onionfence_control
    set -l cookie $__onionfence_cookie_cache
    if test -z "$cookie"
        sudo test -e $__onionfence_cookie; or return 2
        set cookie (sudo od -An -v -tx1 $__onionfence_cookie | string replace -ra '\s' '' | string join '')
        __onionfence_pipefail $pipestatus; or begin
            echo "не удалось прочитать $__onionfence_cookie" >&2
            return 2
        end
    end
    set -l reply (printf '%s\r\n' "AUTHENTICATE $cookie" $argv QUIT | socat -t2 - TCP:127.0.0.1:$__onionfence_ctlport 2>/dev/null)
    __onionfence_pipefail $pipestatus; or begin
        echo "ControlPort 127.0.0.1:$__onionfence_ctlport не отвечает" >&2
        return 3
    end
    string trim -- $reply
end

function __onionfence_newip
    if test "$argv[1]" = --every
        __onionfence_rotate $argv[2]
        return
    else if set -q argv[1]
        __onionfence_say red "✘ Неизвестный параметр: $argv[1] (onionfence newip --every 10m | off)"
        return 1
    end
    if not systemctl -q is-active $__onionfence_unit
        __onionfence_say red "✘ Tor не запущен (onionfence on)"
        return 1
    end
    if not sudo test -e $__onionfence_cookie
        __onionfence_say red "✘ Нет ControlPort — выполни onionfence on заново, чтобы обновить настройки Tor"
        return 1
    end
    set -l reply (__onionfence_control 'SIGNAL NEWNYM' 2>&1)
    if test (count (string match '250 OK' -- $reply)) -ge 2
        __onionfence_say green "✔ Новая цепочка запрошена — новые соединения пойдут через другой IP (Tor делает это не чаще раза в 10 секунд)"
    else
        __onionfence_say red "✘ Новый IP не получен: $reply"
        return 1
    end
end

function __onionfence_country --argument-names cc
    if test -z "$cc"
        __onionfence_say yellow "Страна выхода сейчас: "(__onionfence_exit_country)
        echo "  Укажи код: onionfence country de  (или any — любая)"
        return
    end
    set cc (string lower -- $cc)
    if test "$cc" != any; and not string match -qr '^[a-z]{2}$' -- $cc
        __onionfence_say red "✘ Нужен двухбуквенный код страны (de, nl, us, ch…) или any"
        return 1
    end
    if contains -- $cc (__onionfence_exclude_current)
        __onionfence_say red "✘ Страна $cc исключена, Tor не нашёл бы выхода (onionfence exclude off — снять запрет)"
        return 1
    end

    __onionfence_torrc --country $cc; or return 1
    __onionfence_say green "✔ Страна выхода: "(__onionfence_exit_country)

    if systemctl -q is-active $__onionfence_unit; and not __onionfence_apply_country $cc
        # без ControlPort: перечитать torrc; старые цепочки доживут до NEWNYM (до 10 секунд)
        sudo systemctl reload $__onionfence_unit
        __onionfence_say yellow "  Tor применит это к новым соединениям в течение ~10 секунд"
    end
end

# ---------- диагностика ----------

# Строка отчёта doctor: уровень ok | warn | fail; провалы считаются в __onionfence_doc_fails
function __onionfence_doc_row --argument-names level name detail
    set -g __onionfence_doc_total (math $__onionfence_doc_total + 1)
    switch $level
        case ok
            __onionfence_row $name "$(__onionfence_color green)✔$(__onionfence_color normal) $detail"
        case warn
            __onionfence_row $name "$(__onionfence_color yellow)⚠$(__onionfence_color normal) $detail"
        case fail
            __onionfence_row $name "$(__onionfence_color red)✘$(__onionfence_color normal) $detail"
            set -g __onionfence_doc_fails (math $__onionfence_doc_fails + 1)
    end
end

# Занят ли порт: протокол tcp | udp
function __onionfence_port_used --argument-names proto port
    set -l flag -t
    test $proto = udp; and set flag -u
    test -n "$(ss -Hln $flag "sport = :$port" 2>/dev/null)"
end

function __onionfence_doctor
    set -g __onionfence_doc_fails 0
    set -g __onionfence_doc_total 0
    set -l pm "sudo pacman -S"
    test "$__onionfence_platform" = debian; and set pm "sudo apt install"
    echo "$(__onionfence_color frame)"'  ╭──────── диагностика ─────────────'"$(__onionfence_color normal)"

    # программы
    for tool in tor nft curl jq socat ss systemctl
        if type -q $tool
            set -l detail установлен
            test $tool = tor; and set detail (tor --version 2>/dev/null | string match -rg 'version ([0-9.]+)')
            __onionfence_doc_row ok $tool "$detail"
        else
            __onionfence_doc_row fail $tool "нет: $pm $tool"
        end
    end
    if not type -q fzf
        __onionfence_doc_row warn fzf "нет: меню будет с номерами вместо стрелок"
    end
    set -l tor_ready 1
    type -q tor; or set tor_ready 0
    if test -z "$__onionfence_user"
        __onionfence_doc_row fail "Пользователь" "нет пользователя tor или debian-tor"
    end

    # транспорты для настроенных мостов
    set -l bridges (__onionfence_bridges_current)
    if set -q bridges[1]
        for tr in (string match -rg '^([a-z0-9_]+) ' -- $bridges | sort -u)
            if test -n "$(__onionfence_pt_binary $tr)"
                __onionfence_doc_row ok "Мосты $tr" "транспорт на месте"
            else
                __onionfence_doc_row fail "Мосты $tr" (__onionfence_pt_hint $tr)
            end
        end
    end

    if set -q bridges[1]
        if test -e (__onionfence_tor_dropin_path)
            __onionfence_doc_row ok "DNS мостов" "у службы Tor свой DNS: мосты подключатся и при включённых правилах"
        else
            __onionfence_doc_row warn "DNS мостов" "настройки службы Tor нет: onionfence on создаст её"
        end
    end

    # настройки: Tor сам проверяет итоговый файл
    if test $tor_ready = 1
        set -l defaults
        test -r /usr/share/tor/tor-service-defaults-torrc; and set defaults --defaults-torrc /usr/share/tor/tor-service-defaults-torrc
        set -l verify (sudo tor $defaults --verify-config -f $__onionfence_torrc 2>&1)
        if test $status -eq 0
            __onionfence_doc_row ok "Настройки" "Tor принимает $__onionfence_torrc"
        else
            set -l first (string match -ri '.*\[(?:warn|err)\].*' -- $verify)[1]
            __onionfence_doc_row fail "Настройки" "Tor отвергает $__onionfence_torrc: $first"
        end
    end

    # служба и порты
    set -l active 0
    systemctl -q is-active $__onionfence_unit; and set active 1
    set -l rules 0
    sudo nft list table inet $__onionfence_table >/dev/null 2>&1; and set rules 1
    for entry in "tcp $__onionfence_transport TransPort" "udp $__onionfence_dnsport DNSPort" "tcp $__onionfence_ctlport ControlPort"
        set -l e (string split ' ' -- $entry)
        set -l used 0
        __onionfence_port_used $e[1] $e[2]; and set used 1
        if test $active = 1 -a $used = 0
            __onionfence_doc_row fail $e[3] "порт $e[2] не слушается: Tor ещё запускается или настройки не применились"
        else if test $active = 0 -a $used = 1
            __onionfence_doc_row fail $e[3] "порт $e[2] занят другой программой: sudo ss -lntup | grep $e[2]"
        else if test $active = 1
            __onionfence_doc_row ok $e[3] "порт $e[2] слушается"
        else
            __onionfence_doc_row ok $e[3] "порт $e[2] свободен"
        end
    end

    # согласованность
    if test $rules = 1 -a $active = 0
        __onionfence_doc_row fail "Интернет" "закрыт: правила есть, а Tor не запущен. onionfence on или onionfence off"
    else if test $rules = 1
        __onionfence_doc_row ok "Режим" "включён"
        if systemctl -q is-active $__onionfence_guard_unit
            __onionfence_doc_row ok "Сторож" "вернёт правила, если их сотрут"
        else
            __onionfence_doc_row warn "Сторож" "не запущен: стёртые правила не вернутся сами (onionfence on запустит его)"
        end
    else if test $active = 1
        __onionfence_doc_row warn "Режим" "Tor работает, но трафик идёт напрямую (onionfence on)"
    else
        __onionfence_doc_row ok "Режим" "выключен"
    end
    if test $active = 1
        if set -l reply (__onionfence_control 'GETINFO status/bootstrap-phase' 2>/dev/null); and string match -q '*PROGRESS=100*' -- "$reply"
            __onionfence_doc_row ok "Подключение" "Tor подключён к сети"
        else if string match -q '*BOOTSTRAP*' -- "$reply"
            __onionfence_doc_row warn "Подключение" "Tor ещё подключается"
        else
            __onionfence_doc_row fail "ControlPort" "Tor не отвечает или отверг cookie"
        end
    end

    set -l allowed (__onionfence_allow_current)
    set -q allowed[1]; and __onionfence_doc_row warn "Исключения" "мимо Tor идёт: "(string join ', ' -- $allowed)

    # часы
    if command -q timedatectl
        switch "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)"
            case yes
                __onionfence_doc_row ok "Часы" "синхронизированы"
            case no
                if test $rules = 1
                    __onionfence_doc_row warn "Часы" "не синхронизируются: в Tor-режиме NTP закрыт. Это норма, пока время не разойдётся сильно"
                else
                    __onionfence_doc_row warn "Часы" "не синхронизированы: при большой ошибке Tor не подключится"
                end
        end
    end

    # если Tor не работает, журнал обычно уже называет причину
    if test $active = 0
        set -l why (__onionfence_explain (sudo journalctl -u $__onionfence_unit -n 100 --no-pager -q 2>/dev/null))
        test -n "$why"; and __onionfence_doc_row warn "Прошлый запуск" $why
    end

    echo "$(__onionfence_color frame)"'  ╰──────────────────────────────────'"$(__onionfence_color normal)"
    __onionfence_summary (math $__onionfence_doc_total - $__onionfence_doc_fails) $__onionfence_doc_total
    if test $__onionfence_doc_fails -eq 0
        __onionfence_say green "✔ Неполадок не найдено"
    else
        __onionfence_say red "✘ Неполадок: $__onionfence_doc_fails"
        return 1
    end
end

# ---------- смена цепочки по таймеру ----------

# «30s», «10m», «1h» в секунды. Реже суток и чаще 30 секунд не имеет смысла: Tor сам ограничивает частоту.
function __onionfence_parse_interval --argument-names value
    set -l m (string match -rg '^(\d{1,6})([smh])$' -- $value); or return 1
    set -l seconds $m[1]
    test $m[2] = m; and set seconds (math $m[1] x 60)
    test $m[2] = h; and set seconds (math $m[1] x 3600)
    test $seconds -ge 30 -a $seconds -le 86400; or return 1
    echo $seconds
end

function __onionfence_rotate_script --argument-names seconds
    echo "while sleep $seconds; do c=\$(od -An -v -tx1 $__onionfence_cookie | tr -d ' \\n'); printf 'AUTHENTICATE %s\\r\\nSIGNAL NEWNYM\\r\\nQUIT\\r\\n' \"\$c\" | socat -t2 - TCP:127.0.0.1:$__onionfence_ctlport; done"
end

# Как часто меняется цепочка: пусто, если таймер не запущен
function __onionfence_rotate_current
    systemctl -q is-active $__onionfence_rotate_unit; or return 0
    systemctl show -p Description --value $__onionfence_rotate_unit | string match -rg 'every (\S+)$'
end

# onionfence newip --every 10m | off. Таймер живёт, пока работает Tor, и не переживает перезагрузку.
function __onionfence_rotate --argument-names value
    switch "$value"
        case ''
            set -l current (__onionfence_rotate_current)
            if test -n "$current"
                __onionfence_say green "Цепочка меняется каждые $current"
            else
                __onionfence_say yellow "Таймер смены цепочки не запущен"
            end
            echo "  onionfence newip --every 10m   менять каждые 10 минут (можно 30s, 1h)"
            echo "  onionfence newip --every off   снять таймер"
            return
        case off
            sudo systemctl stop $__onionfence_rotate_unit 2>/dev/null
            __onionfence_say yellow "● Таймер смены цепочки снят"
            return
    end
    set -l seconds (__onionfence_parse_interval $value)
    if test -z "$seconds"
        __onionfence_say red "✘ Нужен интервал от 30 секунд до суток: 30s, 10m, 1h"
        return 1
    end
    if not systemctl -q is-active $__onionfence_unit
        __onionfence_say red "✘ Tor не запущен (onionfence on)"
        return 1
    end
    sudo systemctl stop $__onionfence_rotate_unit 2>/dev/null
    if not sudo systemd-run --quiet --collect --unit=$__onionfence_rotate_unit \
            --description="onionfence: new circuit every $value" \
            -p PartOf=$__onionfence_unit.service -p After=$__onionfence_unit.service \
            /bin/sh -c (__onionfence_rotate_script $seconds)
        __onionfence_say red "✘ Не удалось запустить таймер"
        return 1
    end
    __onionfence_say green "✔ Цепочка будет меняться каждые $value"
    echo "  Открытые соединения не обрываются: новая цепочка действует для новых соединений."
end

# ---------- экстренное отключение ----------

function __onionfence_panic_active
    sudo -n nft list table inet $__onionfence_panic_table >/dev/null 2>&1
end

function __onionfence_panic_file
    set -l config $HOME/.config
    test -n "$XDG_CONFIG_HOME"; and set config $XDG_CONFIG_HOME
    echo $config/onionfence/panic-apps
end

function __onionfence_panic_rules
    echo "
table inet $__onionfence_panic_table {
    chain panic_in { type filter hook input priority -400; policy drop; iifname \"lo\" accept; }
    chain panic_out { type filter hook output priority -400; policy drop; oifname \"lo\" accept; }
    chain panic_fwd { type filter hook forward priority -400; policy drop; }
}"
end

# История команд: файлы известных оболочек обнуляются. Только по явному --wipe-history: это нельзя отменить.
# Открытые терминалы могут дописать своё при закрытии.
function __onionfence_wipe_history
    set -l data $HOME/.local/share
    test -n "$XDG_DATA_HOME"; and set data $XDG_DATA_HOME
    for f in $data/fish/fish_history $HOME/.bash_history $HOME/.zsh_history $HOME/.histfile
        test -f $f; and true >$f
    end
    builtin history clear-session 2>/dev/null
    return 0
end

# onionfence panic [--wipe-history] | off | add ИМЯ | del ИМЯ | list
function __onionfence_panic --argument-names action name
    set -l file (__onionfence_panic_file)
    switch "$action"
        case off
            sudo nft delete table inet $__onionfence_panic_table 2>/dev/null
            if sudo nft list table inet $__onionfence_table >/dev/null 2>&1
                __onionfence_say yellow "● Экстренное отключение снято. Сеть пока закрыта правилами: onionfence on или onionfence off"
            else
                __onionfence_say green "✔ Экстренное отключение снято, обычный интернет восстановлен"
            end
            return
        case list
            if test -s $file
                __onionfence_say yellow "При panic закрываются: "(string join ', ' -- (command cat $file))
            else
                echo "  Список пуст: panic закроет только программы, запущенные через onionfence run"
            end
            echo "  onionfence panic add firefox   добавить программу в список"
            echo "  onionfence panic del firefox   убрать"
            return
        case add
            if not string match -qr '^[A-Za-z0-9._+-]+$' -- "$name"
                __onionfence_say red "✘ Укажи имя процесса: onionfence panic add firefox"
                return 1
            end
            mkdir -p (path dirname $file); or return 1
            test -f $file; and command grep -qxF -- $name $file; or echo $name >>$file
            __onionfence_say green "✔ При panic будет закрываться: $name"
            return
        case del
            if not test -f $file; or not command grep -qxF -- "$name" $file
                __onionfence_say red "✘ Такой программы нет в списке: $name"
                return 1
            end
            set -l left (command grep -vxF -- $name $file)
            printf '%s\n' $left >$file
            test -n "$left"; or true >$file
            __onionfence_say green "✔ Убрано: $name"
            return
        case '' --wipe-history
        case '*'
            __onionfence_say red "✘ Неизвестный параметр: $action (--wipe-history | off | add | del | list)"
            return 1
    end

    # Сначала всё, что не требует пароля: он может задержать, а эти шаги нужны сразу
    if test -f $file
        for app in (command cat $file)
            pkill -KILL -x -- (string sub -l 15 -- $app) 2>/dev/null
        end
    end
    type -q wl-copy; and wl-copy --clear 2>/dev/null
    type -q xclip; and printf '' | xclip -selection clipboard 2>/dev/null
    type -q xsel; and xsel --clipboard --clear 2>/dev/null
    test "$action" = --wipe-history; and __onionfence_wipe_history

    set -l closed 1
    if not sudo nft list table inet $__onionfence_panic_table >/dev/null 2>&1
        __onionfence_panic_rules | sudo nft -f -
        __onionfence_pipefail $pipestatus; or set closed 0
    end
    if test $closed = 0
        __onionfence_say red "✘ Сеть НЕ закрыта: не удалось применить правила. Отключи сеть вручную"
        return 1
    end
    if command -q ip; and sudo ip netns list 2>/dev/null | string match -q "$__onionfence_ns*"
        sudo sh -c (__onionfence_run_script | string collect) onionfence-run --stop
    end
    __onionfence_guard_stop
    sudo systemctl stop $__onionfence_rotate_unit 2>/dev/null
    sudo systemctl stop $__onionfence_unit
    __onionfence_say red "■ ЭКСТРЕННОЕ ОТКЛЮЧЕНИЕ: сеть закрыта полностью, Tor остановлен"
    set -l done_list "программы из списка закрыты, буфер обмена очищен"
    test "$action" = --wipe-history; and set done_list "$done_list, история команд стёрта"
    echo "  Сделано: $done_list."
    echo "  Вернуть сеть: onionfence panic off. После перезагрузки этот запрет снимается сам."
    if test "$action" != --wipe-history
        echo "  История команд не тронута: onionfence panic --wipe-history сотрёт и её."
    end
    echo "  Это не стирает следы с диска: для этого нужно шифрование диска."
end

# ---------- перенос со старого названия ----------

function __onionfence_old_state_dir
    set -l base $HOME/.local/state
    test -n "$XDG_STATE_HOME"; and set base $XDG_STATE_HOME
    echo $base/torproxy/hide
end

function __onionfence_old_present
    test -e $__onionfence_systemd_dir/torproxy-boot.service; and return 0
    test -e $__onionfence_run_systemd/torproxy-guard.service; and return 0
    test -e $__onionfence_old_etc/rules.nft; and return 0
    test -e $__onionfence_old_run/rules.nft; and return 0
    test -e $__onionfence_dropin_root/$__onionfence_unit.service.d/torproxy.conf; and return 0
    test -e $__onionfence_old_dns/resolv.conf; and return 0
    test -r $__onionfence_torrc; and command grep -qxF '# --- torproxy transparent ---' $__onionfence_torrc; and return 0
    count (__onionfence_old_state_dir)/* >/dev/null; and return 0
    return 1
end

# Программа раньше называлась torproxy. Старые службы и таблица не должны работать рядом с новыми:
# off снял бы только новую таблицу, и пользователь остался бы без сети или, хуже, без защиты.
function __onionfence_migrate
    __onionfence_old_present; or return 0
    __onionfence_say yellow "Программа теперь называется onionfence, переношу настройки со старого имени torproxy"
    if not sudo -v
        __onionfence_say red "✘ Для переноса нужен пароль sudo. Команда не выполнена, старые настройки работают как раньше"
        return 1
    end

    # что было включено
    set -l old_boot 0
    test -e $__onionfence_systemd_dir/torproxy-boot.service; and set old_boot 1
    set -l boot_args
    sudo grep -qs torproxy-strict $__onionfence_old_etc/rules.nft; and set boot_args --strict
    set -l tor_was_enabled 0
    sudo test -e $__onionfence_old_etc/tor-was-enabled; and set tor_was_enabled 1
    set -l old_table 0
    set -l mode
    set -l rules (sudo nft list table inet torproxy 2>/dev/null)
    if test $status -eq 0
        set old_table 1
        string match -q '*torproxy-strict*' -- "$rules"; and set mode strict
    end

    # настройки: в torrc меняются только метки
    if test -e $__onionfence_torrc
        sudo sed -i -e "s/^# --- torproxy transparent ---\$/$__onionfence_begin/" -e "s/^# --- torproxy end ---\$/$__onionfence_end/" -e 's/^# torproxy-allow /# onionfence-allow /' $__onionfence_torrc
        or __onionfence_say yellow "  ⚠ Не удалось обновить метки в $__onionfence_torrc"
        if sudo test -e $__onionfence_torrc.bak-torproxy; and not sudo test -e $__onionfence_torrc.bak-onionfence
            sudo mv $__onionfence_torrc.bak-torproxy $__onionfence_torrc.bak-onionfence
        end
    end
    set -l old_hide (__onionfence_old_state_dir)
    if count $old_hide/* >/dev/null
        set -l new_hide (__onionfence_hide_dir)
        mkdir -p $new_hide
        command mv $old_hide/* $new_hide/
        rmdir $old_hide (path dirname $old_hide) 2>/dev/null
    end

    # старые службы
    sudo systemctl stop torproxy-guard 2>/dev/null
    sudo systemctl disable torproxy-boot torproxy-guard 2>/dev/null
    sudo rm -f $__onionfence_systemd_dir/torproxy-boot.service $__onionfence_systemd_dir/torproxy-guard.service $__onionfence_run_systemd/torproxy-guard.service
    sudo rm -f $__onionfence_old_run/rules.nft
    sudo rmdir $__onionfence_old_run 2>/dev/null
    set -l old_dropin $__onionfence_dropin_root/$__onionfence_unit.service.d/torproxy.conf
    sudo rm -f $old_dropin
    sudo rmdir (path dirname $old_dropin) 2>/dev/null
    sudo rm -f $__onionfence_old_dns/resolv.conf $__onionfence_old_dns/resolve/resolv.conf $__onionfence_old_dns/resolve/stub-resolv.conf
    sudo rmdir $__onionfence_old_dns/resolve $__onionfence_old_dns 2>/dev/null
    sudo rm -f $__onionfence_old_etc/rules.nft $__onionfence_old_etc/tor-was-enabled
    sudo rmdir $__onionfence_old_etc 2>/dev/null
    sudo systemctl daemon-reload

    # Режим был включён: сначала новые правила, потом снимаем старые, чтобы не было ни мгновения без защиты
    if test $old_table = 1
        sudo nft delete table inet $__onionfence_table 2>/dev/null
        if __onionfence_rules $mode | sudo nft -f -
            sudo nft delete table inet torproxy 2>/dev/null
            __onionfence_guard_start $mode
        else
            __onionfence_say red "✘ Не удалось создать новые правила: старая таблица оставлена, защита работает. Выполни onionfence on"
        end
    end
    if test $old_boot = 1
        # отметка о том, кто включил Tor, должна остаться прежней: иначе boot off не вернёт всё как было
        __onionfence_boot on $boot_args >/dev/null
        or __onionfence_say red "✘ Защита при загрузке не перенесена: включи заново, onionfence boot on"
        sudo rm -f $__onionfence_etc/tor-was-enabled
        test $tor_was_enabled = 1; and sudo touch $__onionfence_etc/tor-was-enabled
    end
    __onionfence_tor_dropin_sync
    __onionfence_say green "✔ Настройки перенесены"
    return 0
end

# Временная команда со старым именем
function __onionfence_shim_text
    printf '%s\n' \
        '# Старое имя команды: программа теперь называется onionfence.' \
        '# SPDX-License-Identifier: GPL-3.0-or-later' \
        'function torproxy --description '"'"'Старое имя onionfence'"'" \
        '    echo "torproxy теперь называется onionfence, это имя скоро уберём" >&2' \
        '    onionfence $argv' \
        'end'
end

# ---------- установка ----------

# Запускатель для любых оболочек. Текст совпадает с bin/onionfence: один файл ставится и без него.
function __onionfence_launcher_text
    printf '%s\n' \
        '#!/usr/bin/env -S fish --no-config' \
        '# Запуск onionfence из любой оболочки: сам код лежит в functions/onionfence.fish.' \
        '# SPDX-License-Identifier: GPL-3.0-or-later' \
        '' \
        'set -l self (path resolve (status filename))' \
        'for f in (path dirname $self)/../functions/onionfence.fish \\' \
        '        (path dirname $self)/../share/fish/vendor_functions.d/onionfence.fish \\' \
        '        /usr/share/fish/vendor_functions.d/onionfence.fish \\' \
        '        $XDG_CONFIG_HOME/fish/functions/onionfence.fish \\' \
        '        $HOME/.config/fish/functions/onionfence.fish' \
        '    if test -r $f' \
        '        source $f' \
        '        onionfence $argv' \
        '        exit $status' \
        '    end' \
        'end' \
        'echo "onionfence: не найден onionfence.fish" >&2' \
        'exit 127'
end

function __onionfence_install
    set -l config $HOME/.config/fish
    test -n "$XDG_CONFIG_HOME"; and set config $XDG_CONFIG_HOME/fish
    set -l target $config/functions/onionfence.fish
    set -l bin $HOME/.local/bin
    mkdir -p (path dirname $target) $bin; or return 1

    # из своего же каталога копировать нечего: это повторная установка
    if test "$__onionfence_self" != "$(path resolve $target)"
        command cp -- $__onionfence_self $target; or begin
            __onionfence_say red "✘ Не удалось записать $target"
            return 1
        end
    end
    __onionfence_launcher_text >$bin/onionfence; and chmod 755 $bin/onionfence; or begin
        __onionfence_say red "✘ Не удалось записать $bin/onionfence"
        return 1
    end

    # автодополнение есть только в полной версии, один файл работает и без него
    set -l completion (path dirname $__onionfence_self)/../completions/onionfence.fish
    set -l completion_target $config/completions/onionfence.fish
    if test -r $completion
        mkdir -p (path dirname $completion_target)
        if test "$(path resolve $completion)" != "$(path resolve $completion_target)"
            command cp -- $completion $completion_target
        end
    end

    # после прошлой версии: старый файл заменяем временной командой, старый запускатель больше не нужен
    set -l old_function $config/functions/torproxy.fish
    if test "$(__onionfence_shim_text | string collect)" != "$(command cat $old_function 2>/dev/null | string collect)"
        __onionfence_shim_text >$old_function
    end
    rm -f $bin/torproxy $config/completions/torproxy.fish

    __onionfence_say green "✔ onionfence $__onionfence_version установлен"
    if not contains -- $bin $PATH
        echo
        __onionfence_say yellow "  Каталог $bin не в PATH, поэтому в bash и zsh команды может не быть. Добавь его:"
        echo "    bash:  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
        echo "    zsh:   echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
        echo "    В fish это не нужно."
    end
    echo
    echo "  Открой новый терминал и проверь: onionfence doctor"
    echo "  Руководство: onionfence guide. Если нет интернета: onionfence off"
end

function __onionfence_uninstall
    argparse y/yes -- $argv; or return 1
    if not set -q _flag_yes
        if not test -t 0
            __onionfence_say red "✘ Нужно подтверждение: onionfence uninstall -y"
            return 1
        end
        echo "  Будут выключены Tor-режим и защита при загрузке, возвращены настройки сети,"
        echo "  убран блок из $__onionfence_torrc и удалены файлы программы. Tor останется."
        read -P '  Удалить? [y/N] ' -l answer
        string match -qri '^[yд]' -- "$answer"; or return 1
    end

    # Сначала всё, что держит систему в изменённом виде: пока файлы на месте, это ещё можно отменить
    if test -e $__onionfence_systemd_dir/$__onionfence_boot_unit.service
        __onionfence_boot off; or __onionfence_say yellow "  ⚠ Не удалось снять защиту при загрузке"
    end
    if command -q ip; and sudo ip netns list 2>/dev/null | string match -q "$__onionfence_ns*"
        __onionfence_run --stop
    end
    __onionfence_off -y
    if count (__onionfence_hide_dir)/* >/dev/null
        __onionfence_hide off; or __onionfence_say yellow "  ⚠ Настройки сети не возвращены: они сохранены в "(__onionfence_hide_dir)
    end
    if sudo grep -qxF -- $__onionfence_end $__onionfence_torrc
        sudo sed -i "/^$__onionfence_begin\$/,/^$__onionfence_end\$/d" $__onionfence_torrc
        or __onionfence_say yellow "  ⚠ Не удалось убрать блок из $__onionfence_torrc"
    end
    __onionfence_tor_dropin_remove

    set -l config $HOME/.config/fish
    test -n "$XDG_CONFIG_HOME"; and set config $XDG_CONFIG_HOME/fish
    rm -f $config/functions/onionfence.fish $config/functions/torproxy.fish $config/completions/onionfence.fish $HOME/.local/bin/onionfence
    __onionfence_say green "✔ onionfence удалён, Tor и остальные программы не тронуты"
    test -e $__onionfence_torrc.bak-onionfence; and echo "  Копия настроек до первого запуска: $__onionfence_torrc.bak-onionfence"
    echo "  Если ставили пакетом: sudo pacman -R onionfence"
    echo "  В открытых терминалах команда останется до их закрытия."
end

# ---------- руководство ----------

# Текст руководства: строка «# Заголовок» станет заголовком, остальное выводится как есть
function __onionfence_guide_text
    echo '# Руководство пользователя onionfence '$__onionfence_version
    echo '
onionfence направляет весь TCP-трафик и DNS компьютера через сеть Tor, а всё
остальное (UDP, ICMP, IPv6) блокирует, чтобы ничего не ушло мимо Tor.

# Быстрый старт

  onionfence            открыть меню
  onionfence on         включить Tor-режим
  onionfence status     убедиться: «Через Tor ✔ да»
  onionfence off        выключить и вернуть обычный интернет

После включения перезапусти браузер и программы, открытые раньше: их старые
соединения обрываются. Команды просят пароль sudo, он нужен для настройки
файрвола и службы Tor.

# Меню

Команда onionfence без аргументов открывает меню. Пункт выбирается стрелками
и Enter (без fzf — номером), Esc закрывает меню. Сверху виден текущий статус.

# Основные команды

  on                  включить Tor-режим
  on --strict         то же, но закрыть и доступ к локальной сети (кроме DHCP)
  off                 выключить; спросит, если через Tor работают программы
  off -y              выключить без вопроса
  status              режим, служба, страна, мосты, внешний IP
  newip               новая цепочка; Tor делает это не чаще раза в 10 секунд
  newip --every 10m   менять цепочку по таймеру (30s, 10m, 1h); off снимает
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

Мостам нужно найти своих посредников по имени, пока Tor ещё не подключён.
Поэтому служба Tor спрашивает DNS напрямую у 9.9.9.9, 1.1.1.1 и 8.8.8.8.
Так уходят только запросы самого транспорта мостов, у остальных программ
DNS идёт через Tor.

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
запуск, Tor может остаться работать: onionfence off его остановит.

С параметром --fresh программа получает вместо домашнего каталога пустой каталог
в памяти: нет кук, настроек и истории, а твои файлы ей не видны. Всё исчезает
после закрытия, поэтому важные файлы заранее сохраняй в /tmp.

  run --fresh firefox --no-remote     браузер без следов в домашнем каталоге

# Экстренное отключение

  panic               закрыть сеть полностью, остановить Tor, закрыть программы
  panic --wipe-history  то же и стереть историю команд
  panic off           вернуть сеть
  panic add firefox   закрывать эту программу (del — убрать, list — список)

Закрывает всю сеть, даже Tor, и программы из своего списка и из onionfence run,
очищает буфер обмена. Нужен пароль sudo: программы и буфер обрабатываются ещё
до него. После перезагрузки запрет снимается. Следы с диска команда не стирает:
для этого нужно шифрование диска.

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

Пока режим включён, служба onionfence-guard каждые 3 секунды проверяет таблицу
файрвола и возвращает её, если её стёрли: например, перезапуск nftables.service
очищает все правила. Запрет снимается только командой onionfence off.

# Если что-то не работает

Начни с onionfence doctor: он проверит программы, настройки, порты и часы.

  Нет интернета
      onionfence off вернёт обычный интернет. Так бывает, если Tor упал или при
      включённом boot не подключился: правила намеренно закрывают выход.

  Tor не подключается
      onionfence log покажет причину. Tor заблокирован: onionfence bridges auto.
      Застрял в самом начале: проверь время на компьютере, при сильно неверных
      часах Tor не подключается, а в Tor-режиме NTP заблокирован.

  Страна не меняется
      В этой стране могло не оказаться подходящего узла: попробуй другую или
      onionfence country any. Проверить: onionfence status.

  Сайт не открывается или просит капчу
      Сайты часто блокируют узлы выхода Tor: onionfence newip даст другой.

  Внешний IP: нет ответа
      Сайт проверки не ответил. Повтори onionfence status или выполни leaktest.

  «Для мостов … нет программы-транспорта»
      Установи программу, название которой указано в сообщении.

# Старое название

Раньше программа называлась torproxy. Настройки переносятся сами при первом
запуске любой команды onionfence, а старое имя команды пока продолжает работать.

# Установка и удаление

  install             установить этот файл для текущего пользователя
  uninstall           выключить всё, вернуть настройки и удалить программу
  uninstall -y        то же без вопроса

Подробная инструкция для разных случаев лежит в файле INSTALL.md: с GitHub,
из папки или архива, из одного файла, из пакета.

# Настройки вывода

  NO_COLOR=1 onionfence status      вывод без цвета (стандарт no-color.org)

# Файлы

  /etc/tor/torrc                  настройки в блоке между метками onionfence
  /etc/tor/torrc.bak-onionfence     копия файла до первого изменения
  /etc/onionfence/                  правила для запуска при загрузке
  ~/.local/state/onionfence/hide/   прежние настройки сети для hide off

  /etc/systemd/system/*.service.d/onionfence.conf
                                  настройка службы Tor для мостов и загрузки
  /etc/onionfence-dns/              DNS для транспорта мостов

Правила файрвола лежат в отдельной таблице nftables inet onionfence.
onionfence off удаляет только её, другие правила не затрагиваются.'
end

# onionfence guide: в терминале листается, в файл и конвейер выводится чистым текстом
function __onionfence_guide
    if not test -t 1
        __onionfence_guide_text | string replace -r '^# ' ''
        return
    end
    set -l bold "$(__onionfence_color --bold magenta)"
    set -l off "$(__onionfence_color normal)"
    set -l text (__onionfence_guide_text | string replace -r '^# (.*)$' "$bold\$1$off")
    if command -q less
        # текст всегда в UTF-8: без этого в локали C less показал бы кириллицу как <D0><A0>
        printf '%s\n' $text | env LESSCHARSET=utf-8 less -R -P ' стрелки — прокрутка, q — назад '
    else
        printf '%s\n' $text
    end
end

# ---------- схема цепочки и панель ----------

# Цепочки и соединения Tor, по одной записи в строке
function __onionfence_circuit_lines
    __onionfence_control 'GETINFO circuit-status' 'GETINFO stream-status' 2>/dev/null \
        | string replace -r '^250[-+](?:circuit|stream)-status=' ''
    __onionfence_pipefail $pipestatus
end

# Цепочки, по которым ходит обычный трафик: без служебных и внутренних
function __onionfence_circuit_usable
    for line in (string match -r '^\d+ BUILT .*' -- $argv)
        string match -rq ' PURPOSE=(?:GENERAL|CONFLUX_LINKED)\b' -- $line; or continue
        string match -rq 'IS_INTERNAL|ONEHOP_TUNNEL' -- $line; and continue
        echo $line
    end
end

# Цепочка для показа: 1-я строка — путь, 2-я — сайт (если по ней что-то открыто).
# Сначала последнее открытое соединение, иначе последняя готовая цепочка.
function __onionfence_circuit_pick
    set -l usable (__onionfence_circuit_usable $argv)
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
function __onionfence_flag --argument-names cc
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
function __onionfence_hop_country --argument-names fp
    set -l var __onionfence_cc_$fp
    if not set -q $var
        set -l ip (__onionfence_control "GETINFO ns/id/$fp" 2>/dev/null | string match -r '^r .*' | string split ' ')[7]
        set -l cc
        test -n "$ip"; and set cc (__onionfence_control "GETINFO ip-to-country/$ip" 2>/dev/null | string match -rg '^250-ip-to-country/.*=([a-z]{2})$')
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
function __onionfence_chain --argument-names path target
    set -l parts Ты
    for hop in (string split , -- $path)
        set -l fp (string match -rg '^\$([0-9A-F]{40})' -- $hop)
        set -l cc (__onionfence_hop_country $fp)
        set -a parts (__onionfence_flag $cc)" "(string upper -- $cc)
    end
    test -n "$target"; or set target сайт
    set -a parts (string shorten -m28 -- $target)
    string join ' ──▶ ' -- $parts
end

function __onionfence_circuit
    if not systemctl -q is-active $__onionfence_unit
        __onionfence_say red "✘ Tor не запущен (onionfence on)"
        return 1
    end
    set -l lines (__onionfence_circuit_lines)
    if test $status -ne 0
        __onionfence_say red "✘ Нет связи с Tor через ControlPort"
        return 1
    end
    set -l usable (__onionfence_circuit_usable $lines)
    set -l picked (__onionfence_circuit_pick $lines)
    if not set -q picked[1]
        __onionfence_say yellow "Tor ещё не построил цепочек, подожди немного"
        return 1
    end
    echo
    set -l chain (__onionfence_chain $picked[1] "$picked[2]")
    __onionfence_color --bold
    echo "  $chain"
    __onionfence_color normal
    echo
    set -l hops (string split , -- $picked[1])
    set -l bridges (__onionfence_bridges_current)
    for i in (seq (count $hops))
        set -l nick (string match -rg '~(\w+)$' -- $hops[$i])
        test -n "$nick"; or set nick '(без имени)'
        if test $i -eq 1
            if set -q bridges[1]
                __onionfence_row мост "$nick — видит твой IP, но не сайт"
            else
                __onionfence_row вход "$nick — видит твой IP, но не сайт"
            end
        else if test $i -eq (count $hops)
            __onionfence_row выход "$nick — видит сайт, но не тебя"
        else
            __onionfence_row середина "$nick — не видит ни тебя, ни сайт"
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
function __onionfence_spark
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

function __onionfence_rate --argument-names n
    if test $n -lt 1024
        echo "$n Б/с"
    else if test $n -lt 1048576
        echo (math -s1 $n / 1024)" КБ/с"
    else
        echo (math -s1 $n / 1048576)" МБ/с"
    end
end

function __onionfence_duration --argument-names s
    printf '%02d:%02d:%02d\n' (math "floor($s / 3600)") (math "floor($s / 60) % 60") (math "$s % 60")
end

# IP спрашиваем в фоне: сайт может отвечать десятки секунд, а панель не должна замирать
function __onionfence_watch_ip_start
    set -g __onionfence_w_ip_pid
    command curl -s --max-time (__onionfence_check_timeout) https://check.torproject.org/api/ip >$__onionfence_w_ip_file 2>/dev/null </dev/null &
    set -g __onionfence_w_ip_pid $last_pid
    disown
end

# Если запрос завершился, забирает ответ. Следующий запрос: через 5 минут, а после неудачи через 5 секунд.
function __onionfence_watch_ip_poll
    if test -n "$__onionfence_w_ip_pid"; and kill -0 $__onionfence_w_ip_pid 2>/dev/null
        return
    end
    set -l now (date +%s)
    if test -n "$__onionfence_w_ip_pid"
        set -g __onionfence_w_ip_pid
        set -l check (command cat $__onionfence_w_ip_file 2>/dev/null)
        set -l ip (echo $check | jq -r '.IP // empty' 2>/dev/null)
        if test -n "$ip"
            set -l cc (__onionfence_control "GETINFO ip-to-country/$ip" 2>/dev/null | string match -rg '^250-ip-to-country/.*=([a-z]{2})$')
            set -g __onionfence_w_ip $ip
            set -g __onionfence_w_ip_cc (string upper -- "$cc")
            set -g __onionfence_w_istor (echo $check | jq -r .IsTor 2>/dev/null)
            set -g __onionfence_w_ip_next (math $now + 300)
        else
            set -g __onionfence_w_ip_next (math $now + 5)
        end
    end
    test $now -ge $__onionfence_w_ip_next; and __onionfence_watch_ip_start
end

# Один кадр панели из состояния __onionfence_w_*
function __onionfence_watch_frame
    set -l width 30
    if set -q COLUMNS; and test "$COLUMNS" -lt 60
        set width 12
    end
    echo "$(__onionfence_color title)"'  ╭─ O N I O N F E N C E ─────'"$(__onionfence_color normal) $__onionfence_w_mode"
    if test -z "$__onionfence_w_alive"
        __onionfence_row Tor "$(__onionfence_color red)нет связи$(__onionfence_color normal) (onionfence on)"
    else
        set -l ip "$(__onionfence_color dim)запрос…$(__onionfence_color normal)"
        if test -n "$__onionfence_w_ip"
            set ip "$__onionfence_w_ip $__onionfence_w_ip_cc"
            if test "$__onionfence_w_istor" = true
                set ip "$ip  $(__onionfence_color green)✔ через Tor$(__onionfence_color normal)"
            else
                set ip "$ip  $(__onionfence_color red)✘ не через Tor$(__onionfence_color normal)"
            end
        end
        if test -n "$__onionfence_w_progress"; and test "$__onionfence_w_progress" -lt 100
            set -l bar (__onionfence_bar_text $__onionfence_w_progress)
            set -l stage (__onionfence_stage "$__onionfence_w_tag")
            __onionfence_row Подключение "$bar $__onionfence_w_progress% $stage"
        end
        __onionfence_row "Внешний IP" $ip
        # в график идут только последние значения, сколько помещается
        set -l from (math "max(1, "(count $__onionfence_w_down)" - $width + 1)")
        set -l down_graph (__onionfence_spark $__onionfence_w_down[$from..-1])
        set -l up_graph (__onionfence_spark $__onionfence_w_up[$from..-1])
        __onionfence_row "↓ "(__onionfence_rate $__onionfence_w_down[-1]) "$(__onionfence_color frame)$down_graph$(__onionfence_color normal)"
        __onionfence_row "↑ "(__onionfence_rate $__onionfence_w_up[-1]) "$(__onionfence_color frame)$up_graph$(__onionfence_color normal)"
        __onionfence_row Цепочек "$__onionfence_w_circuits"
        __onionfence_row Работает (__onionfence_duration $__onionfence_w_uptime)
        test -n "$__onionfence_w_chain"; and __onionfence_row Путь $__onionfence_w_chain
    end
    test -n "$__onionfence_w_msg"; and __onionfence_row "" "$(__onionfence_color yellow)$__onionfence_w_msg$(__onionfence_color normal)"
    echo "$(__onionfence_color frame)"'  ╰─'"$(__onionfence_color normal) q — выход, n — новый IP"
end

# Опрос Tor для следующего кадра
function __onionfence_watch_update
    set -l reply (__onionfence_control 'GETINFO traffic/read' 'GETINFO traffic/written' 'GETINFO uptime' 'GETINFO status/bootstrap-phase' 2>/dev/null)
    set -g __onionfence_w_progress (string match -rg 'PROGRESS=(\d+)' -- $reply)
    set -g __onionfence_w_tag (string match -rg 'TAG=(\w+)' -- $reply)
    set -l read (string match -rg '^250-traffic/read=(\d+)$' -- $reply)
    set -l written (string match -rg '^250-traffic/written=(\d+)$' -- $reply)
    set -l uptime (string match -rg '^250-uptime=(\d+)$' -- $reply)
    if test -z "$read" -o -z "$written"
        set -g __onionfence_w_alive
        # Tor перезапущен: у него новый cookie. Пароль здесь спрашивать нельзя, отсюда sudo -n.
        set -l cookie (sudo -n od -An -v -tx1 $__onionfence_cookie 2>/dev/null | string replace -ra '\s' '' | string join '')
        test -n "$cookie"; and set -g __onionfence_cookie_cache $cookie
        set -g __onionfence_w_prev
        return
    end
    set -g __onionfence_w_alive 1
    set -g __onionfence_w_uptime $uptime
    set -l now (date +%s.%N)
    set -l down 0
    set -l up 0
    if set -q __onionfence_w_prev[3]
        set -l dt (math "max($now - $__onionfence_w_prev[1], 0.05)")
        # счётчики сбрасываются при перезапуске Tor: отрицательной скорости не бывает
        set down (math "floor(max($read - $__onionfence_w_prev[2], 0) / $dt)")
        set up (math "floor(max($written - $__onionfence_w_prev[3], 0) / $dt)")
    end
    set -g __onionfence_w_prev $now $read $written
    set -a __onionfence_w_down $down
    set -a __onionfence_w_up $up
    # храним только то, что видно на экране
    set -q __onionfence_w_down[61]; and set -e __onionfence_w_down[1]
    set -q __onionfence_w_up[61]; and set -e __onionfence_w_up[1]

    # цепочки меняются редко, а запрос дороже: раз в 5 кадров
    set -g __onionfence_w_tick (math $__onionfence_w_tick + 1)
    if test (math "$__onionfence_w_tick % 5") -eq 1
        set -l lines (__onionfence_circuit_lines)
        set -g __onionfence_w_circuits (count (__onionfence_circuit_usable $lines))
        set -l picked (__onionfence_circuit_pick $lines)
        set -g __onionfence_w_chain
        set -q picked[1]; and set -g __onionfence_w_chain (__onionfence_chain $picked[1] "$picked[2]")
        set -g __onionfence_w_mode "$(__onionfence_color yellow)режим неизвестен$(__onionfence_color normal)"
        if set -l rules (sudo -n nft list table inet $__onionfence_table 2>/dev/null)
            set -g __onionfence_w_mode "$(__onionfence_color green)● включён$(__onionfence_color normal)"
            string match -q '*onionfence-strict*' -- "$rules"; and set -g __onionfence_w_mode "$(__onionfence_color green)● включён, строгий$(__onionfence_color normal)"
        else if sudo -n true 2>/dev/null
            set -g __onionfence_w_mode "$(__onionfence_color yellow)● Tor работает, но трафик идёт напрямую$(__onionfence_color normal)"
        end
    end
end

function __onionfence_watch_reset
    set -g __onionfence_w_alive
    set -g __onionfence_w_progress
    set -g __onionfence_w_tag
    set -g __onionfence_w_prev
    set -g __onionfence_w_down
    set -g __onionfence_w_up
    set -g __onionfence_w_tick 0
    set -g __onionfence_w_ip
    set -g __onionfence_w_ip_cc
    set -g __onionfence_w_istor
    set -g __onionfence_w_ip_pid
    set -g __onionfence_w_ip_next 0
    set -g __onionfence_w_circuits 0
    set -g __onionfence_w_chain
    set -g __onionfence_w_msg
    set -g __onionfence_w_mode
end

function __onionfence_watch
    if not systemctl -q is-active $__onionfence_unit
        __onionfence_say red "✘ Tor не запущен (onionfence on)"
        return 1
    end
    # спросить пароль можно только сейчас, пока терминал в обычном режиме
    sudo -v; or return 1
    set -l cookie (sudo od -An -v -tx1 $__onionfence_cookie 2>/dev/null | string replace -ra '\s' '' | string join '')
    if test -z "$cookie"
        __onionfence_say red "✘ Не удалось прочитать $__onionfence_cookie"
        return 1
    end
    set -g __onionfence_cookie_cache $cookie
    __onionfence_watch_reset

    # не терминал: один кадр, без управляющих последовательностей
    if not test -t 0; or not test -t 1
        __onionfence_watch_update
        __onionfence_watch_frame
        set -e __onionfence_cookie_cache
        return
    end

    set -g __onionfence_w_ip_file (mktemp)
    set -l saved (stty -g)
    # -isig: Ctrl+C приходит обычной клавишей, иначе fish прервал бы функцию и терминал остался бы сломан
    if not stty -echo -icanon -isig min 0 time 10 2>/dev/null
        __onionfence_say red "✘ Не удалось настроить терминал"
        rm -f $__onionfence_w_ip_file
        set -e __onionfence_cookie_cache
        return 1
    end
    printf '\e[?1049h\e[?25l\e[2J'
    set -l eol (printf '\e[K')
    while true
        __onionfence_watch_update
        __onionfence_watch_ip_poll
        printf '\e[H'
        __onionfence_watch_frame | string replace -r '$' $eol
        printf '\e[J'
        set -g __onionfence_w_msg
        set -l key (dd bs=1 count=1 2>/dev/null | od -An -tx1 | string trim)
        switch "$key"
            case 71 51 03 1b # q, Q, Ctrl+C, Esc
                break
            case 6e 4e # n, N
                __onionfence_newip >/dev/null 2>&1
                set -g __onionfence_w_msg "Новая цепочка запрошена"
                set -g __onionfence_w_ip_next 0
                set -g __onionfence_w_tick 0
        end
    end
    printf '\e[?25h\e[?1049l'
    stty $saved
    test -n "$__onionfence_w_ip_pid"; and kill $__onionfence_w_ip_pid 2>/dev/null
    rm -f $__onionfence_w_ip_file
    set -e __onionfence_cookie_cache
end

# Сменить страну в работающем Tor сразу: SETCONF и закрыть цепочки через старую страну.
# CLOSECIRCUIT, в отличие от NEWNYM, не ограничен «раз в 10 секунд».
function __onionfence_apply_country --argument-names cc
    set -l conf 'RESETCONF ExitNodes StrictNodes'
    test $cc != any; and set conf "SETCONF ExitNodes=\"{$cc}\" StrictNodes=1"
    set -l excl 'RESETCONF ExcludeExitNodes'
    set -l codes (__onionfence_exclude_current)
    set -q codes[1]; and set excl "SETCONF ExcludeExitNodes=\""(string join , -- '{'$codes'}')"\""
    set -l cmds $conf $excl
    if __onionfence_has_conflux
        if test $cc != any; or set -q codes[1]
            set -a cmds 'SETCONF ConfluxEnabled=0'
        else
            set -a cmds 'RESETCONF ConfluxEnabled'
        end
    end
    set -l reply (__onionfence_control $cmds 'GETINFO circuit-status' 2>/dev/null); or return 1
    # 250 OK на AUTHENTICATE, каждую настройку и GETINFO
    test (count (string match '250 OK' -- $reply)) -ge (math (count $cmds) + 2); or return 1
    # единственная цепочка приходит в одной строке с заголовком 250-circuit-status=
    set -l ids (string replace -r '^250[-+]circuit-status=' '' -- $reply | string match -rg '^(\d+) (?:LAUNCHED|BUILT|GUARD_WAIT|EXTENDED) ')
    set -q ids[1]; and __onionfence_control (string replace -r '^' 'CLOSECIRCUIT ' -- $ids) >/dev/null 2>&1
    return 0
end

# onionfence exclude [ru,by | off]: страны, через которые нельзя выходить в интернет
function __onionfence_exclude --argument-names arg
    set -l current (__onionfence_exclude_current)
    if test -z "$arg"
        set -l shown нет
        set -q current[1]; and set shown (string join ', ' -- $current)
        __onionfence_say yellow "Исключённые страны: $shown"
        echo "  onionfence exclude ru,by   не выходить через эти страны"
        echo "  onionfence exclude off     снять запрет"
        return
    end
    set -l codes
    if test "$arg" != off
        set codes (string lower -- $arg | string split -n ,)
        for c in $codes
            if not string match -qr '^[a-z]{2}$' -- $c
                __onionfence_say red "✘ Нужны двухбуквенные коды через запятую (ru,by) или off"
                return 1
            end
        end
        if contains -- (__onionfence_exit_country) $codes
            __onionfence_say red "✘ Страна "(__onionfence_exit_country)" сейчас выбрана для выхода: сначала onionfence country any"
            return 1
        end
    end
    __onionfence_torrc --exclude="$(string join , -- $codes)"; or return 1
    if set -q codes[1]
        __onionfence_say green "✔ Выход запрещён через: "(string join ', ' -- $codes)
    else
        __onionfence_say yellow "● Запрет на страны снят"
    end
    if systemctl -q is-active $__onionfence_unit
        set -l cc (__onionfence_exit_country)
        contains -- $cc любая; and set cc any
        if not __onionfence_apply_country $cc
            sudo systemctl reload $__onionfence_unit
            __onionfence_say yellow "  Tor применит это к новым соединениям в течение ~10 секунд"
        end
    end
end

# onionfence bridges auto [--no-direct]: пробует способы подключения по очереди и оставляет первый рабочий.
# Правила nftables не трогает: Tor выходит в сеть сам, остальной трафик в это время закрыт, как и был.
function __onionfence_bridges_auto
    argparse no-direct -- $argv; or return 1
    set -l saved (__onionfence_bridges_current)
    set -l was_active 0
    systemctl -q is-active $__onionfence_unit; and set was_active 1

    set -l ways obfs4 snowflake
    set -q _flag_no_direct; or set ways direct $ways
    set -l found
    for way in $ways
        set -l timeout $__onionfence_auto_timeout
        set -l args --no-bridges
        switch $way
            case obfs4
                set args --bridge=$__onionfence_builtin_obfs4
            case snowflake
                set args --bridge=$__onionfence_builtin_snowflake
                # snowflake сначала ищет добровольца, ему нужно больше времени
                set timeout (math $timeout x 2)
        end
        if test $way != direct; and test -z "$(__onionfence_pt_binary $way)"
            __onionfence_say yellow "  $way пропущен: "(__onionfence_pt_hint $way)
            continue
        end
        echo "  Пробую: $way (до $timeout с)"
        __onionfence_torrc $args; or return 1
        set -l started (date '+%Y-%m-%d %H:%M:%S')
        sudo systemctl restart $__onionfence_unit; or continue
        __onionfence_wait_bootstrap $timeout $started
        set -l rc $status
        echo
        if test $rc -eq 0
            set found $way
            break
        end
        test $rc -eq 2; and __onionfence_say red "✘ Не удалось прочитать журнал Tor"
    end

    if test -z "$found"
        # настройки возвращаем: ни один способ не лучше прежнего
        set -l args --no-bridges
        set -q saved[1]; and set args --bridge=$saved
        __onionfence_torrc $args; or return 1
        if test $was_active = 1
            sudo systemctl restart $__onionfence_unit
        else
            sudo systemctl stop $__onionfence_unit
        end
        __onionfence_say red "✘ Ни один способ не подключился. Настройки мостов не изменены."
        echo "  Свои мосты обычно работают лучше: Telegram @GetBridgesBot, затем onionfence bridges add"
        return 1
    end

    __onionfence_say green "✔ Работает: $found. Мосты: "(__onionfence_bridges_summary)
    if test $was_active = 1
        set -l opts
        __onionfence_is_strict; and set opts --strict
        __onionfence_on $opts
    else
        # проба не должна оставлять Tor работающим: режим включает только onionfence on
        sudo systemctl stop $__onionfence_unit
        echo "  Включить Tor-режим: onionfence on"
    end
end

# onionfence bridges [auto | snowflake | obfs4 | add [СТРОКА…] | off]
function __onionfence_bridges --argument-names mode
    set -l lines
    switch "$mode"
        case ''
            __onionfence_say yellow "Мосты сейчас: "(__onionfence_bridges_summary)
            echo "  onionfence bridges auto        подобрать рабочий способ (--no-direct: не пробовать без мостов)"
            echo "  onionfence bridges snowflake   встроенные Snowflake — работают почти везде, но медленнее"
            echo "  onionfence bridges obfs4       встроенные obfs4 — быстрые, но их адреса часто блокируют"
            echo "  onionfence bridges add         свои мосты: Telegram @GetBridgesBot или bridges.torproject.org"
            echo "  onionfence bridges off         без мостов"
            return
        case auto
            __onionfence_bridges_auto $argv[2..]
            return
        case off
            __onionfence_torrc --no-bridges; or return 1
        case snowflake
            set lines $__onionfence_builtin_snowflake
        case obfs4
            set lines $__onionfence_builtin_obfs4
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
                __onionfence_say yellow "Ничего не добавлено"
                return 1
            end
            for line in $input
                set -l b (__onionfence_bridge_normalize $line)
                if test -z "$b"
                    __onionfence_say red "✘ Не похоже на строку моста: $line"
                    return 1
                end
                set -a lines $b
            end
            # свои мосты добавляются к уже настроенным, без повторов
            set lines (printf '%s\n' (__onionfence_bridges_current) $lines | awk '!seen[$0]++')
        case '*'
            __onionfence_say red "✘ Неизвестный режим: $mode (auto | snowflake | obfs4 | add | off)"
            return 1
    end

    if set -q lines[1]
        set -l args
        for b in $lines
            set -a args --bridge $b
        end
        __onionfence_torrc $args; or return 1
    end
    __onionfence_say green "✔ Мосты: "(__onionfence_bridges_summary)

    # смена мостов требует перезапуска Tor; если режим включён — переподключаемся в том же режиме
    if systemctl -q is-active $__onionfence_unit
        set -l opts
        __onionfence_is_strict; and set opts --strict
        __onionfence_on $opts
    end
end

# ---------- меню ----------

function __onionfence_pick --argument-names prompt
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

function __onionfence_menu
    set -l greeted
    while true
        clear
        if test -z "$greeted"
            __onionfence_splash
            set greeted 1
        else
            __onionfence_banner
        end
        __onionfence_status --quick
        echo
        set -l choice (printf '%s\n' \
            '🟢  Включить Tor-режим' \
            '🔒  Включить в строгом режиме (без локальной сети)' \
            '🔴  Выключить Tor-режим' \
            '🚨  Экстренное отключение' \
            '── Наблюдение ──' \
            '🔍  Проверить IP и страну' \
            '🛡️  Проверка утечек' \
            '🩺  Найти неполадку' \
            '🗺️  Схема цепочки' \
            '📊  Живая панель' \
            '📜  Журнал Tor (q — назад)' \
            '── Анонимность ──' \
            '🌐  Запустить Tor Browser' \
            '🎯  Запустить одну программу через Tor' \
            '🧼  Чистый запуск программы' \
            '🔄  Новый IP (новая цепочка)' \
            '⏱️  Смена цепочки по таймеру' \
            '🌍  Страна выхода' \
            '🚫  Исключить страны' \
            '🕵️  Скрыть устройство в локальной сети' \
            '🧹  Убрать метаданные из файла' \
            '── Настройки ──' \
            '🌉  Мосты (обход блокировок Tor)' \
            '🔓  Исключения: мимо Tor' \
            '🚀  Защита при загрузке' \
            '📖  Руководство пользователя (q — назад)' \
            '🚪  Выход' | __onionfence_pick 'действие')

        switch "$choice"
            case '── *'
                # заголовок раздела: просто показываем меню снова
                continue
            case '*Экстренное*'
                __onionfence_panic
            case '*Чистый запуск*'
                read -P '  Команда (например, firefox --no-remote): ' -t -l cmd
                set -q cmd[1]; and __onionfence_run --fresh (string unescape -- $cmd)
            case '*по таймеру*'
                __onionfence_rotate
                read -P '  Интервал (30s, 10m, 1h), off — снять, Enter — назад: ' -l interval
                test -n "$interval"; and __onionfence_rotate $interval
            case '*строгом*'
                __onionfence_on --strict
            case '*Включить*'
                __onionfence_on
            case '*Выключить*'
                __onionfence_off
            case '*Проверить*'
                __onionfence_status
            case '*утечек*'
                __onionfence_leaktest
            case '*неполадку*'
                __onionfence_doctor
            case '*Схема*'
                __onionfence_circuit
            case '*панель*'
                __onionfence_watch
                continue
            case '*одну программу*'
                read -P '  Команда (например, curl https://example.com): ' -t -l cmd
                # read -t оставляет кавычки в словах
                set -q cmd[1]; and __onionfence_run (string unescape -- $cmd)
            case '*Исключения*'
                __onionfence_allow
                read -P '  Адрес или интерфейс (del АДРЕС — убрать, off — все, Enter — назад): ' -t -l a
                set -q a[1]; and __onionfence_allow $a
            case '*Tor Browser*'
                __onionfence_browser
            case '*Скрыть*'
                set -l a (printf '%s\n' 'on   Случайный MAC, скрыть имя компьютера' 'off  Вернуть как было' | __onionfence_pick 'скрытие')
                set a (string split -f1 ' ' -- $a)
                test -n "$a"; and __onionfence_hide $a
            case '*загрузке*'
                set -l a (printf '%s\n' 'on   Весь трафик через Tor с момента загрузки' 'off  Обычная загрузка' | __onionfence_pick 'загрузка')
                set a (string split -f1 ' ' -- $a)
                test -n "$a"; and __onionfence_boot $a
            case '*Исключить*'
                read -P '  Коды через запятую (ru,by) или off: ' -l codes
                test -n "$codes"; and __onionfence_exclude $codes
            case '*метаданные*'
                read -P '  Путь к файлу: ' -l f
                # read не раскрывает ~, а при перетаскивании файла терминал добавляет кавычки
                set f (string trim -c " '\"" -- $f | string replace -r '^~(?=/|$)' $HOME)
                test -n "$f"; and __onionfence_clean $f
            case '*Новый IP*'
                __onionfence_newip
            case '*Страна*'
                set -l c (printf '%s\n' \
                    'any  Любая (по умолчанию)' 'de   Германия' 'nl   Нидерланды' 'ch   Швейцария' \
                    'se   Швеция' 'fi   Финляндия' 'fr   Франция' 'gb   Великобритания' \
                    'us   США' 'ca   Канада' 'jp   Япония' 'other  Ввести код вручную' \
                    | __onionfence_pick 'страна')
                set c (string split -f1 ' ' -- $c)
                if test "$c" = other
                    read -P '  Код страны (2 буквы): ' c
                end
                test -n "$c"; and __onionfence_country $c
            case '*Мосты*'
                set -l m (printf '%s\n' \
                    'auto       Подобрать автоматически' \
                    'snowflake  Snowflake — встроенные, работают почти везде' \
                    'obfs4      obfs4 — встроенные, быстрые, но часто заблокированы' \
                    'add        Добавить свои (Telegram @GetBridgesBot)' \
                    'off        Без мостов' \
                    | __onionfence_pick 'мосты')
                set m (string split -f1 ' ' -- $m)
                test -n "$m"; and __onionfence_bridges $m
            case '*Руководство*'
                __onionfence_guide
                continue
            case '*Журнал*'
                # pager вместо -f: Ctrl+C в fish прервал бы всё меню
                sudo journalctl -u $__onionfence_unit -n 300 -e
                continue
            case '*'
                return
        end
        echo
        read -P "$(__onionfence_color dim)"'  Enter — назад в меню'"$(__onionfence_color normal)" -l __pause
    end
end
