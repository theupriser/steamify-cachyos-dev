# qmpshot.py <qmp socket> <out.png>: screenshot of the VM's screen over QMP
# (screendump). Needs a VM without virgl (run.sh with VM_NOGL=1): with
# virgl QEMU answers "no surface". Before the guest's desktop is up it shows
# whatever is on screen (boot menu, Calamares, ...).
import json, os, socket, sys, tempfile

sock, out = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX); s.connect(sock); f = s.makefile("rw"); f.readline()
def cmd(c):
    f.write(json.dumps(c) + "\n"); f.flush()
    while True:
        r = json.loads(f.readline())
        if "event" not in r:
            return r
cmd({"execute": "qmp_capabilities"})
ppm = tempfile.mktemp(suffix=".ppm")
r = cmd({"execute": "screendump", "arguments": {"filename": ppm, "format": "ppm"}})
if "error" in r:
    raise SystemExit("screendump: %s" % r["error"]["desc"])
try:
    from PIL import Image
    Image.open(ppm).save(out)
    os.remove(ppm)
except ImportError:
    os.replace(ppm, os.path.splitext(out)[0] + ".ppm")
    print("PIL missing: wrote a .ppm instead", file=sys.stderr)
print(out)
