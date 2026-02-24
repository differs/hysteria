#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Hysteria 2 完整配置生成器
生成服务端配置、Linux/Android 客户端配置和二维码
所有安全功能启用，无需域名
"""

import os
import sys
import json
import secrets
import string
import argparse
import subprocess
import socket
from pathlib import Path
from datetime import datetime
from typing import Optional, Tuple

# 尝试导入 qrcode 库
try:
    import qrcode
    import qrcode.image.pil

    QR_AVAILABLE = True
except ImportError:
    QR_AVAILABLE = False


def generate_secure_password(length: int = 32) -> str:
    """生成安全密码"""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def get_server_ip() -> str:
    """获取服务器公网 IP"""
    try:
        # 尝试获取公网 IP
        result = subprocess.run(
            ["curl", "-s", "https://api.ipify.org"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except Exception:
        pass

    # 备用方法
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "YOUR_SERVER_IP"


def generate_openssl_config(ip: str, output_dir: str) -> Tuple[str, str]:
    """使用 OpenSSL 生成自签名证书"""
    cert_path = os.path.join(output_dir, "server.crt")
    key_path = os.path.join(output_dir, "server.key")

    print(f"📜 正在生成自签名证书 (IP: {ip})...")

    # OpenSSL 命令
    cmd = [
        "openssl",
        "req",
        "-x509",
        "-nodes",
        "-newkey",
        "ec",
        "-pkeyopt",
        "ec_paramgen_curve:prime256v1",
        "-keyout",
        key_path,
        "-out",
        cert_path,
        "-days",
        "3650",
        "-subj",
        f"/CN={ip}/O=Legitimate Company/C=US",
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise Exception(result.stderr)

        # 设置权限
        os.chmod(key_path, 0o600)
        os.chmod(cert_path, 0o644)

        # 获取证书指纹
        fp_cmd = [
            "openssl",
            "x509",
            "-in",
            cert_path,
            "-noout",
            "-sha256",
            "-fingerprint",
        ]
        fp_result = subprocess.run(fp_cmd, capture_output=True, text=True)
        fingerprint = (
            fp_result.stdout.strip().replace("sha256 Fingerprint=", "")
            if fp_result.returncode == 0
            else ""
        )

        print(f"✅ 证书生成成功")
        print(f"   证书：{cert_path}")
        print(f"   私钥：{key_path}")
        if fingerprint:
            print(f"   指纹：{fingerprint}")

        return cert_path, key_path, fingerprint
    except FileNotFoundError:
        print("⚠️  未找到 OpenSSL，将生成证书路径占位符")
        return cert_path, key_path, ""
    except Exception as e:
        print(f"⚠️  证书生成失败：{e}")
        return cert_path, key_path, ""


def generate_server_config(
    server_ip: str,
    server_port: int,
    obfs_password: str,
    auth_password: str,
    cert_path: str,
    key_path: str,
    stats_secret: str,
    output_path: str,
) -> str:
    """生成服务端配置"""

    config = f'''# ============================================
# Hysteria 2 服务端配置
# 生成时间：{datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
# 所有安全功能已启用，无需域名
# ============================================

# ==================== 监听配置 ====================
listen: :{server_port}

# ==================== Salamander 混淆 ====================
obfs:
  type: salamander
  salamander:
    password: "{obfs_password}"

# ==================== TLS 证书（自签名） ====================
tls:
  cert: {cert_path}
  key: {key_path}
  sniGuard: strict
  clientCA: ""

# ==================== QUIC 协议优化 ====================
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 8388608
  maxConnReceiveWindow: 8388608
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false

# ==================== 带宽限制 ====================
bandwidth:
  up: 100 mbps
  down: 100 mbps

# ==================== 认证配置 ====================
auth:
  type: password
  password: "{auth_password}"

# ==================== DNS 解析器 ====================
resolver:
  type: udp
  udp:
    addr: 1.1.1.1:53
    timeout: 2s

# ==================== 协议嗅探（必选） ====================
sniff:
  enable: true
  timeout: 1s
  rewriteDomain: false
  tcpPorts: "80,443,8080,8443"
  udpPorts: "443"

# ==================== ACL 访问控制（必选） ====================
acl:
  inline:
    # 阻止私有网络
    - reject(10.0.0.0/8)
    - reject(172.16.0.0/12)
    - reject(192.168.0.0/16)
    - reject(127.0.0.0/8)
    
    # 阻止常见恶意端口
    - reject(0.0.0.0/0:22)
    - reject(0.0.0.0/0:23)
    - reject(0.0.0.0/0:3389)
    - reject(0.0.0.0/0:445)
    - reject(0.0.0.0/0:135)
    - reject(0.0.0.0/0:139)
    
    # 允许常用端口
    - direct(0.0.0.0/0:80)
    - direct(0.0.0.0/0:443)
    - direct(0.0.0.0/0:8080)
    - direct(0.0.0.0/0:8443)
    
    # 默认规则
    - default(direct)

# ==================== 出站配置 ====================
outbounds:
  - name: direct
    type: direct
    direct:
      mode: auto
      fastOpen: true

# ==================== UDP 配置 ====================
disableUDP: false
udpIdleTimeout: 30s

# ==================== 伪装网站（必选） ====================
masquerade:
  type: proxy
  proxy:
    url: https://www.visa.com
    rewriteHost: true
    insecure: false
  listenHTTP: :80
  listenHTTPS: :{server_port}
  forceHTTPS: true

# ==================== 流量统计 ====================
trafficStats:
  listen: 127.0.0.1:9999
  secret: "{stats_secret}"

# ==================== 速度测试 ====================
speedTest: false
'''

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(config)

    print(f"✅ 服务端配置已生成：{output_path}")
    return config


def generate_linux_client_config(
    server_ip: str,
    server_port: int,
    obfs_password: str,
    auth_password: str,
    cert_fingerprint: str,
    output_path: str,
) -> str:
    """生成 Linux 客户端配置"""

    config = f'''# ============================================
# Hysteria 2 Linux 客户端配置
# 生成时间：{datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
# ============================================

server: {server_ip}:{server_port}

auth: "{auth_password}"

obfs:
  type: salamander
  salamander:
    password: "{obfs_password}"

tls:
  insecure: true
  # 如需固定证书指纹（更安全），取消下面注释并填入指纹：
  # insecure: false
  # pinSHA256: "{cert_fingerprint}"

bandwidth:
  up: 50 mbps
  down: 100 mbps

# SOCKS5 代理
socks5:
  listen: 127.0.0.1:1080

# HTTP 代理
http:
  listen: 127.0.0.1:8080

# 可选：TCP 端口转发
# tcpForwarding:
#   - listen: 127.0.0.1:8888
#     remote: example.com:443

# 可选：UDP 端口转发
# udpForwarding:
#   - listen: 127.0.0.1:5353
#     remote: 8.8.8.8:53
#     timeout: 30s
'''

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(config)

    print(f"✅ Linux 客户端配置已生成：{output_path}")
    return config


def generate_android_client_config(
    server_ip: str,
    server_port: int,
    obfs_password: str,
    auth_password: str,
    cert_fingerprint: str,
) -> dict:
    """生成 Android 客户端配置（JSON 格式）"""

    config = {
        "server": f"{server_ip}:{server_port}",
        "auth": auth_password,
        "obfs": {"type": "salamander", "salamander": {"password": obfs_password}},
        "tls": {
            "insecure": True
            # 如需固定证书指纹：
            # "insecure": False,
            # "pinSHA256": cert_fingerprint
        },
        "bandwidth": {"up": "50 mbps", "down": "100 mbps"},
        "socks5": {"listen": "127.0.0.1:1080"},
        "http": {"listen": "127.0.0.1:8080"},
    }

    return config


def generate_qr_code(
    server_ip: str,
    server_port: int,
    obfs_password: str,
    auth_password: str,
    output_path: str,
) -> Optional[str]:
    """生成配置二维码（Hysteria URI 格式）"""

    if not QR_AVAILABLE:
        print("⚠️  qrcode 库未安装，跳过二维码生成")
        print("   安装命令：pip install qrcode[pil]")
        return None

    # Hysteria URI 格式：hysteria2://auth@server:port?obfs=salamander&obfs-password=xxx#name
    uri = f"hysteria2://{auth_password}@{server_ip}:{server_port}"
    params = {"obfs": "salamander", "obfs-password": obfs_password, "insecure": "1"}

    param_str = "&".join(f"{k}={v}" for k, v in params.items())
    uri = f"{uri}?{param_str}"
    uri = f"{uri}#Hysteria2-Secure"

    # 生成二维码
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(uri)
    qr.make(fit=True)

    img = qr.make_image(fill_color="black", back_color="white")
    img.save(output_path)

    print(f"✅ 配置二维码已生成：{output_path}")
    print(f"   URI: {uri}")

    return uri


def generate_share_link(
    server_ip: str, server_port: int, obfs_password: str, auth_password: str
) -> str:
    """生成分享链接（文本格式）"""

    uri = f"hysteria2://{auth_password}@{server_ip}:{server_port}"
    params = {"obfs": "salamander", "obfs-password": obfs_password, "insecure": "1"}

    param_str = "&".join(f"{k}={v}" for k, v in params.items())
    uri = f"{uri}?{param_str}#Hysteria2-Secure"

    return uri


def main():
    parser = argparse.ArgumentParser(
        description="Hysteria 2 完整配置生成器 - 启用所有安全功能，无需域名",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例用法:
  python3 hysteria_config_generator.py
  python3 hysteria_config_generator.py -i 1.2.3.4 -p 443
  python3 hysteria_config_generator.py --output /etc/hysteria
        """,
    )

    parser.add_argument(
        "-i", "--ip", type=str, default="", help="服务器 IP 地址（默认自动检测）"
    )
    parser.add_argument(
        "-p", "--port", type=int, default=443, help="服务器监听端口（默认：443）"
    )
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        default="./hysteria_configs",
        help="输出目录（默认：当前目录/hysteria_configs）",
    )
    parser.add_argument("--no-qr", action="store_true", help="不生成二维码")
    parser.add_argument(
        "--no-cert",
        action="store_true",
        help="不生成自签名证书（仅生成配置路径占位符）",
    )

    args = parser.parse_args()

    # 打印欢迎信息
    print("=" * 60)
    print("  Hysteria 2 完整配置生成器")
    print("  启用所有安全功能，无需域名")
    print("=" * 60)
    print()

    # 创建输出目录
    output_dir = os.path.abspath(args.output)
    os.makedirs(output_dir, exist_ok=True)
    print(f"📁 输出目录：{output_dir}")

    # 获取服务器 IP
    server_ip = args.ip if args.ip else get_server_ip()
    print(f"🌐 服务器 IP: {server_ip}")
    print(f"🔌 服务器端口：{args.port}")
    print()

    # 生成安全密码
    obfs_password = generate_secure_password(32)
    auth_password = generate_secure_password(32)
    stats_secret = generate_secure_password(24)

    print("🔐 已生成安全密码:")
    print(f"   混淆密码：{obfs_password[:16]}...（{len(obfs_password)} 字符）")
    print(f"   认证密码：{auth_password[:16]}...（{len(auth_password)} 字符）")
    print(f"   统计密钥：{stats_secret[:16]}...（{len(stats_secret)} 字符）")
    print()

    # 生成证书
    cert_fingerprint = ""
    if not args.no_cert:
        cert_path, key_path, cert_fingerprint = generate_openssl_config(
            server_ip, output_dir
        )
    else:
        cert_path = "/path/to/server.crt"
        key_path = "/path/to/server.key"

    print()

    # 生成服务端配置
    server_config_path = os.path.join(output_dir, "server.yaml")
    generate_server_config(
        server_ip=server_ip,
        server_port=args.port,
        obfs_password=obfs_password,
        auth_password=auth_password,
        cert_path=cert_path,
        key_path=key_path,
        stats_secret=stats_secret,
        output_path=server_config_path,
    )

    # 生成 Linux 客户端配置
    linux_config_path = os.path.join(output_dir, "client_linux.yaml")
    generate_linux_client_config(
        server_ip=server_ip,
        server_port=args.port,
        obfs_password=obfs_password,
        auth_password=auth_password,
        cert_fingerprint=cert_fingerprint,
        output_path=linux_config_path,
    )

    # 生成 Android 客户端配置
    android_config = generate_android_client_config(
        server_ip=server_ip,
        server_port=args.port,
        obfs_password=obfs_password,
        auth_password=auth_password,
        cert_fingerprint=cert_fingerprint,
    )

    android_config_path = os.path.join(output_dir, "client_android.json")
    with open(android_config_path, "w", encoding="utf-8") as f:
        json.dump(android_config, f, indent=2, ensure_ascii=False)
    print(f"✅ Android 客户端配置已生成：{android_config_path}")

    # 生成二维码
    if not args.no_qr:
        qr_path = os.path.join(output_dir, "qrcode.png")
        generate_qr_code(
            server_ip=server_ip,
            server_port=args.port,
            obfs_password=obfs_password,
            auth_password=auth_password,
            output_path=qr_path,
        )

    print()

    # 生成分享链接
    share_link = generate_share_link(server_ip, args.port, obfs_password, auth_password)

    # 打印摘要
    print("=" * 60)
    print("  配置生成完成！")
    print("=" * 60)
    print()
    print("📄 生成的文件:")
    print(f"   1. 服务端配置：{os.path.join(output_dir, 'server.yaml')}")
    print(f"   2. Linux 客户端：{os.path.join(output_dir, 'client_linux.yaml')}")
    print(f"   3. Android 客户端：{os.path.join(output_dir, 'client_android.json')}")
    if not args.no_qr and QR_AVAILABLE:
        print(f"   4. 配置二维码：{os.path.join(output_dir, 'qrcode.png')}")
    print()
    print("🔗 Hysteria 分享链接:")
    print(f"   {share_link}")
    print()
    print("📱 使用方法:")
    print("   Linux:   hysteria client -c client_linux.yaml")
    print("   Android: 导入 client_android.json 到 Hysteria App")
    print("   扫码：使用 Hysteria App 扫描 qrcode.png")
    print()
    print("🚀 服务端启动命令:")
    print(f"   sudo hysteria server -c {os.path.join(output_dir, 'server.yaml')}")
    print()
    print("⚠️  重要提示:")
    print("   1. 请将配置文件保存到安全位置")
    print("   2. 建议备份密码和证书文件")
    print("   3. 服务器防火墙需开放端口：80/tcp, 443/udp, 443/tcp")
    print()


if __name__ == "__main__":
    main()
