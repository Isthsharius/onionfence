#!/usr/bin/env fish
# Тесты torproxy.
#   fish ~/.config/fish/tests/torproxy/run.fish            — все тесты
#   fish ~/.config/fish/tests/torproxy/run.fish --offline  — без живого Tor (без интернета)
# Системные Tor, torrc и правила сети не затрагиваются: всё идёт во временном каталоге,
# сетевые тесты — в изолированном namespace, живой Tor — от текущего пользователя на портах 19xxx.

argparse offline keep -- $argv; or exit 2

set -gx DIR (path resolve (status dirname))
set -q SRC; or set -gx SRC (path resolve $DIR/../../functions/torproxy.fish)
set -gx T (mktemp -d /tmp/torproxy-test.XXXXXX)
set -gx MOCK_NFT record
source $DIR/lib.fish

function reset_state
    rm -f $T/calls.log $T/ruleset.nft $T/tor.state
    set -g __torproxy_torrc $T/torrc
    set -g __torproxy_timeout 3
    set -gx MOCK_BOOT 5 100
    set -gx MOCK_SUDO_CACHED 1
    set -gx MOCK_RULES 0
    set -gx MOCK_CHECK '{"IsTor":true,"IP":"1.2.3.4"}'
    set -e MOCK_RESTART_FAIL MOCK_NFT_FAIL MOCK_FAIL
end

# ======================================================================
section "Синтаксис и справка"
fish -n $SRC
t_eq "torproxy.fish без синтаксических ошибок" 0 $status
torproxy help >/dev/null
t_eq "torproxy help → код 0" 0 $status
torproxy -h >/dev/null
t_eq "torproxy -h → код 0" 0 $status
set -l out (torproxy blabla | nocolor)
t_eq "неизвестная команда → код 1" 1 $pipestatus[1]
t_has "неизвестная команда показывает справку" "torproxy newip" $out
t_eq "в справке все 8 команд" 8 (torproxy help | nocolor | string match -r '^\s+torproxy' | count)

# ======================================================================
section "Полоска прогресса"
for case in "0 0 30" "47 14 16" "100 30 0"
    echo $case | read -l pct full empty
    set -l bar (__torproxy_bar $pct | nocolor)
    t_eq "$pct%: заполнено $full, пусто $empty" "$full $empty $pct%" \
        (string match -ra █ -- $bar | count)" "(string match -ra ░ -- $bar | count)" "(string trim (string sub -s -4 -- $bar))
end

# ======================================================================
section "torrc: запись и обновление блока"
reset_state
set -l orig 'User tor' 'Log notice syslog' 'DataDirectory /var/lib/tor'
set -l block_v1 '' '# --- torproxy transparent ---' 'VirtualAddrNetworkIPv4 10.192.0.0/10' 'AutomapHostsOnResolve 1' \
    'TransPort 127.0.0.1:9040 IsolateClientAddr IsolateClientProtocol IsolateDestAddr IsolateDestPort' 'DNSPort 127.0.0.1:5353'

function body_without_block
    sed "/^$__torproxy_begin\$/,/^$__torproxy_end\$/d" $__torproxy_torrc | string match -v ''
end

printf '%s\n' $orig >$__torproxy_torrc
__torproxy_torrc
t_eq "чистый torrc: блок добавлен один раз" 1 (grep -c 'torproxy transparent' $__torproxy_torrc)
t_eq "чистый torrc: есть end-маркер" 1 (grep -c 'torproxy end' $__torproxy_torrc)
t_eq "чистый torrc: исходные строки не изменены" (string join '|' $orig) (string join '|' (body_without_block))
t_eq "чистый torrc: создана резервная копия" (string join '|' $orig) (string join '|' (command cat $__torproxy_torrc.bak-torproxy))
t_has "DNSPort на 9053" "DNSPort 127.0.0.1:9053" (command cat $__torproxy_torrc)
t_has "ControlPort на 9051" "ControlPort 127.0.0.1:9051" (command cat $__torproxy_torrc)
t_has "TransPort на 9040" "TransPort 127.0.0.1:9040" (command cat $__torproxy_torrc)
tor --verify-config -f $__torproxy_torrc --DataDirectory $T/verify-data --User '' >$T/verify.out 2>&1
t_eq "tor --verify-config принимает torrc" 0 $status

