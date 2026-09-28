# qmpclick.py <qmp socket> <screen w> <screen h> <x,y>...: left-clicks at
# those guest-screen pixels (the usb-tablet from run.sh, absolute 0..32767).
import json, socket, sys, time
sock, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
s = socket.socket(socket.AF_UNIX); s.connect(sock); f = s.makefile("rw"); f.readline()
def cmd(c):
    f.write(json.dumps(c) + "\n"); f.flush(); return f.readline()
cmd({"execute": "qmp_capabilities"})
def ev(*events): cmd({"execute": "input-send-event", "arguments": {"events": list(events)}})
for pos in sys.argv[4:]:
    x, y = (int(v) for v in pos.split(","))
    ev({"type": "abs", "data": {"axis": "x", "value": x * 32767 // (w - 1)}},
       {"type": "abs", "data": {"axis": "y", "value": y * 32767 // (h - 1)}})
    time.sleep(0.2)
    ev({"type": "btn", "data": {"down": True, "button": "left"}}); time.sleep(0.08)
    ev({"type": "btn", "data": {"down": False, "button": "left"}}); time.sleep(0.8)
