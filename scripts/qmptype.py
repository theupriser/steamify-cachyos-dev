# qmptype.py <qmp socket> <text>: types <text> (US layout) into the VM, then Enter.
import socket, json, sys, time
sock, text = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX); s.connect(sock); f = s.makefile("rw"); f.readline()
def cmd(c):
    f.write(json.dumps(c) + "\n"); f.flush(); return f.readline()
cmd({"execute": "qmp_capabilities"})
plain = {" ": "spc", "/": "slash", ".": "dot", "-": "minus", "'": "apostrophe", "\n": "ret",
         "=": "equal", ",": "comma", ";": "semicolon", "\\": "backslash", "[": "bracket_left", "]": "bracket_right"}
shifted = {"&": "7", "*": "8", "_": "minus", ":": "semicolon", "|": "backslash", "~": "grave_accent",
           "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "(": "9", ")": "0", "+": "equal", '"': "apostrophe"}
for ch in text + "\n":
    keys = []
    if ch.isalpha():
        if ch.isupper(): keys.append("shift")
        keys.append(ch.lower())
    elif ch.isdigit(): keys.append(ch)
    elif ch in plain: keys.append(plain[ch])
    elif ch in shifted: keys += ["shift", shifted[ch]]
    else: raise SystemExit("no key for %r" % ch)
    cmd({"execute": "send-key", "arguments": {"keys": [{"type": "qcode", "data": k} for k in keys]}})
    time.sleep(0.03)
