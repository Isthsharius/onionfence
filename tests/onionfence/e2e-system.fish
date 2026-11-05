# Настоящий запуск onionfence на системе: sudo, systemd, nftables, сеть.
# Меняет сетевые правила машины — запускать только в одноразовой среде (CI),
# на своём компьютере используйте run.fish.
set -gx T (mktemp -d)
set -gx DIR (path resolve (status dirname))
set -g SRC (path resolve $DIR/../../functions/onionfence.fish)
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

echo "== "(onionfence version)
t_has "платформа определена" "служба $__onionfence_unit" (onionfence version)
t_eq "до включения — напрямую" false (istor)

onionfence on
t_eq "on → код 0" 0 $status
t_eq "таблица nftables создана" 1 (sudo nft list tables | grep -c 'inet onionfence')
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

onionfence leaktest
t_eq "leaktest на настоящей системе → код 0" 0 $status
t_eq "leaktest не уронил Tor" active (systemctl is-active $__onionfence_unit)
t_eq "… и Tor работает" true (istor)

onionfence newip
t_eq "newip → код 0" 0 $status
onionfence country de
set -l out (onionfence status)
t_has "country de → выход в Германии" " DE" (string match '*Внешний IP*' -- $out)
set -g country_answers 0
# Страна не должна «протекать»: раньше Conflux изредка уводил запросы мимо неё
for i in (seq 5)
    onionfence country any >/dev/null
    onionfence newip >/dev/null
    onionfence country de >/dev/null
    # «нет ответа» не значит неверная страна: проверяем только ответы сайта
    set -l row
    for try in (seq 3)
        set row (string match '*Внешний IP*' -- (onionfence status))
        string match -q '*нет ответа*' -- "$row"; or break
        sleep 5
    end
    # неверная страна — ошибка, а сайт, который не ответил, ничего о стране не говорит
    if string match -q '*нет ответа*' -- "$row"
        echo "  (country de, попытка $i: сайт проверки не ответил)"
    else
        t_has "country de, попытка $i: выход в Германии" " DE" "$row"
        set -g country_answers (math $country_answers + 1)
    end
end
t_eq "сайт проверки ответил хотя бы раз из 5" 1 (test $country_answers -ge 1; and echo 1; or echo 0)
onionfence country any >/dev/null

set -l out (onionfence exclude de,nl)
t_eq "exclude → код 0" 0 $status
for i in (seq 3)
    set -l row (string match '*Внешний IP*' -- (onionfence status))
    t_eq "exclude de,nl, попытка $i: выход вне этих стран" 0 (string match -qr ' (DE|NL)' -- "$row"; and echo 1; or echo 0)
end
onionfence exclude off >/dev/null

curl -s --max-time 60 -o /dev/null https://check.torproject.org/api/ip
t_has "circuit на настоящей системе" "──▶" (onionfence circuit)
t_has "watch на настоящей системе: один кадр" "Цепочек" (onionfence watch </dev/null)
t_has "guide открывается" "Быстрый старт" (onionfence guide)
t_has "команда для других оболочек" "Страна выхода" (bash -c "'$DIR/../../bin/onionfence' status")

onionfence doctor
t_eq "doctor на настоящей системе → код 0" 0 $status

# Сторож: стираем таблицу как чужая программа и ждём, пока он её вернёт
t_eq "сторож запущен" active (systemctl is-active onionfence-guard)
sudo nft flush ruleset
for i in (seq 15)
    sudo nft list table inet onionfence >/dev/null 2>&1; and break
    sleep 1
end
t_eq "сторож вернул стёртые правила" 1 (sudo nft list tables | grep -c 'inet onionfence')
t_eq "… и трафик снова идёт через Tor" true (istor)

onionfence on --strict >/dev/null
t_eq "on --strict → код 0" 0 $status
t_eq "строгий режим: трафик через Tor" true (istor)
onionfence leaktest
t_eq "строгий режим: leaktest → код 0" 0 $status
onionfence bridges auto >/dev/null
t_eq "bridges auto в строгом режиме → код 0" 0 $status
t_eq "… режим остался строгим" 1 (sudo nft list table inet onionfence | grep -c onionfence-strict)
t_eq "… трафик через Tor" true (istor)

onionfence off
t_eq "off: таблица удалена" 0 (sudo nft list tables | grep -c 'inet onionfence')
t_eq "off: сторож остановлен" inactive (systemctl is-active onionfence-guard)
sleep 5
t_eq "off: сторож не вернул таблицу" 0 (sudo nft list tables | grep -c 'inet onionfence')
t_eq "off: снова напрямую" false (istor)

