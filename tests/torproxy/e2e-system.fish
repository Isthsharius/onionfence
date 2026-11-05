# Настоящий запуск torproxy на системе: sudo, systemd, nftables, сеть.
# Меняет сетевые правила машины — запускать только в одноразовой среде (CI),
# на своём компьютере используйте run.fish.
set -gx T (mktemp -d)
set -gx DIR (path resolve (status dirname))
set -g SRC (path resolve $DIR/../../functions/torproxy.fish)
source $SRC

# проверки без заглушек из lib.fish
function __t_record --argument-names result name detail
    echo "$result $name" >>$T/results
    test $result = PASS; and echo "  ✔ $name"; or echo "  ✘ $name  $detail"
end
function t_eq --argument-names name expected actual
    test "$expected" = "$actual"; and __t_record PASS $name; or __t_record FAIL $name "ожидалось «$expected», получено «$actual»"
end
function t_has --argument-names name needle
    set -e argv[1..2]
    string match -q -- "*$needle*" "$argv"; and __t_record PASS $name; or __t_record FAIL $name "нет «$needle» в «$argv»"
end
function istor
    # Tor иногда закрывает отдельное соединение: повторяем и печатаем причину.
    # Утечку повтор не скроет: ответ false остаётся ответом и сразу возвращается.
    for i in (seq 3)
        set -l reply (curl -sS --max-time 60 https://check.torproject.org/api/ip 2>$T/curl.err)
        set -l r (echo $reply | jq -r '.IsTor' 2>/dev/null)
        # не «.IsTor // …»: jq считает false пустым и подставил бы запасное значение
        if test -n "$r"
            echo $r
            return
        end
        echo "  (попытка $i: "(command cat $T/curl.err)")" >&2
        sleep 5
    end
    echo "нет ответа"
end

echo "== "(torproxy version)
t_has "платформа определена" "служба $__torproxy_unit" (torproxy version)
t_eq "до включения — напрямую" false (istor)

torproxy on
t_eq "on → код 0" 0 $status
t_eq "таблица nftables создана" 1 (sudo nft list tables | grep -c 'inet torproxy')
t_eq "трафик идёт через Tor" true (istor)
t_eq "DNS работает через Tor" 1 (getent hosts check.torproject.org >/dev/null; and echo 1; or echo 0)
t_eq "UDP мимо Tor заблокирован" BLOCKED (python3 -c "
import socket
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
try: s.sendto(b'x',('8.8.8.8',443)); print('SENT')
except PermissionError: print('BLOCKED')")
t_eq "IPv6 мимо Tor заблокирован" BLOCKED (python3 -c "
import socket
try:
    s=socket.socket(socket.AF_INET6,socket.SOCK_DGRAM); s.sendto(b'x',('2001:4860:4860::8888',443)); print('SENT')
except PermissionError: print('BLOCKED')
except OSError: print('BLOCKED')")

torproxy leaktest
t_eq "leaktest на настоящей системе → код 0" 0 $status

torproxy newip
t_eq "newip → код 0" 0 $status
torproxy country de
set -l out (torproxy status)
t_has "country de → выход в Германии" " DE" (string match '*Внешний IP*' -- $out)
# Страна не должна «протекать»: раньше Conflux изредка уводил запросы мимо неё
for i in (seq 5)
    torproxy country any >/dev/null
    torproxy newip >/dev/null
    torproxy country de >/dev/null
    t_has "country de, попытка $i: выход в Германии" " DE" (string match '*Внешний IP*' -- (torproxy status))
end
torproxy country any >/dev/null

set -l out (torproxy exclude de,nl)
t_eq "exclude → код 0" 0 $status
for i in (seq 3)
    set -l row (string match '*Внешний IP*' -- (torproxy status))
    t_eq "exclude de,nl, попытка $i: выход вне этих стран" 0 (string match -qr ' (DE|NL)' -- "$row"; and echo 1; or echo 0)
end
torproxy exclude off >/dev/null

curl -s --max-time 60 -o /dev/null https://check.torproject.org/api/ip
t_has "circuit на настоящей системе" "──▶" (torproxy circuit)
t_has "watch на настоящей системе: один кадр" "Цепочек" (torproxy watch </dev/null)
t_has "guide открывается" "Быстрый старт" (torproxy guide)
t_has "команда для других оболочек" "Страна выхода" (bash -c "'$DIR/../../bin/torproxy' status")

torproxy doctor
t_eq "doctor на настоящей системе → код 0" 0 $status

# Сторож: стираем таблицу как чужая программа и ждём, пока он её вернёт
t_eq "сторож запущен" active (systemctl is-active torproxy-guard)
sudo nft flush ruleset
for i in (seq 15)
    sudo nft list table inet torproxy >/dev/null 2>&1; and break
    sleep 1
end
t_eq "сторож вернул стёртые правила" 1 (sudo nft list tables | grep -c 'inet torproxy')
t_eq "… и трафик снова идёт через Tor" true (istor)

torproxy on --strict >/dev/null
t_eq "on --strict → код 0" 0 $status
t_eq "строгий режим: трафик через Tor" true (istor)
torproxy leaktest
t_eq "строгий режим: leaktest → код 0" 0 $status
torproxy bridges auto >/dev/null
t_eq "bridges auto в строгом режиме → код 0" 0 $status
t_eq "… режим остался строгим" 1 (sudo nft list table inet torproxy | grep -c torproxy-strict)
t_eq "… трафик через Tor" true (istor)

torproxy off
t_eq "off: таблица удалена" 0 (sudo nft list tables | grep -c 'inet torproxy')
t_eq "off: сторож остановлен" inactive (systemctl is-active torproxy-guard)
sleep 5
t_eq "off: сторож не вернул таблицу" 0 (sudo nft list tables | grep -c 'inet torproxy')
t_eq "off: снова напрямую" false (istor)

# Одна программа через Tor: настоящая изоляция, остальная система идёт напрямую
function run_istor
    torproxy run curl -s --max-time 60 https://check.torproject.org/api/ip | string match '{*' | jq -r .IsTor
end
for i in (seq 3)
    set -g run_result (run_istor)
    test "$run_result" = true; and break
    sleep 5
end
t_eq "run: программа идёт через Tor" true "$run_result"
t_eq "run: после неё Tor снова остановлен" inactive (systemctl is-active $__torproxy_unit)
t_eq "run: система всё это время напрямую" false (istor)
t_eq "run: пространство убрано" 0 (sudo ip netns list | grep -c torproxy-run)
t_eq "run: правила убраны" 0 (sudo nft list tables | grep -c torproxy_run)
sudo systemctl start $__torproxy_unit
for i in (seq 120)
    curl -s --max-time 10 --socks5-hostname 127.0.0.1:9050 -o /dev/null https://check.torproject.org/api/ip; and break
    sleep 1
end
torproxy run --force sh -c 'exit 7' >/dev/null
t_eq "run: код возврата программы" 7 $status
torproxy run --force sh -c 'test ! -e /run/systemd/resolve/io.systemd.Resolve' >/dev/null
t_eq "run: сокет systemd-resolved спрятан" 0 $status
torproxy run --force sh -c 'getent hosts check.torproject.org' >/dev/null
t_eq "run: имена разрешаются через Tor" 0 $status
torproxy run --force sh -c 'ping -c1 -W2 1.1.1.1' >/dev/null 2>&1
t_eq "run: ICMP отброшен" 1 $status
torproxy run --force python3 -c "
import socket
try:
    socket.create_connection(('2001:4860:4860::8888',443),3); raise SystemExit(0)
except OSError:
    raise SystemExit(5)" >/dev/null 2>&1
t_eq "run: IPv6 недоступен" 5 $status
torproxy run --force ip route show >$T/run-route.txt
t_has "run: своя сетевая среда" "172.31.250" (command cat $T/run-route.txt)
torproxy run --force id -u >$T/run-id.txt
t_eq "run: программа не от root" (id -u) (string match -r '^\d+$' -- (command cat $T/run-id.txt))
# программа, оставшаяся в фоне, не даёт убрать пространство; --stop завершает её
torproxy run --force sh -c 'sleep 300 >/dev/null 2>&1 &' >/dev/null
t_eq "run: фоновая программа оставляет пространство" 1 (sudo ip netns list | grep -c torproxy-run)
torproxy run --stop >/dev/null
t_eq "run --stop убирает всё" 0 (sudo ip netns list | grep -c torproxy-run)
sudo systemctl stop $__torproxy_unit

# Исключения: заведомо известный адрес идёт напрямую, а сняли исключение — снова через Tor
function cf_ip
    curl -s --max-time 40 https://1.1.1.1/cdn-cgi/trace | string match -rg '^ip=(.*)$'
end
set -l direct_ip (cf_ip)
torproxy on >/dev/null
torproxy allow 1.1.1.1 >/dev/null
t_eq "allow: адрес идёт напрямую, с настоящего IP" "$direct_ip" (cf_ip)
t_eq "allow: остальное через Tor" true (istor)
t_eq "allow: сторож работает и после смены правил" active (systemctl is-active torproxy-guard)
torproxy allow off >/dev/null
t_eq "allow off: настоящего IP больше не видно" 0 (test "$(cf_ip)" = "$direct_ip"; and echo 1; or echo 0)
torproxy off -y >/dev/null

# Защита при загрузке: перезагрузить машину CI нельзя, поэтому запускаем службу вручную
torproxy boot on
t_eq "boot on → код 0" 0 $status
t_eq "служба включена" enabled (systemctl is-enabled torproxy-boot)
sudo systemctl start torproxy-boot
t_eq "служба поднимает правила" 1 (sudo nft list tables | grep -c 'inet torproxy')
# При настоящей загрузке Tor запускает systemd, а до его старта выхода быть не должно
curl -s --max-time 5 -o /dev/null https://check.torproject.org/api/ip
t_eq "пока Tor не запущен, выхода нет" 1 (test $status -ne 0; and echo 1; or echo 0)
sudo systemctl start $__torproxy_unit
for i in (seq 120)
    curl -s --max-time 10 -o /dev/null https://check.torproject.org/api/ip; and break
    sleep 1
end
t_eq "… и трафик идёт через Tor" true (istor)
torproxy off -y >/dev/null
torproxy boot off
t_eq "boot off: служба удалена" 1 (systemctl cat torproxy-boot >/dev/null 2>&1; and echo 0; or echo 1)
t_eq "после boot off — напрямую" false (istor)

# Установка с нуля, как у нового пользователя: чистый домашний каталог, пакеты уже стоят
set -l fresh $T/fresh
mkdir -p $fresh
env HOME=$fresh sh $DIR/../../install.sh --yes >/dev/null 2>&1
t_eq "install.sh на настоящей системе" 0 $status
t_has "установленная команда работает" "служба $__torproxy_unit" (env HOME=$fresh bash -c "$fresh/.local/bin/torproxy version")
env HOME=$fresh $fresh/.local/bin/torproxy on >/dev/null
t_eq "установленная команда включает режим" 1 (sudo nft list tables | grep -c 'inet torproxy')
t_eq "… и трафик через Tor" true (istor)
env HOME=$fresh $fresh/.local/bin/torproxy uninstall -y >/dev/null
t_eq "uninstall снимает правила" 0 (sudo nft list tables | grep -c 'inet torproxy')
t_eq "uninstall убирает блок из torrc" 0 (sudo grep -c 'torproxy' $__torproxy_torrc)
t_eq "uninstall останавливает Tor" inactive (systemctl is-active $__torproxy_unit)
t_eq "после uninstall снова напрямую" false (istor)

set -l failed (grep -c '^FAIL' $T/results)
echo
test $failed -eq 0; and echo "  Системный запуск: всё в порядке"; or echo "  Системный запуск: провалено $failed"
test $failed -eq 0
