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
    set -e MOCK_RESTART_FAIL MOCK_NFT_FAIL MOCK_FAIL MOCK_NFT_CHECK_FAIL MOCK_TOR_ENABLED MOCK_ENABLE_FAIL
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
t_eq "в справке все 14 команд" 14 (torproxy help | nocolor | string match -r '^\s+torproxy' | count)

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
section "Платформы: Arch и Debian/Ubuntu"
reset_state
mkdir -p $T/root-deb/usr/lib/systemd/system $T/root-deb-old/lib/systemd/system $T/root-arch/usr/lib/systemd/system
touch $T/root-deb/usr/lib/systemd/system/tor@default.service $T/root-deb-old/lib/systemd/system/tor@default.service
touch $T/root-arch/usr/lib/systemd/system/tor.service

function detect_in --argument-names root
    __torproxy_detect $root
    echo "$__torproxy_platform $__torproxy_unit $__torproxy_cookie"
end
t_eq "Arch: служба tor, cookie в /var/lib/tor" "arch tor /var/lib/tor/control_auth_cookie" (detect_in $T/root-arch)
t_eq "Debian/Ubuntu: служба tor@default, cookie в /run/tor" "debian tor@default /run/tor/control.authcookie" (detect_in $T/root-deb)
t_eq "старый Debian (/lib без /usr): тоже tor@default" "debian tor@default /run/tor/control.authcookie" (detect_in $T/root-deb-old)
# пустой список в "$root/..." раньше превращал проверку в `test -e` без пути → всегда «Debian»
__torproxy_detect
set -l expected arch
test -e /usr/lib/systemd/system/tor@default.service -o -e /lib/systemd/system/tor@default.service; and set expected debian
t_eq "без аргумента — определяется по этой системе ($expected)" $expected $__torproxy_platform

function getent
    test "$argv[1]" = passwd; and contains -- $argv[2] $MOCK_USERS
end
set -gx MOCK_USERS debian-tor
__torproxy_detect $T/root-deb
t_eq "пользователь Tor на Debian: debian-tor" debian-tor $__torproxy_user
set -gx MOCK_USERS tor debian-tor
__torproxy_detect $T/root-arch
t_eq "пользователь Tor на Arch: tor" tor $__torproxy_user
set -gx MOCK_USERS
__torproxy_detect $T/root-arch
t_eq "Tor не установлен: пользователя нет" "" "$__torproxy_user"
set -l out (torproxy on 2>&1 | nocolor)
t_eq "Tor не установлен → on, код 1" 1 $pipestatus[1]
t_has "Tor не установлен → подсказка установки" "apt install tor" $out
functions -e getent
set -e MOCK_USERS
__torproxy_detect
set -g __torproxy_platform arch
set -g __torproxy_unit tor

# транспорты: на Debian/Ubuntu AppArmor пускает obfs4proxy и snowflake-client, а не lyrebird
mkdir -p $T/pt
for b in lyrebird obfs4proxy snowflake-client
    printf '#!/bin/sh\n' >$T/pt/$b
    chmod +x $T/pt/$b
end
set -l saved_path $PATH
set -gx PATH $T/pt $PATH
# только заглушки из $T/pt, без системных программ (lyrebird может быть установлен)
function pt
    set -lx PATH $T/pt
    __torproxy_pt_binary $argv[1] | path basename
end
set -g __torproxy_platform arch
t_eq "Arch: obfs4 / snowflake / webtunnel → lyrebird" "lyrebird lyrebird lyrebird" (pt obfs4)" "(pt snowflake)" "(pt webtunnel)
set -g __torproxy_platform debian
t_eq "Debian: obfs4 → obfs4proxy, snowflake → snowflake-client" "obfs4proxy snowflake-client" (pt obfs4)" "(pt snowflake)
rm $T/pt/lyrebird
t_eq "obfs4proxy не умеет webtunnel" "" "$(pt webtunnel)"
t_has "Debian: подсказка для snowflake — apt" "apt install snowflake-client" (__torproxy_pt_hint snowflake)
t_has "Debian: webtunnel — честно, что пакета нет" "пакета для webtunnel нет" (__torproxy_pt_hint webtunnel)
set -g __torproxy_platform arch
t_has "Arch: подсказка — lyrebird из AUR" "paru -S lyrebird-proxy" (__torproxy_pt_hint obfs4)

