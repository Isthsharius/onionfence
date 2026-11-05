# torproxy

[![tests](https://github.com/Isthsharius/torproxy/actions/workflows/tests.yml/badge.svg)](https://github.com/Isthsharius/torproxy/actions/workflows/tests.yml)

Весь трафик компьютера на Linux через Tor одной командой. Функция для оболочки [fish](https://fishshell.com/): правила nftables перенаправляют TCP и DNS в Tor, а всё, что не может идти через Tor (UDP, ICMP, IPv6), блокируется, чтобы ничего не ушло мимо.

```fish
torproxy on       # включить
torproxy status   # проверить: «Через Tor ✔ да», внешний IP и страна
torproxy off      # выключить, обычный интернет
```

> **Это не анонимность.** torproxy прячет ваш IP-адрес и закрывает часть технических утечек, но не защитит от входа в свои аккаунты, манеры письма или заражённого компьютера. Подробнее — в разделе [Анонимность](#анонимность). Если ошибка может дорого стоить, используйте [Tails](https://tails.net/) или [Whonix](https://www.whonix.org/).

## Поддерживаемые системы

| Система | Как проверено |
|---|---|
| Arch Linux, CachyOS | вручную автором и тестами |
| Ubuntu 24.04 | автоматически при каждом изменении: тесты и настоящий запуск с sudo, systemd и nftables |
| Debian 13 | автоматически: тесты и проверка конфигурации Tor |

Различия дистрибутивов torproxy определяет сам: в Debian и Ubuntu служба называется `tor@default`, а пользователь — `debian-tor`. Команда `torproxy version` показывает, что определилось.

## Установка

**Arch Linux, CachyOS:**

```fish
sudo pacman -S fish tor nftables curl jq socat fzf
paru -S lyrebird-proxy                           # по желанию: мосты
sudo pacman -S torbrowser-launcher mat2          # по желанию: Tor Browser и очистка метаданных
git clone https://github.com/Isthsharius/torproxy.git
mkdir -p ~/.config/fish/functions
cp torproxy/functions/torproxy.fish ~/.config/fish/functions/
```

**Debian, Ubuntu:**

```fish
sudo apt install fish tor nftables curl jq socat fzf
sudo apt install obfs4proxy snowflake-client     # по желанию: мосты
sudo apt install torbrowser-launcher mat2        # по желанию: Tor Browser и очистка метаданных
git clone https://github.com/Isthsharius/torproxy.git
mkdir -p ~/.config/fish/functions
cp torproxy/functions/torproxy.fish ~/.config/fish/functions/
```

Откройте новый терминал, и команда `torproxy` станет доступна. Пароль sudo понадобится при каждом включении и выключении.

| Пакет | Зачем |
|---|---|
| `fish`, `tor`, `nftables`, `sudo`, systemd | основа |
| `curl`, `jq` | проверка IP в `status` |
| `socat` | `newip` и смена страны через ControlPort |
| `fzf` | меню со стрелками (без него будет нумерованный список) |
| `lyrebird-proxy` (Arch) или `obfs4proxy` + `snowflake-client` (Debian/Ubuntu) | только для мостов |
| `torbrowser-launcher` | только для `torproxy browser` |
| `mat2` | только для `torproxy clean` |
| NetworkManager | только для `torproxy hide` |

## Команды

| Команда | Что делает |
|---|---|
| `torproxy` | интерактивное меню |
| `torproxy on` / `off` | включить / выключить; `on --strict` — без доступа к локальной сети, `off -y` — без вопроса |
| `torproxy leaktest` | проверка утечек: IP, DNS, UDP, IPv6, ICMP |
| `torproxy browser` | Tor Browser через системный Tor |
| `torproxy boot on` / `off` | защита с момента загрузки системы; `boot on --strict` — в строгом режиме |
| `torproxy hide on` / `off` | случайный MAC и скрытие имени компьютера в локальной сети |
| `torproxy clean файл` | убрать метаданные: рядом появится `файл.cleaned.расширение` |
| `torproxy status` | режим, внешний IP, страна, проверка через check.torproject.org |
| `torproxy newip` | новая цепочка Tor, то есть новый IP (Tor делает это не чаще раза в 10 секунд) |
| `torproxy country de` | выход через выбранную страну, `any` — любая |
| `torproxy bridges snowflake` | мосты для сетей, где Tor заблокирован; также `obfs4`, `add` (свои), `off` |
| `torproxy log` | журнал Tor в реальном времени |
| `torproxy version` | версия и определившаяся платформа |
| `torproxy help` | справка |

**Свои мосты** обычно работают лучше встроенных. Получить их можно у бота [@GetBridgesBot](https://t.me/GetBridgesBot) в Telegram или на [bridges.torproject.org](https://bridges.torproject.org/), затем добавить командой `torproxy bridges add`. В Debian и Ubuntu поддерживаются мосты obfs4 и snowflake, а webtunnel нет: для него в стабильных версиях нет пакета.

## Анонимность

Скрипт закрывает технические утечки. Анонимность зависит и от остального: чаще всего человека выдают браузер, аккаунты и поведение.

| Угроза | Что делать |
|---|---|
| Сайт узнаёт браузер по отпечатку и кукам | `torproxy browser`. Обычный браузер в Tor-режиме по-прежнему узнаваем |
| Программы выходят в сеть напрямую сразу после загрузки | `torproxy boot on` |
| Программа продолжает сессию с настоящего IP после выключения | `torproxy off` перечисляет такие программы: закройте их до выключения |
| Роутер и владелец Wi-Fi узнают устройство | `torproxy hide on`: случайный MAC, имя компьютера не передаётся по DHCP, mDNS и LLMNR |
| Программы и страницы обращаются к устройствам в локальной сети | `torproxy on --strict` |
| В файлах остаются GPS, автор и модель камеры | `torproxy clean файл` |
| Провайдер видит, что вы используете Tor | мосты (`torproxy bridges`) |

**Что скрипт не решит:** вход в свои аккаунты сразу раскрывает, кто вы; остаются манера письма и время активности; вредоносная программа на компьютере может узнать, кто вы, и в Tor-режиме.

**Не запускайте Tor Browser сам по себе в Tor-режиме:** его трафик пойдёт через Tor дважды. Команда `torproxy browser` подключает его к системному Tor.

**Защита при загрузке:** если Tor при старте не подключится, интернета не будет, пока вы не выполните `torproxy off`. Синхронизация времени (NTP) заблокирована, а при сильно неверных часах Tor не подключается.

**`torproxy hide`** меняет профиль NetworkManager, сеть при этом переподключается. MAC-адрес виден только в локальной сети, сайты и провайдер за роутером его не видят. Сети с привязкой по MAC могут вас не пустить, тогда верните настройки командой `torproxy hide off`.

## Как это работает

1. В `/etc/tor/torrc` дописывается блок между маркерами `# --- torproxy transparent ---` и `# --- torproxy end ---`: TransPort 9040, DNSPort 9053, ControlPort 9051. Перед первой записью создаётся копия `torrc.bak-torproxy`.
2. Запускается Tor. Скрипт ждёт, пока Tor подключится. Если не подключился, правила не применяются и интернет не пропадает.
3. Создаётся отдельная таблица nftables `inet torproxy`:
   - весь TCP перенаправляется в TransPort, DNS — в DNSPort;
   - трафик самого Tor и локальной сети (192.168.x, 10.x, 172.16–31.x) идёт напрямую, DHCP работает;
   - остальное (UDP, ICMP, IPv6) блокируется.
4. `torproxy off` удаляет эту таблицу и останавливает Tor. Другие правила файрвола (например, ufw) не затрагиваются.

## Ограничения

- После включения перезапустите браузер и программы, открытые до этого: их старые соединения обрываются.
- В Tor-режиме не работают UDP-сервисы: игры, звонки, QUIC, VPN, синхронизация времени (NTP).
- Трафик Docker и виртуальных машин не перехватывается, только трафик самого компьютера.
- После перезагрузки режим выключен, если не включена защита при загрузке (`torproxy boot on`).
- Встроенные мосты Snowflake подключаются в живом тесте, но работают медленно. Встроенные obfs4 тоже подключились при ручной проверке; свои мосты от @GetBridgesBot обычно работают лучше встроенных.

## Тесты

```fish
fish tests/torproxy/run.fish            # все тесты, около минуты
fish tests/torproxy/run.fish --offline  # без запуска настоящего Tor
```

Тесты не трогают системный Tor, torrc и сеть:

- **модульные тесты с заглушками:** torrc, страны, мосты, статус, меню, браузер, загрузка, скрытие, метаданные, обработка ошибок;
- **межсетевой экран:** настоящие правила nftables в изолированном сетевом namespace, без root, включая строгий режим и `leaktest`;
- **живой Tor:** отдельный процесс на портах 19xxx, проверка через check.torproject.org;
- если установлен `lyrebird`, проверяется ещё и подключение через Snowflake.

## Как написан

Код написан вместе с ИИ (Claude) и покрыт тестами выше. Вручную автором проверены основные команды; функции из раздела «Анонимность» проверены тестами, но ещё не вживую на его машине. Независимого аудита безопасности не было. Если найдёте проблему, откройте issue.

## Лицензия

[GNU GPL v3](LICENSE) или любая более поздняя версия. Изменённые версии, которые распространяются дальше, тоже должны оставаться открытыми под GPL. Программа поставляется без каких-либо гарантий.