set -l sum1 (md5sum <$__torproxy_torrc)
__torproxy_torrc
t_eq "повторный вызов ничего не меняет" $sum1 (md5sum <$__torproxy_torrc)

rm -f $__torproxy_torrc.bak-torproxy
printf '%s\n' $orig $block_v1 >$__torproxy_torrc
__torproxy_torrc
t_eq "старый блок v1: заменён, блок один" 1 (grep -c 'torproxy transparent' $__torproxy_torrc)
t_lacks "старый блок v1: порт 5353 убран" ":5353" (command cat $__torproxy_torrc)
t_eq "старый блок v1: исходные строки целы" (string join '|' $orig) (string join '|' (body_without_block))

printf '%s\n' $orig '# --- torproxy transparent ---' 'DNSPort 127.0.0.1:5353' 'ExitNodes {se}' 'StrictNodes 1' '# --- torproxy end ---' >$__torproxy_torrc
__torproxy_torrc
t_lacks "старый блок v2: порт 5353 убран" ":5353" (command cat $__torproxy_torrc)
t_eq "старый блок v2: страна выхода сохранена" se (__torproxy_exit_country)

# ======================================================================
section "Страна выхода"
reset_state
printf '%s\n' 'ExitNodes {us}' $orig >$__torproxy_torrc
t_eq "без настройки — любая" любая (__torproxy_exit_country)
torproxy country de >/dev/null
t_eq "country de" de (__torproxy_exit_country)
torproxy country NL >/dev/null
t_eq "country NL → nl (регистр)" nl (__torproxy_exit_country)
t_eq "в блоке одна строка ExitNodes" 1 (sed -n "/^$__torproxy_begin\$/,/^$__torproxy_end\$/p" $__torproxy_torrc | grep -c '^ExitNodes')
t_eq "в блоке одна строка StrictNodes" 1 (grep -c '^StrictNodes' $__torproxy_torrc)
torproxy country any >/dev/null
t_eq "country any → любая" любая (__torproxy_exit_country)
t_eq "country any убирает StrictNodes" 0 (grep -c '^StrictNodes' $__torproxy_torrc)
t_eq "ExitNodes пользователя вне блока сохранён" 'ExitNodes {us}' (head -1 $__torproxy_torrc)
for bad in germany d1 DEU 'de;rm'
    torproxy country $bad >/dev/null
    t_eq "country «$bad» отклонён (код 1)" 1 $status
end
t_eq "после неверных кодов страна не изменилась" любая (__torproxy_exit_country)
t_has "country без кода показывает текущую" "любая" (torproxy country | nocolor)
rm -f $T/calls.log
torproxy country de >/dev/null
t_lacks "Tor выключен → reload не вызывается" "reload" (command cat $T/calls.log 2>/dev/null)
echo 1 >$T/tor.state
set -l out (torproxy country se | nocolor)
t_has "Tor включён, ControlPort недоступен → reload tor" "systemctl reload tor" (command cat $T/calls.log 2>/dev/null)
t_has "… и честное предупреждение о задержке" "10 секунд" $out

# ======================================================================
section "Мосты"
reset_state
printf '%s\n' $orig >$__torproxy_torrc
# заглушка программы-транспорта (настоящий lyrebird может быть не установлен)
mkdir -p $T/bin
printf '#!/bin/sh\nexit 0\n' >$T/bin/lyrebird
chmod +x $T/bin/lyrebird
set -l saved_path $PATH
set -gx PATH $T/bin $PATH

function block
    sed -n "/^$__torproxy_begin\$/,/^$__torproxy_end\$/p" $__torproxy_torrc
end

