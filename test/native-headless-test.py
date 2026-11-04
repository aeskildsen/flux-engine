"""Plays the woodbar test note in headless native SuperSonic and records it.

Starts the server with --headless and a Unix socket as the command transport,
gives it a per-boot secret on stdin, and sends /clockwork/auth with the secret.
Then it sends /d_recv and /s_new, records the output with
/clockwork/record/start and stops the server. Exits with an error if the
server does not answer /done /d_recv, or answers /fail.

Usage: native-headless-test.py <SuperSonic> <wb.scsyndef> <out.wav>
"""
import os, secrets, socket, struct, subprocess, tempfile, time, sys


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

# The socket is in a directory that only this user can enter (mode 0700).
# -u 0: no shared-memory segment, so a server that runs at the same time
# (for example a SuperCollider session on port 57110) does not interfere.
tmp = tempfile.TemporaryDirectory()
path = os.path.join(tmp.name, "supersonic.sock")
secret = secrets.token_bytes(32)
p = subprocess.Popen([exe, "--headless", "-u", "0", "--uds", path],
                     stdin=subprocess.PIPE, stderr=subprocess.PIPE, stdout=subprocess.PIPE)
p.stdin.write(secret.hex().encode() + b"\n")
p.stdin.close()

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
deadline = time.monotonic() + 10
while True:
    try:
        s.connect(path)
        break
    except (FileNotFoundError, ConnectionRefusedError):
        if p.poll() is not None or time.monotonic() > deadline:
            p.kill()
            print(p.stderr.read().decode()[-1500:])
            sys.exit("FAIL: the server did not open its Unix socket")
        time.sleep(0.1)
s.settimeout(1)
replies = []
received = b""


def send(m):
    # Each packet has its length before it, as a 4-byte big-endian integer.
    global received
    s.sendall(struct.pack(">i", len(m)) + m)
    try:
        while True:
            r = s.recv(65536)
            if not r: break
            received += r
            while len(received) >= 4:
                n = struct.unpack(">i", received[:4])[0]
                if len(received) < 4 + n: break
                packet, received = received[4:4 + n], received[4 + n:]
                replies.append(packet)
                print("reply:", packet[:60])
    except socket.timeout: pass


send(msg("/clockwork/auth", secret))
send(msg("/d_recv", open(sd, "rb").read()))
send(msg("/clockwork/record/start", out))
send(msg("/s_new", "wb", 1000, 0, 0, "freq", 220.0, "gain", 0.8))
time.sleep(2)
send(msg("/n_set", 1000, "gate", 0.0))
time.sleep(0.5)
send(msg("/clockwork/record/stop"))
s.close()
p.terminate()
print(p.stderr.read().decode()[-1500:])

done_d_recv = any(r.startswith(pad(b"/done")) and pad(b"/d_recv") in r for r in replies)
fails = [r for r in replies if r.startswith(pad(b"/fail"))]
if fails:
    sys.exit(f"FAIL: the server answered /fail: {fails[0]!r}")
if not done_d_recv:
    sys.exit("FAIL: no /done /d_recv from the server")
print("OK: /done /d_recv, no /fail")
