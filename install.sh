#!/bin/sh
# Установка torproxy: нужные программы, затем сам скрипт в домашний каталог.
# Использование: sh install.sh [--yes] [--no-deps]
# SPDX-License-Identifier: GPL-3.0-or-later
set -u

assume_yes=0
deps=1
for arg in "$@"; do
    case "$arg" in
        --yes | -y) assume_yes=1 ;;
        --no-deps) deps=0 ;;
        *)
            echo "Использование: sh install.sh [--yes] [--no-deps]" >&2
            exit 2
            ;;
    esac
done

if [ "$(id -u)" = 0 ]; then
    echo "Запустите без sudo: программа ставится вашему пользователю, пароль спросят, когда он понадобится." >&2
    exit 1
fi

here=$(cd -- "$(dirname -- "$0")" && pwd)
if [ ! -r "$here/functions/torproxy.fish" ]; then
    echo "Не найден functions/torproxy.fish рядом с install.sh. Запустите установщик из папки программы." >&2
    exit 1
fi

if [ "$deps" = 1 ]; then
    if command -v pacman >/dev/null 2>&1; then
        install_cmd="sudo pacman -S --needed fish tor nftables curl jq socat iproute2 util-linux fzf"
    elif command -v apt-get >/dev/null 2>&1; then
        install_cmd="sudo apt-get install -y fish tor nftables curl jq socat iproute2 util-linux fzf"
    else
        echo "Эта система не поддерживается: нужны Arch, Debian, Ubuntu или их производные." >&2
        echo "Подробности: INSTALL.md" >&2
        exit 1
    fi

    echo "Нужные программы будут установлены командой:"
    echo "  $install_cmd"
    if [ "$assume_yes" = 0 ]; then
        printf "Продолжить? [y/N] "
        read -r answer || answer=
        case "$answer" in
            y* | Y* | д* | Д*) ;;
            *)
                echo "Отменено. Установить вручную: INSTALL.md" >&2
                exit 1
                ;;
        esac
    fi
    if ! $install_cmd; then
        echo "Не удалось установить программы." >&2
        exit 1
    fi
fi

if ! command -v fish >/dev/null 2>&1; then
    echo "Нет fish: установите его и запустите установщик снова." >&2
    exit 1
fi

exec fish --no-config -c 'source $argv[1]; torproxy install' "$here/functions/torproxy.fish"
