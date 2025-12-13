#!/usr/bin/env bash
# 一键设置系统代理，用法：
#   sudo bash <(curl -fsSL https://raw.githubusercontent.com/jereter/linux-script/main/set_proxy.sh) 192.168.3.197:7890

set -euo pipefail

PROXY_FILE="/etc/profile.d/proxy.sh"

# 必须是 root
[ "$(id -u)" -eq 0 ] || { echo "请用 sudo 或 root 运行"; exit 1; }

# 必须带一个参数：IP:PORT 或 域名:PORT
[ $# -eq 1 ] || { 
    echo "用法: $0 <IP:PORT>"
    echo "例: $0 192.168.3.197:7890"
    echo "例: $0 127.0.0.1:7890" 
    echo "例: $0 proxy.example.com:8080"
    exit 1 
}

HOST_PORT="$1"

# 验证参数格式
if [[ ! "$HOST_PORT" =~ ^[^:]+:[0-9]{1,5}$ ]]; then
    echo "错误：参数格式不正确，应为 IP:PORT 或 域名:PORT"
    echo "正确格式示例: 192.168.1.100:7890 或 proxy.com:8080"
    exit 1
fi

# 提取端口号验证范围
port="${HOST_PORT##*:}"
if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo "错误：端口号应在 1-65535 范围内"
    exit 1
fi

PROXY_URL="http://${HOST_PORT}"

# 测试代理连接（可选）
echo "测试代理连接..."
if ! curl -fs --connect-timeout 5 --max-time 10 "$PROXY_URL" > /dev/null 2>&1; then
    echo "警告：无法连接到代理服务器 $PROXY_URL"
    read -p "是否继续设置？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "已取消设置"
        exit 1
    fi
else
    echo "代理连接测试成功"
fi

# 写入配置
cat > "$PROXY_FILE" <<EOF
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export no_proxy="localhost,127.0.0.1,::1,172.16.0.0/12,192.168.0.0/16,.svc,.svc.cluster.local"
EOF

chmod +x "$PROXY_FILE"

echo ""
echo "==========================================="
echo "✅ 系统代理设置完成"
echo "==========================================="
echo "代理地址: $PROXY_URL"
echo "配置文件: $PROXY_FILE"
echo ""
echo "📋 使用说明:"
echo "  - 新打开的终端会自动生效"
echo "  - 当前终端需要手动执行: source $PROXY_FILE"
echo "  - 如需取消代理，运行: sudo rm -f $PROXY_FILE"
echo "  - 查看当前代理: env | grep -i proxy"
echo ""
echo "🔍 验证代理是否生效:"
echo "  curl -I http://www.google.com"
echo "==========================================="