t_eq "по умолчанию мостов нет" нет (__torproxy_bridges_summary)
torproxy bridges snowflake >/dev/null
t_eq "snowflake: код 0" 0 $status
t_eq "snowflake: 2 встроенных моста" 2 (block | grep -c '^Bridge snowflake ')
t_eq "snowflake: UseBridges 1" 1 (block | grep -cx 'UseBridges 1')
t_eq "snowflake: транспорт lyrebird" "ClientTransportPlugin snowflake exec $T/bin/lyrebird" (block | grep '^ClientTransportPlugin')
t_eq "snowflake: сводка для статуса" "snowflake ×2" (__torproxy_bridges_summary)
t_has "статус показывает мосты" "snowflake ×2" (__torproxy_status --quick | nocolor)
tor --verify-config -f $__torproxy_torrc --DataDirectory $T/verify-data --User '' >$T/verify.out 2>&1
t_eq "tor --verify-config принимает torrc с мостами" 0 $status

torproxy country de >/dev/null
t_eq "смена страны не теряет мосты" 2 (block | grep -c '^Bridge ')
__torproxy_torrc
t_eq "перезапись блока (on) не теряет мосты" 2 (block | grep -c '^Bridge ')
t_eq "перезапись блока не теряет страну" de (__torproxy_exit_country)

torproxy bridges obfs4 >/dev/null
t_eq "obfs4: заменяет snowflake на 7 встроенных obfs4" "7 0" (block | grep -c '^Bridge obfs4 ')" "(block | grep -c '^Bridge snowflake ')

set -l wt 'webtunnel [2001:db8::1]:443 0123456789ABCDEF0123456789ABCDEF01234567 url=https://example.com/abc ver=0.0.1'
torproxy bridges add "  Bridge   obfs4  5.6.7.8:443 AAAA cert=x+y/z= iat-mode=0  " $wt >/dev/null
t_eq "add: код 0" 0 $status
t_eq "add: префикс Bridge и лишние пробелы убраны" 1 (block | grep -cx 'Bridge obfs4 5.6.7.8:443 AAAA cert=x+y/z= iat-mode=0')
t_eq "add: добавляет к уже настроенным" "obfs4 ×8, webtunnel ×1" (__torproxy_bridges_summary)
t_eq "add: транспорты obfs4 и webtunnel" "obfs4 webtunnel" (block | string match -rg '^ClientTransportPlugin (\S+)' | string join ' ')
torproxy bridges add $wt >/dev/null
t_eq "add: повтор не дублируется" 1 (block | grep -c '^Bridge webtunnel ')
torproxy bridges add '1.2.3.4:9001 ABCDEF' >/dev/null
t_has "add: обычный мост без транспорта" "обычные ×1" (__torproxy_bridges_summary)

set -l sum (md5sum <$__torproxy_torrc)
for bad in hello 'obfs4 999.1:443' 'obfs4 1.2.3.4' 'obfs4 1.2.3.4:443 x #коммент'
    torproxy bridges add $bad >/dev/null
    t_eq "add «$bad» отклонён" 1 $status
end
t_eq "после отклонённых строк torrc не изменился" $sum (md5sum <$__torproxy_torrc)
torproxy bridges add "$(printf 'obfs4 9.9.9.9:443 BBBB cert=q\nExitNodes {ru}')" >/dev/null
t_eq "перевод строки в мосте не создаёт новую директиву torrc" 0 (grep -c '^ExitNodes {ru}' $__torproxy_torrc)

printf 'obfs4 7.7.7.7:443 CCCC cert=w iat-mode=0\n\n' | torproxy bridges add >/dev/null
t_eq "add без аргументов читает строки из ввода" 1 (block | grep -c '^Bridge obfs4 7.7.7.7:443')
set -l out (printf '\n' | torproxy bridges add | nocolor)
t_eq "add с пустым вводом → код 1" 1 $pipestatus[2]
t_has "add с пустым вводом → сообщение" "Ничего не добавлено" $out
torproxy bridges blabla >/dev/null
t_eq "неизвестный режим → код 1" 1 $status
t_has "bridges без аргументов показывает подсказку" "@GetBridgesBot" (torproxy bridges | nocolor)

