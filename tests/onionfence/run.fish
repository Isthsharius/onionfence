#!/usr/bin/env fish
# Тесты onionfence.
#   fish ~/.config/fish/tests/onionfence/run.fish            — все тесты
#   fish ~/.config/fish/tests/onionfence/run.fish --offline  — без живого Tor (без интернета)
# Системные Tor, torrc и правила сети не затрагиваются: всё идёт во временном каталоге,
# сетевые тесты — в изолированном namespace, живой Tor — от текущего пользователя на портах 19xxx.

argparse offline keep -- $argv; or exit 2

set -gx DIR (path resolve (status dirname))
set -q SRC; or set -gx SRC (path resolve $DIR/../../functions/onionfence.fish)
set -gx T (mktemp -d /tmp/onionfence-test.XXXXXX)
set -gx MOCK_NFT record
source $DIR/lib.fish

function reset_state
    rm -f $T/calls.log $T/ruleset.nft $T/tor.state
    set -g __onionfence_torrc $T/torrc
    set -g __onionfence_timeout 3
    set -gx MOCK_BOOT 5 100
    set -gx MOCK_SUDO_CACHED 1
    set -gx MOCK_RULES 0
    set -gx MOCK_CHECK '{"IsTor":true,"IP":"1.2.3.4"}'
    set -e MOCK_RESTART_FAIL MOCK_NFT_FAIL MOCK_FAIL MOCK_NFT_CHECK_FAIL MOCK_TOR_ENABLED MOCK_ENABLE_FAIL
end

# ======================================================================
section "Синтаксис и справка"
fish -n $SRC
t_eq "onionfence.fish без синтаксических ошибок" 0 $status
onionfence help >/dev/null
t_eq "onionfence help → код 0" 0 $status
onionfence -h >/dev/null
t_eq "onionfence -h → код 0" 0 $status
set -l out (onionfence blabla | nocolor)
t_eq "неизвестная команда → код 1" 1 $pipestatus[1]
t_has "неизвестная команда показывает справку" "onionfence newip" $out
t_eq "в справке все 23 команд" 23 (onionfence help | nocolor | string match -r '^\s+onionfence' | count)

# ======================================================================
section "Полоска прогресса"
for case in "0 0 30" "47 14 16" "100 30 0"
    echo $case | read -l pct full empty
    set -l bar (__onionfence_bar $pct | nocolor)
    t_eq "$pct%: заполнено $full, пусто $empty" "$full $empty $pct%" \
        (string match -ra █ -- $bar | count)" "(string match -ra ░ -- $bar | count)" "(string trim (string sub -s -4 -- $bar))
end

# ======================================================================
section "torrc: запись и обновление блока"
reset_state
set -l orig 'User tor' 'Log notice syslog' 'DataDirectory /var/lib/tor'
set -l block_v1 '' '# --- onionfence transparent ---' 'VirtualAddrNetworkIPv4 10.192.0.0/10' 'AutomapHostsOnResolve 1' \
    'TransPort 127.0.0.1:9040 IsolateClientAddr IsolateClientProtocol IsolateDestAddr IsolateDestPort' 'DNSPort 127.0.0.1:5353'

function body_without_block
    sed "/^$__onionfence_begin\$/,/^$__onionfence_end\$/d" $__onionfence_torrc | string match -v ''
end

printf '%s\n' $orig >$__onionfence_torrc
__onionfence_torrc
t_eq "чистый torrc: блок добавлен один раз" 1 (grep -c 'onionfence transparent' $__onionfence_torrc)
t_eq "чистый torrc: есть end-маркер" 1 (grep -c 'onionfence end' $__onionfence_torrc)
t_eq "чистый torrc: исходные строки не изменены" (string join '|' $orig) (string join '|' (body_without_block))
t_eq "чистый torrc: создана резервная копия" (string join '|' $orig) (string join '|' (command cat $__onionfence_torrc.bak-onionfence))
t_has "DNSPort на 9053" "DNSPort 127.0.0.1:9053" (command cat $__onionfence_torrc)
t_has "ControlPort на 9051" "ControlPort 127.0.0.1:9051" (command cat $__onionfence_torrc)
t_has "TransPort на 9040" "TransPort 127.0.0.1:9040" (command cat $__onionfence_torrc)
tor --verify-config -f $__onionfence_torrc --DataDirectory $T/verify-data --User '' >$T/verify.out 2>&1
t_eq "tor --verify-config принимает torrc" 0 $status

set -l sum1 (md5sum <$__onionfence_torrc)
__onionfence_torrc
t_eq "повторный вызов ничего не меняет" $sum1 (md5sum <$__onionfence_torrc)

rm -f $__onionfence_torrc.bak-onionfence
printf '%s\n' $orig $block_v1 >$__onionfence_torrc
__onionfence_torrc
t_eq "старый блок v1: заменён, блок один" 1 (grep -c 'onionfence transparent' $__onionfence_torrc)
t_lacks "старый блок v1: порт 5353 убран" ":5353" (command cat $__onionfence_torrc)
t_eq "старый блок v1: исходные строки целы" (string join '|' $orig) (string join '|' (body_without_block))

printf '%s\n' $orig '# --- onionfence transparent ---' 'DNSPort 127.0.0.1:5353' 'ExitNodes {se}' 'StrictNodes 1' '# --- onionfence end ---' >$__onionfence_torrc
__onionfence_torrc
t_lacks "старый блок v2: порт 5353 убран" ":5353" (command cat $__onionfence_torrc)
t_eq "старый блок v2: страна выхода сохранена" se (__onionfence_exit_country)

# ======================================================================
section "Страна выхода"
reset_state
printf '%s\n' 'ExitNodes {us}' $orig >$__onionfence_torrc
t_eq "без настройки — любая" любая (__onionfence_exit_country)
onionfence country de >/dev/null
t_eq "country de" de (__onionfence_exit_country)
onionfence country NL >/dev/null
t_eq "country NL → nl (регистр)" nl (__onionfence_exit_country)
t_eq "в блоке одна строка ExitNodes" 1 (sed -n "/^$__onionfence_begin\$/,/^$__onionfence_end\$/p" $__onionfence_torrc | grep -c '^ExitNodes')
t_eq "в блоке одна строка StrictNodes" 1 (grep -c '^StrictNodes' $__onionfence_torrc)
onionfence country any >/dev/null
t_eq "country any → любая" любая (__onionfence_exit_country)
t_eq "country any убирает StrictNodes" 0 (grep -c '^StrictNodes' $__onionfence_torrc)
t_eq "ExitNodes пользователя вне блока сохранён" 'ExitNodes {us}' (head -1 $__onionfence_torrc)
for bad in germany d1 DEU 'de;rm'
    onionfence country $bad >/dev/null
    t_eq "country «$bad» отклонён (код 1)" 1 $status
end
t_eq "после неверных кодов страна не изменилась" любая (__onionfence_exit_country)
t_has "country без кода показывает текущую" "любая" (onionfence country | nocolor)
rm -f $T/calls.log
onionfence country de >/dev/null
t_lacks "Tor выключен → reload не вызывается" "reload" (command cat $T/calls.log 2>/dev/null)
echo 1 >$T/tor.state
set -l out (onionfence country se | nocolor)
t_has "Tor включён, ControlPort недоступен → reload tor" "systemctl reload tor" (command cat $T/calls.log 2>/dev/null)
t_has "… и честное предупреждение о задержке" "10 секунд" $out

# ======================================================================
section "Платформы: Arch и Debian/Ubuntu"
reset_state
mkdir -p $T/root-deb/usr/lib/systemd/system $T/root-deb-old/lib/systemd/system $T/root-arch/usr/lib/systemd/system
touch $T/root-deb/usr/lib/systemd/system/tor@default.service $T/root-deb-old/lib/systemd/system/tor@default.service
touch $T/root-arch/usr/lib/systemd/system/tor.service

function detect_in --argument-names root
    __onionfence_detect $root
    echo "$__onionfence_platform $__onionfence_unit $__onionfence_cookie"
end
t_eq "Arch: служба tor, cookie в /var/lib/tor" "arch tor /var/lib/tor/control_auth_cookie" (detect_in $T/root-arch)
t_eq "Debian/Ubuntu: служба tor@default, cookie в /run/tor" "debian tor@default /run/tor/control.authcookie" (detect_in $T/root-deb)
t_eq "старый Debian (/lib без /usr): тоже tor@default" "debian tor@default /run/tor/control.authcookie" (detect_in $T/root-deb-old)
# пустой список в "$root/..." раньше превращал проверку в `test -e` без пути → всегда «Debian»
__onionfence_detect
set -l expected arch
test -e /usr/lib/systemd/system/tor@default.service -o -e /lib/systemd/system/tor@default.service; and set expected debian
t_eq "без аргумента — определяется по этой системе ($expected)" $expected $__onionfence_platform

function getent
    test "$argv[1]" = passwd; and contains -- $argv[2] $MOCK_USERS
end
set -gx MOCK_USERS debian-tor
__onionfence_detect $T/root-deb
t_eq "пользователь Tor на Debian: debian-tor" debian-tor $__onionfence_user
set -gx MOCK_USERS tor debian-tor
__onionfence_detect $T/root-arch
t_eq "пользователь Tor на Arch: tor" tor $__onionfence_user
set -gx MOCK_USERS
__onionfence_detect $T/root-arch
t_eq "Tor не установлен: пользователя нет" "" "$__onionfence_user"
set -l out (onionfence on 2>&1 | nocolor)
t_eq "Tor не установлен → on, код 1" 1 $pipestatus[1]
t_has "Tor не установлен → подсказка установки" "apt install tor" $out
functions -e getent
set -e MOCK_USERS
__onionfence_detect
set -g __onionfence_platform arch
set -g __onionfence_unit tor

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
    __onionfence_pt_binary $argv[1] | path basename
end
set -g __onionfence_platform arch
t_eq "Arch: obfs4 / snowflake / webtunnel → lyrebird" "lyrebird lyrebird lyrebird" (pt obfs4)" "(pt snowflake)" "(pt webtunnel)
set -g __onionfence_platform debian
t_eq "Debian: obfs4 → obfs4proxy, snowflake → snowflake-client" "obfs4proxy snowflake-client" (pt obfs4)" "(pt snowflake)
rm $T/pt/lyrebird
t_eq "obfs4proxy не умеет webtunnel" "" "$(pt webtunnel)"
t_has "Debian: подсказка для snowflake — apt" "apt install snowflake-client" (__onionfence_pt_hint snowflake)
t_has "Debian: webtunnel — честно, что пакета нет" "пакета для webtunnel нет" (__onionfence_pt_hint webtunnel)
set -g __onionfence_platform arch
t_has "Arch: подсказка — lyrebird из AUR" "paru -S lyrebird-proxy" (__onionfence_pt_hint obfs4)

# весь цикл on/off на Debian идёт через tor@default
reset_state
set -g __onionfence_platform debian
set -g __onionfence_unit tor@default
printf '%s\n' $orig >$__onionfence_torrc
onionfence on >/dev/null 2>&1
t_eq "Debian: on → код 0" 0 $status
t_has "Debian: перезапуск tor@default" "systemctl restart tor@default" (command cat $T/calls.log 2>/dev/null)
t_has "Debian: журнал tor@default" "journalctl -u tor@default" (command cat $T/calls.log 2>/dev/null)
onionfence off >/dev/null 2>&1
t_has "Debian: off останавливает tor@default" "systemctl stop tor@default" (command cat $T/calls.log 2>/dev/null)
t_has "version показывает платформу" "debian: служба tor@default" (onionfence version)
t_has "version показывает номер версии" "onionfence $__onionfence_version" (onionfence version)
set -g __onionfence_platform arch
set -g __onionfence_unit tor

# ======================================================================
section "Мосты"
reset_state
printf '%s\n' $orig >$__onionfence_torrc
# заглушка программы-транспорта (настоящий lyrebird может быть не установлен)
mkdir -p $T/bin
printf '#!/bin/sh\nexit 0\n' >$T/bin/lyrebird
chmod +x $T/bin/lyrebird
set -l saved_path $PATH
set -gx PATH $T/bin $PATH

function block
    sed -n "/^$__onionfence_begin\$/,/^$__onionfence_end\$/p" $__onionfence_torrc
end

t_eq "по умолчанию мостов нет" нет (__onionfence_bridges_summary)
t_eq "без мостов сайт проверки ждём 30 секунд" 30 (__onionfence_check_timeout)
onionfence bridges snowflake >/dev/null
t_eq "snowflake: код 0" 0 $status
t_eq "с мостами сайт проверки ждём 60 секунд" 60 (__onionfence_check_timeout)
t_eq "snowflake: 2 встроенных моста" 2 (block | grep -c '^Bridge snowflake ')
t_eq "snowflake: UseBridges 1" 1 (block | grep -cx 'UseBridges 1')
t_eq "snowflake: транспорт lyrebird" "ClientTransportPlugin snowflake exec $T/bin/lyrebird" (block | grep '^ClientTransportPlugin')
t_eq "snowflake: сводка для статуса" "snowflake ×2" (__onionfence_bridges_summary)
t_has "статус показывает мосты" "snowflake ×2" (__onionfence_status --quick | nocolor)
tor --verify-config -f $__onionfence_torrc --DataDirectory $T/verify-data --User '' >$T/verify.out 2>&1
t_eq "tor --verify-config принимает torrc с мостами" 0 $status