# Одна программа через Tor: настоящая изоляция, остальная система идёт напрямую
function run_istor
    onionfence run curl -s --max-time 60 https://check.torproject.org/api/ip | string match '{*' | jq -r .IsTor
end
for i in (seq 3)
    set -g run_result (run_istor)
    test "$run_result" = true; and break
    sleep 5
end
t_eq "run: программа идёт через Tor" true "$run_result"
t_eq "run: после неё Tor снова остановлен" inactive (systemctl is-active $__onionfence_unit)
t_eq "run: система всё это время напрямую" false (istor)
t_eq "run: пространство убрано" 0 (sudo ip netns list | grep -c onionfence-run)
t_eq "run: правила убраны" 0 (sudo nft list tables | grep -c onionfence_run)
sudo systemctl start $__onionfence_unit
for i in (seq 120)
    curl -s --max-time 10 --socks5-hostname 127.0.0.1:9050 -o /dev/null https://check.torproject.org/api/ip; and break
    sleep 1
end
onionfence run --force sh -c 'exit 7' >/dev/null
t_eq "run: код возврата программы" 7 $status
onionfence run --force sh -c 'test ! -e /run/systemd/resolve/io.systemd.Resolve' >/dev/null
t_eq "run: сокет systemd-resolved спрятан" 0 $status
onionfence run --force sh -c 'getent hosts check.torproject.org' >/dev/null
t_eq "run: имена разрешаются через Tor" 0 $status
onionfence run --force sh -c 'ping -c1 -W2 1.1.1.1' >/dev/null 2>&1
# код зависит от системы: 1 — нет ответа, 2 — ping не смог отправить; важно, что ответа нет
t_eq "run: ICMP отброшен" 1 (test $status -ne 0; and echo 1; or echo 0)
onionfence run --force python3 -c "
import socket
try:
    socket.create_connection(('2001:4860:4860::8888',443),3); raise SystemExit(0)
except OSError:
    raise SystemExit(5)" >/dev/null 2>&1
t_eq "run: IPv6 недоступен" 5 $status
onionfence run --force ip route show >$T/run-route.txt
t_has "run: своя сетевая среда" "172.31.250" (command cat $T/run-route.txt)
onionfence run --force id -u >$T/run-id.txt
t_eq "run: программа не от root" (id -u) (string match -r '^\d+$' -- (command cat $T/run-id.txt))
# программа, оставшаяся в фоне, не даёт убрать пространство; --stop завершает её
onionfence run --force sh -c 'sleep 300 >/dev/null 2>&1 &' >/dev/null
t_eq "run: фоновая программа оставляет пространство" 1 (sudo ip netns list | grep -c onionfence-run)
onionfence run --stop >/dev/null
t_eq "run --stop убирает всё" 0 (sudo ip netns list | grep -c onionfence-run)
sudo systemctl stop $__onionfence_unit

# Исключения: заведомо известный адрес идёт напрямую, а сняли исключение — снова через Tor
function cf_ip
    curl -s --max-time 40 https://1.1.1.1/cdn-cgi/trace | string match -rg '^ip=(.*)$'
end
set -l direct_ip (cf_ip)
onionfence on >/dev/null
onionfence allow 1.1.1.1 >/dev/null
t_eq "allow: адрес идёт напрямую, с настоящего IP" "$direct_ip" (cf_ip)
t_eq "allow: остальное через Tor" true (istor)
t_eq "allow: сторож работает и после смены правил" active (systemctl is-active onionfence-guard)
onionfence allow off >/dev/null
t_eq "allow off: настоящего IP больше не видно" 0 (test "$(cf_ip)" = "$direct_ip"; and echo 1; or echo 0)
onionfence off -y >/dev/null

# Мосты при уже включённых правилах: у транспорта должен быть DNS мимо Tor. Без этого был замкнутый круг.
if command -q snowflake-client
    onionfence on >/dev/null
    onionfence bridges snowflake >$T/sf-under-rules.txt 2>&1
    set -l sf_rc $status
    t_eq "мосты при включённых правилах: Tor подключился" 0 $sf_rc
    test $sf_rc = 0; or journalctl -u $__onionfence_unit -n 40 --no-pager | cut -c1-150
    set -l pid (systemctl show -p MainPID --value $__onionfence_unit)
    t_has "служба Tor видит свой resolv.conf" "nameserver 9.9.9.9" (sudo nsenter -t $pid -m cat /etc/resolv.conf)
    t_eq "сокет resolved скрыт от Tor" 0 (sudo nsenter -t $pid -m sh -c 'test -e /run/systemd/resolve/io.systemd.Resolve'; and echo 1; or echo 0)
    t_eq "остальная система resolv.conf не меняла" 0 (grep -c 9.9.9.9 /etc/resolv.conf)
    sudo nsenter -t $pid -m setpriv --reuid=$__onionfence_user --clear-groups getent hosts app.datapacket.com >/dev/null
    t_eq "пользователь Tor разрешает имя брокера" 0 $status
    t_eq "трафик системы всё равно через Tor" true (istor)
    onionfence bridges off >/dev/null
    t_eq "мосты сняты: настройка службы убрана" 1 (test ! -e /etc/systemd/system/$__onionfence_unit.service.d/onionfence.conf; and echo 1; or echo 0)
    onionfence off -y >/dev/null
