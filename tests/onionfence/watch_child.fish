# Запускается в псевдотерминале из watch_pty.py: панель на заглушках и проверка stty.
source $argv[1]
function sudo
    test "$argv[1]" = -n; and set -e argv[1]
    switch "$argv[1]"
        case -v true
            return 0
        case od
            echo 00 11
        case nft
            echo 'table inet onionfence {}'
    end
end
function systemctl
    return 0
end
if test "$argv[2]" = guide
    set -l before (stty -g)
    onionfence guide
    test "$before" = "$(stty -g)"; and echo STTY_OK; or echo STTY_CHANGED
    exit
end
if test "$argv[2]" = live
    # настоящие ControlPort и сайт проверки, заглушены только sudo и systemctl
    set -g __onionfence_ctlport $TP_CTL
    set -g __onionfence_cookie $TP_COOKIE
    functions -e sudo
    function sudo
        test "$argv[1]" = -n; and set -e argv[1]
        switch "$argv[1]"
            case -v true
                return 0
            case nft
                return 1
            case '*'
                $argv
        end
    end
else
    function __onionfence_watch_ip_start
        set -g __onionfence_w_ip 1.2.3.4
        set -g __onionfence_w_istor true
        set -g __onionfence_w_ip_next (math (date +%s) + 300)
    end
    function __onionfence_newip
        echo NEWNYM_SENT >>$argv[1]
        printf 'NEWNYM_SENT\n' >/dev/tty
    end
    function __onionfence_control
        for c in $argv
            switch $c
                case 'GETINFO traffic/read'
                    echo "250-traffic/read="(date +%s)
                case 'GETINFO traffic/written'
                    echo '250-traffic/written=1000'
                case 'GETINFO uptime'
                    echo '250-uptime=5'
                case 'GETINFO circuit-status'
                    echo '250-circuit-status=5 BUILT $AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA~a PURPOSE=GENERAL'
            end
        end
    end
end
set -l before (stty -g)
__onionfence_watch
set -l rc $status
test "$before" = "$(stty -g)"; and echo STTY_OK; or echo STTY_CHANGED
exit $rc
