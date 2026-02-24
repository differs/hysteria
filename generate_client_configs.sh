#!/bin/bash
# ============================================
# Hysteria 2 客户端配置生成脚本
# 生成 Linux 和 Android 客户端配置
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查凭证文件
if [[ ! -f /etc/hysteria/credentials.txt ]]; then
    echo -e "${RED}错误：未找到凭证文件${NC}"
    echo "请先运行安装脚本：./install_hysteria_server.sh"
    exit 1
fi

# 读取凭证
OBFS_PASSWORD=$(grep -A1 "混淆密码" /etc/hysteria/credentials.txt | tail -n1 | xargs)
AUTH_PASSWORD=$(grep -A1 "认证密码" /etc/hysteria/credentials.txt | tail -n1 | xargs)
FINGERPRINT=$(grep -A1 "证书指纹" /etc/hysteria/credentials.txt | tail -n1 | xargs)

# 获取服务器 IP
echo -e "${YELLOW}请输入服务器 IP 地址（回车自动检测）:${NC}"
read -p "> " SERVER_IP_INPUT

if [[ -z "$SERVER_IP_INPUT" ]]; then
    # 自动检测
    SERVER_IP=$(curl -s https://api.ipify.org)
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP=$(hostname -I | awk '{print $1}')
    fi
else
    SERVER_IP="$SERVER_IP_INPUT"
fi

echo -e "${GREEN}服务器 IP: ${SERVER_IP}${NC}"
echo ""

# 输入端口
read -p "请输入服务器端口（默认：443）: " SERVER_PORT_INPUT
SERVER_PORT=${SERVER_PORT_INPUT:-443}

# 创建输出目录
OUTPUT_DIR="./hysteria_client_configs"
mkdir -p "$OUTPUT_DIR"

# 生成 Linux 客户端配置
cat > "${OUTPUT_DIR}/client_linux.yaml" << EOF
# ============================================
# Hysteria 2 Linux 客户端配置
# 生成时间：$(date '+%Y-%m-%d %H:%M:%S')
# ============================================

server: ${SERVER_IP}:${SERVER_PORT}

auth: "${AUTH_PASSWORD}"

obfs:
  type: salamander
  salamander:
    password: "${OBFS_PASSWORD}"

tls:
  insecure: true
  # 如需固定证书指纹（更安全），取消下面注释：
  # insecure: false
  # pinSHA256: "${FINGERPRINT}"

bandwidth:
  up: 50 mbps
  down: 100 mbps

socks5:
  listen: 127.0.0.1:1080

http:
  listen: 127.0.0.1:8080
EOF

echo -e "${GREEN}✅ Linux 客户端配置已生成：${OUTPUT_DIR}/client_linux.yaml${NC}"

# 生成 Android 客户端配置（JSON）
cat > "${OUTPUT_DIR}/client_android.json" << EOF
{
  "server": "${SERVER_IP}:${SERVER_PORT}",
  "auth": "${AUTH_PASSWORD}",
  "obfs": {
    "type": "salamander",
    "salamander": {
      "password": "${OBFS_PASSWORD}"
    }
  },
  "tls": {
    "insecure": true
  },
  "bandwidth": {
    "up": "50 mbps",
    "down": "100 mbps"
  },
  "socks5": {
    "listen": "127.0.0.1:1080"
  },
  "http": {
    "listen": "127.0.0.1:8080"
  }
}
EOF

echo -e "${GREEN}✅ Android 客户端配置已生成：${OUTPUT_DIR}/client_android.json${NC}"

# 生成分享链接
URI="hysteria2://${AUTH_PASSWORD}@${SERVER_IP}:${SERVER_PORT}?obfs=salamander&obfs-password=${OBFS_PASSWORD}&insecure=1#Hysteria2-Secure"

# 生成二维码（如果安装了 qrcode）
if command -v qrencode &> /dev/null; then
    echo "$URI" | qrencode -o "${OUTPUT_DIR}/qrcode.png" -t PNG
    echo -e "${GREEN}✅ 配置二维码已生成：${OUTPUT_DIR}/qrcode.png${NC}"
else
    echo -e "${YELLOW}⚠️  qrencode 未安装，跳过二维码生成${NC}"
    echo "   安装命令：sudo apt install qrencode 或 sudo yum install qrencode"
fi

# 显示分享链接
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  客户端配置生成完成！${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "📱 Hysteria 分享链接:"
echo "${URI}"
echo ""
echo "📄 配置文件位置:"
echo "   Linux:   ${OUTPUT_DIR}/client_linux.yaml"
echo "   Android: ${OUTPUT_DIR}/client_android.json"
if [[ -f "${OUTPUT_DIR}/qrcode.png" ]]; then
    echo "   二维码：${OUTPUT_DIR}/qrcode.png"
fi
echo ""
echo "🚀 使用方法:"
echo "   Linux:   hysteria client -c ${OUTPUT_DIR}/client_linux.yaml"
echo "   Android: 导入 client_android.json 或使用二维码扫描"
echo ""
