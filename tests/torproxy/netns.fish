# Межсетевой экран в изолированном сетевом namespace (запускается из run.fish через unshare).
# Внутри: uid 0 — «root», 1000 — обычный пользователь, 43 — пользователь tor.
cd /
source $DIR/lib.fish
set -g __torproxy_torrc $T/ns.torrc
printf 'User tor\n' >$__torproxy_torrc
set -g __torproxy_timeout 3
set -gx MOCK_BOOT 5 60 100
set -gx MOCK_CHECK '{"IsTor":true,"IP":"1.2.3.4"}'

# «Интернет»: dummy-интерфейс, роутер 192.168.88.1, IPv6 по умолчанию
ip link set lo up
ip link add d0 type dummy
ip link set d0 up
ip addr add 192.168.88.50/24 dev d0
ip route add default via 192.168.88.1
ip -6 addr add 2001:db8::50/64 dev d0 nodad
ip -6 route add default via 2001:db8::1 dev d0

# Счётчик пакетов, реально ушедших в сеть (после всех фильтров)
echo '
table inet obs {
    counter out {}
    chain post { type filter hook postrouting priority 500; policy accept; oifname "d0" counter name "out"; }
}' | nft -f -

python3 -I $DIR/listen.py $__torproxy_transport $__torproxy_dnsport &
set -l listener $last_pid
sleep 0.5

# Результат: HIT-* (попал в Tor), LEFT (ушёл напрямую в сеть), BLOCKED (никуда не ушёл)
function probe --argument-names who kind host port
    nft reset counter inet obs out >/dev/null
    set -l cmd python3 -I - $kind $host $port
    switch $who
        case user
            set cmd setpriv --reuid=1000 --regid=1000 --clear-groups $cmd
        case tor
            set -l uid (id -u $__torproxy_user)
            set cmd setpriv --reuid=$uid --regid=$uid --clear-groups $cmd
    end
    set -l r ($cmd <$DIR/probe.py 2>&1)
    set -l n (nft list counter inet obs out | string match -rg 'packets (\d+)')
    if string match -q 'HIT-*' -- $r
        echo $r
    else if test "$n" -gt 0
        echo LEFT
    else
        echo BLOCKED
    end
end

function probe_ping
    nft reset counter inet obs out >/dev/null
    ping -c1 -W1 $argv[1] >/dev/null 2>&1
    test (nft list counter inet obs out | string match -rg 'packets (\d+)') -gt 0; and echo LEFT; or echo BLOCKED
end

set -l TP HIT-TCP-$__torproxy_transport
set -l DP HIT-UDP-$__torproxy_dnsport

section "Сеть без torproxy (проверка самого стенда)"
t_eq "TCP наружу уходит напрямую" LEFT (probe user tcp 1.1.1.1 443)
t_eq "UDP наружу уходит напрямую" LEFT (probe user udp 8.8.8.8 443)

section "torproxy on (настоящие правила nftables)"
__torproxy_on >$T/ns-on.out 2>&1
t_eq "on завершился успешно" 0 $status
t_eq "таблица torproxy создана" 1 (nft list tables | grep -c 'inet torproxy')
nft list table inet torproxy >$T/ns-ruleset.txt
t_lacks "нет правила established (утечка старых соединений)" established (command cat $T/ns-ruleset.txt)

section "Обычный пользователь: всё через Tor"
t_eq "TCP 1.1.1.1:443 → TransPort" $TP (probe user tcp 1.1.1.1 443)
t_eq "TCP 10.200.0.5 (адрес .onion) → TransPort" $TP (probe user tcp 10.200.0.5 80)
t_eq "DNS UDP 1.1.1.1 → DNSPort" $DP (probe user udp 1.1.1.1 53)
t_eq "DNS UDP 127.0.0.53 (resolved) → DNSPort" $DP (probe user udp 127.0.0.53 53)
t_eq "DNS UDP роутер → DNSPort" $DP (probe user udp 192.168.88.1 53)
t_eq "DNS TCP 8.8.8.8 → TransPort" $TP (probe user tcp 8.8.8.8 53)
t_eq "DNS TCP роутер → TransPort (без утечки)" $TP (probe user tcp 192.168.88.1 53)
t_eq "QUIC UDP 443 заблокирован" BLOCKED (probe user udp 8.8.8.8 443)
t_eq "NTP UDP 123 заблокирован" BLOCKED (probe user udp 8.8.8.8 123)
t_eq "IPv6 TCP заблокирован" BLOCKED (probe user tcp6 2001:db8::1 443)
t_eq "ICMP (ping) заблокирован" BLOCKED (probe_ping 1.1.1.1)
t_eq "TCP в локальную сеть — напрямую" LEFT (probe user tcp 192.168.88.1 80)
t_eq "UDP в локальную сеть — напрямую" LEFT (probe user udp 192.168.88.1 5000)
t_eq "DHCP (68→67 broadcast) проходит" LEFT (probe root dhcp 255.255.255.255 67)