end

# Защита при загрузке: перезагрузить машину CI нельзя, поэтому запускаем службу вручную
onionfence boot on
t_eq "boot on → код 0" 0 $status
t_eq "служба включена" enabled (systemctl is-enabled onionfence-boot)
sudo systemctl start onionfence-boot
t_eq "служба поднимает правила" 1 (sudo nft list tables | grep -c 'inet onionfence')
# При настоящей загрузке Tor запускает systemd, а до его старта выхода быть не должно
curl -s --max-time 5 -o /dev/null https://check.torproject.org/api/ip
t_eq "пока Tor не запущен, выхода нет" 1 (test $status -ne 0; and echo 1; or echo 0)
sudo systemctl start $__onionfence_unit
for i in (seq 120)
    curl -s --max-time 10 -o /dev/null https://check.torproject.org/api/ip; and break
    sleep 1
end
t_eq "… и трафик идёт через Tor" true (istor)
onionfence off -y >/dev/null
onionfence boot off
t_eq "boot off: служба удалена" 1 (systemctl cat onionfence-boot >/dev/null 2>&1; and echo 0; or echo 1)
t_eq "после boot off — напрямую" false (istor)

# Чистый запуск: настоящий домашний каталог скрыт, а след не остаётся
sudo systemctl start $__onionfence_unit
for i in (seq 120)
    curl -s --max-time 10 --socks5-hostname 127.0.0.1:9050 -o /dev/null https://check.torproject.org/api/ip; and break
    sleep 1