onionfence country de >/dev/null
t_eq "смена страны не теряет мосты" 2 (block | grep -c '^Bridge ')
__onionfence_torrc
t_eq "перезапись блока (on) не теряет мосты" 2 (block | grep -c '^Bridge ')
t_eq "перезапись блока не теряет страну" de (__onionfence_exit_country)

onionfence bridges obfs4 >/dev/null
t_eq "obfs4: заменяет snowflake на 7 встроенных obfs4" "7 0" (block | grep -c '^Bridge obfs4 ')" "(block | grep -c '^Bridge snowflake ')

set -l wt 'webtunnel [2001:db8::1]:443 0123456789ABCDEF0123456789ABCDEF01234567 url=https://example.com/abc ver=0.0.1'
onionfence bridges add "  Bridge   obfs4  5.6.7.8:443 AAAA cert=x+y/z= iat-mode=0  " $wt >/dev/null
t_eq "add: код 0" 0 $status
t_eq "add: префикс Bridge и лишние пробелы убраны" 1 (block | grep -cx 'Bridge obfs4 5.6.7.8:443 AAAA cert=x+y/z= iat-mode=0')
t_eq "add: добавляет к уже настроенным" "obfs4 ×8, webtunnel ×1" (__onionfence_bridges_summary)
t_eq "add: транспорты obfs4 и webtunnel" "obfs4 webtunnel" (block | string match -rg '^ClientTransportPlugin (\S+)' | string join ' ')
onionfence bridges add $wt >/dev/null
t_eq "add: повтор не дублируется" 1 (block | grep -c '^Bridge webtunnel ')
onionfence bridges add '1.2.3.4:9001 ABCDEF' >/dev/null
t_has "add: обычный мост без транспорта" "обычные ×1" (__onionfence_bridges_summary)

set -l sum (md5sum <$__onionfence_torrc)
for bad in hello 'obfs4 999.1:443' 'obfs4 1.2.3.4' 'obfs4 1.2.3.4:443 x #коммент'
    onionfence bridges add $bad >/dev/null
    t_eq "add «$bad» отклонён" 1 $status
end
t_eq "после отклонённых строк torrc не изменился" $sum (md5sum <$__onionfence_torrc)
onionfence bridges add "$(printf 'obfs4 9.9.9.9:443 BBBB cert=q\nExitNodes {ru}')" >/dev/null
t_eq "перевод строки в мосте не создаёт новую директиву torrc" 0 (grep -c '^ExitNodes {ru}' $__onionfence_torrc)

printf 'obfs4 7.7.7.7:443 CCCC cert=w iat-mode=0\n\n' | onionfence bridges add >/dev/null
t_eq "add без аргументов читает строки из ввода" 1 (block | grep -c '^Bridge obfs4 7.7.7.7:443')
set -l out (printf '\n' | onionfence bridges add | nocolor)
t_eq "add с пустым вводом → код 1" 1 $pipestatus[2]
t_has "add с пустым вводом → сообщение" "Ничего не добавлено" $out
onionfence bridges blabla >/dev/null
t_eq "неизвестный режим → код 1" 1 $status
t_has "bridges без аргументов показывает подсказку" "@GetBridgesBot" (onionfence bridges | nocolor)

onionfence bridges off >/dev/null
t_eq "off: мостов нет" нет (__onionfence_bridges_summary)
t_eq "off: нет UseBridges/ClientTransportPlugin" 0 (block | grep -cE '^(UseBridges|ClientTransportPlugin|Bridge )')
t_eq "off: страна сохранена" de (__onionfence_exit_country)

set -gx PATH $saved_path
if not command -sq lyrebird; and not command -sq snowflake-client
    set -l sum (md5sum <$__onionfence_torrc)
    set -l out (onionfence bridges snowflake | nocolor)
    t_eq "нет lyrebird → код 1" 1 $pipestatus[1]
    t_has "нет lyrebird → подсказка установки" "paru -S lyrebird-proxy" $out
    t_eq "нет lyrebird → torrc не изменился" $sum (md5sum <$__onionfence_torrc)
else
    echo "  (проверка «нет lyrebird» пропущена: он установлен в системе)"
end
set -gx PATH $T/bin $saved_path

rm -f $T/calls.log
echo 1 >$T/tor.state
onionfence bridges snowflake >/dev/null 2>&1
t_has "Tor работает → смена мостов переподключает (on)" "systemctl restart tor" (command cat $T/calls.log)

reset_state
set -gx MOCK_BOOT 50
set -g __onionfence_timeout 2
set -l out (onionfence on 2>&1 | nocolor)
t_has "с мостами время ожидания удваивается" "за 4 секунд" $out
t_has "режим не был включён → правила не применены" "правила НЕ применены" $out
set -l out (MOCK_RULES=1 onionfence on 2>&1 | nocolor)
t_has "режим уже включён → честное сообщение: интернет закрыт" "остаётся включённым" $out
onionfence bridges off >/dev/null 2>&1
set -gx PATH $saved_path

# ======================================================================
section "Статус"
reset_state
set -gx MOCK_SUDO_CACHED 0
t_has "быстрый статус без sudo не спрашивает пароль" "нужен sudo" (__onionfence_status --quick | nocolor)
set -gx MOCK_SUDO_CACHED 1
t_has "правила есть → ВКЛЮЧЁН" "ВКЛЮЧЁН" (MOCK_RULES=1 __onionfence_status --quick | nocolor)
t_has "правил нет → выключен" "выключен" (__onionfence_status --quick | nocolor)
t_lacks "быстрый статус не ходит в сеть" "Внешний IP" (__onionfence_status --quick | nocolor)
set -l out (__onionfence_status | nocolor)
t_has "IsTor=true → ✔ да" "✔ да" $out
t_has "IP и страна показаны" "1.2.3.4 DE, Berlin" $out
t_has "IsTor=false → ✘ нет" "✘ нет" (MOCK_CHECK='{"IsTor":false,"IP":"5.6.7.8"}' __onionfence_status | nocolor)
for resp in '' '<html>502 Bad Gateway</html>' '{"IsTor":true}'
    set -l out (MOCK_CHECK=$resp __onionfence_status 2>&1 | nocolor)
    t_has "ответ «$resp» → нет ответа" "нет ответа" $out
    t_lacks "ответ «$resp» → без ошибок test/jq" "test:" $out
end

# ======================================================================
section "Новый IP (ControlPort)"
reset_state
set -g __onionfence_cookie $T/cookie
set -g __onionfence_ctlport 19151
onionfence newip >/dev/null
t_eq "Tor выключен → код 1" 1 $status
echo 1 >$T/tor.state
t_has "нет cookie → понятная ошибка" "Нет ControlPort" (onionfence newip | nocolor)
head -c 32 /dev/urandom >$T/cookie
python3 -I $DIR/fake_control.py 19151 (python3 -c "import sys;print(open(sys.argv[1],'rb').read().hex())" $T/cookie) $T/ctl.log &
set -l fake $last_pid
sleep 0.5
set -l out (onionfence newip | nocolor)
t_eq "верный cookie → код 0" 0 $pipestatus[1]
t_has "верный cookie → цепочка запрошена" "Новая цепочка" $out
set -l out (__onionfence_status | nocolor)
t_has "статус при запущенном Tor: страна из GeoIP Tor" "1.2.3.4 DE" $out
t_lacks "статус при запущенном Tor: ipinfo не нужен" "Berlin" $out
printf "" >$T/ctl.log; rm -f $T/calls.log
set -l out (onionfence country de | nocolor)
t_has "country при работающем Tor: SETCONF сразу" 'SETCONF ExitNodes="{de}" StrictNodes=1' (command cat $T/ctl.log 2>/dev/null)
t_eq "country: закрыты живые цепочки, CLOSED не трогается" "CLOSECIRCUIT 5|CLOSECIRCUIT 7" (string join '|' (grep CLOSECIRCUIT $T/ctl.log))
t_lacks "country: без HUP-перезагрузки" "reload" (command cat $T/calls.log 2>/dev/null)
t_lacks "country: без предупреждения о 10 секундах" "10 секунд" $out
printf "" >$T/ctl.log # не rm: поддельный ControlPort держит файл открытым
onionfence country any >/dev/null
t_has "country any при работающем Tor: RESETCONF" "RESETCONF ExitNodes StrictNodes" (command cat $T/ctl.log 2>/dev/null)
head -c 32 /dev/urandom >$T/cookie
set -l out (onionfence newip | nocolor)
t_eq "неверный cookie → код 1" 1 $pipestatus[1]
t_has "неверный cookie → ответ Tor показан" "515" $out
kill $fake
wait $fake 2>/dev/null
set -l out (onionfence newip | nocolor)
t_eq "ControlPort молчит → код 1" 1 $pipestatus[1]
t_has "ControlPort молчит → понятная ошибка (pipefail)" "не отвечает" $out
set -l out (MOCK_FAIL=od onionfence newip | nocolor)
t_eq "cookie не читается → код 1" 1 $pipestatus[1]
t_has "cookie не читается → понятная ошибка (pipefail)" "не удалось прочитать" $out
set -g __onionfence_cookie /var/lib/tor/control_auth_cookie
set -g __onionfence_ctlport 9051

# ======================================================================
section "onionfence on / off (заглушки, без изменения сети)"
reset_state
printf '%s\n' $orig >$__onionfence_torrc
set -l out (onionfence on 2>&1 | nocolor)
t_eq "on → код 0" 0 $pipestatus[1]
t_has "прогресс доходит до 100%" "100%" $out
t_has "правила: DNS на DNSPort 9053" "udp dport 53 redirect to :9053" (command cat $T/ruleset.nft 2>/dev/null)
t_has "правила: TCP на TransPort 9040" "meta l4proto tcp redirect to :9040" (command cat $T/ruleset.nft 2>/dev/null)
t_has "правила: uid Tor = "(id -u $__onionfence_user) "skuid "(id -u $__onionfence_user)" accept" (command cat $T/ruleset.nft 2>/dev/null)
t_lacks "правила: нет 5353" "5353" (command cat $T/ruleset.nft 2>/dev/null)
t_lacks "правила: нет established" "established" (grep -v "#" $T/ruleset.nft)
t_has "кэш DNS сброшен" "resolvectl flush-caches" (command cat $T/calls.log 2>/dev/null)

reset_state
set -gx MOCK_BOOT 5 50
set -l out (onionfence on 2>&1 | nocolor)
t_eq "Tor не загрузился → код 1" 1 $pipestatus[1]
t_has "Tor не загрузился → сообщение" "не подключился за 3 секунд" $out
t_eq "Tor не загрузился → правила не применялись" 0 (test -e $T/ruleset.nft; and echo 1; or echo 0)
t_has "Tor не загрузился → Tor остановлен" "systemctl stop tor" (command cat $T/calls.log 2>/dev/null)

reset_state
set -gx MOCK_RESTART_FAIL 1
onionfence on >/dev/null 2>&1
t_eq "Tor не запустился → код 1" 1 $status
t_eq "Tor не запустился → правила не применялись" 0 (test -e $T/ruleset.nft; and echo 1; or echo 0)

reset_state
set -gx MOCK_NFT_FAIL 1
set -l out (onionfence on 2>&1 | nocolor)
t_eq "nft отказал → код 1" 1 $pipestatus[1]
t_has "nft отказал → сообщение" "Ошибка применения правил" $out

reset_state
printf '%s\n' $orig >$__onionfence_torrc
set -l out (MOCK_FAIL=tee onionfence on 2>&1 | nocolor)
t_eq "torrc не записался → код 1 (pipefail)" 1 $pipestatus[1]
t_has "torrc не записался → сообщение" "Не удалось записать" $out
t_lacks "torrc не записался → Tor не перезапускался" "restart" (command cat $T/calls.log 2>/dev/null)
set -l out (MOCK_FAIL=tee onionfence country de 2>&1 | nocolor)
t_eq "country: torrc не записался → код 1" 1 $pipestatus[1]
t_lacks "country: при ошибке нет ложного «✔»" "✔" $out

reset_state
set -l out (MOCK_FAIL=journalctl onionfence on 2>&1 | nocolor)
t_eq "журнал не читается → код 1 (pipefail)" 1 $pipestatus[1]
t_has "журнал не читается → сообщение сразу, без ожидания" "Не удалось прочитать журнал" $out
t_eq "журнал не читается → правила не применялись" 0 (test -e $T/ruleset.nft; and echo 1; or echo 0)

