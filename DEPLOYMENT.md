# Hysteria 2 完整部署指南

## 📦 文件说明

| 文件 | 用途 |
|------|------|
| `install_hysteria_server.sh` | **一键安装脚本** - 自动安装 Hysteria、配置 systemd、生成证书和配置 |
| `hysteria-server.service` | systemd 服务文件 - 用于自启动 |
| `hysteria-server.logrotate` | 日志轮转配置 |
| `generate_client_configs.sh` | 客户端配置生成脚本 |
| `hysteria_config_generator.py` | Python 配置生成器（跨平台） |

---

## 🚀 快速部署（推荐）

### 方式一：一键安装脚本

```bash
# 1. 下载脚本
cd ~
wget https://raw.githubusercontent.com/apernet/hysteria/master/install_hysteria_server.sh
chmod +x install_hysteria_server.sh

# 2. 运行安装（需要 root 权限）
sudo ./install_hysteria_server.sh
```

安装完成后会自动：
- ✅ 下载并安装最新版 Hysteria
- ✅ 生成自签名证书
- ✅ 创建配置文件（启用所有安全功能）
- ✅ 配置 systemd 自启动
- ✅ 配置防火墙规则
- ✅ 生成认证信息文件

### 方式二：手动部署

```bash
# 1. 下载 Hysteria
wget https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64
chmod +x hysteria-linux-amd64
sudo mv hysteria-linux-amd64 /usr/local/bin/hysteria

# 2. 创建目录
sudo mkdir -p /etc/hysteria /var/log/hysteria

# 3. 生成证书
cd /etc/hysteria
sudo openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
  -keyout server.key -out server.crt -days 3650 \
  -subj "/CN=Hysteria Server/O=Legitimate Company/C=US"
sudo chmod 600 server.key
sudo chmod 644 server.crt

# 4. 复制配置文件
sudo cp hysteria-server.service /etc/systemd/system/
sudo cp hysteria-server.logrotate /etc/logrotate.d/hysteria-server

# 5. 编辑配置文件（填入密码和证书路径）
sudo nano /etc/hysteria/config.yaml

# 6. 启动服务
sudo systemctl daemon-reload
sudo systemctl enable hysteria-server
sudo systemctl start hysteria-server
sudo systemctl status hysteria-server
```

---

## 📱 生成客户端配置

### 方式一：使用脚本（推荐）

```bash
# 在服务器上运行
sudo ./generate_client_configs.sh

# 按提示输入服务器 IP（或直接回车自动检测）
# 生成的配置文件在当前目录的 hysteria_client_configs/ 文件夹
```

### 方式二：使用 Python 生成器（跨平台）

```bash
# 安装依赖
pip3 install qrcode[pil]

# 运行生成器
python3 hysteria_config_generator.py -i YOUR_SERVER_IP -p 443

# 配置文件输出到 hysteria_configs/ 目录
```

### 方式三：手动配置

**Linux 客户端配置** (`client_linux.yaml`):

```yaml
server: YOUR_SERVER_IP:443

auth: "你的认证密码"

obfs:
  type: salamander
  salamander:
    password: "你的混淆密码"

tls:
  insecure: true  # 自签名证书需启用

bandwidth:
  up: 50 mbps
  down: 100 mbps

socks5:
  listen: 127.0.0.1:1080

http:
  listen: 127.0.0.1:8080
```

**Android 客户端**：
1. 下载 Hysteria Android App
2. 扫描二维码或导入 JSON 配置

---

## 🔧 服务管理命令

```bash
# 启动
sudo systemctl start hysteria-server.service

# 停止
sudo systemctl stop hysteria-server.service

# 重启
sudo systemctl restart hysteria-server.service

# 查看状态
sudo systemctl status hysteria-server.service

# 查看日志
sudo journalctl -u hysteria-server.service -f

# 查看最近 100 行日志
sudo journalctl -u hysteria-server.service -n 100

# 开机自启
sudo systemctl enable hysteria-server.service

# 禁用自启
sudo systemctl disable hysteria-server.service
```

---

## 🔐 查看认证信息

```bash
# 查看密码和证书指纹
sudo cat /etc/hysteria/credentials.txt
```

---

## 🔍 验证安装

### 检查服务状态

