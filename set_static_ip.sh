#!/bin/bash

# Rocky Linux 静态IP设置脚本（修复版）
# 使用方法: sudo ./set_static_ip.sh <IP地址>

# 配置参数
INTERFACE="eth0"                    # 网卡名称
DNS="8.8.8.8;114.114.114.114;"      # DNS服务器

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用sudo运行此脚本: sudo $0${NC}"
    exit 1
fi

# 显示使用说明
show_usage() {
    echo "使用方法: sudo $0 <IP地址>"
    echo "示例: sudo $0 192.168.3.117"
    echo ""
    echo "注意: 脚本会自动推导网关和掩码"
    echo "当前网络接口状态:"
    ip addr show | grep "inet " | grep -v "127.0.0.1"
}

# 检查参数
if [ $# -ne 1 ]; then
    echo -e "${RED}错误: 请提供IP地址${NC}"
    show_usage
    exit 1
fi

IP_ADDRESS=$1

# 验证IP地址格式
if ! echo "$IP_ADDRESS" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo -e "${RED}错误: IP地址格式不正确，请使用格式: 192.168.1.100${NC}"
    show_usage
    exit 1
fi

# 从IP地址推导网关（假设网关是网段的第一个地址）
GATEWAY=$(echo "$IP_ADDRESS" | awk -F. '{print $1"."$2"."$3".1"}')

# 设置掩码为/24
NETMASK="24"
FULL_IP="${IP_ADDRESS}/${NETMASK}"

echo -e "${YELLOW}网络配置信息:${NC}"
echo "网卡接口: $INTERFACE"
echo "IP地址: $IP_ADDRESS"
echo "子网掩码: /$NETMASK (255.255.255.0)"
echo "网关: $GATEWAY (自动推导)"
echo "DNS: $DNS"
echo ""

# 检查网络接口是否存在
if ! ip link show "$INTERFACE" &>/dev/null; then
    echo -e "${RED}错误: 网络接口 $INTERFACE 不存在${NC}"
    echo -e "${YELLOW}可用的网络接口:${NC}"
    ip -o link show | awk -F': ' '{print $2}'
    exit 1
fi

# 配置文件路径
CONFIG_DIR="/etc/NetworkManager/system-connections"
CONFIG_FILE="$CONFIG_DIR/${INTERFACE}.nmconnection"
ORIGINAL_BACKUP="$CONFIG_DIR/${INTERFACE}.nmconnection.original"

# 安全警告
echo -e "${RED}警告: 此操作将更改网络配置，可能导致当前SSH连接断开！${NC}"
echo -e "${YELLOW}请确保你有其他方式访问服务器（如控制台），或者确认IP变更不会影响连接。${NC}"
echo ""
read -p "是否继续？(y/N): " confirm

if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "操作已取消"
    exit 0
fi

# 检查并管理备份文件
if [ ! -f "$ORIGINAL_BACKUP" ] && [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$ORIGINAL_BACKUP"
    echo -e "${GREEN}已创建原始配置备份: $ORIGINAL_BACKUP${NC}"
elif [ -f "$ORIGINAL_BACKUP" ]; then
    echo -e "${BLUE}原始备份已存在，跳过备份: $ORIGINAL_BACKUP${NC}"
else
    echo -e "${YELLOW}没有找到原始配置文件，将创建新配置${NC}"
fi

# 创建新的配置文件
echo -e "${YELLOW}正在创建网络配置文件...${NC}"

# 生成UUID
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || (command -v uuidgen >/dev/null && uuidgen) || echo "00000000-0000-0000-0000-000000000000")

cat > "$CONFIG_FILE" << EOF
[connection]
id=$INTERFACE
uuid=$UUID
type=ethernet
interface-name=$INTERFACE

[ipv4]
method=manual
addresses=$FULL_IP
gateway=$GATEWAY
dns=$DNS

[ipv6]
method=disabled

[ethernet]
EOF

# 设置文件权限
chmod 600 "$CONFIG_FILE"
chown root:root "$CONFIG_FILE"

echo -e "${GREEN}配置文件已创建: $CONFIG_FILE${NC}"

# 显示配置文件内容用于调试
echo -e "${YELLOW}配置文件内容:${NC}"
cat "$CONFIG_FILE"
echo ""

# 停止NetworkManager并直接处理网络接口
echo -e "${YELLOW}停止NetworkManager服务...${NC}"
systemctl stop NetworkManager

# 关闭网络接口
echo -e "${YELLOW}关闭网络接口 $INTERFACE ...${NC}"
ip link set "$INTERFACE" down

# 刷新IP地址
echo -e "${YELLOW}刷新IP地址...${NC}"
ip addr flush dev "$INTERFACE"

# 启动NetworkManager
echo -e "${YELLOW}启动NetworkManager服务...${NC}"
systemctl start NetworkManager

# 等待服务启动
sleep 5

# 重新加载连接配置
echo -e "${YELLOW}重新加载连接配置...${NC}"
nmcli connection reload

# 激活连接
echo -e "${YELLOW}激活连接...${NC}"
nmcli connection up "$INTERFACE"

# 等待网络稳定
sleep 5

echo -e "${GREEN}网络配置完成！${NC}"
echo "=================================="

# 显示当前IP信息
echo -e "${YELLOW}当前网络状态:${NC}"
CURRENT_IP=$(ip addr show "$INTERFACE" | grep "inet " | head -1 | awk '{print $2}')
if [ -n "$CURRENT_IP" ]; then
    echo "检测到的IP: $CURRENT_IP"
    if [ "$CURRENT_IP" = "$FULL_IP" ]; then
        echo -e "${GREEN}✓ IP地址设置成功！${NC}"
    else
        echo -e "${RED}✗ IP地址设置失败，当前IP: $CURRENT_IP，期望IP: $FULL_IP${NC}"
    fi
else
    echo -e "${RED}✗ 未检测到IP地址${NC}"
fi

# 显示路由信息
echo ""
echo -e "${YELLOW}路由信息:${NC}"
ip route show | grep -E "(default|$INTERFACE)"

# 显示DNS信息
echo ""
echo -e "${YELLOW}DNS配置:${NC}"
nmcli device show "$INTERFACE" | grep -E "IP4.DNS|IP4.GATEWAY"

echo "=================================="

# 网络连通性测试
echo ""
echo -e "${YELLOW}网络连通性测试:${NC}"
if ping -c 2 -W 1 "$GATEWAY" &> /dev/null; then
    echo -e "网关连通性 ($GATEWAY): ${GREEN}正常${NC}"
else
    echo -e "网关连通性 ($GATEWAY): ${RED}失败${NC}"
fi

if ping -c 2 -W 1 "8.8.8.8" &> /dev/null; then
    echo -e "外网连通性 (8.8.8.8): ${GREEN}正常${NC}"
else
    echo -e "外网连通性 (8.8.8.8): ${RED}失败${NC}"
fi

# 显示恢复提示
if [ -f "$ORIGINAL_BACKUP" ]; then
    echo ""
    echo -e "${BLUE}恢复提示: 如果需要恢复原始配置，可以执行:${NC}"
    echo -e "  sudo cp $ORIGINAL_BACKUP $CONFIG_FILE"
    echo -e "  sudo systemctl restart NetworkManager"
    echo -e "  sudo nmcli connection up $INTERFACE"
fi

echo ""
echo -e "${YELLOW}如果SSH连接已断开，请使用新IP地址重新连接:${NC}"
echo -e "   ssh 你的用户名@$IP_ADDRESS"