# весь цикл on/off на Debian идёт через tor@default
reset_state
set -g __torproxy_platform debian
set -g __torproxy_unit tor@default
printf '%s\n' $orig >$__torproxy_torrc
torproxy on >/dev/null 2>&1
t_eq "Debian: on → код 0" 0 $status
t_has "Debian: перезапуск tor@default" "systemctl restart tor@default" (command cat $T/calls.log 2>/dev/null)
t_has "Debian: журнал tor@default" "journalctl -u tor@default" (command cat $T/calls.log 2>/dev/null)
torproxy off >/dev/null 2>&1
t_has "Debian: off останавливает tor@default" "systemctl stop tor@default" (command cat $T/calls.log 2>/dev/null)
t_has "version показывает платформу" "debian: служба tor@default" (torproxy version)
t_has "version показывает номер версии" "torproxy 0.2.0" (torproxy version)
set -g __torproxy_platform arch
set -g __torproxy_unit tor

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
t_eq "без мостов сайт проверки ждём 30 секунд" 30 (__torproxy_check_timeout)
torproxy bridges snowflake >/dev/null
t_eq "snowflake: код 0" 0 $status
t_eq "с мостами сайт проверки ждём 60 секунд" 60 (__torproxy_check_timeout)
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
t_has "правила: uid Tor = "(id -u $__torproxy_user) "skuid "(id -u $__torproxy_user)" accept" (command cat $T/ruleset.nft 2>/dev/null)
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
section "Tor Browser"
reset_state
torproxy browser >/dev/null
t_eq "Tor выключен → код 1" 1 $status
echo 1 >$T/tor.state
mkdir -p $T/tb $T/empty
printf '#!/bin/sh\nenv >"%s/browser.env"\n' $T >$T/tb/tor-browser
chmod +x $T/tb/tor-browser
set -l saved_path $PATH
set -gx PATH $T/tb $PATH
set -l out (torproxy browser | nocolor)
t_eq "запуск → код 0" 0 $pipestatus[1]
set -gx PATH $saved_path
for i in (seq 30)
    test -s $T/browser.env; and break
    sleep 0.1
end
set -l tbenv (command cat $T/browser.env 2>/dev/null)
t_has "свой Tor браузер не запускает" "TOR_SKIP_LAUNCH=1" $tbenv
t_has "провайдер Tor отключён" "TOR_PROVIDER=none" $tbenv
t_has "браузер идёт в системный SocksPort" "TOR_SOCKS_PORT=9050" $tbenv
t_has "… на локальном адресе" "TOR_SOCKS_HOST=127.0.0.1" $tbenv

function browser_bin --argument-names home path
    set -lx HOME $home
    set -lx PATH $path
    __torproxy_browser_binary
end
set -l tbb $T/home/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser
mkdir -p $tbb $T/launcher
printf '#!/bin/sh\n' >$tbb/start-tor-browser
printf '#!/bin/sh\n' >$T/launcher/torbrowser-launcher
chmod +x $tbb/start-tor-browser $T/launcher/torbrowser-launcher
t_eq "находит браузер, скачанный лаунчером" $tbb/start-tor-browser (browser_bin $T/home $T/empty)
t_eq "скачанный браузер важнее лаунчера" $tbb/start-tor-browser (browser_bin $T/home $T/launcher)
t_eq "браузера нет → лаунчер скачает его" $T/launcher/torbrowser-launcher (browser_bin $T/empty $T/launcher)
t_eq "нет ни браузера, ни лаунчера" "" "$(browser_bin $T/empty $T/empty)"
functions -c __torproxy_browser_binary __saved_browser_binary
functions -e __torproxy_browser_binary
function __torproxy_browser_binary
end
set -l out (torproxy browser | nocolor)
t_eq "не найден → код 1" 1 $pipestatus[1]
t_has "не найден → подсказка установки" "torbrowser-launcher" $out
functions -e __torproxy_browser_binary
functions -c __saved_browser_binary __torproxy_browser_binary

