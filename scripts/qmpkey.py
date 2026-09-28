# qmpkey.py <qmp socket> <combo>...: presses keys in the VM (QEMU qcodes), e.g. down right ctrl-ret ret esc
import socket, json, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); f = s.makefile("rw"); f.readline()
def cmd(c): f.write(json.dumps(c) + "\n"); f.flush(); return f.readline()
cmd({"execute": "qmp_capabilities"})
for combo in sys.argv[2:]:
    cmd({"execute": "send-key", "arguments": {"keys": [{"type": "qcode", "data": k} for k in combo.split("-")]}})
    time.sleep(0.4)