section "__onionfence_pipefail"
__onionfence_pipefail 0 0 0
t_eq "все звенья 0 → 0" 0 $status
__onionfence_pipefail 0 3 0
t_eq "упало среднее звено → его код 3" 3 $status
__onionfence_pipefail 1 0
t_eq "упало первое звено → 1 (без pipefail было бы 0)" 1 $status

reset_state
onionfence off >/dev/null
t_has "off удаляет таблицу" "nft delete table inet onionfence" (command cat $T/calls.log 2>/dev/null)
t_has "off останавливает Tor" "systemctl stop tor" (command cat $T/calls.log 2>/dev/null)

# ======================================================================
section "Tor Browser"
reset_state
onionfence browser >/dev/null
t_eq "Tor выключен → код 1" 1 $status
echo 1 >$T/tor.state
mkdir -p $T/tb $T/empty
printf '#!/bin/sh\nenv >"%s/browser.env"\n' $T >$T/tb/tor-browser
chmod +x $T/tb/tor-browser
set -l saved_path $PATH
set -gx PATH $T/tb $PATH
set -l out (onionfence browser | nocolor)
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
    __onionfence_browser_binary
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
functions -c __onionfence_browser_binary __saved_browser_binary
functions -e __onionfence_browser_binary
function __onionfence_browser_binary
end
set -l out (onionfence browser | nocolor)
t_eq "не найден → код 1" 1 $pipestatus[1]
t_has "не найден → подсказка установки" "torbrowser-launcher" $out
functions -e __onionfence_browser_binary
functions -c __saved_browser_binary __onionfence_browser_binary

# ======================================================================
section "Защита при загрузке"
reset_state
printf '%s\n' $orig >$__onionfence_torrc
set -g __onionfence_etc $T/etc
set -g __onionfence_systemd_dir $T/sd
mkdir -p $T/sd
set -l service $T/sd/onionfence-boot.service
onionfence boot on >/dev/null
t_eq "boot on → код 0" 0 $status
t_has "правила записаны" "redirect to :9040" (command cat $T/etc/rules.nft 2>/dev/null)
t_lacks "по умолчанию не строгий" "onionfence-strict" (command cat $T/etc/rules.nft 2>/dev/null)
t_has "torrc обновлён" "TransPort" (command cat $__onionfence_torrc)
t_has "службы включены" "systemctl enable onionfence-boot tor" (command cat $T/calls.log 2>/dev/null)
t_lacks "сейчас ничего не запускается" "start" (command cat $T/calls.log 2>/dev/null)
t_has "служба раньше сети" "Before=network-pre.target" (command cat $service 2>/dev/null)
t_has "служба позже nftables.service (его flush стёр бы правила)" "After=local-fs.target nftables.service" (command cat $service 2>/dev/null)
t_has "служба в sysinit.target" "WantedBy=sysinit.target" (command cat $service 2>/dev/null)
if command -q systemd-analyze; and command -q nft
    systemd-analyze verify $service >$T/verify-unit.out 2>&1
    t_eq "systemd-analyze принимает службу" 0 $status
end
onionfence boot on --strict >/dev/null
t_has "boot on --strict → строгие правила" "onionfence-strict" (command cat $T/etc/rules.nft 2>/dev/null)
t_eq "Tor не был включён → отметки нет" 0 (test -e $T/etc/tor-was-enabled; and echo 1; or echo 0)

rm -f $T/calls.log
onionfence boot off >/dev/null
t_eq "boot off → служба удалена" 0 (test -e $service; and echo 1; or echo 0)
t_eq "boot off → правила удалены" 0 (test -e $T/etc; and echo 1; or echo 0)
t_eq "boot off → Tor снова выключен при загрузке" 1 (grep -cx "systemctl disable tor" $T/calls.log)

rm -f $T/calls.log
onionfence boot on >/dev/null
set -gx MOCK_TOR_ENABLED 1
onionfence boot on >/dev/null
t_eq "повторный on: Tor включён нами, а не пользователем → отметки нет" 0 (test -e $T/etc/tor-was-enabled; and echo 1; or echo 0)
onionfence boot off >/dev/null
t_eq "… и boot off выключает его" 1 (grep -cx "systemctl disable tor" $T/calls.log)

rm -f $T/calls.log
set -l out (onionfence boot off | nocolor)
t_eq "boot off без on → код 0" 0 $pipestatus[1]
t_has "boot off без on → сообщение" "и так выключена" $out
t_lacks "boot off без on → автозапуск Tor не трогает" "disable" (command cat $T/calls.log 2>/dev/null)

rm -f $T/calls.log
onionfence boot on >/dev/null
t_eq "Tor включал сам пользователь → отметка" 1 (test -e $T/etc/tor-was-enabled; and echo 1; or echo 0)
onionfence boot off >/dev/null
t_eq "… и boot off его не трогает" 0 (grep -cx "systemctl disable tor" $T/calls.log)
set -e MOCK_TOR_ENABLED

rm -f $T/calls.log $service
set -gx MOCK_NFT_CHECK_FAIL 1
set -l out (onionfence boot on | nocolor)
t_eq "nft не принял правила → код 1" 1 $pipestatus[1]
t_has "nft не принял → сообщение" "защита не включена" $out
t_eq "nft не принял → служба не создана" 0 (test -e $service; and echo 1; or echo 0)
t_lacks "nft не принял → ничего не включено" "enable" (command cat $T/calls.log 2>/dev/null)
set -e MOCK_NFT_CHECK_FAIL
set -gx MOCK_ENABLE_FAIL 1
onionfence boot on >/dev/null
t_eq "systemctl enable упал → код 1" 1 $status
set -e MOCK_ENABLE_FAIL
onionfence boot off >/dev/null
onionfence boot blabla >/dev/null
t_eq "неизвестное действие → код 1" 1 $status
t_has "boot без аргументов — подсказка" "onionfence boot on" (onionfence boot | nocolor)

touch $T/boot.enabled
t_has "статус: защита при загрузке вкл" "При загрузке вкл" (__onionfence_status --quick | nocolor | string replace -ra ' +' ' ')
t_has "off напоминает, что режим вернётся при загрузке" "При следующей загрузке" (onionfence off | nocolor)
rm -f $T/boot.enabled
t_has "статус: защита при загрузке выкл" "При загрузке выкл" (__onionfence_status --quick | nocolor | string replace -ra ' +' ' ')
set -g __onionfence_etc $T/system-etc
set -g __onionfence_systemd_dir $T/system-sd

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
t_eq "программы: только идущие наружу, без повторов и без Tor" "opera telegram-desktop" (string join ' ' (__onionfence_online_apps))
set -gx MOCK_RULES 1
set -l out (onionfence off </dev/null | nocolor)
t_eq "без терминала: не спрашивает, выключает" 0 $pipestatus[1]
t_has "предупреждение называет программы" "opera, telegram-desktop" $out
t_has "… и выключает" "systemctl stop tor" (command cat $T/calls.log 2>/dev/null)
functions -q isatty; and functions -c isatty __saved_isatty
function isatty
    true
end
rm -f $T/calls.log
set -l out (echo n | onionfence off | nocolor)
t_eq "ответ «n» → код 1" 1 $pipestatus[2]
t_has "ответ «n» → отменено" "Отменено" $out
t_lacks "ответ «n» → правила не сняты" "delete table" (command cat $T/calls.log 2>/dev/null)
t_lacks "ответ «n» → Tor работает" "systemctl stop" (command cat $T/calls.log 2>/dev/null)
rm -f $T/calls.log
echo | onionfence off >/dev/null
t_lacks "пустой ответ (Enter) = отмена" "delete table" (command cat $T/calls.log 2>/dev/null)
for yes in y Y да
    rm -f $T/calls.log
    echo $yes | onionfence off >/dev/null
    t_has "ответ «$yes» → выключает" "delete table" (command cat $T/calls.log 2>/dev/null)
