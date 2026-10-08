# Fake LLM : renvoie le body reçu
from http.server import BaseHTTPRequestHandler, HTTPServer

class EchoHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        print(body.decode())
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)


HTTPServer(("0.0.0.0", 8080), EchoHandler).serve_forever()