section "Пользователь Tor ($__torproxy_user): напрямую, без петли"
t_eq "TCP от tor не перенаправляется" LEFT (probe tor tcp 1.1.1.1 443)
t_eq "DNS от tor не перенаправляется" LEFT (probe tor udp 1.1.1.1 53)

section "Повторный on"
__torproxy_on >/dev/null 2>&1
t_eq "повторный on: одна таблица, не дубли" 1 (nft list tables | grep -c 'inet torproxy')
t_eq "повторный on: правила те же" (command cat $T/ns-ruleset.txt | string join \n | md5sum) (nft list table inet torproxy | string join \n | md5sum)

section "torproxy off"
__torproxy_off >/dev/null 2>&1
t_eq "таблица удалена" 0 (nft list tables | grep -c 'inet torproxy')
t_eq "TCP снова напрямую" LEFT (probe user tcp 1.1.1.1 443)
t_eq "UDP снова напрямую" LEFT (probe user udp 8.8.8.8 443)
t_eq "чужие таблицы не тронуты" 1 (nft list tables | grep -c 'inet obs')

section "torproxy leaktest"
set -g __torproxy_leak_wait 1
set -l out (__torproxy_leaktest 2>&1 | nocolor)
t_eq "режим выключен → утечки найдены, код 1" 1 $pipestatus[1]
t_has "… видно, что UDP уходит" "✘ мимо Tor не выходит" $out
__torproxy_on >/dev/null 2>&1
set -l out (__torproxy_leaktest 2>&1 | nocolor)
t_eq "режим включён → код 0" 0 $pipestatus[1]
t_has "… утечек нет" "Утечек не найдено" $out
__torproxy_off -y >/dev/null 2>&1

section "torproxy on --strict"
__torproxy_on --strict >/dev/null 2>&1
t_eq "on --strict → код 0" 0 $status
t_has "статус показывает строгий режим" "ВКЛЮЧЁН (строгий)" (__torproxy_status --quick | nocolor)
t_eq "TCP наружу → TransPort" $TP (probe user tcp 1.1.1.1 443)
t_eq "TCP в локальную сеть не уходит напрямую" $TP (probe user tcp 192.168.88.1 80)
t_eq "UDP в локальную сеть заблокирован" BLOCKED (probe user udp 192.168.88.1 5000)
t_eq "DNS → DNSPort" $DP (probe user udp 192.168.88.1 53)
t_eq "DHCP проходит" LEFT (probe root dhcp 255.255.255.255 67)
t_eq "ICMP заблокирован" BLOCKED (probe_ping 192.168.88.1)
t_eq "трафик Tor идёт напрямую" LEFT (probe tor tcp 1.1.1.1 443)
__torproxy_bridges off >/dev/null 2>&1
t_has "смена мостов не снимает строгий режим" "ВКЛЮЧЁН (строгий)" (__torproxy_status --quick | nocolor)
t_eq "… и локальная сеть по-прежнему закрыта" BLOCKED (probe user udp 192.168.88.1 5000)
__torproxy_on >/dev/null 2>&1
t_eq "обычный on снова открывает локальную сеть" LEFT (probe user udp 192.168.88.1 5000)
__torproxy_off -y >/dev/null 2>&1

