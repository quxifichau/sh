#!/bin/bash
# ==========================================
# Sing-box 本地 HTTP 转远端 TUIC v5 一键部署脚本
# 适配国内 VPS 环境 (官方源 / 多镜像加速轮询下载)
# ==========================================

# ----------------- [ 配置区 ] -----------------
# 请在下方 "" 内填入你自己的真实节点参数：

# 1. 你的海外 VPS 公网 IP
REMOTE_SERVER_IP="193.177.221.37"

# 2. TUIC 服务端监听端口
REMOTE_SERVER_PORT=12345

# 3. TUIC 用户的 UUID
TUIC_UUID="84f186d2-73ce-4ec4-bc07-9c91c5601752"

# 4. TUIC 密码
TUIC_PASSWORD="d3674cfb"

# 5. SNI (伪装域名)，请填入您目前正常使用的客户端中的 SNI
TUIC_SNI="www.bing.com"

# 6. 本地监听端口 (后续在 New API 渠道代理处填写的端口)
LOCAL_PORT=10080
# ----------------------------------------------

# 确保使用 Root 运行
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 权限运行此脚本 (例如 sudo bash deploy.sh)"
  exit 1
fi

echo "⏳ 开始安装 Sing-box..."

# curl -fsSL https://sing-box.app/install.sh | bash
# 或者直接上传安装sing-box_1.14.2_linux_amd64.deb

sudo dpkg -i sing-box_1.14.2_linux_amd64.deb

sing-box version || { echo "❌ Sing-box 安装失败"; exit 1; }

# 2. 生成配置文件
echo "--> 正在生成 Sing-box 配置文件..."
mkdir -p /etc/sing-box

cat << EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "http",
      "tag": "http-in",
      "listen": "0.0.0.0",
      "listen_port": ${LOCAL_PORT}
    }
  ],
  "outbounds": [
    {
      "type": "tuic",
      "tag": "tuic-out",
      "server": "${REMOTE_SERVER_IP}",
      "server_port": ${REMOTE_SERVER_PORT},
      "uuid": "${TUIC_UUID}",
      "password": "${TUIC_PASSWORD}",
      "congestion_control": "bbr",
      "udp_relay_mode": "native",
      "tls": {
        "enabled": true,
        "server_name": "${TUIC_SNI}",
        "alpn": ["h3"],
        "insecure": true
      }
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": "http-in",
        "outbound": "tuic-out"
      }
    ],
    "auto_detect_interface": true
  }
}
EOF
chmod 644 /etc/sing-box/config.json

# 3. 启动并设置开机自启
echo "--> 正在启动守护进程..."
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

sleep 3
if systemctl is-active --quiet sing-box; then
    echo "✅ 官方 Systemd 守护服务已成功启动！"
else
    echo "❌ 服务启动失败，请使用 journalctl -u sing-box -n 50 查看日志"
    exit 1
fi

# 4. 连通性测试
echo "--> 正在测试代理连通性 (本地 127.0.0.1:${LOCAL_PORT}) ..."
# 测试 IP 出口，超时时间10秒
IP_INFO=$(curl -s -x "http://127.0.0.1:${LOCAL_PORT}" -m 10 https://ipinfo.io/ip)

if [ -n "$IP_INFO" ]; then
    echo "========================================="
    echo "🎉 恭喜！隧道畅通！"
    echo "🌍 当前代理的海外出口 IP 为: $IP_INFO"
    echo "========================================="
    echo "👉 接下来，请前往国内机器的 New API 后台："
    echo "在渠道设置的【代理 (Proxy)】处填写："
    echo "http://172.17.0.1:${LOCAL_PORT}  (Docker部署用户专属)"
    echo "========================================="
    echo "⚠️ 安全提示：请勿在云服务器控制台的防火墙/安全组中开放 ${LOCAL_PORT} 端口，"
    echo "保持其处于内网封闭状态即可完美保证安全。"
else
    echo "========================================="
    echo "❌ 隧道联通失败 (请求超时或被阻断)。可能原因："
    echo "1. 您填写的参数 (UUID/密码/SNI/端口) 有误。"
    echo "2. 国内 VPS 提供商 (如阿里云/腾讯云) 安全组阻断了 UDP 协议出站。"
    echo "3. 海外 VPS 防火墙未放行 ${REMOTE_SERVER_PORT} 的 UDP 端口。"
    echo "查看实时报错日志命令: journalctl -u sing-box -f"
    echo "========================================="
fi