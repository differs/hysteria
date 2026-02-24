#!/bin/bash
# ============================================
# Hysteria 2 服务端安装脚本
# 自动配置 systemd 自启动
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：此脚本需要 root 权限运行${NC}"
        echo "请使用 sudo 运行此脚本"
        exit 1
    fi
}

# 检测系统架构
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            HYSTERIA_ARCH="linux-amd64"
            ;;
        aarch64)
            HYSTERIA_ARCH="linux-arm64"
            ;;
        armv7l)
            HYSTERIA_ARCH="linux-armv7"
            ;;
        *)
            echo -e "${RED}不支持的架构：$ARCH${NC}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}检测到架构：$ARCH${NC}"
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}正在安装依赖...${NC}"
    
    if command -v apt &> /dev/null; then
        apt update
        apt install -y curl wget openssl ufw
    elif command -v yum &> /dev/null; then
        yum install -y curl wget openssl firewalld
    elif command -v dnf &> /dev/null; then
        dnf install -y curl wget openssl firewalld
    elif command -v pacman &> /dev/null; then
        pacman -Sy --noconfirm curl wget openssl iptables
    else
        echo -e "${RED}未检测到支持的包管理器${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}依赖安装完成${NC}"
}

# 下载并安装 Hysteria
install_hysteria() {
    echo -e "${YELLOW}正在下载 Hysteria...${NC}"
    
    # 获取最新版本
    LATEST_VERSION=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    LATEST_VERSION=${LATEST_VERSION#v}
    
    DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/v${LATEST_VERSION}/hysteria-${HYSTERIA_ARCH}"
    
    echo "下载版本：v${LATEST_VERSION}"
    echo "下载地址：${DOWNLOAD_URL}"
    
    # 下载
    curl -L -o /tmp/hysteria "${DOWNLOAD_URL}"
    
    if [[ ! -f /tmp/hysteria ]]; then
        echo -e "${RED}下载失败${NC}"
        exit 1
    fi
    
    # 安装
    chmod +x /tmp/hysteria
    mv /tmp/hysteria /usr/local/bin/hysteria
    
    # 验证
    if hysteria version &> /dev/null; then
        echo -e "${GREEN}Hysteria 安装成功 (v${LATEST_VERSION})${NC}"
    else
        echo -e "${RED}Hysteria 安装失败${NC}"
        exit 1
    fi
}

# 创建目录和配置文件
setup_config() {
    echo -e "${YELLOW}正在配置 Hysteria...${NC}"
    
    # 创建目录
    mkdir -p /etc/hysteria
    mkdir -p /var/log/hysteria
    
    # 生成证书（带 SANs）
    echo "生成自签名证书（带 SANs）..."
    cd /etc/hysteria
    
    # 创建 OpenSSL 配置文件（带 SANs）
    cat > /tmp/openssl_san.cnf << 'OPENEOL'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
CN = Hysteria Server
O = Legitimate Company
C = US

[v3_ca]
subjectAltName = @alt_names
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = localhost
IP.1 = 127.0.0.1
OPENEOL
    
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout server.key \
        -out server.crt \
        -days 3650 \
        -config /tmp/openssl_san.cnf
    
    chmod 600 server.key
    chmod 644 server.crt
    rm -f /tmp/openssl_san.cnf
    
    echo -e "${GREEN}证书生成完成${NC}"
    echo "  证书：/etc/hysteria/server.crt"
    echo "  私钥：/etc/hysteria/server.key"
    
    # 获取证书指纹
    FINGERPRINT=$(openssl x509 -in server.crt -noout -sha256 -fingerprint | cut -d'=' -f2)
    echo "  指纹：${FINGERPRINT}"
}

# 生成随机密码
generate_password() {
    local length=$1
    cat /dev/urandom | tr -dc 'a-zA-Z0-9!@#$%^&*' | fold -w ${length} | head -n 1
}

# 创建配置文件
create_config_file() {
    echo -e "${YELLOW}正在创建配置文件...${NC}"
    
    # 生成密码
    OBFS_PASSWORD=$(generate_password 32)
    AUTH_PASSWORD=$(generate_password 32)
    STATS_SECRET=$(generate_password 24)
    
    # 创建配置文件
    cat > /etc/hysteria/config.yaml << EOF
# ============================================
# Hysteria 2 服务端配置
# 生成时间：$(date '+%Y-%m-%d %H:%M:%S')
# ============================================

listen: :443

obfs:
  type: salamander
  salamander:
    password: "${OBFS_PASSWORD}"

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
  sniGuard: strict
  clientCA: ""

quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 8388608
  maxConnReceiveWindow: 8388608
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false

bandwidth:
  up: 100 mbps
  down: 100 mbps

auth:
  type: password
  password: "${AUTH_PASSWORD}"

resolver:
  type: udp
  udp:
    addr: 1.1.1.1:53
    timeout: 2s

sniff:
  enable: true
  timeout: 1s
  rewriteDomain: false
  tcpPorts: "80,443,8080,8443"
  udpPorts: "443"

acl:
  inline:
    - reject(10.0.0.0/8)
    - reject(172.16.0.0/12)
    - reject(192.168.0.0/16)
    - reject(127.0.0.0/8)
    - reject(all, tcp/22)
    - reject(all, tcp/23)
    - reject(all, tcp/3389)
    - reject(all, tcp/445)
    - direct(all, tcp/80)
    - direct(all, tcp/443)
    - default(direct)

outbounds:
  - name: direct
    type: direct
    direct:
      mode: auto
      fastOpen: true

disableUDP: false
udpIdleTimeout: 30s

masquerade:
  type: proxy
  proxy:
    url: https://www.visa.com
    rewriteHost: true
    insecure: false
  listenHTTP: :80
  listenHTTPS: :443
  forceHTTPS: true

trafficStats:
  listen: 127.0.0.1:9999
  secret: "${STATS_SECRET}"

speedTest: false
EOF

    chmod 600 /etc/hysteria/config.yaml
    
    # 保存密码到文件
    cat > /etc/hysteria/credentials.txt << EOF
# Hysteria 2 认证信息
# 生成时间：$(date '+%Y-%m-%d %H:%M:%S')
# ============================================

混淆密码 (Obfs Password):
${OBFS_PASSWORD}

认证密码 (Auth Password):
${AUTH_PASSWORD}

流量统计密钥 (Stats Secret):
${STATS_SECRET}

证书指纹 (SHA256):
${FINGERPRINT}

# 客户端配置示例（安全）：
# server: YOUR_SERVER_IP:443
# auth: "${AUTH_PASSWORD}"
# obfs:
#   type: salamander
#   salamander:
#     password: "${OBFS_PASSWORD}"
# tls:
#   ca: /etc/hysteria/server.crt  # 使用 CA 证书验证（推荐）
#   # 或 insecure: true（仅测试用，不安全）
# bandwidth:
#   up: 50 mbps
#   down: 100 mbps
# socks5:
#   listen: 127.0.0.1:1080
EOF

    chmod 600 /etc/hysteria/credentials.txt
    
    echo -e "${GREEN}配置文件创建完成${NC}"
    echo "  配置文件：/etc/hysteria/config.yaml"
    echo "  凭证文件：/etc/hysteria/credentials.txt"
}

# 安装 systemd 服务
install_systemd() {
    echo -e "${YELLOW}正在安装 systemd 服务...${NC}"
    
    # 复制服务文件
    cp hysteria-server.service /etc/systemd/system/hysteria-server.service
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    # 启用服务
    systemctl enable hysteria-server.service
    
    echo -e "${GREEN}systemd 服务安装完成${NC}"
}

# 配置防火墙
setup_firewall() {
    echo -e "${YELLOW}正在配置防火墙...${NC}"
    
    if command -v ufw &> /dev/null; then
        # UFW (Ubuntu/Debian)
        ufw allow 80/tcp comment "Hysteria HTTP masquerade"
        ufw allow 443/tcp comment "Hysteria HTTPS masquerade"
        ufw allow 443/udp comment "Hysteria QUIC"
        ufw allow 9999/tcp comment "Hysteria stats (localhost only)"
        echo -e "${GREEN}UFW 防火墙规则已添加${NC}"
        
    elif command -v firewall-cmd &> /dev/null; then
        # Firewalld (CentOS/RHEL)
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --permanent --add-port=443/udp
        firewall-cmd --permanent --add-port=9999/tcp
        firewall-cmd --reload
        echo -e "${GREEN}Firewalld 防火墙规则已添加${NC}"
        
    elif command -v iptables &> /dev/null; then
        # 基础 iptables
        iptables -A INPUT -p tcp --dport 80 -j ACCEPT
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT
        iptables -A INPUT -p udp --dport 443 -j ACCEPT
        iptables -A INPUT -p tcp --dport 9999 -s 127.0.0.1 -j ACCEPT
        echo -e "${GREEN}iptables 防火墙规则已添加${NC}"
        echo "  注意：iptables 规则重启后失效，请自行保存"
    else
        echo -e "${YELLOW}未检测到防火墙工具，请手动配置${NC}"
    fi
}

# 启动服务
start_service() {
    echo -e "${YELLOW}正在启动 Hysteria 服务...${NC}"
    
    systemctl start hysteria-server.service
    
    # 检查状态
    sleep 2
    if systemctl is-active --quiet hysteria-server.service; then
        echo -e "${GREEN}Hysteria 服务启动成功${NC}"
    else
        echo -e "${RED}Hysteria 服务启动失败${NC}"
        echo "查看日志：journalctl -u hysteria-server.service -n 50"
    fi
}

# 显示配置信息
show_info() {
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Hysteria 2 安装完成！${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo "📄 配置文件位置:"
    echo "   /etc/hysteria/config.yaml"
    echo ""
    echo "🔐 认证信息:"
    echo "   /etc/hysteria/credentials.txt"
    echo ""
    echo "📜 证书文件:"
    echo "   /etc/hysteria/server.crt"
    echo "   /etc/hysteria/server.key"
    echo ""
    echo "🚀 服务管理命令:"
    echo "   启动：sudo systemctl start hysteria-server.service"
    echo "   停止：sudo systemctl stop hysteria-server.service"
    echo "   重启：sudo systemctl restart hysteria-server.service"
    echo "   状态：sudo systemctl status hysteria-server.service"
    echo "   日志：sudo journalctl -u hysteria-server.service -f"
    echo ""
    echo "🔍 查看认证信息:"
    echo "   sudo cat /etc/hysteria/credentials.txt"
    echo ""
    echo "⚠️  重要提示:"
    echo "   1. 请妥善保存 /etc/hysteria/credentials.txt 中的密码"
    echo "   2. 建议将证书和配置文件备份到安全位置"
    echo "   3. 服务器 IP 需要手动替换到客户端配置中"
    echo ""
}

# 主函数
main() {
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Hysteria 2 服务端安装脚本${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    
    check_root
    detect_arch
    install_dependencies
    install_hysteria
    setup_config
    create_config_file
    install_systemd
    setup_firewall
    start_service
    show_info
}

# 执行
main "$@"