section "torproxy allow"
torproxy allow 192.0.2.50 >/dev/null 2>&1
__torproxy_on --strict >/dev/null 2>&1
t_eq "исключённый адрес идёт напрямую" LEFT (probe user udp 192.0.2.50 5000)
t_eq "TCP к нему тоже мимо TransPort" 1 (test (probe user tcp 192.0.2.50 80) != $TP; and echo 1; or echo 0)
t_eq "соседний адрес по-прежнему через Tor" $TP (probe user tcp 192.0.2.51 80)
t_eq "DNS к исключённому адресу всё равно через Tor" $DP (probe user udp 192.0.2.50 53)
torproxy allow off >/dev/null 2>&1
t_eq "снято на лету: снова через Tor" $TP (probe user tcp 192.0.2.50 80)
__torproxy_off -y >/dev/null 2>&1

section "torproxy run: файрвол отдельного пространства"
# Вложенное пространство вместо ip netns (тому нужен настоящий root): правила и маршруты те же
unshare -n sleep 60 &
set -g child $last_pid
sleep 0.3
ip link add $__torproxy_ns_host type veth peer name $__torproxy_ns_peer
ip link set $__torproxy_ns_peer netns $child
sysctl -qw net.ipv4.conf.$__torproxy_ns_host.route_localnet=1
sysctl -qw net.ipv4.conf.$__torproxy_ns_host.rp_filter=0
ip addr add $__torproxy_ns_host_ip/30 dev $__torproxy_ns_host
ip link set $__torproxy_ns_host up
function inner
    nsenter -t $child -n $argv
end
inner ip link set lo up
inner ip addr add $__torproxy_ns_peer_ip/30 dev $__torproxy_ns_peer
inner ip link set $__torproxy_ns_peer up
inner ip route add default via $__torproxy_ns_host_ip
__torproxy_run_rules | nft -f -
t_eq "правила приняты" 0 $status
function iprobe
    inner python3 -I $DIR/probe.py $argv
end
# только адреса из проверок: общий счётчик ловит и посторонний фон интерфейса
nft add counter inet obs leak
nft add rule inet obs post ip daddr '{ 1.1.1.1, 192.0.2.1, 192.168.88.1 }' counter name leak
t_eq "программа: TCP наружу → TransPort" $TP (iprobe tcp 1.1.1.1 443)
t_eq "программа: DNS → DNSPort" $DP (iprobe udp 192.0.2.1 53)
t_eq "программа: UDP наружу отброшен" TIMEOUT (iprobe udp 1.1.1.1 443)
t_eq "программа: UDP в локальную сеть отброшен" TIMEOUT (iprobe udp 192.168.88.1 5000)
t_eq "программа: ничего не ушло в сеть напрямую" 0 (nft list counter inet obs leak | string match -rg 'packets (\d+)')
t_eq "хост при этом работает как обычно" LEFT (probe user udp 1.1.1.1 443)
nft delete table inet torproxy_run
ip link del $__torproxy_ns_host
kill $child 2>/dev/null

section "Правила защиты при загрузке"
set -g __torproxy_etc $T/ns-etc
set -g __torproxy_systemd_dir $T/ns-sd
mkdir -p $T/ns-sd
__torproxy_boot on >/dev/null 2>&1
t_eq "boot on: настоящий nft проверил правила" 0 $status
nft -f $T/ns-etc/rules.nft
t_eq "файл правил применяется" 0 $status
t_eq "из файла: TCP наружу → TransPort" $TP (probe user tcp 1.1.1.1 443)
t_eq "из файла: UDP заблокирован" BLOCKED (probe user udp 8.8.8.8 443)
nft delete table inet torproxy
__torproxy_boot on --strict >/dev/null 2>&1
nft -f $T/ns-etc/rules.nft
t_eq "boot on --strict: локальная сеть закрыта" BLOCKED (probe user udp 192.168.88.1 5000)
nft delete table inet torproxy
__torproxy_boot off >/dev/null 2>&1

section "Tor не подключился за отведённое время"
set -gx MOCK_BOOT 5 50
__torproxy_on >$T/ns-timeout.out 2>&1
t_eq "on вернул ошибку" 1 $status
t_eq "правила НЕ применены (интернет не пропал)" 0 (nft list tables | grep -c 'inet torproxy')
t_eq "TCP по-прежнему работает" LEFT (probe user tcp 1.1.1.1 443)
t_eq "Tor остановлен" stop (tail -1 $T/calls.log | string match -rg 'systemctl (stop) tor')

kill $listener