end
echo secret >$HOME/.e2e-real-file
onionfence run --force --fresh sh -c 'test ! -e ~/.e2e-real-file' >/dev/null
t_eq "--fresh: настоящие файлы не видны" 0 $status
onionfence run --force --fresh sh -c 'findmnt -n -o FSTYPE ~' >$T/fresh-fs.txt
t_has "--fresh: домашний каталог в памяти" tmpfs (command cat $T/fresh-fs.txt)
onionfence run --force --fresh sh -c 'echo trace >~/.e2e-fresh-file; test -f ~/.e2e-fresh-file' >/dev/null
t_eq "--fresh: программа может писать" 0 $status
t_eq "--fresh: на настоящий диск ничего не попало" 0 (test -e $HOME/.e2e-fresh-file; and echo 1; or echo 0)
onionfence run --force --fresh sh -c 'test "$(id -u)" != 0 && test "$PWD" = "$HOME"' >/dev/null
t_eq "--fresh: не от root и в чистом каталоге" 0 $status
t_eq "--fresh: файл на месте после выхода" secret (command cat $HOME/.e2e-real-file)
for i in (seq 3)
    set -g fresh_tor (onionfence run --force --fresh curl -s --max-time 60 https://check.torproject.org/api/ip | string match '{*' | jq -r .IsTor)
    test "$fresh_tor" = true; and break
    sleep 5
end
t_eq "--fresh: через Tor" true "$fresh_tor"
rm -f $HOME/.e2e-real-file
sudo systemctl stop $__onionfence_unit

# Смена цепочки по таймеру
onionfence on >/dev/null
onionfence newip --every 30s >/dev/null
t_eq "таймер запущен" active (systemctl is-active onionfence-rotate)
t_has "статус показывает таймер" "каждые 30s" (onionfence status)
sleep 36
t_has "таймер сменил цепочку, Tor ответил" "250 OK" (sudo journalctl -u onionfence-rotate --no-pager -q)
onionfence newip --every off >/dev/null
t_eq "таймер снят" inactive (systemctl is-active onionfence-rotate)
onionfence newip --every 30s >/dev/null

# Экстренное отключение: полностью закрывает сеть, даже Tor, а off возвращает
sleep 300 &
set -l victim $last_pid
disown
onionfence panic add sleep >/dev/null
onionfence panic >/dev/null
t_eq "panic: таблица стоит" 1 (sudo nft list tables | grep -c onionfence_panic)
t_eq "panic: Tor остановлен" inactive (systemctl is-active $__onionfence_unit)
t_eq "panic: таймер остановлен" inactive (systemctl is-active onionfence-rotate)
t_eq "panic: сторож остановлен" inactive (systemctl is-active onionfence-guard)
t_eq "panic: программа из списка закрыта" 1 (kill -0 $victim 2>/dev/null; and echo 0; or echo 1)
sudo -u $__onionfence_user curl -s --max-time 5 -o /dev/null https://1.1.1.1 2>/dev/null
t_eq "panic: даже пользователь Tor не выходит" 1 (test $status -ne 0; and echo 1; or echo 0)
onionfence on >/dev/null
t_eq "panic: on отказывается" 1 $status
onionfence panic off >/dev/null
t_eq "panic off: запрет снят" 0 (sudo nft list tables | grep -c onionfence_panic)
onionfence off -y >/dev/null
t_eq "после off снова напрямую" false (istor)
onionfence panic >/dev/null
onionfence off -y >/dev/null
t_eq "off снимает и экстренный запрет" 0 (sudo nft list tables | grep -c onionfence_panic)
t_eq "… и интернет есть" false (istor)
onionfence panic del sleep >/dev/null

# Перенос со старого имени на настоящей системе: воссоздаём состояние прошлой версии
# sed, а не string: string внутри функции не читает канал без терминала
function __e2e_old
    command sed s/onionfence/torproxy/g
end
sudo mkdir -p /etc/torproxy
__onionfence_torrc >/dev/null
sudo sed -i -e 's/^# --- onionfence transparent ---$/# --- torproxy transparent ---/' -e 's/^# --- onionfence end ---$/# --- torproxy end ---/' $__onionfence_torrc
__onionfence_rules strict | __e2e_old | sudo tee /etc/torproxy/rules.nft >/dev/null
__onionfence_rules strict | __e2e_old | sudo nft -f -
__onionfence_boot_unit_text | __e2e_old | sudo tee /etc/systemd/system/torproxy-boot.service >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable torproxy-boot $__onionfence_unit
sudo systemctl start $__onionfence_unit
t_eq "старая таблица есть" 1 (sudo nft list tables | grep -c 'inet torproxy')
onionfence status >/dev/null
t_eq "перенос: старая таблица снята" 0 (sudo nft list tables | grep -c 'inet torproxy')
t_eq "перенос: новая таблица стоит" 1 (sudo nft list tables | grep -c 'inet onionfence')
t_eq "перенос: строгий режим сохранён" 1 (sudo nft list table inet onionfence | grep -c onionfence-strict)
t_eq "перенос: старая служба убрана" 0 (test -e /etc/systemd/system/torproxy-boot.service; and echo 1; or echo 0)
t_eq "перенос: новая служба включена" enabled (systemctl is-enabled onionfence-boot)
t_eq "перенос: сторож работает" active (systemctl is-active onionfence-guard)
for i in (seq 60)
    curl -s --max-time 10 -o /dev/null https://check.torproject.org/api/ip; and break
    sleep 1
end
t_eq "перенос: трафик через Tor" true (istor)
onionfence off -y >/dev/null
onionfence boot off >/dev/null
t_eq "перенос: после off напрямую" false (istor)

# Установка с нуля, как у нового пользователя: чистый домашний каталог, пакеты уже стоят
set -l fresh $T/fresh
mkdir -p $fresh
env HOME=$fresh sh $DIR/../../install.sh --yes >/dev/null 2>&1
t_eq "install.sh на настоящей системе" 0 $status
t_has "установленная команда работает" "служба $__onionfence_unit" (env HOME=$fresh bash -c "$fresh/.local/bin/onionfence version")
env HOME=$fresh $fresh/.local/bin/onionfence on >/dev/null
t_eq "установленная команда включает режим" 1 (sudo nft list tables | grep -c 'inet onionfence')
t_eq "… и трафик через Tor" true (istor)
env HOME=$fresh $fresh/.local/bin/onionfence uninstall -y >/dev/null
t_eq "uninstall снимает правила" 0 (sudo nft list tables | grep -c 'inet onionfence')
t_eq "uninstall убирает блок из torrc" 0 (sudo grep -c 'onionfence' $__onionfence_torrc)
t_eq "uninstall останавливает Tor" inactive (systemctl is-active $__onionfence_unit)
t_eq "после uninstall снова напрямую" false (istor)

set -l failed (grep -c '^FAIL' $T/results)
echo
test $failed -eq 0; and echo "  Системный запуск: всё в порядке"; or echo "  Системный запуск: провалено $failed"
test $failed -eq 0