# ======================================================================
section "Защита при загрузке"
reset_state
printf '%s\n' $orig >$__torproxy_torrc
set -g __torproxy_etc $T/etc
set -g __torproxy_systemd_dir $T/sd
mkdir -p $T/sd
set -l service $T/sd/torproxy-boot.service
torproxy boot on >/dev/null
t_eq "boot on → код 0" 0 $status
t_has "правила записаны" "redirect to :9040" (command cat $T/etc/rules.nft 2>/dev/null)
t_lacks "по умолчанию не строгий" "torproxy-strict" (command cat $T/etc/rules.nft 2>/dev/null)
t_has "torrc обновлён" "TransPort" (command cat $__torproxy_torrc)
t_has "службы включены" "systemctl enable torproxy-boot tor" (command cat $T/calls.log 2>/dev/null)
t_lacks "сейчас ничего не запускается" "start" (command cat $T/calls.log 2>/dev/null)
t_has "служба раньше сети" "Before=network-pre.target" (command cat $service 2>/dev/null)
t_has "служба позже nftables.service (его flush стёр бы правила)" "After=local-fs.target nftables.service" (command cat $service 2>/dev/null)
t_has "служба в sysinit.target" "WantedBy=sysinit.target" (command cat $service 2>/dev/null)
if command -q systemd-analyze; and command -q nft
    systemd-analyze verify $service >$T/verify-unit.out 2>&1
    t_eq "systemd-analyze принимает службу" 0 $status
end
torproxy boot on --strict >/dev/null
t_has "boot on --strict → строгие правила" "torproxy-strict" (command cat $T/etc/rules.nft 2>/dev/null)
t_eq "Tor не был включён → отметки нет" 0 (test -e $T/etc/tor-was-enabled; and echo 1; or echo 0)

rm -f $T/calls.log
torproxy boot off >/dev/null
t_eq "boot off → служба удалена" 0 (test -e $service; and echo 1; or echo 0)
t_eq "boot off → правила удалены" 0 (test -e $T/etc; and echo 1; or echo 0)
t_eq "boot off → Tor снова выключен при загрузке" 1 (grep -cx "systemctl disable tor" $T/calls.log)

rm -f $T/calls.log
torproxy boot on >/dev/null
set -gx MOCK_TOR_ENABLED 1
torproxy boot on >/dev/null
t_eq "повторный on: Tor включён нами, а не пользователем → отметки нет" 0 (test -e $T/etc/tor-was-enabled; and echo 1; or echo 0)
torproxy boot off >/dev/null
t_eq "… и boot off выключает его" 1 (grep -cx "systemctl disable tor" $T/calls.log)

rm -f $T/calls.log
set -l out (torproxy boot off | nocolor)
t_eq "boot off без on → код 0" 0 $pipestatus[1]
t_has "boot off без on → сообщение" "и так выключена" $out
t_lacks "boot off без on → автозапуск Tor не трогает" "disable" (command cat $T/calls.log 2>/dev/null)

rm -f $T/calls.log
torproxy boot on >/dev/null
t_eq "Tor включал сам пользователь → отметка" 1 (test -e $T/etc/tor-was-enabled; and echo 1; or echo 0)
torproxy boot off >/dev/null
t_eq "… и boot off его не трогает" 0 (grep -cx "systemctl disable tor" $T/calls.log)
set -e MOCK_TOR_ENABLED

