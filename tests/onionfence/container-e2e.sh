#!/bin/sh
# Настоящий запуск в контейнере с systemd: тесты и e2e-system.fish на нужном дистрибутиве.
# Меняет сетевые правила контейнера, поэтому запускается только в CI.
# Использование: sh tests/onionfence/container-e2e.sh ОБРАЗ
set -eu
image=$1

case "$image" in
    archlinux* | manjarolinux*)
        install='pacman-key --init && pacman-key --populate && pacman -Syu --noconfirm --needed fish tor nftables curl jq socat iproute2 iputils procps-ng util-linux sudo systemd python less diffutils'
        ;;
    debian* | ubuntu*)
        install='apt-get update && apt-get install -y fish tor nftables curl jq socat iproute2 iputils-ping procps util-linux sudo systemd systemd-sysv python3 ca-certificates less dbus'
        ;;
    *)
        echo "неизвестный образ: $image" >&2
        exit 2
        ;;
esac

docker build -t onionfence-system - <<DOCKERFILE
FROM $image
RUN $install
RUN useradd -m tester && echo 'tester ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/tester
# Проверки файрвола во вложенном пространстве пользователя в контейнере не работают: ядро не даёт доступ
# к nftables. Без subuid тесты их пропускают, эти проверки идут на виртуальной машине Ubuntu.
RUN sed -i '/^tester:/d' /etc/subuid /etc/subgid
CMD ["/usr/lib/systemd/systemd"]
DOCKERFILE

docker run -d --name onionfence-system --privileged --cgroupns=private \
    --tmpfs /run --tmpfs /run/lock -v "$PWD:/repo:ro" onionfence-system
trap 'docker rm -f onionfence-system >/dev/null 2>&1 || true' EXIT

# ждём загрузки: degraded в контейнере нормален, часть служб там не нужна
docker exec onionfence-system sh -c 'for i in $(seq 60); do s=$(systemctl is-system-running 2>/dev/null || true); case "$s" in running|degraded) exit 0 ;; esac; sleep 1; done; exit 1'
docker exec onionfence-system sh -c 'cat /etc/os-release | head -2; fish --version; tor --version | head -1'

as_tester() {
    docker exec -u tester -w /home/tester -e HOME=/home/tester -e TERM=xterm-256color onionfence-system "$@"
}
# оба этапа идут до конца: падение первого не должно скрывать результат второго
rc=0
as_tester fish /repo/tests/onionfence/run.fish || rc=1
as_tester fish /repo/tests/onionfence/e2e-system.fish || rc=1
exit $rc
