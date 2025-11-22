#!/usr/bin/env bash
# 一键设置系统代理

set -euo pipefail

PROXY_FILE="/etc/profile.d/proxy.sh"

# 必须是 root
[ "$(id -u)" -eq 0 ] || { echo "请用 sudo 或 root 运行"; exit 1; }

# 交互式输入代理地址
echo "设置系统代理"
read -p "请输入代理地址 (格式: IP:PORT 或 域名:PORT): " HOST_PORT

# 验证输入不为空
if [ -z "$HOST_PORT" ]; then
    echo "错误：代理地址不能为空"
    exit 1
fi

# 验证参数格式
if [[ ! "$HOST_PORT" =~ ^[^:]+:[0-9]{1,5}$ ]]; then
    echo "错误：参数格式应为 IP:PORT 或 域名:PORT"
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
fi

# 写入配置
cat > "$PROXY_FILE" <<EOF
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export no_proxy="localhost,127.0.0.1,::1"
EOF

chmod +x "$PROXY_FILE"

echo "系统代理已设为: $PROXY_URL"
echo ""
echo "注意："
echo "1. 新打开的终端会自动生效"
echo "2. 当前终端需要手动执行: source $PROXY_FILE"
echo "3. 如需取消代理，运行: rm -f $PROXY_FILE"
echo "4. 查看当前代理: env | grep -i proxy"
