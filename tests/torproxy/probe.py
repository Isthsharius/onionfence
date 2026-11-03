# Пробный пакет: probe.py tcp|tcp6|udp|dhcp HOST PORT
# Печатает ответ слушателя (HIT-...), BLOCKED (EPERM), TIMEOUT или REFUSED.
import socket
import sys

kind, host, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
fam = socket.AF_INET6 if kind == "tcp6" else socket.AF_INET
try:
    if kind in ("tcp", "tcp6"):
        s = socket.socket(fam, socket.SOCK_STREAM)
        s.settimeout(1)
        s.connect((host, port))
        print(s.recv(99).decode() or "CONNECTED")
    else:
        s = socket.socket(fam, socket.SOCK_DGRAM)
        s.settimeout(1)
        if kind == "dhcp":
            s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            s.bind(("0.0.0.0", 68))
        s.sendto(b"x", (host, port))
        print(s.recv(99).decode())
except PermissionError:
    print("BLOCKED")
except (socket.timeout, TimeoutError):
    print("TIMEOUT")
except ConnectionRefusedError:
    print("REFUSED")