rm -f $T/calls.log $service
set -gx MOCK_NFT_CHECK_FAIL 1
set -l out (torproxy boot on | nocolor)
t_eq "nft не принял правила → код 1" 1 $pipestatus[1]
t_has "nft не принял → сообщение" "защита не включена" $out
t_eq "nft не принял → служба не создана" 0 (test -e $service; and echo 1; or echo 0)
t_lacks "nft не принял → ничего не включено" "enable" (command cat $T/calls.log 2>/dev/null)
set -e MOCK_NFT_CHECK_FAIL
set -gx MOCK_ENABLE_FAIL 1
torproxy boot on >/dev/null
t_eq "systemctl enable упал → код 1" 1 $status
set -e MOCK_ENABLE_FAIL
torproxy boot off >/dev/null
torproxy boot blabla >/dev/null
t_eq "неизвестное действие → код 1" 1 $status
t_has "boot без аргументов — подсказка" "torproxy boot on" (torproxy boot | nocolor)

touch $T/boot.enabled
t_has "статус: защита при загрузке вкл" "При загрузке     вкл" (__torproxy_status --quick | nocolor)
t_has "off напоминает, что режим вернётся при загрузке" "При следующей загрузке" (torproxy off | nocolor)
rm -f $T/boot.enabled
t_has "статус: защита при загрузке выкл" "При загрузке     выкл" (__torproxy_status --quick | nocolor)
set -g __torproxy_etc /etc/torproxy
set -g __torproxy_systemd_dir /etc/systemd/system

# ======================================================================
section "Предупреждение при выключении"
reset_state
function ss
    printf '%s\n' \
        '0 0 192.168.1.5:45110 93.184.216.34:443 users:(("opera",pid=1,fd=1))' \
        '0 0 192.168.1.5:45111 93.184.216.35:443 users:(("opera",pid=1,fd=2))' \
        '0 0 192.168.1.5:45112 1.1.1.1:443 users:(("telegram-desktop",pid=2,fd=1))' \
        '0 0 192.168.1.5:22 192.168.1.9:50000 users:(("sshd",pid=3,fd=1))' \
        '0 0 127.0.0.1:5000 127.0.0.1:5001 users:(("local",pid=4,fd=1))' \
        '0 0 192.168.1.5:9001 5.6.7.8:443 users:(("tor",pid=5,fd=1))' \
        '0 0 [::1]:5000 [::1]:5001 users:(("local6",pid=6,fd=1))'
end
t_eq "программы: только идущие наружу, без повторов и без Tor" "opera telegram-desktop" (string join ' ' (__torproxy_online_apps))
set -gx MOCK_RULES 1
set -l out (torproxy off </dev/null | nocolor)
t_eq "без терминала: не спрашивает, выключает" 0 $pipestatus[1]
t_has "предупреждение называет программы" "opera, telegram-desktop" $out
t_has "… и выключает" "systemctl stop tor" (command cat $T/calls.log 2>/dev/null)
function isatty
    true
end
rm -f $T/calls.log
set -l out (echo n | torproxy off | nocolor)
t_eq "ответ «n» → код 1" 1 $pipestatus[2]
t_has "ответ «n» → отменено" "Отменено" $out
t_lacks "ответ «n» → правила не сняты" "delete table" (command cat $T/calls.log 2>/dev/null)
t_lacks "ответ «n» → Tor работает" "systemctl stop" (command cat $T/calls.log 2>/dev/null)
rm -f $T/calls.log
echo | torproxy off >/dev/null
t_lacks "пустой ответ (Enter) = отмена" "delete table" (command cat $T/calls.log 2>/dev/null)
for yes in y Y да
    rm -f $T/calls.log
    echo $yes | torproxy off >/dev/null
    t_has "ответ «$yes» → выключает" "delete table" (command cat $T/calls.log 2>/dev/null)
