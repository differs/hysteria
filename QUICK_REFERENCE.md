# Hysteria 2 快速参考卡片

## 🚀 一键部署

```bash
# 服务端安装（root 运行）
sudo ./install_hysteria_server.sh

# 查看认证信息
sudo cat /etc/hysteria/credentials.txt

# 生成客户端配置
sudo ./generate_client_configs.sh
```

---

## 📁 重要文件路径

| 文件 | 路径 |
|------|------|
| 服务端配置 | `/etc/hysteria/config.yaml` |
| 认证信息 | `/etc/hysteria/credentials.txt` |
| TLS 证书 | `/etc/hysteria/server.crt` |
| TLS 私钥 | `/etc/hysteria/server.key` |
| systemd 服务 | `/etc/systemd/system/hysteria-server.service` |
| 日志目录 | `/var/log/hysteria/` |

---

## 🔧 常用命令

### 服务管理

```bash
systemctl start hysteria-server.service      # 启动
systemctl stop hysteria-server.service       # 停止
systemctl restart hysteria-server.service    # 重启
systemctl status hysteria-server.service     # 状态
systemctl enable hysteria-server.service     # 开机自启
systemctl disable hysteria-server.service    # 禁用自启
```

### 查看日志

```bash
journalctl -u hysteria-server.service -f     # 实时日志
journalctl -u hysteria-server.service -n 50  # 最近 50 行
journalctl -u hysteria-server.service --since today  # 今天的日志
```

### 查看认证信息

```bash
sudo cat /etc/hysteria/credentials.txt
```

---

## 📱 客户端配置

### Linux

```bash
hysteria client -c client_linux.yaml
```

### Android

1. 打开 Hysteria App
2. 扫描二维码 或 导入 JSON 配置

### 配置示例

```yaml
server: YOUR_SERVER_IP:443
auth: "认证密码"
obfs:
  type: salamander
  salamander:
    password: "混淆密码"
tls:
  insecure: true
```

---

## 🔐 安全功能清单

✅ Salamander 混淆  
✅ 强密码认证  
✅ 自签名 TLS 证书  
✅ 严格 SNI 防护  
✅ 协议嗅探  
✅ ACL 访问控制  
✅ 伪装网站（https://www.visa.com）  
✅ 流量统计  

---

## 🔍 验证命令

```bash
# 检查服务状态
systemctl is-active hysteria-server.service

# 检查端口监听
sudo ss -tulnp | grep hysteria

# 测试伪装网站
curl -v http://YOUR_SERVER_IP/
curl -vk https://YOUR_SERVER_IP/

# 测试客户端连接
hysteria client -c client_linux.yaml
```

---

## 🛡️ 防火墙配置

### UFW (Ubuntu/Debian)

```bash
ufw allow 80/tcp      # HTTP 伪装
ufw allow 443/tcp     # HTTPS 伪装
ufw allow 443/udp     # Hysteria QUIC
ufw enable
```

### Firewalld (CentOS/RHEL)

```bash
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=443/udp
firewall-cmd --reload
```

---

## 📊 流量统计

```bash
# 查看流量
curl -H "Authorization: 统计密钥" http://127.0.0.1:9999/traffic

# 查看在线用户
curl -H "Authorization: 统计密钥" http://127.0.0.1:9999/online
```

---

## ⚠️ 故障排查

```bash
# 查看详细错误
journalctl -u hysteria-server.service -n 100 --no-pager

# 检查配置语法
hysteria server -c /etc/hysteria/config.yaml

# 检查端口占用
sudo ss -tulnp | grep :443

# 重启服务
systemctl restart hysteria-server.service
```

---

## 📞 获取帮助

- 官方文档：https://v2.hysteria.network/
- GitHub Issues: https://github.com/apernet/hysteria/issues
- Telegram: https://t.me/hysteria_github

---

**版本**: v2.0  
**更新时间**: 2026-02-24
