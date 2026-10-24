"""Plays the woodbar test note in headless native SuperSonic and records it.

Starts the server with --headless, sends /d_recv and /s_new, records the
output with /clockwork/record/start and stops the server. Exits with an error
if the server does not answer /done /d_recv, or answers /fail.

Usage: native-headless-test.py <SuperSonic> <wb.scsyndef> <out.wav>
"""
import socket, struct, subprocess, time, sys


def pad(b): return b + b"\0" * (4 - len(b) % 4)


def msg(addr, *args):
    tags, data = ",", b""
    for a in args:
        if isinstance(a, int): tags += "i"; data += struct.pack(">i", a)
        elif isinstance(a, float): tags += "f"; data += struct.pack(">f", a)
        elif isinstance(a, bytes): tags += "b"; data += struct.pack(">i", len(a)) + a + b"\0" * (-len(a) % 4)
        else: tags += "s"; data += pad(a.encode())
    return pad(addr.encode()) + pad(tags.encode()) + data


exe, sd, out = sys.argv[1:4]
p = subprocess.Popen([exe, "--headless"], stderr=subprocess.PIPE, stdout=subprocess.PIPE)
time.sleep(3)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(1)
replies = []


def send(m):
    s.sendto(m, ("127.0.0.1", 57110))
    try:
        while True:
            r = s.recv(4096)
            replies.append(r)
            print("reply:", r[:60])
    except socket.timeout: pass


send(msg("/d_recv", open(sd, "rb").read()))
send(msg("/clockwork/record/start", out))
send(msg("/s_new", "wb", 1000, 0, 0, "freq", 220.0, "gain", 0.8))
time.sleep(2)
send(msg("/n_set", 1000, "gate", 0.0))
time.sleep(0.5)
send(msg("/clockwork/record/stop"))
p.terminate()
print(p.stderr.read().decode()[-1500:])

done_d_recv = any(r.startswith(pad(b"/done")) and pad(b"/d_recv") in r for r in replies)
fails = [r for r in replies if r.startswith(pad(b"/fail"))]
if fails:
    sys.exit(f"FAIL: the server answered /fail: {fails[0]!r}")
if not done_d_recv:
    sys.exit("FAIL: no /done /d_recv from the server")
print("OK: /done /d_recv, no /fail")
