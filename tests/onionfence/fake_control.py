# Поддельный ControlPort Tor: fake_control.py PORT COOKIE_HEX [ЛОГ_КОМАНД]
# Понимает AUTHENTICATE, SIGNAL NEWNYM, GETINFO ip-to-country/… и circuit-status,
# SETCONF/RESETCONF, CLOSECIRCUIT, QUIT — как настоящий Tor.
import socket
import sys

port, cookie = int(sys.argv[1]), sys.argv[2].lower()
log = open(sys.argv[3], "a", buffering=1) if len(sys.argv) > 3 else None
srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", port))
srv.listen()
while True:
    c, _ = srv.accept()
    f = c.makefile("rwb")
    authed = False
    for line in f:
        cmd = line.decode().strip()
        if cmd.startswith("AUTHENTICATE"):
            authed = cmd.split(" ", 1)[-1].lower() == cookie
            f.write(b"250 OK\r\n" if authed else b"515 Authentication failed\r\n")
        elif not authed:
            f.write(b"514 Authentication required.\r\n")
        elif cmd == "QUIT":
            f.write(b"250 closing connection\r\n")
            f.flush()
            break
        else:
            if log:
                log.write(cmd + "\n")
            if cmd.startswith("GETINFO ip-to-country/"):
                f.write(b"250-%s=de\r\n250 OK\r\n" % cmd.split(" ", 1)[1].encode())
            elif cmd == "GETINFO circuit-status":
                f.write(b"250+circuit-status=\r\n"
                        b"5 BUILT $AAAA~a,$BBBB~b PURPOSE=GENERAL\r\n"
                        b"7 BUILT $CCCC~c PURPOSE=GENERAL\r\n"
                        b"9 CLOSED $DDDD~d PURPOSE=GENERAL\r\n"
                        b".\r\n250 OK\r\n")
            elif cmd.split(" ")[0] in ("SIGNAL", "SETCONF", "RESETCONF", "CLOSECIRCUIT"):
                f.write(b"250 OK\r\n")
            else:
                f.write(b'510 Unrecognized command "%s"\r\n' % cmd.encode())
        f.flush()
    c.close()
