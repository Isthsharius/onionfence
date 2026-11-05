#!/usr/bin/env python3
"""Запускает панель onionfence в настоящем псевдотерминале и нажимает клавиши."""
import os, pty, select, sys, time

child, src, scenario = sys.argv[1:4]
keys = {"q": [b"q"], "ctrl-c": [b"\x03"], "n-then-q": [b"n", b"q"],
        "guide": [b"q"], "live": [b"q"]}[scenario]

pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.execvp("fish", ["fish", "--no-config", child, src, scenario])


def drain(seconds):
    data = b""
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                return data, True
            if not chunk:
                return data, True
            data += chunk
    return data, False


out, _ = drain(14 if scenario == "live" else 3)
for key in keys:
    os.write(fd, key)
    more, closed = drain(2.5)
    out += more
    if closed:
        break
more, _ = drain(5)
out += more
os.kill(pid, 9) if os.waitpid(pid, os.WNOHANG) == (0, 0) else None
text = out.decode("utf-8", "replace")
if "\x1b[?1049h" in text:
    print("SCREEN_ON")
if "\x1b[?25h\x1b[?1049l" in text:
    print("SCREEN_OFF")
print(text.replace("\x1b", "^["))