torproxy bridges off >/dev/null
t_eq "off: мостов нет" нет (__torproxy_bridges_summary)
t_eq "off: нет UseBridges/ClientTransportPlugin" 0 (block | grep -cE '^(UseBridges|ClientTransportPlugin|Bridge )')
t_eq "off: страна сохранена" de (__torproxy_exit_country)

set -gx PATH $saved_path
if not command -sq lyrebird; and not command -sq snowflake-client
    set -l sum (md5sum <$__torproxy_torrc)
    set -l out (torproxy bridges snowflake | nocolor)
    t_eq "нет lyrebird → код 1" 1 $pipestatus[1]
    t_has "нет lyrebird → подсказка установки" "paru -S lyrebird-proxy" $out
    t_eq "нет lyrebird → torrc не изменился" $sum (md5sum <$__torproxy_torrc)
else
    echo "  (проверка «нет lyrebird» пропущена: он установлен в системе)"
end
set -gx PATH $T/bin $saved_path

rm -f $T/calls.log
echo 1 >$T/tor.state
torproxy bridges snowflake >/dev/null 2>&1
t_has "Tor работает → смена мостов переподключает (on)" "systemctl restart tor" (command cat $T/calls.log)

reset_state
set -gx MOCK_BOOT 50
set -g __torproxy_timeout 2
set -l out (torproxy on 2>&1 | nocolor)
t_has "с мостами время ожидания удваивается" "за 4 секунд" $out
t_has "режим не был включён → правила не применены" "правила НЕ применены" $out
set -l out (MOCK_RULES=1 torproxy on 2>&1 | nocolor)
t_has "режим уже включён → честное сообщение: интернет закрыт" "остаётся включённым" $out
torproxy bridges off >/dev/null 2>&1
set -gx PATH $saved_path

# ======================================================================
section "Статус"
reset_state
set -gx MOCK_SUDO_CACHED 0
t_has "быстрый статус без sudo не спрашивает пароль" "нужен sudo" (__torproxy_status --quick | nocolor)
set -gx MOCK_SUDO_CACHED 1
t_has "правила есть → ВКЛЮЧЁН" "ВКЛЮЧЁН" (MOCK_RULES=1 __torproxy_status --quick | nocolor)
t_has "правил нет → выключен" "выключен" (__torproxy_status --quick | nocolor)
t_lacks "быстрый статус не ходит в сеть" "Внешний IP" (__torproxy_status --quick | nocolor)
set -l out (__torproxy_status | nocolor)
t_has "IsTor=true → ✔ да" "✔ да" $out
t_has "IP и страна показаны" "1.2.3.4 DE, Berlin" $out
t_has "IsTor=false → ✘ нет" "✘ нет" (MOCK_CHECK='{"IsTor":false,"IP":"5.6.7.8"}' __torproxy_status | nocolor)
for resp in '' '<html>502 Bad Gateway</html>' '{"IsTor":true}'
    set -l out (MOCK_CHECK=$resp __torproxy_status 2>&1 | nocolor)
    t_has "ответ «$resp» → нет ответа" "нет ответа" $out
    t_lacks "ответ «$resp» → без ошибок test/jq" "test:" $out
end