end
rm -f $T/calls.log
torproxy off -y >/dev/null
t_has "off -y: без вопроса" "delete table" (command cat $T/calls.log 2>/dev/null)
functions -e isatty
set -gx MOCK_RULES 0
t_lacks "режим не включён → без предупреждения" "Через Tor" (torproxy off </dev/null | nocolor)
functions -e ss

# ======================================================================
section "Скрытие устройства"
reset_state
set -gx MOCK_MAC ''
function nmcli
    echo "nmcli $argv" >>$T/nm.log
    switch "$argv"
        case '-t -f UUID,TYPE connection show --active'
            test "$MOCK_NM_NOCONN" = 1; and return
            printf '%s\n' uuid-wifi:802-11-wireless uuid-lo:loopback uuid-eth:802-3-ethernet
        case '-t -f UUID connection show --active'
            printf '%s\n' uuid-wifi uuid-lo uuid-eth
        case '-g *.cloned-mac-address connection show *'
            echo $MOCK_MAC
        case '-g *'
            echo -1
        case 'connection up *'
            test "$MOCK_NM_UP_FAIL" != 1
    end
end
set -l hd $XDG_STATE_HOME/torproxy/hide
t_has "статус: скрытие выключено" "Скрытие          выкл" (__torproxy_status --quick | nocolor)
torproxy hide on >/dev/null
t_eq "hide on → код 0" 0 $status
t_has "Wi-Fi: случайный MAC" "modify uuid-wifi 802-11-wireless.cloned-mac-address random" (command cat $T/nm.log)
t_has "Ethernet: случайный MAC" "modify uuid-eth 802-3-ethernet.cloned-mac-address random" (command cat $T/nm.log)
t_has "имя не передаётся по DHCP" "ipv4.dhcp-send-hostname no ipv6.dhcp-send-hostname no" (command cat $T/nm.log)
t_has "имя не передаётся по mDNS и LLMNR" "connection.mdns no connection.llmnr no" (command cat $T/nm.log)
t_has "подключение перезапущено" "connection up uuid-wifi" (command cat $T/nm.log)
t_lacks "loopback не трогаем" "uuid-lo" (grep -E 'modify|connection up' $T/nm.log)
t_eq "старые значения сохранены" "802-11-wireless.cloned-mac-address=|ipv4.dhcp-send-hostname=-1|ipv6.dhcp-send-hostname=-1|connection.mdns=-1|connection.llmnr=-1" (string join '|' (command cat $hd/uuid-wifi))
t_has "статус: скрытие включено" "Скрытие          вкл" (__torproxy_status --quick | nocolor)
t_has "hide без аргументов показывает состояние" "Устройство скрыто" (torproxy hide | nocolor)
set -gx MOCK_MAC random
torproxy hide on >/dev/null
t_has "повторный on не затирает настоящие значения" "cloned-mac-address=" (head -1 $hd/uuid-wifi)
t_lacks "… в файле нет random" "random" (command cat $hd/uuid-wifi)
printf '' >$T/nm.log
torproxy hide off >/dev/null
t_eq "hide off → код 0" 0 $status
t_has "off возвращает прежние значения" "modify uuid-wifi 802-11-wireless.cloned-mac-address  ipv4.dhcp-send-hostname -1 ipv6.dhcp-send-hostname -1 connection.mdns -1 connection.llmnr -1" (command cat $T/nm.log)
t_has "off перезапускает подключение" "connection up uuid-wifi" (command cat $T/nm.log)
t_eq "off удаляет сохранённое" 0 (count $hd/*)
set -gx MOCK_NM_UP_FAIL 1
set -l out (torproxy hide on | nocolor)
t_eq "подключение не поднялось → код 1" 1 $pipestatus[1]
t_has "… и подсказка, как вернуть" "torproxy hide off" $out
set -e MOCK_NM_UP_FAIL
torproxy hide off >/dev/null
set -gx MOCK_NM_NOCONN 1
torproxy hide on >/dev/null
t_eq "нет Wi-Fi и Ethernet → код 1" 1 $status
set -e MOCK_NM_NOCONN
torproxy hide blabla >/dev/null
t_eq "неизвестное действие → код 1" 1 $status
functions -e nmcli
if command -q nmcli
    # настоящий nmcli без связи со службой: принимает ли он наши свойства и значения
    command nmcli --offline connection add type wifi con-name t ssid t 802-11-wireless.cloned-mac-address random \
        ipv4.dhcp-send-hostname no ipv6.dhcp-send-hostname no connection.mdns no connection.llmnr no >/dev/null 2>&1
    t_eq "nmcli принимает настройки скрытия (Wi-Fi)" 0 $status
    command nmcli --offline connection add type ethernet con-name t 802-3-ethernet.cloned-mac-address random >/dev/null 2>&1
    t_eq "nmcli принимает настройки скрытия (Ethernet)" 0 $status
    command nmcli --offline connection add type wifi con-name t ssid t 802-11-wireless.cloned-mac-address '' \
        ipv4.dhcp-send-hostname -1 ipv6.dhcp-send-hostname -1 connection.mdns -1 connection.llmnr -1 >/dev/null 2>&1
    t_eq "nmcli принимает значения для возврата" 0 $status
end

# ======================================================================
section "Метаданные"
reset_state
torproxy clean >/dev/null
t_eq "без файла → код 1" 1 $status
function mat2
    test "$MOCK_MAT2_FAIL" != 1
end
printf x >"$T/моё фото.jpg"
set -l out (torproxy clean "$T/моё фото.jpg" | nocolor)
t_eq "файл с пробелом → код 0" 0 $pipestatus[1]
t_has "показывает имя очищенного файла" "моё фото.cleaned.jpg" $out
t_has "предупреждает о том, что mat2 не убирает" "не убирает" $out
torproxy clean $T/nofile >/dev/null
t_eq "нет файла → код 1" 1 $status
set -gx MOCK_MAT2_FAIL 1
torproxy clean "$T/моё фото.jpg" >/dev/null
t_eq "mat2 не справился → код 1" 1 $status
set -e MOCK_MAT2_FAIL
functions -e mat2
if command -q mat2
    python3 -c "
import struct,sys,zlib
def c(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d))
open(sys.argv[1],'wb').write(b'\x89PNG\r\n\x1a\n'+c(b'IHDR',struct.pack('>IIBBBBB',1,1,8,0,0,0,0))+c(b'tEXt',b'Author\0SecretName')+c(b'IDAT',zlib.compress(b'\0\0'))+c(b'IEND',b''))" $T/meta.png
    t_has "исходный файл содержит метаданные" "SecretName" (command mat2 --show $T/meta.png)
    torproxy clean $T/meta.png >/dev/null
    t_eq "настоящий mat2 → код 0" 0 $status
    t_lacks "настоящий mat2 убрал автора" "SecretName" (command mat2 --show $T/meta.cleaned.png)
else
    set -l out (torproxy clean $T/meta.png | nocolor)
    t_has "mat2 не установлен → подсказка" "mat2" $out
end

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
t_eq "справка: все 14 команд видны" 14 (string match -r '^\s+torproxy' -- $out | count)
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

    set -l out (torproxy country de | nocolor)
    t_lacks "country de применён сразу через ControlPort (без HUP)" "10 секунд" $out
    t_has "country de → Tor принял ExitNodes" "ExitNodes={de}" (__torproxy_control 'GETCONF ExitNodes')
    set -l out (torproxy status | nocolor)
    if not t_has "status: выход действительно в Германии" " DE" (string match '*Внешний IP*' -- $out)
        echo "  --- диагностика: "(tor --version | head -1)
        __torproxy_control 'GETCONF ExitNodes StrictNodes' 'GETINFO circuit-status' | string replace -r '^' '      '
    end
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
