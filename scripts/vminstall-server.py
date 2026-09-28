# vminstall-server.py <dir> <port>: serves <dir> to the installing VM (the
# guest reaches the host as 10.0.2.2) and stores what it PUTs there (the
# install log, the final status). Only on 127.0.0.1. Used by vminstall.sh.
import http.server, os, sys

root, port = sys.argv[1], int(sys.argv[2])
os.chdir(root)


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_PUT(self):
        name = os.path.basename(self.path)
        if not name:
            self.send_error(400)
            return
        data = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        with open(name, "wb") as f:
            f.write(data)
        self.send_response(204)
        self.end_headers()

    def log_message(self, fmt, *args):
        # requests.log: shows the live system reached the host, and when.
        with open("requests.log", "a") as f:
            f.write("%s %s\n" % (self.log_date_time_string(), fmt % args))


http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
