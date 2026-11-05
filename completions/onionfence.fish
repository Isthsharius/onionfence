# Автодополнение для onionfence
# SPDX-License-Identifier: GPL-3.0-or-later

set -l commands on off status leaktest doctor circuit watch run allow browser boot hide clean newip country exclude bridges log version help guide install uninstall
set -l countries de nl ch se fi no is at fr us ca gb ro

complete -c onionfence -f
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a on -d 'Включить: весь трафик через Tor'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a off -d 'Выключить: обычный интернет'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a status -d 'Статус, внешний IP и страна'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a leaktest -d 'Проверка утечек'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a doctor -d 'Найти неполадку'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a circuit -d 'Схема цепочки'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a watch -d 'Живая панель'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a run -d 'Только эта программа через Tor'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a allow -d 'Исключения: мимо Tor'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a browser -d 'Tor Browser через системный Tor'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a boot -d 'Защита с момента загрузки'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a hide -d 'Случайный MAC, скрыть имя компьютера'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a clean -d 'Убрать метаданные из файлов'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a newip -d 'Новая цепочка Tor'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a country -d 'Страна выхода'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a exclude -d 'Не выходить через эти страны'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a bridges -d 'Мосты'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a log -d 'Журнал Tor'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a version -d 'Версия и платформа'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a help -d 'Краткий список команд'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a install -d 'Установить для текущего пользователя'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a uninstall -d 'Удалить и вернуть настройки'
complete -c onionfence -n "not __fish_seen_subcommand_from $commands" -a guide -d 'Руководство пользователя'

complete -c onionfence -n '__fish_seen_subcommand_from on' -l strict -d 'Закрыть и локальную сеть'
complete -c onionfence -n '__fish_seen_subcommand_from off' -s y -l yes -d 'Без вопроса'
complete -c onionfence -n '__fish_seen_subcommand_from boot' -a 'on off'
complete -c onionfence -n '__fish_seen_subcommand_from boot; and __fish_seen_subcommand_from on' -l strict -d 'Закрыть и локальную сеть'
complete -c onionfence -n '__fish_seen_subcommand_from hide' -a 'on off'
complete -c onionfence -n '__fish_seen_subcommand_from country' -a "any $countries"
complete -c onionfence -n '__fish_seen_subcommand_from exclude' -a 'off ru by cn ir'
complete -c onionfence -n '__fish_seen_subcommand_from bridges' -a auto -d 'Подобрать рабочий способ'
complete -c onionfence -n '__fish_seen_subcommand_from bridges' -a snowflake -d 'Встроенные Snowflake'
complete -c onionfence -n '__fish_seen_subcommand_from bridges' -a obfs4 -d 'Встроенные obfs4'
complete -c onionfence -n '__fish_seen_subcommand_from bridges' -a add -d 'Свои мосты'
complete -c onionfence -n '__fish_seen_subcommand_from bridges' -a off -d 'Без мостов'
complete -c onionfence -n '__fish_seen_subcommand_from bridges; and __fish_seen_subcommand_from auto' -l no-direct -d 'Не пробовать без мостов'
complete -c onionfence -n '__fish_seen_subcommand_from clean' -F
complete -c onionfence -n '__fish_seen_subcommand_from allow' -a 'del off'
complete -c onionfence -n '__fish_seen_subcommand_from run' -l force -d 'Запустить, даже если уже открыта'
complete -c onionfence -n '__fish_seen_subcommand_from run' -l stop -d 'Завершить запущенное так'
complete -c onionfence -n '__fish_seen_subcommand_from run' -a '(__fish_complete_subcommand --fcs-skip=2)'
complete -c onionfence -n '__fish_seen_subcommand_from uninstall' -s y -l yes -d 'Без вопроса'
