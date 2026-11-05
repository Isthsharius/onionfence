# Старое имя команды: программа теперь называется onionfence.
# SPDX-License-Identifier: GPL-3.0-or-later
function torproxy --description 'Старое имя onionfence'
    echo "torproxy теперь называется onionfence, это имя скоро уберём" >&2
    onionfence $argv
end
