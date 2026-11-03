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
    set -l r (curl -s --max-time 60 https://check.torproject.org/api/ip | jq -r '.IsTor' 2>/dev/null)
    # не «.IsTor // …»: jq считает false пустым и подставил бы запасное значение
    test -n "$r"; and echo $r; or echo "нет ответа"
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

torproxy newip
t_eq "newip → код 0" 0 $status
torproxy country de
set -l out (torproxy status)
t_has "country de → выход в Германии" " DE" (string match '*Внешний IP*' -- $out)
torproxy country any >/dev/null

torproxy off
t_eq "off: таблица удалена" 0 (sudo nft list tables | grep -c 'inet torproxy')
t_eq "off: снова напрямую" false (istor)

set -l failed (grep -c '^FAIL' $T/results)
echo
test $failed -eq 0; and echo "  Системный запуск: всё в порядке"; or echo "  Системный запуск: провалено $failed"
test $failed -eq 0
