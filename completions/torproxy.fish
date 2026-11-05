# Автодополнение для torproxy
# SPDX-License-Identifier: GPL-3.0-or-later

set -l commands on off status leaktest doctor circuit watch browser boot hide clean newip country exclude bridges log version help guide
set -l countries de nl ch se fi no is at fr us ca gb ro

complete -c torproxy -f
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a on -d 'Включить: весь трафик через Tor'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a off -d 'Выключить: обычный интернет'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a status -d 'Статус, внешний IP и страна'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a leaktest -d 'Проверка утечек'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a doctor -d 'Найти неполадку'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a circuit -d 'Схема цепочки'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a watch -d 'Живая панель'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a browser -d 'Tor Browser через системный Tor'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a boot -d 'Защита с момента загрузки'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a hide -d 'Случайный MAC, скрыть имя компьютера'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a clean -d 'Убрать метаданные из файлов'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a newip -d 'Новая цепочка Tor'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a country -d 'Страна выхода'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a exclude -d 'Не выходить через эти страны'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a bridges -d 'Мосты'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a log -d 'Журнал Tor'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a version -d 'Версия и платформа'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a help -d 'Краткий список команд'
complete -c torproxy -n "not __fish_seen_subcommand_from $commands" -a guide -d 'Руководство пользователя'

complete -c torproxy -n '__fish_seen_subcommand_from on' -l strict -d 'Закрыть и локальную сеть'
complete -c torproxy -n '__fish_seen_subcommand_from off' -s y -l yes -d 'Без вопроса'
complete -c torproxy -n '__fish_seen_subcommand_from boot' -a 'on off'
complete -c torproxy -n '__fish_seen_subcommand_from boot; and __fish_seen_subcommand_from on' -l strict -d 'Закрыть и локальную сеть'
complete -c torproxy -n '__fish_seen_subcommand_from hide' -a 'on off'
complete -c torproxy -n '__fish_seen_subcommand_from country' -a "any $countries"
complete -c torproxy -n '__fish_seen_subcommand_from exclude' -a 'off ru by cn ir'
complete -c torproxy -n '__fish_seen_subcommand_from bridges' -a auto -d 'Подобрать рабочий способ'
complete -c torproxy -n '__fish_seen_subcommand_from bridges' -a snowflake -d 'Встроенные Snowflake'
complete -c torproxy -n '__fish_seen_subcommand_from bridges' -a obfs4 -d 'Встроенные obfs4'
complete -c torproxy -n '__fish_seen_subcommand_from bridges' -a add -d 'Свои мосты'
complete -c torproxy -n '__fish_seen_subcommand_from bridges' -a off -d 'Без мостов'
complete -c torproxy -n '__fish_seen_subcommand_from bridges; and __fish_seen_subcommand_from auto' -l no-direct -d 'Не пробовать без мостов'
complete -c torproxy -n '__fish_seen_subcommand_from clean' -F
