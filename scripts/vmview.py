#!/usr/bin/env python3
# vmview.py <VM dir or qmp socket> [seconds]: a window that shows a headless VM's screen, refreshed
# every 2 seconds (QMP screendump; read-only, no input). For watching an automated run without
# giving the VM a window. Needs python-pillow and tk; on WSL set the WSLg env (wsl-build-host skill).
import io, json, os, socket, sys, tempfile, tkinter as tk
from PIL import Image, ImageTk

target = sys.argv[1]
sock_path = os.path.join(target, "qmp.sock") if os.path.isdir(target) else target
every = int(float(sys.argv[2]) * 1000) if len(sys.argv) > 2 else 2000

def shot():
    s = socket.socket(socket.AF_UNIX); s.settimeout(5); s.connect(sock_path); f = s.makefile()
    f.readline(); s.sendall(b'{"execute":"qmp_capabilities"}'); f.readline()
    out = os.path.join(tempfile.gettempdir(), f"vmview-{os.getpid()}.ppm")
    s.sendall(json.dumps({"execute": "screendump", "arguments": {"filename": out}}).encode())
    reply = json.loads(f.readline()); s.close()
    if "error" in reply: raise RuntimeError(reply["error"].get("desc"))
    with open(out, "rb") as fh: img = Image.open(io.BytesIO(fh.read()))
    os.unlink(out); return img

root = tk.Tk(); root.title(f"vmview: {target}")
label = tk.Label(root, bg="black", fg="white"); label.pack(fill="both", expand=True)
def tick():
    try:
        img = shot(); w = min(img.width, 1280); img = img.resize((w, img.height * w // img.width))
        label.photo = ImageTk.PhotoImage(img); label.config(image=label.photo, text="")
    except Exception as e:
        label.config(image="", text=f"no screen: {e}", width=60, height=10)
    root.after(every, tick)
tick(); root.mainloop()