# ======================================================================
section "Новый IP (ControlPort)"
reset_state
set -g __torproxy_cookie $T/cookie
set -g __torproxy_ctlport 19151
torproxy newip >/dev/null
t_eq "Tor выключен → код 1" 1 $status
echo 1 >$T/tor.state
t_has "нет cookie → понятная ошибка" "Нет ControlPort" (torproxy newip | nocolor)
head -c 32 /dev/urandom >$T/cookie
python3 -I $DIR/fake_control.py 19151 (python3 -c "import sys;print(open(sys.argv[1],'rb').read().hex())" $T/cookie) $T/ctl.log &
set -l fake $last_pid
sleep 0.5
set -l out (torproxy newip | nocolor)
t_eq "верный cookie → код 0" 0 $pipestatus[1]
t_has "верный cookie → цепочка запрошена" "Новая цепочка" $out
set -l out (__torproxy_status | nocolor)
t_has "статус при запущенном Tor: страна из GeoIP Tor" "1.2.3.4 DE" $out
t_lacks "статус при запущенном Tor: ipinfo не нужен" "Berlin" $out
printf "" >$T/ctl.log; rm -f $T/calls.log
set -l out (torproxy country de | nocolor)
t_has "country при работающем Tor: SETCONF сразу" 'SETCONF ExitNodes="{de}" StrictNodes=1' (command cat $T/ctl.log 2>/dev/null)
t_eq "country: закрыты живые цепочки, CLOSED не трогается" "CLOSECIRCUIT 5|CLOSECIRCUIT 7" (string join '|' (grep CLOSECIRCUIT $T/ctl.log))
t_lacks "country: без HUP-перезагрузки" "reload" (command cat $T/calls.log 2>/dev/null)
t_lacks "country: без предупреждения о 10 секундах" "10 секунд" $out
printf "" >$T/ctl.log # не rm: поддельный ControlPort держит файл открытым
torproxy country any >/dev/null
t_has "country any при работающем Tor: RESETCONF" "RESETCONF ExitNodes StrictNodes" (command cat $T/ctl.log 2>/dev/null)
head -c 32 /dev/urandom >$T/cookie
set -l out (torproxy newip | nocolor)
t_eq "неверный cookie → код 1" 1 $pipestatus[1]
t_has "неверный cookie → ответ Tor показан" "515" $out
kill $fake
wait $fake 2>/dev/null
set -l out (torproxy newip | nocolor)
t_eq "ControlPort молчит → код 1" 1 $pipestatus[1]
t_has "ControlPort молчит → понятная ошибка (pipefail)" "не отвечает" $out
set -l out (MOCK_FAIL=od torproxy newip | nocolor)
t_eq "cookie не читается → код 1" 1 $pipestatus[1]
t_has "cookie не читается → понятная ошибка (pipefail)" "не удалось прочитать" $out
set -g __torproxy_cookie /var/lib/tor/control_auth_cookie
set -g __torproxy_ctlport 9051

# ======================================================================
section "torproxy on / off (заглушки, без изменения сети)"
reset_state
printf '%s\n' $orig >$__torproxy_torrc
set -l out (torproxy on 2>&1 | nocolor)
t_eq "on → код 0" 0 $pipestatus[1]
t_has "прогресс доходит до 100%" "100%" $out
t_has "правила: DNS на DNSPort 9053" "udp dport 53 redirect to :9053" (command cat $T/ruleset.nft 2>/dev/null)
t_has "правила: TCP на TransPort 9040" "meta l4proto tcp redirect to :9040" (command cat $T/ruleset.nft 2>/dev/null)
t_has "правила: uid Tor = "(id -u tor) "skuid "(id -u tor)" accept" (command cat $T/ruleset.nft 2>/dev/null)
t_lacks "правила: нет 5353" "5353" (command cat $T/ruleset.nft 2>/dev/null)
t_lacks "правила: нет established" "established" (grep -v "#" $T/ruleset.nft)
t_has "кэш DNS сброшен" "resolvectl flush-caches" (command cat $T/calls.log 2>/dev/null)

reset_state
set -gx MOCK_BOOT 5 50
set -l out (torproxy on 2>&1 | nocolor)
t_eq "Tor не загрузился → код 1" 1 $pipestatus[1]
t_has "Tor не загрузился → сообщение" "не подключился за 3 секунд" $out
t_eq "Tor не загрузился → правила не применялись" 0 (test -e $T/ruleset.nft; and echo 1; or echo 0)
t_has "Tor не загрузился → Tor остановлен" "systemctl stop tor" (command cat $T/calls.log 2>/dev/null)