```bash
# 检查 systemd 服务
systemctl is-active hysteria-server.service

# 检查端口监听
sudo ss -tulnp | grep hysteria

# 应该看到：
# udp   0  0  :443  :443  users:(("hysteria",pid=1234,fd=5))
# tcp   0  0  :80   :80   users:(("hysteria",pid=1234,fd=6))
# tcp   0  0  :443  :443  users:(("hysteria",pid=1234,fd=7))
```

### 测试伪装网站

```bash
# 测试 HTTP 伪装（应该返回 Visa 网站内容）
curl -v http://YOUR_SERVER_IP/

# 测试 HTTPS 伪装（忽略证书错误）
curl -vk https://YOUR_SERVER_IP/
```

### 测试连接

```bash
# 在客户端测试连接
hysteria client -c client_linux.yaml

# 测试速度
hysteria speedtest
```

---

## 🛡️ 安全加固建议

### 1. 修改默认端口

编辑 `/etc/hysteria/config.yaml`:

```yaml
listen: :8443  # 改为其他端口

masquerade:
  # ...
  listenHTTP: :8080   # HTTP 伪装端口
  listenHTTPS: :8443  # HTTPS 伪装端口（与 listen 一致）
```

### 2. 配置 fail2ban

```bash
# 安装 fail2ban
sudo apt install fail2ban

# 创建配置文件
sudo nano /etc/fail2ban/jail.local
```

添加以下内容：

```ini
[hysteria]
enabled = true
port = 443
protocol = udp
filter = hysteria
logpath = /var/log/hysteria/*.log
maxretry = 5
bantime = 3600
```

### 3. 定期更新证书

```bash
# 每年运行一次
cd /etc/hysteria
sudo openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
  -keyout server.key -out server.crt -days 3650 \
  -subj "/CN=Hysteria Server/O=Legitimate Company/C=US"
sudo chmod 600 server.key
sudo systemctl restart hysteria-server
```

### 4. 监控日志

```bash
# 实时监控
sudo journalctl -u hysteria-server.service -f

# 查看错误日志
sudo journalctl -u hysteria-server.service -p err

# 查看认证失败
sudo grep "authentication failed" /var/log/hysteria/*.log
```

---

## 📊 流量统计

```bash
# 查看流量统计 API
curl -H "Authorization: 你的统计密钥" http://127.0.0.1:9999/traffic

# 查看在线用户
curl -H "Authorization: 你的统计密钥" http://127.0.0.1:9999/online
```

---

## ⚠️ 故障排查

### 服务无法启动

```bash
# 查看详细错误
sudo journalctl -u hysteria-server.service -n 50 --no-pager

# 检查配置文件语法
sudo hysteria server -c /etc/hysteria/config.yaml

# 检查端口占用
sudo ss -tulnp | grep :443
```

### 客户端无法连接

```bash
# 检查防火墙
sudo ufw status
sudo iptables -L -n

# 检查证书
openssl x509 -in /etc/hysteria/server.crt -noout -dates

# 检查密码是否正确
sudo cat /etc/hysteria/credentials.txt
```

### 性能问题

```bash
# 查看资源使用
systemctl status hysteria-server.service

# 查看连接数
sudo ss -s

# 调整带宽限制
sudo nano /etc/hysteria/config.yaml
# 修改 bandwidth.up 和 bandwidth.down
```

---

## 📝 配置示例

### 完整服务端配置

```yaml
listen: :443

obfs:
  type: salamander
  salamander:
    password: "your_obfs_password"

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
  sniGuard: strict

quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 8388608
  maxConnReceiveWindow: 8388608
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024

bandwidth:
  up: 100 mbps
  down: 100 mbps

auth:
  type: password
  password: "your_auth_password"

resolver:
  type: udp
  udp:
    addr: 1.1.1.1:53
    timeout: 2s

sniff:
  enable: true
  timeout: 1s
  rewriteDomain: false
  tcpPorts: "80,443"
  udpPorts: "443"

acl:
  inline:
    - reject(10.0.0.0/8)
    - reject(172.16.0.0/12)
    - reject(192.168.0.0/16)
    - direct(0.0.0.0/0:80)
    - direct(0.0.0.0/0:443)
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
  listenHTTP: :80
  listenHTTPS: :443
  forceHTTPS: true

trafficStats:
  listen: 127.0.0.1:9999
  secret: "your_stats_secret"

speedTest: false
```

---

## 🔗 相关链接

- 官方文档：https://v2.hysteria.network/
- GitHub: https://github.com/apernet/hysteria
- Telegram: https://t.me/hysteria_github

---

## 📄 许可证

MIT License
