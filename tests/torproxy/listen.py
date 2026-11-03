# Заглушки портов Tor: listen.py TRANSPORT DNSPORT
# TCP на TransPort отвечает HIT-TCP-<порт>, UDP на DNSPort — HIT-UDP-<порт>.
import socket
import sys
import threading
import time

trans, dns = int(sys.argv[1]), int(sys.argv[2])


def tcp(port):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", port))
    s.listen()
    while True:
        c, _ = s.accept()
        c.sendall(b"HIT-TCP-%d" % port)
        c.close()


def udp(port):
    s = socket.socket(type=socket.SOCK_DGRAM)
    s.bind(("127.0.0.1", port))
    while True:
        _, a = s.recvfrom(999)
        s.sendto(b"HIT-UDP-%d" % port, a)


threading.Thread(target=tcp, args=(trans,), daemon=True).start()
threading.Thread(target=udp, args=(dns,), daemon=True).start()
time.sleep(120)
