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
            raise RuntimeError("SOCKS 服务器关闭了 TCP 控制连接")
        data += chunk
    return data


def encode_addr(host):
    try:
        return b"\x01" + socket.inet_aton(host)
    except OSError:
        raw = host.encode("idna")
        if len(raw) > 255:
            raise ValueError("主机名过长")
        return b"\x03" + bytes([len(raw)]) + raw


def decode_bound_addr(sock, atyp):
    if atyp == 1:
        return socket.inet_ntoa(read_exact(sock, 4))
    if atyp == 3:
        size = read_exact(sock, 1)[0]
        return read_exact(sock, size).decode("idna")
    if atyp == 4:
        return socket.inet_ntop(socket.AF_INET6, read_exact(sock, 16))
    raise RuntimeError(f"不支持的 SOCKS 地址类型：{atyp}")


def socks5_udp_associate(proxy_host, proxy_port, username, password, timeout):
    ctrl = socket.create_connection((proxy_host, proxy_port), timeout=timeout)
    ctrl.settimeout(timeout)

    if username or password:
        ctrl.sendall(b"\x05\x02\x00\x02")
        method = read_exact(ctrl, 2)
        if method != b"\x05\x02":
            raise RuntimeError(f"SOCKS 用户名/密码认证未被接受：{method!r}")
        user = username.encode()
        passwd = password.encode()
        if len(user) > 255 or len(passwd) > 255:
            raise RuntimeError("SOCKS 用户名或密码过长")
        ctrl.sendall(b"\x01" + bytes([len(user)]) + user + bytes([len(passwd)]) + passwd)
        auth = read_exact(ctrl, 2)
        if auth != b"\x01\x00":
            raise RuntimeError("SOCKS 用户名/密码认证失败")
    else:
        ctrl.sendall(b"\x05\x01\x00")
        method = read_exact(ctrl, 2)
        if method != b"\x05\x00":
            raise RuntimeError(f"SOCKS 无认证模式未被接受：{method!r}")

    ctrl.sendall(b"\x05\x03\x00" + encode_addr("0.0.0.0") + struct.pack("!H", 0))
    head = read_exact(ctrl, 4)
    if head[:2] != b"\x05\x00":
        raise RuntimeError(f"SOCKS UDP ASSOCIATE 失败，回复={head.hex()}")

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
        raise RuntimeError("DNS 响应过短")
    query_id, flags, qdcount, ancount, _, _ = struct.unpack("!HHHHHH", data[:12])
    if query_id != expected_id:
        raise RuntimeError("DNS 响应 ID 与请求不一致")
    if flags & 0x000F:
        raise RuntimeError(f"DNS 返回 rcode={flags & 0x000F}")
    return qdcount, ancount


def main():
    parser = argparse.ArgumentParser(description="用一次 UDP DNS 查询测试 SOCKS5 UDP ASSOCIATE 是否可用。")
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
            raise RuntimeError("SOCKS UDP 中继响应头无效")
        atyp = response[3]
        offset = 4
        if atyp == 1:
            offset += 4
        elif atyp == 3:
            offset += 1 + response[offset]
        elif atyp == 4:
            offset += 16
        else:
            raise RuntimeError(f"SOCKS UDP 地址类型无效：{atyp}")
        offset += 2
        _, ancount = parse_dns_response(response[offset:], query_id)
        print(f"正常：SOCKS5 UDP 可通过 {args.proxy_host}:{args.proxy_port} 工作；DNS 应答数={ancount}")
        return 0
    except Exception as exc:
        print(f"失败：SOCKS5 UDP 测试失败：{exc}", file=sys.stderr)
        return 1
    finally:
        if udp:
            udp.close()
        if ctrl:
            ctrl.close()


if __name__ == "__main__":
    sys.exit(main())
