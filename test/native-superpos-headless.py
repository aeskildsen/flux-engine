"""Plays the SuperPos test cloud in headless native SuperSonic and records it.

The same steps as native-headless-test.py (Unix socket, per-boot secret,
/clockwork/auth), with the test buffer first: /b_alloc and /b_gen sine1, as in
superpos-synthdefs.scd. Then /d_recv, /s_new sp, 2 s of recording, /n_free.
Exits with an error if the server answers /fail, or does not answer /done for
/b_alloc, /b_gen and /d_recv.

Usage: native-superpos-headless.py <SuperSonic> <sp.scsyndef> <out.wav>
"""
import os, secrets, socket, struct, subprocess, tempfile, time, sys

# The same values as ~superposBufferFrames and ~superposPartials in
# superpos-synthdefs.scd.
BUFFER_FRAMES = 8192
PARTIALS = [1, 0.5, 0.8, 0.25, 0.6, 0.1, 0.45, 0.3, 0.05, 0.35, 0.2, 0.15]


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

# -u 0: no shared-memory segment, so that a server that runs at the same time
# does not interfere. The socket is in a folder that only this user can enter.
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
send(msg("/b_alloc", 0, BUFFER_FRAMES, 1))
send(msg("/b_gen", 0, "sine1", 5, *[float(a) for a in PARTIALS]))
send(msg("/d_recv", open(sd, "rb").read()))
send(msg("/clockwork/record/start", out))
send(msg("/s_new", "sp", 1000, 0, 0, "buf", 0))
time.sleep(2.5)
send(msg("/n_free", 1000))
time.sleep(0.2)
send(msg("/clockwork/record/stop"))
s.close()
p.terminate()
print(p.stderr.read().decode()[-1500:])

fails = [r for r in replies if r.startswith(pad(b"/fail"))]
if fails:
    sys.exit(f"FAIL: the server answered /fail: {fails[0]!r}")
for command in (b"/b_alloc", b"/b_gen", b"/d_recv"):
    if not any(r.startswith(pad(b"/done")) and pad(command) in r for r in replies):
        sys.exit(f"FAIL: no /done {command.decode()} from the server")
print("OK: /done for /b_alloc, /b_gen and /d_recv, no /fail")
