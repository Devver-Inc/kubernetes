"""Application locale derrière le tunnel de test (127.0.0.1:18010).

Le client OpenTunnel lui envoie un en-tête PROXY v2 (route --proxy-protocol v2)
avec l'adresse du visiteur ; la page renvoie cette adresse.
"""
import ipaddress
import socket
import struct
import threading

SIG = b"\r\n\r\n\x00\r\nQUIT\n"


def visitor(conn):
    head = conn.recv(16)
    if head[:12] != SIG:
        return "sans-en-tete-proxy"
    length = struct.unpack("!H", head[14:16])[0]
    body = b""
    while len(body) < length:
        body += conn.recv(length - len(body))
    family = head[13] >> 4
    if family == 1:
        return str(ipaddress.ip_address(body[0:4]))
    if family == 2:
        return str(ipaddress.ip_address(body[0:16]))
    return "inconnue"


def handle(conn):
    with conn:
        ip = visitor(conn)
        conn.settimeout(2)
        try:
            conn.recv(65536)
        except OSError:
            pass
        page = f"devver-share-test visiteur={ip}\n".encode()
        conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n"
                     b"Content-Length: %d\r\n\r\n" % len(page) + page)


server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", 18010))
server.listen()
while True:
    threading.Thread(target=handle, args=(server.accept()[0],), daemon=True).start()