end
rm -f $T/calls.log
onionfence off -y >/dev/null
t_has "off -y: без вопроса" "delete table" (command cat $T/calls.log 2>/dev/null)
functions -e isatty
functions -q __saved_isatty; and functions -c __saved_isatty isatty; and functions -e __saved_isatty
set -gx MOCK_RULES 0
t_lacks "режим не включён → без предупреждения" "Через Tor" (onionfence off </dev/null | nocolor)
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
set -l hd $XDG_STATE_HOME/onionfence/hide
t_has "статус: скрытие выключено" "Скрытие выкл" (__onionfence_status --quick | nocolor | string replace -ra ' +' ' ')
onionfence hide on >/dev/null
t_eq "hide on → код 0" 0 $status
t_has "Wi-Fi: случайный MAC" "modify uuid-wifi 802-11-wireless.cloned-mac-address random" (command cat $T/nm.log)
t_has "Ethernet: случайный MAC" "modify uuid-eth 802-3-ethernet.cloned-mac-address random" (command cat $T/nm.log)
t_has "имя не передаётся по DHCP" "ipv4.dhcp-send-hostname no ipv6.dhcp-send-hostname no" (command cat $T/nm.log)
t_has "имя не передаётся по mDNS и LLMNR" "connection.mdns no connection.llmnr no" (command cat $T/nm.log)
t_has "подключение перезапущено" "connection up uuid-wifi" (command cat $T/nm.log)
t_lacks "loopback не трогаем" "uuid-lo" (grep -E 'modify|connection up' $T/nm.log)
t_eq "старые значения сохранены" "802-11-wireless.cloned-mac-address=|ipv4.dhcp-send-hostname=-1|ipv6.dhcp-send-hostname=-1|connection.mdns=-1|connection.llmnr=-1" (string join '|' (command cat $hd/uuid-wifi))
t_has "статус: скрытие включено" "Скрытие вкл" (__onionfence_status --quick | nocolor | string replace -ra ' +' ' ')
t_has "hide без аргументов показывает состояние" "Устройство скрыто" (onionfence hide | nocolor)
set -gx MOCK_MAC random
onionfence hide on >/dev/null
t_has "повторный on не затирает настоящие значения" "cloned-mac-address=" (head -1 $hd/uuid-wifi)
t_lacks "… в файле нет random" "random" (command cat $hd/uuid-wifi)
printf '' >$T/nm.log
onionfence hide off >/dev/null
t_eq "hide off → код 0" 0 $status
t_has "off возвращает прежние значения" "modify uuid-wifi 802-11-wireless.cloned-mac-address  ipv4.dhcp-send-hostname -1 ipv6.dhcp-send-hostname -1 connection.mdns -1 connection.llmnr -1" (command cat $T/nm.log)
t_has "off перезапускает подключение" "connection up uuid-wifi" (command cat $T/nm.log)
t_eq "off удаляет сохранённое" 0 (count $hd/*)
set -gx MOCK_NM_UP_FAIL 1
set -l out (onionfence hide on | nocolor)
t_eq "подключение не поднялось → код 1" 1 $pipestatus[1]
t_has "… и подсказка, как вернуть" "onionfence hide off" $out
set -e MOCK_NM_UP_FAIL
onionfence hide off >/dev/null
set -gx MOCK_NM_NOCONN 1
onionfence hide on >/dev/null
t_eq "нет Wi-Fi и Ethernet → код 1" 1 $status
set -e MOCK_NM_NOCONN
onionfence hide blabla >/dev/null
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
onionfence clean >/dev/null
t_eq "без файла → код 1" 1 $status
function mat2
    test "$MOCK_MAT2_FAIL" != 1
end
printf x >"$T/моё фото.jpg"
set -l out (onionfence clean "$T/моё фото.jpg" | nocolor)
t_eq "файл с пробелом → код 0" 0 $pipestatus[1]
t_has "показывает имя очищенного файла" "моё фото.cleaned.jpg" $out
t_has "предупреждает о том, что mat2 не убирает" "не убирает" $out
onionfence clean $T/nofile >/dev/null
t_eq "нет файла → код 1" 1 $status
set -gx MOCK_MAT2_FAIL 1
onionfence clean "$T/моё фото.jpg" >/dev/null
t_eq "mat2 не справился → код 1" 1 $status
set -e MOCK_MAT2_FAIL
functions -e mat2
if command -q mat2
    python3 -c "
import struct,sys,zlib
def c(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d))
open(sys.argv[1],'wb').write(b'\x89PNG\r\n\x1a\n'+c(b'IHDR',struct.pack('>IIBBBBB',1,1,8,0,0,0,0))+c(b'tEXt',b'Author\0SecretName')+c(b'IDAT',zlib.compress(b'\0\0'))+c(b'IEND',b''))" $T/meta.png
    t_has "исходный файл содержит метаданные" "SecretName" (command mat2 --show $T/meta.png)
    onionfence clean $T/meta.png >/dev/null
    t_eq "настоящий mat2 → код 0" 0 $status
    t_lacks "настоящий mat2 убрал автора" "SecretName" (command mat2 --show $T/meta.cleaned.png)
else
    set -l out (onionfence clean $T/meta.png | nocolor)
    t_has "mat2 не установлен → подсказка" "mat2" $out
end

# ======================================================================
section "Терминал без цветов (TERM=dumb)"
# set_color там ничего не выводит; без кавычек вокруг "$(set_color …)" пропадал весь текст
printf '%s\n' $orig >$T/dumb.torrc
set -l out (env TERM=dumb fish -c '
    source $DIR/lib.fish
    set -g __onionfence_torrc $T/dumb.torrc
    set -g __onionfence_timeout 2
    onionfence help
    __onionfence_bar 47; echo
    __onionfence_status --quick
    MOCK_FAIL=journalctl onionfence on' 2>&1)
t_eq "справка: все 23 команд видны" 23 (string match -r '^\s+onionfence' -- $out | count)
t_has "полоска прогресса видна" "47%" $out
t_has "статус виден" "Страна выхода" $out
t_has "сообщение об ошибке видно" "Не удалось прочитать журнал" $out

# ======================================================================
section "Исключение стран"
reset_state
printf '%s\n' '# user' >$__onionfence_torrc
onionfence exclude ru,BY >/dev/null
t_eq "exclude → код 0" 0 $status
t_eq "exclude: строка torrc, коды в нижнем регистре" 1 (grep -cx 'ExcludeExitNodes {ru},{by}' $__onionfence_torrc)
t_eq "exclude: чтение обратно" "ru by" (string join ' ' (__onionfence_exclude_current))
t_has "статус показывает исключённые страны" "ru, by" (__onionfence_status --quick | nocolor)
t_has "exclude без аргумента показывает список" "ru, by" (onionfence exclude | nocolor)
onionfence on >/dev/null
t_eq "on не теряет исключённые страны" 1 (grep -cx 'ExcludeExitNodes {ru},{by}' $__onionfence_torrc)
onionfence country ru >/dev/null
t_eq "нельзя выбрать исключённую страну" 1 $status
t_eq "… страна не применилась" любая (__onionfence_exit_country)
onionfence country de >/dev/null
t_eq "страна и исключения вместе" "1 1" (grep -cx 'ExitNodes {de}' $__onionfence_torrc)" "(grep -cx 'ExcludeExitNodes {ru},{by}' $__onionfence_torrc)
onionfence exclude de >/dev/null
t_eq "нельзя исключить выбранную страну" 1 $status
onionfence country any >/dev/null
for bad in r russia ru,, 'ru;by' 12
    set -l before (md5sum <$__onionfence_torrc)
    onionfence exclude $bad >/dev/null 2>&1
    set -l rc $status
    if test $bad = 'ru,,'
        t_eq "лишние запятые не мешают" 0 $rc
    else
        t_eq "неверный код «$bad» → код 1" 1 $rc
        t_eq "… torrc не изменён" $before (md5sum <$__onionfence_torrc)
    end
end
onionfence exclude off >/dev/null
t_eq "exclude off → код 0" 0 $status
t_eq "exclude off убирает строку" 0 (grep -c ExcludeExitNodes $__onionfence_torrc)
if __onionfence_has_conflux
    t_eq "без ограничений Conflux не трогаем" 0 (grep -c ConfluxEnabled $__onionfence_torrc)
    onionfence country de >/dev/null
    t_eq "со страной Conflux выключен" 1 (grep -cx 'ConfluxEnabled 0' $__onionfence_torrc)
    onionfence country any >/dev/null
    onionfence exclude ru >/dev/null
    t_eq "с исключением Conflux выключен" 1 (grep -cx 'ConfluxEnabled 0' $__onionfence_torrc)
    onionfence exclude off >/dev/null
    t_eq "снято — Conflux снова как в сети" 0 (grep -c ConfluxEnabled $__onionfence_torrc)
end
functions -c __onionfence_has_conflux __mock_has_conflux
function __onionfence_has_conflux; false; end
onionfence country de >/dev/null
t_eq "старый Tor без Conflux: настройки нет, иначе он не запустится" 0 (grep -c ConfluxEnabled $__onionfence_torrc)
onionfence country any >/dev/null
functions -e __onionfence_has_conflux
functions -c __mock_has_conflux __onionfence_has_conflux

# ======================================================================
section "Автоподбор мостов"
reset_state
printf '%s\n' '# user' >$__onionfence_torrc
set -g __onionfence_auto_timeout 1
set -l saved_path $PATH
set -gx PATH $T/bin $saved_path
functions -c journalctl __mock_journalctl
# MOCK_WORKS — какой способ «подключается»
function journalctl
    echo "journalctl $argv" >>$T/calls.log
    set -l have direct
    grep -q '^Bridge obfs4 ' $__onionfence_torrc; and set have obfs4
    grep -q '^Bridge snowflake ' $__onionfence_torrc; and set have snowflake
    test "$have" = "$MOCK_WORKS"; and echo "Tor[1]: Bootstrapped 100% (mock)"; or echo "Tor[1]: Bootstrapped 5% (mock)"
end

set -gx MOCK_WORKS direct
set -l out (onionfence bridges auto 2>&1 | nocolor)
t_eq "auto: напрямую работает → код 0" 0 $pipestatus[1]
t_has "auto: сообщает способ" "Работает: direct" $out
t_eq "auto: мостов нет" 0 (grep -c '^Bridge ' $__onionfence_torrc)
t_eq "auto: Tor был выключен → остаётся выключенным" 0 (command cat $T/tor.state)

set -gx MOCK_WORKS obfs4
set -l out (onionfence bridges auto 2>&1 | nocolor)
t_has "auto: напрямую не вышло → obfs4" "Работает: obfs4" $out
t_eq "auto: записаны все встроенные obfs4" 7 (grep -c '^Bridge obfs4 ' $__onionfence_torrc)
t_eq "auto: snowflake не понадобился" 0 (grep -c '^Bridge snowflake ' $__onionfence_torrc)

set -gx MOCK_WORKS snowflake
set -l out (onionfence bridges auto --no-direct 2>&1 | nocolor)
t_lacks "auto --no-direct: без мостов не пробует" "direct" $out
t_has "auto --no-direct: дошёл до snowflake" "Работает: snowflake" $out
t_eq "auto: записаны 2 snowflake" 2 (grep -c '^Bridge snowflake ' $__onionfence_torrc)

set -gx MOCK_WORKS none
set -l before (__onionfence_bridges_current)
set -l out (onionfence bridges auto 2>&1 | nocolor)
t_eq "auto: ничего не работает → код 1" 1 $pipestatus[1]
t_has "auto: подсказка про свои мосты" "@GetBridgesBot" $out
t_eq "auto: настройки мостов возвращены" "$before" "$(string join ' ' -- (__onionfence_bridges_current))"
t_eq "auto: Tor остановлен" 0 (command cat $T/tor.state)

# режим был включён: снова включаем в том же виде
set -gx MOCK_WORKS direct
onionfence bridges off >/dev/null
onionfence on >/dev/null
rm -f $T/calls.log
set -l out (onionfence bridges auto 2>&1 | nocolor)
t_eq "auto при включённом режиме → код 0" 0 $pipestatus[1]
t_has "auto при включённом режиме: режим включён снова" "Tor-режим ВКЛЮЧЁН" $out
t_eq "auto: Tor работает" 1 (command cat $T/tor.state)

set -gx MOCK_WORKS none
set -l out (onionfence bridges auto 2>&1 | nocolor)
t_eq "auto, режим включён, всё упало → код 1" 1 $pipestatus[1]
t_eq "… Tor снова запущен, а не брошен" 1 (command cat $T/tor.state)

# нет транспорта: способ пропускается, а не ломает подбор
onionfence off -y >/dev/null
functions -c __onionfence_pt_binary __mock_pt
function __onionfence_pt_binary; return 1; end
set -gx MOCK_WORKS direct
set -l out (onionfence bridges auto --no-direct 2>&1 | nocolor)
t_eq "auto без транспортов → код 1" 1 $pipestatus[1]
t_has "auto без транспортов: объясняет" "obfs4 пропущен" $out
functions -e __onionfence_pt_binary
functions -c __mock_pt __onionfence_pt_binary
functions -e __mock_pt

functions -e journalctl
functions -c __mock_journalctl journalctl
functions -e __mock_journalctl
set -e MOCK_WORKS
set -gx PATH $saved_path
set -g __onionfence_auto_timeout 60
onionfence bridges off >/dev/null

# ======================================================================
section "Команда для любой оболочки и автодополнение"
set -g repo (path resolve $DIR/../..)
t_eq "bin/onionfence: синтаксис" 0 (fish --no-config -n $repo/bin/onionfence; echo $status)
t_has "bin/onionfence запускается не из fish" "onionfence $__onionfence_version" (sh -c "'$repo/bin/onionfence' version")
sh -c "'$repo/bin/onionfence' nosuch" >/dev/null 2>&1
t_eq "bin/onionfence передаёт код возврата" 1 $status
mkdir -p $T/inst/bin
ln -sf $repo/bin/onionfence $T/inst/bin/onionfence
t_has "bin/onionfence работает через символическую ссылку" "onionfence $__onionfence_version" ($T/inst/bin/onionfence version)
t_eq "completions: синтаксис" 0 (fish --no-config -n $repo/completions/onionfence.fish; echo $status)
function compl
    fish --no-config -c "source '$repo/completions/onionfence.fish'; complete -C '$argv'" | string split -f1 \t
end
t_has "дополнение: команды" "bridges" (compl 'onionfence br')
t_has "дополнение: exclude" "exclude" (compl 'onionfence ex')
t_has "дополнение: режимы мостов" "auto" (compl 'onionfence bridges a')
t_has "дополнение: bridges auto --no-direct" "--no-direct" (compl 'onionfence bridges auto --')
t_has "дополнение: on --strict" "--strict" (compl 'onionfence on --')
t_has "дополнение: страны" "de" (compl 'onionfence country d')
# справка и дополнение не должны расходиться с диспетчером
for c in on off status leaktest doctor circuit watch run allow browser boot hide clean newip country exclude bridges log version help guide install uninstall
    t_has "дополнение знает команду $c" $c (compl "onionfence $c")
end

# ======================================================================
section "Повтор запроса к сайту проверки"
reset_state
functions -c curl __mock_curl
function curl
    echo x >>$T/curl.tries
    test (count (command cat $T/curl.tries)) -gt $MOCK_CURL_DROPS; and __mock_curl $argv
end
rm -f $T/curl.tries
set -gx MOCK_CURL_DROPS 2
t_has "два быстрых обрыва → ответ получен" "1.2.3.4" (__onionfence_check_ip)
t_eq "… третьей попыткой" 3 (count (command cat $T/curl.tries))
rm -f $T/curl.tries
set -gx MOCK_CURL_DROPS 9
__onionfence_check_ip >/dev/null
t_eq "сайт недоступен → код 1" 1 $status
t_eq "… попыток не больше трёх" 3 (count (command cat $T/curl.tries))
rm -f $T/curl.tries
function curl
    echo x >>$T/curl.tries
    sleep 10
end
__onionfence_check_ip >/dev/null
t_eq "таймаут не повторяем" 1 (count (command cat $T/curl.tries))
functions -e curl
functions -c __mock_curl curl
functions -e __mock_curl
set -e MOCK_CURL_DROPS

# ======================================================================
section "Схема цепочки и панель"
reset_state
t_eq "флаг Германии" 🇩🇪 (__onionfence_flag de)
t_eq "неизвестная страна — глобус" 🌐 (__onionfence_flag '??')
t_eq "мини-график: масштаб по максимуму" ▁▁▄█ (__onionfence_spark 0 1 4 8)
t_eq "мини-график: нули не делят на ноль" ▁▁▁ (__onionfence_spark 0 0 0)
t_eq "скорость: байты" "512 Б/с" (__onionfence_rate 512)
t_eq "скорость: килобайты" "1.5 КБ/с" (__onionfence_rate 1536)
t_eq "скорость: мегабайты" "2.0 МБ/с" (string replace -r '^2 ' '2.0 ' (__onionfence_rate 2097152))
t_eq "время работы" 01:02:03 (__onionfence_duration 3723)

set -l fpa AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
set -l fpb BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
set -l fpc CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
set -l fpd DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD
set -l path1 "\$$fpa~guard1,\$$fpb~middle1,\$$fpc~exit1"
set -l path2 "\$$fpa~guard1,\$$fpb~middle1,\$$fpd~exit2"
set -g CANNED \
    "5 BUILT $path1 BUILD_FLAGS=NEED_CAPACITY PURPOSE=GENERAL" \
    "6 BUILT $path2 BUILD_FLAGS=NEED_CAPACITY PURPOSE=GENERAL" \
    "7 BUILT $path2 BUILD_FLAGS=IS_INTERNAL,NEED_CAPACITY PURPOSE=GENERAL" \
    "8 BUILT $path2 BUILD_FLAGS=NEED_CAPACITY PURPOSE=HS_VANGUARDS" \
    "9 LAUNCHED BUILD_FLAGS=NEED_CAPACITY PURPOSE=GENERAL" \
    "3 SUCCEEDED 5 example.com:443"
t_eq "служебные цепочки не считаются" 2 (count (__onionfence_circuit_usable $CANNED))
set -l p (__onionfence_circuit_pick $CANNED)
t_eq "выбрана цепочка с открытым соединением" $path1 $p[1]
t_eq "… и её сайт" example.com "$p[2]"
set -l p (__onionfence_circuit_pick $CANNED[1..2])
t_eq "нет соединений → последняя готовая" $path2 $p[1]
t_eq "… и сайт неизвестен" 1 (count $p)
t_eq "только служебные → ничего" 1 (__onionfence_circuit_pick $CANNED[3..4] >/dev/null; echo $status)
set -l p (__onionfence_circuit_pick $CANNED[1] '4 SUCCEEDED 5 ex$(am)ple;.com:443')
t_eq "имя сайта из сети очищается" example.com "$p[2]"

functions -c __onionfence_control __mock_real_control
function __onionfence_control
    test "$MOCK_CTL_FAIL" = 1; and return 3
    for c in $argv
        switch $c
            case 'GETINFO circuit-status'
                # одна запись приходит в строке заголовка, несколько — блоком
                if test (count $CANNED_CIRC) -eq 1
                    echo "250-circuit-status=$CANNED_CIRC"
                else
                    echo '250+circuit-status='
                    printf '%s\n' $CANNED_CIRC . '250 OK'
                end
            case 'GETINFO stream-status'
                echo "250-stream-status=$CANNED_STREAM"
            case 'GETINFO ns/id/*'
                set -l letter (string sub -s 15 -l 1 -- $c)
                echo "r n x y 2026-01-01 00:00:00 10.0.0.$letter 443 0"
            case 'GETINFO ip-to-country/10.0.0.A'
                echo '250-ip-to-country/10.0.0.A=de'
            case 'GETINFO ip-to-country/10.0.0.B'
                echo '250-ip-to-country/10.0.0.B=nl'
            case 'GETINFO ip-to-country/10.0.0.C'
                echo '250-ip-to-country/10.0.0.C=se'
            case 'GETINFO traffic/read'
                echo "250-traffic/read=$MOCK_TRAFFIC"
            case 'GETINFO traffic/written'
                echo '250-traffic/written=1000'
            case 'GETINFO uptime'
                echo '250-uptime=3723'
        end
    end
end
set -g CANNED_CIRC $CANNED[1..5]
set -g CANNED_STREAM '3 SUCCEEDED 5 example.com:443'
set -g MOCK_TRAFFIC 5000
echo 1 >$T/tor.state
set -l out (onionfence circuit | nocolor)
t_eq "circuit → код 0" 0 $pipestatus[1]
t_has "схема: страны по порядку и сайт" "Ты ──▶ 🇩🇪 DE ──▶ 🇳🇱 NL ──▶ 🇸🇪 SE ──▶ example.com" "$out"
t_has "схема: вход" "guard1 — видит твой IP" "$out"
t_has "схема: выход" "exit1 — видит сайт" "$out"
t_has "схема: разные сайты — разные цепочки" "всего: 2" "$out"
set -g CANNED_CIRC $CANNED[1]
t_has "схема: единственная цепочка в строке заголовка" "Ты ──▶" (onionfence circuit | nocolor)
set -g CANNED_CIRC 
set -g CANNED_STREAM
onionfence circuit >/dev/null
t_eq "цепочек нет → код 1" 1 $status
set -g MOCK_CTL_FAIL 1
set -l out (onionfence circuit | nocolor)
t_eq "ControlPort не отвечает → код 1" 1 $pipestatus[1]
t_has "ControlPort не отвечает → сообщение" "Нет связи" $out
set -e MOCK_CTL_FAIL
echo 0 >$T/tor.state
onionfence circuit >/dev/null
t_eq "Tor не запущен → код 1" 1 $status
set -e __onionfence_cc_EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
set -g MOCK_CTL_FAIL 1
t_eq "сбой связи: страна неизвестна" '??' (__onionfence_hop_country EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE)
t_eq "… и это не запоминается" 0 (set -q __onionfence_cc_EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE; and echo 1; or echo 0)
set -e MOCK_CTL_FAIL
onionfence watch >/dev/null
t_eq "watch: Tor не запущен → код 1" 1 $status

echo 1 >$T/tor.state
set -g CANNED_CIRC $CANNED[1..2]
set -g CANNED_STREAM '3 SUCCEEDED 5 example.com:443'
echo fakecookie >$T/cookie
set -g __onionfence_cookie $T/cookie
set -l out (onionfence watch </dev/null | nocolor)
t_eq "watch без терминала → код 0" 0 $pipestatus[1]
t_has "watch: один кадр, время работы" 01:02:03 "$out"
t_has "watch: число цепочек" "Цепочек 2" (string replace -ra ' +' ' ' -- "$out")
t_has "watch: путь" "🇩🇪 DE ──▶" "$out"
t_lacks "watch без терминала: нет управляющих последовательностей" "[?1049" "$out"
t_eq "watch: кэш cookie не остаётся" 0 (set -q __onionfence_cookie_cache; and echo 1; or echo 0)

__onionfence_watch_reset
set -g MOCK_TRAFFIC 5000
__onionfence_watch_update
sleep 0.2
set -g MOCK_TRAFFIC 105000
__onionfence_watch_update
t_eq "скорость считается по разнице счётчиков" 1 (test $__onionfence_w_down[-1] -gt 100000; and echo 1; or echo "$__onionfence_w_down")
set -g MOCK_TRAFFIC 10
__onionfence_watch_update
t_eq "перезапуск Tor: скорость не отрицательная" 0 $__onionfence_w_down[-1]
set -g MOCK_CTL_FAIL 1
__onionfence_watch_update
t_has "Tor пропал: панель пишет об этом" "нет связи" (__onionfence_watch_frame | nocolor)
set -e MOCK_CTL_FAIL
set -e __onionfence_cookie_cache
functions -e __onionfence_control
functions -c __mock_real_control __onionfence_control
functions -e __mock_real_control
set -e CANNED CANNED_CIRC CANNED_STREAM MOCK_TRAFFIC
echo 0 >$T/tor.state

# настоящий псевдотерминал: панель должна вернуть терминал в исходное состояние
if command -q python3
    for key in q ctrl-c n-then-q
        set -l out (python3 -I $DIR/watch_pty.py $DIR/watch_child.fish $SRC $key 2>&1)
        t_has "терминал ($key): панель открылась" "SCREEN_ON" "$out"
        t_has "терминал ($key): кадр нарисован" "Цепочек" "$out"
        t_has "терминал ($key): экран и курсор возвращены" "SCREEN_OFF" "$out"
        t_has "терминал ($key): настройки stty те же" "STTY_OK" "$out"
    end
    set -l out (python3 -I $DIR/watch_pty.py $DIR/watch_child.fish $SRC guide 2>&1)
    t_has "терминал: guide открывается" "Руководство пользователя" "$out"
    # в минимальных системах less нет: тогда текст просто выводится
    command -q less; and t_has "терминал: подсказка less" "q — назад" "$out"
    t_has "терминал: guide закрывается по q, настройки stty те же" "STTY_OK" "$out"
    t_has "терминал (n): новая цепочка запрошена" "NEWNYM_SENT" (python3 -I $DIR/watch_pty.py $DIR/watch_child.fish $SRC n-then-q 2>&1)
end

# ======================================================================
section "Приветствие"
set -l out (__onionfence_splash | nocolor)
t_has "приветствие: название" "O N I O N F E N C E" "$out"
t_has "приветствие: версия" "v$__onionfence_version" "$out"
t_has "приветствие: картинка не потеряла обратные косые" '\|/' "$out"
t_eq "приветствие: строк картинки" 11 (__onionfence_splash | count)
set -l widest 0
for line in (__onionfence_splash | nocolor)
    set -l w (string length -- $line)
    test $w -gt $widest; and set widest $w
end
t_eq "приветствие помещается в окно шириной 60" 1 (test $widest -le 60; and echo 1; or echo $widest)
set -l out (COLUMNS=40 __onionfence_splash | nocolor)
t_lacks "узкое окно: без картинки" "Весь трафик" "$out"
t_has "узкое окно: обычный заголовок" "O N I O N" "$out"

# ======================================================================
section "Руководство пользователя"
set -l out (onionfence guide)
t_eq "guide → код 0" 0 $status
t_lacks "guide вне терминала: без цветовых кодов" (printf '\e') "$out"
t_lacks "guide вне терминала: разметка заголовков убрана" "# Быстрый" "$out"
t_has "guide: версия" "onionfence $__onionfence_version" "$out"
t_has "manual — то же самое" "Быстрый старт" (onionfence manual)
# руководство не должно отставать от команд: сверяем с разбором аргументов в самом скрипте
set -l commands (string match -rg '^        case ([a-z]+)\b.*$' -- (functions onionfence | string replace -r '^\s+case' '        case'))
t_eq "список команд из диспетчера получен" 1 (test (count $commands) -ge 15; and echo 1; or echo "$commands")
for c in $commands
    t_has "guide описывает команду $c" "  $c" "$out"
    test $c = help; or t_has "help описывает команду $c" "onionfence $c" (onionfence help | nocolor)
end
for section in "Если что-то не работает" "Что скрипт не решит" "Мосты" "Страны" "Анонимность" "Файлы" "Меню"
    t_has "guide: раздел «$section»" $section "$out"
end
set -l widest 0
for line in (onionfence guide)
    set -l w (string length -- $line)
    test $w -gt $widest; and set widest $w
end
t_eq "guide помещается в окно шириной 80" 1 (test $widest -le 80; and echo 1; or echo $widest)
# меню и быстрый статус не должны спрашивать пароль: torrc обычно доступен без sudo
reset_state
printf '%s\n' '# --- onionfence transparent ---' 'ExitNodes {de}' 'ExcludeExitNodes {ru}' 'Bridge obfs4 1.2.3.4:443 AAAA' '# --- onionfence end ---' >$__onionfence_torrc
functions -c sudo __saved_sudo
function sudo
    echo "$argv" >>$T/sudo.log
    __saved_sudo $argv
end
rm -f $T/sudo.log
set -l out (__onionfence_status --quick | nocolor)
t_has "быстрый статус читает страну" " de" (string match '*Страна*' -- $out)
t_has "быстрый статус читает мосты" "obfs4" (string match '*Мосты*' -- $out)
t_lacks "быстрый статус: нет sudo без -n для чтения torrc" "sed" (command cat $T/sudo.log 2>/dev/null)
chmod 000 $__onionfence_torrc
if not test -r $__onionfence_torrc
    __onionfence_exit_country >/dev/null 2>&1
    t_has "torrc без доступа на чтение → через sudo" "sed" (command cat $T/sudo.log 2>/dev/null)
end
chmod 644 $__onionfence_torrc
functions -e sudo
functions -c __saved_sudo sudo
functions -e __saved_sudo

# полоса загрузки вне терминала не повторяется
set -gx MOCK_BOOT 5
set -l out (__onionfence_wait_bootstrap 3 now | string collect | string split \r | string match '*%')
t_eq "вне терминала одинаковые проценты выводятся один раз" 1 (count $out)
reset_state

# ======================================================================
section "Причины сбоя"
reset_state
printf '%s\n' '# user' >$__onionfence_torrc
t_has "часы" "часы" (__onionfence_explain 'Our clock is 3 hours behind' 'Bootstrapped 5%')
t_has "занятый порт" "порт" (__onionfence_explain 'Could not bind to 127.0.0.1:9040: Address already in use')
t_has "ошибка настроек" "настройках" (__onionfence_explain 'Failed to parse/validate config: Unknown option')
t_has "права" "прав" (__onionfence_explain 'Could not open: Permission denied')
t_has "транспорт" "транспорт" (__onionfence_explain 'Could not launch managed proxy executable at /x')
t_has "нет сети" "нет подключения" (__onionfence_explain 'Bootstrapped 0%' 'Network is unreachable')
t_has "застрял без мостов → автоподбор" "bridges auto" (__onionfence_explain 'Bootstrapped 5%')
t_eq "пустой журнал → причин не выдумываем" 0 (count (__onionfence_explain))

set -gx MOCK_BOOT 5
set -l out (onionfence on 2>&1 | nocolor)
t_eq "Tor не подключился → код 1" 1 $pipestatus[1]
t_has "… и причина названа" "Вероятная причина" $out
reset_state

function timedatectl
    echo no
end
set -l out (onionfence on 2>&1 | nocolor)
t_has "часы не синхронизированы → предупреждение" "Часы не синхронизированы" $out
function timedatectl
    echo yes
end
t_lacks "часы в порядке → без предупреждения" "Часы не" (onionfence on 2>&1 | nocolor)
functions -e timedatectl

# ======================================================================
section "Сторож правил"
reset_state
rm -f $T/guard.active
__onionfence_guard_unit_text >$T/run-sd/check.service
t_has "сторож читает сначала текущие правила" "[ -r $__onionfence_run/rules.nft ]" (command cat $T/run-sd/check.service)
t_has "… затем правила загрузки" "f=$__onionfence_etc/rules.nft" (command cat $T/run-sd/check.service)
t_has "сторож стартует после службы загрузки" "After=local-fs.target onionfence-boot.service" (command cat $T/run-sd/check.service)
if command -q systemd-analyze; and command -q nft
    systemd-analyze verify $T/run-sd/check.service >$T/verify-guard.out 2>&1
    t_eq "systemd-analyze принимает сторожа" 0 $status
end
rm -f $T/run-sd/check.service

onionfence on --strict >/dev/null
t_eq "on запускает сторожа" 1 (test -e $T/guard.active; and echo 1; or echo 0)
t_has "сторож знает строгие правила" "onionfence-strict" (command cat $__onionfence_run/rules.nft 2>/dev/null)
t_eq "служба сторожа записана" 1 (test -e $T/run-sd/onionfence-guard.service; and echo 1; or echo 0)
set -l calls (command cat $T/calls.log)
set -l stop_at (contains -i -- "systemctl stop onionfence-guard" $calls)
set -l del_at (contains -i -- "nft delete table inet onionfence" $calls)
t_eq "on останавливает сторожа раньше, чем удаляет таблицу" 1 (test -n "$stop_at" -a -n "$del_at"; and test $stop_at -lt $del_at; and echo 1; or echo "$stop_at $del_at")
rm -f $T/calls.log
onionfence off -y >/dev/null
t_eq "off останавливает сторожа" 0 (test -e $T/guard.active; and echo 1; or echo 0)
t_eq "off убирает правила сторожа" 0 (test -e $__onionfence_run/rules.nft; and echo 1; or echo 0)
t_eq "off убирает службу" 0 (test -e $T/run-sd/onionfence-guard.service; and echo 1; or echo 0)
set -l calls (command cat $T/calls.log)
set -l stop_at (contains -i -- "systemctl stop onionfence-guard" $calls)
set -l del_at (contains -i -- "nft delete table inet onionfence" $calls)
t_eq "off останавливает сторожа раньше, чем удаляет таблицу" 1 (test -n "$stop_at" -a -n "$del_at"; and test $stop_at -lt $del_at; and echo 1; or echo "$stop_at $del_at")
set -gx MOCK_GUARD_FAIL 1
set -l out (onionfence on 2>&1 | nocolor)
t_eq "сторож не запустился → режим всё равно включён" 0 $pipestatus[1]
t_has "… и об этом сказано" "Не удалось запустить сторожа" $out
set -e MOCK_GUARD_FAIL
onionfence off -y >/dev/null

set -g __onionfence_etc $T/etc
set -g __onionfence_systemd_dir $T/sd
rm -f $T/calls.log
onionfence boot on >/dev/null
t_eq "boot on ставит сторожа" 1 (test -e $T/sd/onionfence-guard.service; and echo 1; or echo 0)
t_has "boot on включает сторожа" "onionfence-guard" (string match '*systemctl enable*' -- (command cat $T/calls.log))
onionfence boot off >/dev/null
t_eq "boot off убирает сторожа" 0 (test -e $T/sd/onionfence-guard.service; and echo 1; or echo 0)
set -g __onionfence_etc $T/system-etc
set -g __onionfence_systemd_dir $T/system-sd

# ======================================================================
section "Диагностика"
reset_state
printf '%s\n' '# user' >$__onionfence_torrc
function tor
    if contains -- --verify-config $argv
        test "$MOCK_VERIFY_FAIL" = 1; and echo '[warn] Failed to parse/validate config: Unknown option Foo'; and return 1
        return 0
    end
    echo 'Tor version 0.4.9.14.'
end
# порты считаем свободными, пока тест не скажет иначе
function __onionfence_port_used
    test "$MOCK_PORTS" = 1
end
echo 0 >$T/tor.state
set -l out (onionfence doctor 2>&1 | nocolor)
t_eq "всё выключено и исправно → код 0" 0 $pipestatus[1]
t_has "doctor: порты свободны" "порт 9040 свободен" $out
t_has "doctor: режим выключен" "выключен" $out

set -gx MOCK_VERIFY_FAIL 1
set -l out (onionfence doctor 2>&1 | nocolor)
t_eq "Tor отвергает настройки → код 1" 1 $pipestatus[1]
t_has "… причина показана" "Unknown option Foo" $out
set -e MOCK_VERIFY_FAIL

set -gx MOCK_PORTS 1
set -l out (onionfence doctor 2>&1 | nocolor)
t_eq "Tor выключен, порт занят → код 1" 1 $pipestatus[1]
t_has "… сказано, как найти программу" "занят другой программой" $out
set -e MOCK_PORTS

# настоящая проверка порта: занимаем его сами
if command -q ss; and command -q python3
    functions -e __onionfence_port_used
    source $SRC # вернуть настоящую функцию; настройки ниже восстанавливаем
    source $DIR/lib.fish
    set -l freeport (python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
    t_eq "настоящий ss: свободный порт" 1 (__onionfence_port_used tcp $freeport; echo $status)
    python3 -I -c 'import socket,sys,time;s=socket.socket();s.bind(("127.0.0.1",int(sys.argv[1])));s.listen();time.sleep(3)' $freeport &
    set -l listener $last_pid
    disown
    sleep 0.7
    t_eq "настоящий ss: занятый порт" 0 (__onionfence_port_used tcp $freeport; echo $status)
    kill $listener 2>/dev/null
    function __onionfence_port_used
        test "$MOCK_PORTS" = 1
    end
end
reset_state
printf '%s\n' '# user' >$__onionfence_torrc

echo 1 >$T/tor.state
set -gx MOCK_PORTS 1
functions -c __onionfence_control __doc_control
function __onionfence_control
    echo '250-status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS=100 TAG=done'
end
set -l out (onionfence doctor 2>&1 | nocolor)
t_has "Tor работает: подключение подтверждено" "Tor подключён к сети" $out
t_has "Tor работает без правил → предупреждение" "трафик идёт напрямую" $out
functions -e __onionfence_control
functions -c __doc_control __onionfence_control
functions -e __doc_control
set -e MOCK_PORTS

set -gx MOCK_RULES 1
function nft
    return 0
end
echo 0 >$T/tor.state
set -l out (onionfence doctor 2>&1 | nocolor)
t_eq "правила есть, Tor не запущен → код 1" 1 $pipestatus[1]
t_has "… объяснено, почему нет интернета" "закрыт" $out
functions -e nft tor __onionfence_port_used
source $DIR/lib.fish
reset_state

# ======================================================================
section "Этапы подключения и NO_COLOR"
t_eq "этап: рукопожатие" рукопожатие (__onionfence_stage handshake_done)
t_eq "этап: цепочка" "строю цепочку" (__onionfence_stage circuit_create)
t_eq "этап: неизвестная метка — без подписи" 0 (count (__onionfence_stage neznayu))
t_has "полоса с подписью этапа" "строю цепочку" (__onionfence_bar 80 "строю цепочку" | nocolor)
t_lacks "вне терминала этап не печатается" "готово" (__onionfence_wait_bootstrap 1 now | nocolor)
t_lacks "NO_COLOR: справка без управляющих кодов" (printf '\e') "$(NO_COLOR=1 TERM=xterm-256color onionfence help)"
t_lacks "NO_COLOR: приветствие без кодов" (printf '\e') "$(NO_COLOR=1 TERM=xterm-256color __onionfence_splash)"
t_has "NO_COLOR: текст приветствия на месте" "O N I O N" "$(NO_COLOR=1 __onionfence_splash)"

# ======================================================================
section "Исключения"
reset_state
printf '%s\n' '# user' >$__onionfence_torrc
t_has "без исключений так и сказано" "Исключений нет" (onionfence allow | nocolor)
set -l out (onionfence allow 100.64.0.0/10 | nocolor)
t_eq "allow сеть → код 0" 0 $pipestatus[1]
t_has "allow честно предупреждает" "настоящего IP" $out
t_eq "исключение сохранено" 1 (grep -cx '# onionfence-allow 100.64.0.0/10' $__onionfence_torrc)
onionfence allow 192.0.2.7 >/dev/null
t_eq "можно несколько" "100.64.0.0/10 192.0.2.7" (string join ' ' (__onionfence_allow_current))
t_has "правила: nat пропускает" 'ip daddr 100.64.0.0/10 return comment "onionfence-allow"' (__onionfence_rules)
t_has "правила: фильтр пропускает" 'ip daddr 100.64.0.0/10 accept comment "onionfence-allow"' (__onionfence_rules)
t_has "правила: и в строгом режиме" 'ip daddr 192.0.2.7 accept' (__onionfence_rules strict)
t_has "статус показывает" "100.64.0.0/10, 192.0.2.7" (__onionfence_status --quick | nocolor)
onionfence on >/dev/null
t_eq "on не теряет исключения" 1 (grep -cx '# onionfence-allow 192.0.2.7' $__onionfence_torrc)
onionfence country de >/dev/null
t_eq "смена страны не теряет исключения" 1 (grep -cx '# onionfence-allow 192.0.2.7' $__onionfence_torrc)
onionfence country any >/dev/null
onionfence off -y >/dev/null
onionfence allow 192.0.2.7 >/dev/null
t_eq "повтор не дублирует" 1 (grep -cx '# onionfence-allow 192.0.2.7' $__onionfence_torrc)
onionfence allow del 192.0.2.7 >/dev/null
t_eq "del убирает одно" 100.64.0.0/10 (__onionfence_allow_current)
onionfence allow del 192.0.2.7 >/dev/null
t_eq "del несуществующего → код 1" 1 $status
for bad in 0.0.0.0/0 10.0.0.0/7 300.1.1.1 1.2.3 '1.1.1.1/33' 'bad name' 'a;b' -x
    set -l before (md5sum <$__onionfence_torrc)
    onionfence allow $bad >/dev/null 2>&1
    t_eq "неверное «$bad» отклонено" 1 $status
    t_eq "… torrc не изменён" $before (md5sum <$__onionfence_torrc)
end
set -l out (onionfence allow lo | nocolor)
t_eq "lo нельзя" 1 $pipestatus[1]
function ip
    if test "$argv[1..3]" = "route show default"
        echo 'default via 192.168.1.1 dev wlan7 proto dhcp'
    end
end
set -l out (onionfence allow wlan7 | nocolor)
t_eq "интерфейс интернета нельзя" 1 $pipestatus[1]
t_has "… объяснено почему" "отключило бы защиту" $out
functions -e ip
onionfence allow tailscale0 >/dev/null
t_has "интерфейс: nat" 'oifname "tailscale0" return' (__onionfence_rules)
t_has "интерфейс: фильтр" 'oifname "tailscale0" accept' (__onionfence_rules)
onionfence allow off >/dev/null
t_eq "off убирает все" 0 (count (__onionfence_allow_current))
t_lacks "правила снова без исключений" "onionfence-allow" (__onionfence_rules)
# применение к работающему режиму и к правилам загрузки
set -gx MOCK_RULES 1
set -g __onionfence_etc $T/etc
mkdir -p $T/etc
__onionfence_rules >$T/etc/rules.nft
functions -c __onionfence_is_strict __saved_strict
function __onionfence_is_strict; false; end
rm -f $T/calls.log
onionfence allow 192.0.2.9 >/dev/null
t_has "режим включён: правила заменены сразу" "nft delete table inet onionfence" (command cat $T/calls.log)
t_has "… правила загрузки тоже" "192.0.2.9" (command cat $T/etc/rules.nft)
onionfence allow off >/dev/null
functions -e __onionfence_is_strict
functions -c __saved_strict __onionfence_is_strict
functions -e __saved_strict
rm -f $T/etc/rules.nft
set -g __onionfence_etc $T/system-etc
set -gx MOCK_RULES 0

# ======================================================================
section "Одна программа через Tor"
reset_state
printf '%s\n' '# user' >$__onionfence_torrc
__onionfence_run_script >$T/run.sh
sh -n $T/run.sh
t_eq "сценарий: синтаксис sh" 0 $status
if command -q shellcheck
    shellcheck -S error -s sh $T/run.sh >/dev/null
    t_eq "сценарий: shellcheck без ошибок" 0 $status
end
t_has "сценарий прячет systemd-resolved" "/run/systemd/resolve" (command cat $T/run.sh)
t_has "сценарий отключает IPv6 в пространстве" "net.ipv6.conf.all.disable_ipv6=1" (command cat $T/run.sh)
t_has "правила: всё остальное отбрасывается" 'iifname "ofrun0" drop' (__onionfence_run_rules)
onionfence run >/dev/null
t_eq "run без программы → код 1" 1 $status
onionfence run nosuchprogram-xyz >/dev/null
t_eq "run: программа не найдена → 127" 127 $status

functions -c sudo __saved_sudo
# сценарий от root здесь не запускаем: настоящую изоляцию проверяет e2e-system.fish
function sudo
    if test "$argv[1]" = sh
        printf '%s\n' $argv[4..] >$T/run.args
        return $MOCK_RUN_RC
    end
    __saved_sudo $argv
end
set -g MOCK_RUN_RC 7
function pgrep; return 1; end
echo 0 >$T/tor.state
set -l out (onionfence run sh -c 'echo "два слова"' 2>&1 | nocolor)
t_eq "run передаёт код возврата программы" 7 $pipestatus[1]
t_has "run запускает Tor, если он выключен" "systemctl restart tor" (command cat $T/calls.log)
t_lacks "run не включает правила всей системы" "nft -f" (command cat $T/calls.log)
t_has "аргументы переданы без искажений" 'echo "два слова"' (command cat $T/run.args)
t_lacks "env не получает «--»: он принял бы его за программу" "--" (command tail -n +3 $T/run.args | string match -v '*=*' | string join ' ')
t_eq "первыми идут uid и gid" "onionfence-run $(id -u) $(id -g)" (string join ' ' (command head -3 $T/run.args))
t_has "окружение графики и PATH передано" "PATH=" (command cat $T/run.args)
t_eq "после программы Tor снова остановлен" 0 (command cat $T/tor.state)
echo 1 >$T/tor.state
rm -f $T/calls.log
onionfence run sh -c true >/dev/null 2>&1
t_eq "Tor работал раньше → не останавливаем" 1 (command cat $T/tor.state)
function pgrep; return 0; end
set -l out (onionfence run sh -c true </dev/null 2>&1 | nocolor)
t_eq "программа уже запущена и нет терминала → отказ" 1 $pipestatus[1]
t_has "… причина названа" "МИМО Tor" $out
onionfence run --force sh -c true >/dev/null 2>&1
t_eq "--force запускает" 7 $status
functions -e pgrep
functions -e sudo
functions -c __saved_sudo sudo
functions -e __saved_sudo
set -e MOCK_RUN_RC
echo 0 >$T/tor.state
reset_state

# ======================================================================
section "Установка и удаление"
set -l repo (path resolve $DIR/../..)
t_eq "install.sh: синтаксис sh" 0 (sh -n $repo/install.sh; echo $status)
if command -q shellcheck
    shellcheck -S warning -s sh $repo/install.sh >/dev/null
    t_eq "install.sh: shellcheck" 0 $status
end
t_eq "текст запускателя совпадает с bin/onionfence" "$(command cat $repo/bin/onionfence)" "$(__onionfence_launcher_text)"
for doc in 'sh install.sh' 'onionfence.fish; onionfence install' 'pacman -U' 'sha256sum' 'onionfence uninstall' 'onionfence doctor'
    t_has "INSTALL.md: «$doc»" $doc (command cat $repo/INSTALL.md)
end
t_has "INSTALL.md сверяет с текущей версией" "/v$__onionfence_version/functions/onionfence.fish" (command cat $repo/INSTALL.md)

# Установка из одного файла: чистый домашний каталог, файл лежит где угодно
set -l h1 $T/home1
mkdir -p $h1 $T/single
command cp $SRC $T/single/onionfence.fish
env HOME=$h1 XDG_CONFIG_HOME=$h1/.config fish --no-config -c 'source '$T/single/onionfence.fish'; onionfence install' >$T/inst.out 2>&1
t_eq "один файл: install → код 0" 0 $status
t_eq "один файл: скопирован" 1 (cmp -s $SRC $h1/.config/fish/functions/onionfence.fish; and echo 1; or echo 0)
t_eq "один файл: запускатель исполняемый" 1 (test -x $h1/.local/bin/onionfence; and echo 1; or echo 0)
t_has "один файл: команда работает из sh" "onionfence $__onionfence_version" (env HOME=$h1 sh -c "'$h1/.local/bin/onionfence' version")
t_eq "один файл: без автодополнения" 0 (test -e $h1/.config/fish/completions/onionfence.fish; and echo 1; or echo 0)
t_has "подсказка про PATH" ".bashrc" (command cat $T/inst.out)
t_has "подсказка про проверку" "onionfence doctor" (command cat $T/inst.out)
env HOME=$h1 XDG_CONFIG_HOME=$h1/.config fish --no-config -c 'source '$h1'/.config/fish/functions/onionfence.fish; onionfence install' >/dev/null 2>&1
t_eq "повторная установка поверх себя: код 0" 0 $status
t_eq "… файл не испорчен" 1 (cmp -s $SRC $h1/.config/fish/functions/onionfence.fish; and echo 1; or echo 0)

# XDG_CONFIG_HOME вне домашнего каталога: запускатель должен найти файл и там
set -l h4 $T/home4
mkdir -p $h4 $T/xdg4
env HOME=$h4 XDG_CONFIG_HOME=$T/xdg4 fish --no-config -c 'source '$T/single/onionfence.fish'; onionfence install' >/dev/null 2>&1
t_eq "XDG_CONFIG_HOME: файл там" 1 (test -r $T/xdg4/fish/functions/onionfence.fish; and echo 1; or echo 0)
t_has "XDG_CONFIG_HOME: команда работает" "onionfence $__onionfence_version" (env HOME=$h4 XDG_CONFIG_HOME=$T/xdg4 sh -c "'$h4/.local/bin/onionfence' version")

# Установщик из папки, без установки пакетов
if test (id -u) = 0
    # контейнер CI работает от root, а там установщик должен отказаться
    set -l out (env HOME=$T sh $repo/install.sh --no-deps 2>&1)
    t_eq "install.sh от root → код 1" 1 $status
    t_has "… объяснено" "без sudo" $out
else
    set -l h2 $T/home2
    mkdir -p $h2
    set -l out (env HOME=$h2 XDG_CONFIG_HOME=$h2/.config sh $repo/install.sh --no-deps 2>&1)
    t_eq "install.sh --no-deps → код 0" 0 $status
    t_eq "install.sh: автодополнение поставлено" 1 (test -r $h2/.config/fish/completions/onionfence.fish; and echo 1; or echo 0)
    t_has "install.sh: команда работает" "onionfence $__onionfence_version" (env HOME=$h2 $h2/.local/bin/onionfence version)
    set -l out (env HOME=$h2 sh $repo/install.sh --bad 2>&1)
    t_eq "install.sh: неизвестный параметр → код 2" 2 $status
    mkdir -p $T/noprog
    command cp $repo/install.sh $T/noprog/
    set -l out (env HOME=$h2 sh $T/noprog/install.sh --no-deps 2>&1)
    t_eq "install.sh без программы рядом → код 1" 1 $status
    t_has "… объяснено" "Не найден" $out
    # нет подтверждения — ничего не ставим
    set -l fakebin $T/fakebin
    mkdir -p $fakebin
    printf '#!/bin/sh\necho PACMAN-CALLED >>%s\n' $T/pm.log >$fakebin/pacman
    printf '#!/bin/sh\n"$@"\n' >$fakebin/sudo
    chmod +x $fakebin/pacman $fakebin/sudo
    echo n | env HOME=$h2 PATH="$fakebin:"(string join : $PATH) sh $repo/install.sh >/dev/null 2>&1
    t_eq "install.sh: ответ «нет» → код 1" 1 $status
    t_eq "… пакеты не ставились" 0 (test -e $T/pm.log; and echo 1; or echo 0)
    echo y | env HOME=$h2 XDG_CONFIG_HOME=$h2/.config PATH="$fakebin:"(string join : $PATH) sh $repo/install.sh >/dev/null 2>&1
    t_eq "install.sh: ответ «да» → код 0" 0 $status
    t_eq "… пакеты поставлены" 1 (test -e $T/pm.log; and echo 1; or echo 0)
end

# Удаление: возвращает систему в исходное состояние
reset_state
printf '%s\n' '# моё' >$__onionfence_torrc
onionfence on >/dev/null
set -l h3 $T/home3
mkdir -p $h3/.config/fish/functions $h3/.config/fish/completions $h3/.local/bin
touch $h3/.config/fish/functions/onionfence.fish $h3/.config/fish/completions/onionfence.fish $h3/.local/bin/onionfence $h3/.local/bin/другая
set -l oldhome $HOME
set -lx XDG_CONFIG_HOME $h3/.config
set -gx HOME $h3
set -l out (onionfence uninstall </dev/null 2>&1 | nocolor)
t_eq "uninstall без терминала и -y → отказ" 1 $pipestatus[1]
t_eq "… файлы на месте" 1 (test -e $h3/.local/bin/onionfence; and echo 1; or echo 0)
set -l out (onionfence uninstall -y 2>&1 | nocolor)
t_eq "uninstall -y → код 0" 0 $pipestatus[1]
t_eq "файлы удалены" 0 (test -e $h3/.local/bin/onionfence -o -e $h3/.config/fish/functions/onionfence.fish; and echo 1; or echo 0)
t_eq "чужие файлы не тронуты" 1 (test -e $h3/.local/bin/другая; and echo 1; or echo 0)
t_eq "блок убран из torrc" 0 (grep -c onionfence $__onionfence_torrc)
t_eq "настройки пользователя остались" 1 (grep -cx '# моё' $__onionfence_torrc)
t_eq "Tor остановлен" 0 (command cat $T/tor.state)
t_has "правила сняты" "nft delete table inet onionfence" (command cat $T/calls.log)
set -gx HOME $oldhome
set -e XDG_CONFIG_HOME
reset_state

# ======================================================================
section "Служба Tor: мосты при включённых правилах и загрузка"
reset_state
printf '%s\n' '# user' >$__onionfence_torrc
set -g saved_path_dropin $PATH
set -gx PATH $T/bin $PATH
set -l dropin (__onionfence_tor_dropin_path)
t_eq "путь учитывает службу" $T/dropin/tor.service.d/onionfence.conf $dropin
onionfence country de >/dev/null
onionfence country any >/dev/null
t_eq "без мостов и загрузки настройки нет" 0 (test -e $dropin; and echo 1; or echo 0)

rm -f $T/calls.log
onionfence bridges snowflake >/dev/null
t_eq "мосты → настройка службы создана" 1 (test -e $dropin; and echo 1; or echo 0)
t_has "служба получает свой resolv.conf" "$T/tor-dns" (command cat $dropin)
t_has "… в нём публичные DNS" "nameserver 9.9.9.9" (command cat $T/tor-dns/resolv.conf)
# каталог свой: в контейнерах без systemd-resolved настоящего нет
mkdir -p $T/fake-resolve
set -g __onionfence_resolve_dir $T/fake-resolve
t_has "… подмена каталога resolved прячет его сокет" "$T/tor-dns/resolve:$T/fake-resolve" (__onionfence_tor_dropin_text 1 0)
set -g __onionfence_resolve_dir /run/systemd/resolve
t_has "настройка применена" "systemctl daemon-reload" (command cat $T/calls.log)
t_lacks "мостам ещё не нужно ждать сеть: это для загрузки" "network-online" (command cat $dropin)
rm -f $T/calls.log
onionfence country de >/dev/null
t_lacks "без изменений службу не трогаем" "daemon-reload" (command cat $T/calls.log 2>/dev/null)
onionfence country any >/dev/null

set -g __onionfence_etc $T/etc
set -g __onionfence_systemd_dir $T/sd
mkdir -p $T/sd
onionfence boot on >/dev/null
t_has "загрузка: Tor ждёт сеть" "After=network-online.target NetworkManager-wait-online.service" (command cat $dropin)
t_has "загрузка: и мосты остаются" "BindReadOnlyPaths" (command cat $dropin)
onionfence bridges off >/dev/null
t_lacks "мосты сняты: свой DNS больше не нужен" "BindReadOnlyPaths" (command cat $dropin)
t_has "… ожидание сети осталось" "network-online" (command cat $dropin)
onionfence boot off >/dev/null
t_eq "boot off и без мостов → настройки нет" 0 (test -e $dropin; and echo 1; or echo 0)
t_eq "… и каталог DNS убран" 0 (test -e $T/tor-dns/resolv.conf; and echo 1; or echo 0)

# resolv.conf-ссылка внутрь каталога resolved: хватает подмены каталога
function path
    if test "$argv[1]" = resolve; and test "$argv[2]" = /etc/resolv.conf
        echo /run/systemd/resolve/stub-resolv.conf
    else
        builtin path $argv
    end
end
t_lacks "resolv.conf ведёт в resolved: отдельная подмена не нужна" ":/etc/resolv.conf" (__onionfence_tor_dropin_text 1 0)
functions -e path
set -g __onionfence_resolve_dir $T/nonexistent
t_lacks "нет каталога resolved: его и не подменяем" "$T/nonexistent" (__onionfence_tor_dropin_text 1 0)
set -g __onionfence_resolve_dir /run/systemd/resolve
if command -q systemd-analyze
    mkdir -p $T/verify-tor/tor.service.d
    __onionfence_tor_dropin_text 1 1 >$T/verify-tor/tor.service.d/onionfence.conf
    t_has "настройка: оба раздела" "[Service]" (command cat $T/verify-tor/tor.service.d/onionfence.conf)
end
t_has "причина: брокер не нашёлся по имени" "брокера" (__onionfence_explain 'Managed proxy "/usr/bin/lyrebird": broker failure dial tcp: lookup app.datapacket.com: Temporary failure in name resolution')
set -g __onionfence_etc $T/system-etc
set -g __onionfence_systemd_dir $T/system-sd
set -gx PATH $saved_path_dropin
reset_state

# ======================================================================
section "Новое название и перенос настроек"
reset_state
set -l repo (path resolve $DIR/../..)
t_eq "имя старой команды: файл совпадает с текстом install" "$(command cat $repo/functions/torproxy.fish)" "$(__onionfence_shim_text)"
t_has "старая команда работает и предупреждает" "onionfence $__onionfence_version" (fish --no-config -c "source $SRC; source $repo/functions/torproxy.fish; torproxy version 2>/dev/null")
t_eq "старое имя больше нигде в логике" 0 (string match -r '^function torproxy' -- (command cat $SRC) | count)
t_eq "пока старых настроек нет, перенос ничего не делает" 1 (__onionfence_old_present; echo $status)

# как после прошлой версии: защита при загрузке в строгом режиме, включённый режим, исключение, мосты, скрытие
mkdir -p $T/system-sd $T/run-sd $T/old-etc $T/old-run $T/old-dns/resolve $T/dropin/tor.service.d
mkdir -p $XDG_STATE_HOME/torproxy/hide
echo 'old' >$XDG_STATE_HOME/torproxy/hide/some-uuid
printf '%s\n' '# user' '# --- torproxy transparent ---' 'TransPort 127.0.0.1:9040' '# torproxy-allow 192.0.2.77' '# --- torproxy end ---' >$__onionfence_torrc
echo orig >$__onionfence_torrc.bak-torproxy
rm -f $__onionfence_torrc.bak-onionfence
echo unit >$T/system-sd/torproxy-boot.service
echo unit >$T/system-sd/torproxy-guard.service
echo unit >$T/run-sd/torproxy-guard.service
echo 'comment "torproxy-strict"' >$T/old-etc/rules.nft
echo rules >$T/old-run/rules.nft
echo conf >$T/dropin/tor.service.d/torproxy.conf
echo dns >$T/old-dns/resolv.conf
t_eq "старые настройки обнаружены" 0 (__onionfence_old_present; echo $status)
set -gx MOCK_RULES 1
set -g __onionfence_etc $T/new-etc
set -g __onionfence_systemd_dir $T/system-sd
rm -f $T/calls.log
set -l out (onionfence version)
t_lacks "version перенос не запускает" "переношу" "$out"
t_eq "… и старое осталось" 0 (__onionfence_old_present; echo $status)
set -l out (onionfence status 2>&1 | nocolor)
t_has "перенос сообщает о себе" "переношу настройки" "$out"
t_has "перенос завершён" "Настройки перенесены" "$out"
t_eq "метки torrc новые" 1 (grep -cx '# --- onionfence transparent ---' $__onionfence_torrc)
t_eq "исключение перенесено" "192.0.2.77" (__onionfence_allow_current)
t_eq "настройки пользователя целы" 1 (grep -cx '# user' $__onionfence_torrc)
t_eq "копия torrc под новым именем" orig (command cat $__onionfence_torrc.bak-onionfence)
t_eq "скрытие перенесено" old (command cat $XDG_STATE_HOME/onionfence/hide/some-uuid)
t_eq "старые службы удалены" 0 (test -e $T/system-sd/torproxy-boot.service -o -e $T/system-sd/torproxy-guard.service -o -e $T/run-sd/torproxy-guard.service; and echo 1; or echo 0)
t_eq "старые каталоги убраны" 0 (test -e $T/old-etc -o -e $T/old-run -o -e $T/old-dns; and echo 1; or echo 0)
t_eq "старая настройка службы Tor убрана" 0 (test -e $T/dropin/tor.service.d/torproxy.conf; and echo 1; or echo 0)
t_has "старая таблица снята" "nft delete table inet torproxy" (command cat $T/calls.log)
t_has "старый сторож остановлен" "systemctl stop torproxy-guard" (command cat $T/calls.log)
set -l calls (command cat $T/calls.log)
set -l new_at (contains -i -- "nft -f -" $calls)
set -l del_at (contains -i -- "nft delete table inet torproxy" $calls)
t_eq "новые правила раньше снятия старых" 1 (test -n "$new_at" -a -n "$del_at"; and test $new_at -lt $del_at; and echo 1; or echo "$new_at $del_at")
t_eq "защита при загрузке перенесена" 1 (test -e $T/system-sd/onionfence-boot.service; and echo 1; or echo 0)
t_has "… в том же строгом режиме" "onionfence-strict" (command cat $T/new-etc/rules.nft)
rm -f $T/calls.log
onionfence status >/dev/null 2>&1
t_lacks "второй раз перенос не повторяется" "torproxy" (command cat $T/calls.log)
set -gx MOCK_RULES 0
# нет пароля: команда не выполняется, старое не трогаем
echo unit >$T/system-sd/torproxy-boot.service
functions -c sudo __saved_sudo
function sudo
    test "$argv[1]" = -v; and return 1
    __saved_sudo $argv
end
rm -f $T/calls.log
set -l out (onionfence off -y 2>&1 | nocolor)
t_eq "нет пароля → код 1" 1 $pipestatus[1]
t_has "… объяснено" "нужен пароль" "$out"
t_eq "… старая служба на месте" 1 (test -e $T/system-sd/torproxy-boot.service; and echo 1; or echo 0)
functions -e sudo
functions -c __saved_sudo sudo
functions -e __saved_sudo
rm -f $T/system-sd/torproxy-boot.service $T/system-sd/onionfence-boot.service $T/system-sd/onionfence-guard.service
set -g __onionfence_etc $T/system-etc
set -g __onionfence_systemd_dir $T/system-sd
reset_state

# установка поверх прошлой версии
set -l h5 $T/home5
mkdir -p $h5/.config/fish/functions $h5/.config/fish/completions $h5/.local/bin
echo 'старый код' >$h5/.config/fish/functions/torproxy.fish
echo x >$h5/.config/fish/completions/torproxy.fish
echo x >$h5/.local/bin/torproxy
env HOME=$h5 XDG_CONFIG_HOME=$h5/.config fish --no-config -c "source $SRC; onionfence install" >/dev/null 2>&1
t_eq "поверх старой версии: старый код заменён" "$(__onionfence_shim_text)" "$(command cat $h5/.config/fish/functions/torproxy.fish)"
t_eq "… старый запускатель и дополнение убраны" 0 (test -e $h5/.local/bin/torproxy -o -e $h5/.config/fish/completions/torproxy.fish; and echo 1; or echo 0)

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
    set -g __onionfence_transport 19040
    set -g __onionfence_dnsport 19053
    set -g __onionfence_ctlport 19051
    set -g __onionfence_cookie $T/tordata/control_auth_cookie
    set -g __onionfence_timeout 120
    set -g __onionfence_torrc $T/live.torrc
    mkdir -m 700 $T/tordata
    printf '%s\n' "DataDirectory $T/tordata" "SocksPort 127.0.0.1:$LIVE_SOCKS" "Log notice file $T/tor.log" >$__onionfence_torrc

    set -l out (onionfence on 2>&1 | nocolor)
    t_eq "on с настоящим Tor → код 0" 0 $pipestatus[1]
    t_has "Tor подключился (100%)" "100%" $out
    t_has "check.torproject.org подтверждает Tor" "✔ да" $out
    t_has "правила используют тестовые порты" "redirect to :19053" (command cat $T/ruleset.nft 2>/dev/null)

    set -l ans (python3 -I -c "
import socket,struct,sys
q=struct.pack('>HHHHHH',0x1234,0x0100,1,0,0,0)+b''.join(bytes([len(p)])+p.encode() for p in 'check.torproject.org'.split('.'))+b'\0'+struct.pack('>HH',1,1)
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.settimeout(15); s.sendto(q,('127.0.0.1',int(sys.argv[1])))
r=s.recv(512); print(struct.unpack('>H',r[6:8])[0])" $__onionfence_dnsport 2>&1)
    t_eq "DNSPort отвечает на A-запрос (есть ответы)" 1 (test "$ans" -gt 0 2>/dev/null; and echo 1; or echo "$ans")

    python3 -I -c "import socket,sys; socket.create_connection(('127.0.0.1',int(sys.argv[1])),3)" $__onionfence_transport 2>/dev/null
    t_eq "TransPort принимает соединения" 0 $status

    set -l out (onionfence newip | nocolor)
    t_eq "newip с настоящим Tor → код 0" 0 $pipestatus[1]

    set -l out (onionfence country de | nocolor)
    t_lacks "country de применён сразу через ControlPort (без HUP)" "10 секунд" $out
    t_has "country de → Tor принял ExitNodes" "ExitNodes={de}" (__onionfence_control 'GETCONF ExitNodes')
    set -l out (onionfence status | nocolor)
    if not t_has "status: выход действительно в Германии" " DE" (string match '*Внешний IP*' -- $out)
        echo "  --- диагностика: "(tor --version | head -1)
        __onionfence_control 'GETCONF ExitNodes StrictNodes' 'GETINFO circuit-status' | string replace -r '^' '      '
    end
    t_has "status: по-прежнему через Tor" "✔ да" $out
    onionfence country any >/dev/null
    t_lacks "country any → ExitNodes снят" "{de}" (__onionfence_control 'GETCONF ExitNodes')

    if __onionfence_has_conflux
        onionfence country de >/dev/null
        t_has "country de → Conflux выключен: его цепочки шли бы мимо страны" "ConfluxEnabled=0" (__onionfence_control 'GETCONF ConfluxEnabled')
        onionfence country any >/dev/null
        t_has "country any → Conflux снова как в сети" "ConfluxEnabled=auto" (__onionfence_control 'GETCONF ConfluxEnabled')
    end
    onionfence exclude de,nl >/dev/null
    t_has "exclude → Tor принял запрет" "ExcludeExitNodes={de},{nl}" (__onionfence_control 'GETCONF ExcludeExitNodes')
    set -l out (onionfence status | nocolor)
    t_lacks "exclude de,nl: выход не в Германии" " DE" (string match '*Внешний IP*' -- $out)
    t_lacks "exclude de,nl: выход не в Нидерландах" " NL" (string match '*Внешний IP*' -- $out)
    onionfence exclude off >/dev/null
    t_lacks "exclude off → запрет снят" "{de}" (__onionfence_control 'GETCONF ExcludeExitNodes')

    curl -s --max-time 40 -o /dev/null https://check.torproject.org/api/ip
    set -l out (onionfence circuit | nocolor)
    t_eq "circuit с настоящим Tor → код 0" 0 $pipestatus[1]
    t_has "circuit: путь через узлы" "──▶" "$out"
    t_has "circuit: выход назван" "видит сайт" "$out"
    t_eq "circuit: в пути три узла" 4 (count (string match -ra '──▶' -- "$(string match '*Ты*' -- $out)"))
    set -l out (onionfence watch </dev/null | nocolor)
    t_eq "watch с настоящим Tor → код 0" 0 $pipestatus[1]
    t_has "watch: настоящий счётчик цепочек" "Цепочек" "$out"
    t_lacks "watch: Tor на связи" "нет связи" "$out"

    if command -q python3
        set -l out (TP_CTL=$__onionfence_ctlport TP_COOKIE=$__onionfence_cookie python3 -I $DIR/watch_pty.py $DIR/watch_child.fish $SRC live 2>&1)
        t_has "панель в терминале с настоящим Tor: путь" "──▶" "$out"
        t_lacks "панель в терминале с настоящим Tor: связь есть" "нет связи" "$out"
        t_eq "панель: фоновый запрос вернул IP" 1 (string match -qr 'Внешний IP\s+\S*\d+\.\d+\.\d+\.\d+' -- "$out"; and echo 1; or echo 0)
        t_has "панель: терминал возвращён" "STTY_OK" "$out"
        t_has "панель: экран возвращён" "SCREEN_OFF" "$out"
    end

    set -l out (onionfence bridges auto 2>&1 | nocolor)
    t_eq "bridges auto с настоящим Tor → код 0" 0 $pipestatus[1]
    t_has "bridges auto: сеть открыта → напрямую" "Работает: direct" $out
    t_has "bridges auto: режим снова включён, Tor подтверждён" "✔ да" $out

    if command -sq lyrebird
        set -l out (onionfence bridges snowflake 2>&1 | nocolor)
        t_eq "живые мосты snowflake → код 0" 0 $pipestatus[1]
        t_has "через snowflake Tor подключился" "✔ да" $out
        set -l out (onionfence bridges off 2>&1 | nocolor)
        t_has "мосты выключены → снова напрямую в Tor" "✔ да" $out
    else
        echo "  (живой тест мостов пропущен: нет lyrebird — paru -S lyrebird-proxy)"
    end

    onionfence off >/dev/null
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
