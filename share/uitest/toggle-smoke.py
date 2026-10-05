import sys, os, importlib.machinery, importlib.util, json
os.environ["QT_QPA_PLATFORM"] = "offscreen"
sys.argv = ["steamify-ui"]
loader = importlib.machinery.SourceFileLoader("ui", sys.argv[0] if False else os.environ["UI"])
spec = importlib.util.spec_from_loader("ui", loader); ui = importlib.util.module_from_spec(spec); loader.exec_module(ui)
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtCore import QTimer, QObject, QMetaObject, Q_ARG, Qt
app = QGuiApplication(sys.argv)
backend = ui.Backend(ui.find_script()); pad = ui.Gamepad(); engine = QQmlApplicationEngine()
engine.setInitialProperties({"backend": backend, "gamepad": pad, "fullscreen": False, "fromSteam": False, "iconUrl": ""})
engine.load(os.path.join(ui.HERE, "qml", "Main.qml"))
assert engine.rootObjects(), "QML did not load"
root = engine.rootObjects()[0]; backend.refresh()
def find_state():
    for o in root.findChildren(QObject):
        if o.property("want") is not None and o.property("resolution") is not None: return o
state = None
def step():
    global state
    state = find_state(); assert state, "no AppState"
    def want(): return {k for k, v in state.property("want").toVariant().items() if v} if hasattr(state.property("want"),"toVariant") else {k for k,v in state.property("want").items() if v}
    def toggle(i): QMetaObject.invokeMethod(state, "toggle", Qt.DirectConnection, Q_ARG("QVariant", i))
    def vis(): 
        r = state.property("resolution"); r = r.toVariant() if hasattr(r,"toVariant") else r
        return set(r["visible"])
    def plan():
        r = state.property("resolution"); r = r.toVariant() if hasattr(r,"toVariant") else r
        return [(p["id"], p["action"]) for p in r["plan"]]
    print("start want", want(), "plan", plan(), "canApply", state.property("canApply"))
    assert want() == {"theme"}
    toggle("single"); print("after single", want(), plan())
    assert want() == {"theme", "single", "gaming"} and plan() == [("gaming","on"),("single","on")]
    assert "silent" in vis() and "poweroff" not in vis()
    toggle("machine"); print("after machine", want(), vis())
    assert "poweroff" in want() and "poweroff" in vis()
    toggle("gaming"); print("after gaming off", want())
    assert want() == {"theme", "machine", "poweroff"}
    assert state.property("canApply") is True
    print("UI OK"); app.quit()
QTimer.singleShot(4000, step)
sys.exit(app.exec())
