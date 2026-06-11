#!/usr/bin/env python3
import argparse
import os
import random
import socket
import struct
import sys


def read_exact(sock, size):
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise RuntimeError("SOCKS server closed the TCP control connection")
        data += chunk
    return data


def encode_addr(host):
    try:
        return b"\x01" + socket.inet_aton(host)
    except OSError:
        raw = host.encode("idna")
        if len(raw) > 255:
            raise ValueError("hostname is too long")
        return b"\x03" + bytes([len(raw)]) + raw


def decode_bound_addr(sock, atyp):
    if atyp == 1:
        return socket.inet_ntoa(read_exact(sock, 4))
    if atyp == 3:
        size = read_exact(sock, 1)[0]
        return read_exact(sock, size).decode("idna")
    if atyp == 4:
        return socket.inet_ntop(socket.AF_INET6, read_exact(sock, 16))
    raise RuntimeError(f"unsupported SOCKS address type: {atyp}")


def socks5_udp_associate(proxy_host, proxy_port, username, password, timeout):
    ctrl = socket.create_connection((proxy_host, proxy_port), timeout=timeout)
    ctrl.settimeout(timeout)

    if username or password:
        ctrl.sendall(b"\x05\x02\x00\x02")
        method = read_exact(ctrl, 2)
        if method != b"\x05\x02":
            raise RuntimeError(f"SOCKS username/password auth was not accepted: {method!r}")
        user = username.encode()
        passwd = password.encode()
        if len(user) > 255 or len(passwd) > 255:
            raise RuntimeError("SOCKS username/password is too long")
        ctrl.sendall(b"\x01" + bytes([len(user)]) + user + bytes([len(passwd)]) + passwd)
        auth = read_exact(ctrl, 2)
        if auth != b"\x01\x00":
            raise RuntimeError("SOCKS username/password authentication failed")
    else:
        ctrl.sendall(b"\x05\x01\x00")
        method = read_exact(ctrl, 2)
        if method != b"\x05\x00":
            raise RuntimeError(f"SOCKS no-auth was not accepted: {method!r}")

    ctrl.sendall(b"\x05\x03\x00" + encode_addr("0.0.0.0") + struct.pack("!H", 0))
    head = read_exact(ctrl, 4)
    if head[:2] != b"\x05\x00":
        raise RuntimeError(f"SOCKS UDP ASSOCIATE failed with reply={head.hex()}")

    relay_host = decode_bound_addr(ctrl, head[3])
    relay_port = struct.unpack("!H", read_exact(ctrl, 2))[0]
    if relay_host == "0.0.0.0":
        relay_host = proxy_host
    return ctrl, relay_host, relay_port


def dns_query(name):
    query_id = random.randrange(0, 65536)
    labels = b"".join(bytes([len(part)]) + part.encode("ascii") for part in name.rstrip(".").split("."))
    header = struct.pack("!HHHHHH", query_id, 0x0100, 1, 0, 0, 0)
    question = labels + b"\x00" + struct.pack("!HH", 1, 1)
    return query_id, header + question


def parse_dns_response(data, expected_id):
    if len(data) < 12:
        raise RuntimeError("short DNS response")
    query_id, flags, qdcount, ancount, _, _ = struct.unpack("!HHHHHH", data[:12])
    if query_id != expected_id:
        raise RuntimeError("DNS response id does not match query")
    if flags & 0x000F:
        raise RuntimeError(f"DNS returned rcode={flags & 0x000F}")
    return qdcount, ancount


def main():
    parser = argparse.ArgumentParser(description="Test SOCKS5 UDP ASSOCIATE with a UDP DNS query.")
    parser.add_argument("--proxy-host", required=True)
    parser.add_argument("--proxy-port", required=True, type=int)
    parser.add_argument("--username", default="")
    parser.add_argument("--password", default="")
    parser.add_argument("--dns-server", default="1.1.1.1")
    parser.add_argument("--dns-port", default=53, type=int)
    parser.add_argument("--name", default="cloudflare.com")
    parser.add_argument("--timeout", default=8, type=float)
    args = parser.parse_args()

    ctrl = None
    udp = None
    try:
        ctrl, relay_host, relay_port = socks5_udp_associate(
            args.proxy_host, args.proxy_port, args.username, args.password, args.timeout
        )
        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        udp.settimeout(args.timeout)
        query_id, payload = dns_query(args.name)
        packet = b"\x00\x00\x00" + encode_addr(args.dns_server) + struct.pack("!H", args.dns_port) + payload
        udp.sendto(packet, (relay_host, relay_port))
        response, _ = udp.recvfrom(4096)
        if len(response) < 10 or response[:3] != b"\x00\x00\x00":
            raise RuntimeError("invalid SOCKS UDP relay response header")
        atyp = response[3]
        offset = 4
        if atyp == 1:
            offset += 4
        elif atyp == 3:
            offset += 1 + response[offset]
        elif atyp == 4:
            offset += 16
        else:
            raise RuntimeError(f"invalid SOCKS UDP address type: {atyp}")
        offset += 2
        _, ancount = parse_dns_response(response[offset:], query_id)
        print(f"OK: SOCKS5 UDP works via {args.proxy_host}:{args.proxy_port}; DNS answers={ancount}")
        return 0
    except Exception as exc:
        print(f"FAIL: SOCKS5 UDP test failed: {exc}", file=sys.stderr)
        return 1
    finally:
        if udp:
            udp.close()
        if ctrl:
            ctrl.close()


if __name__ == "__main__":
    sys.exit(main())