reset_state
set -gx MOCK_RESTART_FAIL 1
torproxy on >/dev/null 2>&1
t_eq "Tor не запустился → код 1" 1 $status
t_eq "Tor не запустился → правила не применялись" 0 (test -e $T/ruleset.nft; and echo 1; or echo 0)

reset_state
set -gx MOCK_NFT_FAIL 1
set -l out (torproxy on 2>&1 | nocolor)
t_eq "nft отказал → код 1" 1 $pipestatus[1]
t_has "nft отказал → сообщение" "Ошибка применения правил" $out

reset_state
printf '%s\n' $orig >$__torproxy_torrc
set -l out (MOCK_FAIL=tee torproxy on 2>&1 | nocolor)
t_eq "torrc не записался → код 1 (pipefail)" 1 $pipestatus[1]
t_has "torrc не записался → сообщение" "Не удалось записать" $out
t_lacks "torrc не записался → Tor не перезапускался" "restart" (command cat $T/calls.log 2>/dev/null)
set -l out (MOCK_FAIL=tee torproxy country de 2>&1 | nocolor)
t_eq "country: torrc не записался → код 1" 1 $pipestatus[1]
t_lacks "country: при ошибке нет ложного «✔»" "✔" $out

reset_state
set -l out (MOCK_FAIL=journalctl torproxy on 2>&1 | nocolor)
t_eq "журнал не читается → код 1 (pipefail)" 1 $pipestatus[1]
t_has "журнал не читается → сообщение сразу, без ожидания" "Не удалось прочитать журнал" $out
t_eq "журнал не читается → правила не применялись" 0 (test -e $T/ruleset.nft; and echo 1; or echo 0)

section "__torproxy_pipefail"
__torproxy_pipefail 0 0 0
t_eq "все звенья 0 → 0" 0 $status
__torproxy_pipefail 0 3 0
t_eq "упало среднее звено → его код 3" 3 $status
__torproxy_pipefail 1 0
t_eq "упало первое звено → 1 (без pipefail было бы 0)" 1 $status

reset_state
torproxy off >/dev/null
t_has "off удаляет таблицу" "nft delete table inet torproxy" (command cat $T/calls.log 2>/dev/null)
t_has "off останавливает Tor" "systemctl stop tor" (command cat $T/calls.log 2>/dev/null)

# ======================================================================
section "Терминал без цветов (TERM=dumb)"
# set_color там ничего не выводит; без кавычек вокруг "$(set_color …)" пропадал весь текст
printf '%s\n' $orig >$T/dumb.torrc
set -l out (env TERM=dumb fish -c '
    source $DIR/lib.fish
    set -g __torproxy_torrc $T/dumb.torrc
    set -g __torproxy_timeout 2
    torproxy help
    __torproxy_bar 47; echo
    __torproxy_status --quick
    MOCK_FAIL=journalctl torproxy on' 2>&1)
t_eq "справка: все 8 команд видны" 8 (string match -r '^\s+torproxy' -- $out | count)
t_has "полоска прогресса видна" "47%" $out
t_has "статус виден" "Страна выхода" $out
t_has "сообщение об ошибке видно" "Не удалось прочитать журнал" $out

# ======================================================================
section "Меню"
reset_state
fish $DIR/menu.fish

# ======================================================================
section "Межсетевой экран (изолированный namespace)"
set -l sub (string split : (grep "^$USER:" /etc/subuid))
if test (count $sub) -eq 3; and command -q unshare setpriv
    rm -f $T/calls.log
    env -u MOCK_NFT unshare --map-root-user --map-users=1:$sub[2]:$sub[3] --map-groups=1:$sub[2]:$sub[3] -n fish $DIR/netns.fish
else
    echo "  (пропущено: нет subuid в /etc/subuid или unshare/setpriv)"
end

# ======================================================================
if not set -q _flag_offline
    section "Живой Tor (свой процесс на портах 19xxx, системный Tor не трогается)"
    reset_state
    set -gx LIVE 1
    set -gx LIVE_SOCKS 19050
    set -g __torproxy_transport 19040
    set -g __torproxy_dnsport 19053
    set -g __torproxy_ctlport 19051
    set -g __torproxy_cookie $T/tordata/control_auth_cookie
    set -g __torproxy_timeout 120
    set -g __torproxy_torrc $T/live.torrc
    mkdir -m 700 $T/tordata
    printf '%s\n' "DataDirectory $T/tordata" "SocksPort 127.0.0.1:$LIVE_SOCKS" "Log notice file $T/tor.log" >$__torproxy_torrc

    set -l out (torproxy on 2>&1 | nocolor)
    t_eq "on с настоящим Tor → код 0" 0 $pipestatus[1]
    t_has "Tor подключился (100%)" "100%" $out
    t_has "check.torproject.org подтверждает Tor" "✔ да" $out
    t_has "правила используют тестовые порты" "redirect to :19053" (command cat $T/ruleset.nft 2>/dev/null)

    set -l ans (python3 -I -c "
import socket,struct,sys
q=struct.pack('>HHHHHH',0x1234,0x0100,1,0,0,0)+b''.join(bytes([len(p)])+p.encode() for p in 'check.torproject.org'.split('.'))+b'\0'+struct.pack('>HH',1,1)
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.settimeout(15); s.sendto(q,('127.0.0.1',int(sys.argv[1])))
r=s.recv(512); print(struct.unpack('>H',r[6:8])[0])" $__torproxy_dnsport 2>&1)
    t_eq "DNSPort отвечает на A-запрос (есть ответы)" 1 (test "$ans" -gt 0 2>/dev/null; and echo 1; or echo "$ans")

    python3 -I -c "import socket,sys; socket.create_connection(('127.0.0.1',int(sys.argv[1])),3)" $__torproxy_transport 2>/dev/null
    t_eq "TransPort принимает соединения" 0 $status

    set -l out (torproxy newip | nocolor)
    t_eq "newip с настоящим Tor → код 0" 0 $pipestatus[1]

    torproxy country de >/dev/null
    t_has "country de → Tor принял ExitNodes" "ExitNodes={de}" (__torproxy_control 'GETCONF ExitNodes')
    set -l out (torproxy status | nocolor)
    t_has "status: выход действительно в Германии" " DE" (string match '*Внешний IP*' -- $out)
    t_has "status: по-прежнему через Tor" "✔ да" $out
    torproxy country any >/dev/null
    t_lacks "country any → ExitNodes снят" "{de}" (__torproxy_control 'GETCONF ExitNodes')

    if command -sq lyrebird
        set -l out (torproxy bridges snowflake 2>&1 | nocolor)
        t_eq "живые мосты snowflake → код 0" 0 $pipestatus[1]
        t_has "через snowflake Tor подключился" "✔ да" $out
        set -l out (torproxy bridges off 2>&1 | nocolor)
        t_has "мосты выключены → снова напрямую в Tor" "✔ да" $out
    else
        echo "  (живой тест мостов пропущен: нет lyrebird — paru -S lyrebird-proxy)"
    end

    torproxy off >/dev/null
    sleep 1
    __mock_tor_alive
    t_eq "off → процесс Tor завершён" 1 $status
    set -e LIVE
end

# ======================================================================
set -l passed (grep -c '^PASS' $T/results)
set -l failed (grep -c '^FAIL' $T/results)
echo
if test $failed -eq 0
    echo "$(set_color --bold green)  Все тесты пройдены: $passed$(set_color normal)"
else
    echo "$(set_color --bold red)  Провалено: $failed из "(math $passed + $failed)"$(set_color normal)"
    grep '^FAIL' $T/results | string replace FAIL '   ✘'
end
set -q _flag_keep; and echo "  Каталог теста: $T"; or rm -rf $T
test $failed -eq 0
