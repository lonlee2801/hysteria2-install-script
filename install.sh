#!/bin/bash

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# --- 辅助函数：获取公网IP ---
get_public_ip() {
    local ip=$(curl -s4 ifconfig.me)
    if [[ -z "$ip" ]]; then
        ip=$(curl -s4 icanhazip.com)
    fi
    echo "$ip"
}

# --- 检查 Root ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：必须使用 root 权限运行此脚本！${PLAIN}"
    exit 1
fi

echo -e "${GREEN}=== Hysteria 2 全自动部署脚本 (带分享链接) ===${PLAIN}"

# ==========================================================
# 1. 用户交互配置 (Input & Config)
# ==========================================================

# --- 1.1 端口设置 ---
echo -e ""
read -p "请输入端口号 [默认 443]: " PORT
PORT=${PORT:-443}
if [[ $PORT -le 0 || $PORT -gt 65535 ]]; then
    echo -e "${RED}端口无效，请输入 1-65535 之间的数字${PLAIN}"
    exit 1
fi

# --- 1.2 域名与证书模式 ---
echo -e ""
echo -e "请选择证书模式："
echo -e "  1) ${GREEN}自签证书 (推荐)${PLAIN} - 无需域名，使用 IP 连接，自动伪装 (如 www.bing.com)"
echo -e "  2) ${YELLOW}自有域名 (ACME)${PLAIN} - 需要你拥有域名并已解析到本机 IP，脚本自动申请真实证书"
read -p "请选择 [默认 1]: " CERT_MODE
CERT_MODE=${CERT_MODE:-1}

# --- 1.3 密码设置 ---
echo -e ""
read -p "请输入连接密码 [回车自动生成随机强密码]: " PASSWORD
if [[ -z "$PASSWORD" ]]; then
    PASSWORD=$(openssl rand -base64 16)
    echo -e "${YELLOW}已生成随机密码: ${PASSWORD}${PLAIN}"
fi

# --- 逻辑处理 ---
PUBLIC_IP=$(get_public_ip)
SNI_DOMAIN=""
INSECURE="0" # 0=False, 1=True

if [[ "$CERT_MODE" == "2" ]]; then
    # --- 自有域名模式 ---
    echo -e ""
    echo -e "${YELLOW}注意：请确保你的域名已经 A 记录解析指向了本机 IP: ${PUBLIC_IP}${PLAIN}"
    read -p "请输入你的域名 (例如 myserver.com): " CUSTOM_DOMAIN
    if [[ -z "$CUSTOM_DOMAIN" ]]; then
        echo -e "${RED}域名不能为空${PLAIN}"; exit 1
    fi
    DOMAIN="$CUSTOM_DOMAIN"
    SNI_DOMAIN="$CUSTOM_DOMAIN"
    INSECURE="0"
    echo -e "${GREEN}将在配置文件中启用内置 ACME 自动申请证书...${PLAIN}"
else
    # --- 自签证书模式 ---
    echo -e ""
    read -p "请输入伪装域名 [默认 www.bing.com]: " FAKE_DOMAIN
    FAKE_DOMAIN=${FAKE_DOMAIN:-www.bing.com}
    DOMAIN="$PUBLIC_IP" # 连接地址是IP
    SNI_DOMAIN="$FAKE_DOMAIN" # SNI 是伪装域名
    INSECURE="1" # 客户端必须开启跳过证书验证
    echo -e "${GREEN}将生成针对 ${FAKE_DOMAIN} 的自签证书...${PLAIN}"
fi

# ==========================================================
# 2. 安装过程 (Installation)
# ==========================================================

echo -e ""
echo -e "${YELLOW}[1/5] 安装依赖与环境检查...${PLAIN}"
if [ -x "$(command -v apt)" ]; then
    apt update -q && apt install -y curl wget openssl
elif [ -x "$(command -v yum)" ]; then
    yum install -y curl wget openssl
fi

echo -e "${YELLOW}[2/5] 获取并下载 Hysteria 2 最新版...${PLAIN}"
LATEST_URL=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/apernet/hysteria/releases/latest)
VERSION=$(echo "$LATEST_URL" | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+")
ARCH=$(uname -m)
case $ARCH in
    x86_64) HY_ARCH="amd64" ;;
    aarch64) HY_ARCH="arm64" ;;
    *) echo -e "${RED}不支持的架构: $ARCH${PLAIN}"; exit 1 ;;
esac
wget -q --show-progress -O /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/download/${VERSION}/hysteria-linux-${HY_ARCH}"
chmod +x /usr/local/bin/hysteria

# ==========================================================
# 3. 配置文件生成 (Configuration)
# ==========================================================

echo -e "${YELLOW}[3/5] 生成配置文件...${PLAIN}"
mkdir -p /etc/hysteria

# --- 配置生成逻辑 ---
# 基础头部
cat > /etc/hysteria/config.yaml <<EOF
listen: :$PORT

bandwidth:
  up: 100 mbps
  down: 100 mbps

auth:
  type: password
  password: "$PASSWORD"

ignoreClientBandwidth: false
EOF

# TLS 部分逻辑
if [[ "$CERT_MODE" == "2" ]]; then
    # ---> ACME 模式配置
    cat >> /etc/hysteria/config.yaml <<EOF
tls:
  type: acme
  domain: $CUSTOM_DOMAIN
  email: admin@$CUSTOM_DOMAIN
EOF
else
    # ---> 自签模式配置
    # 生成自签证书
    openssl req -x509 -newkey rsa:4096 -nodes -sha256 \
    -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
    -days 3650 -subj "/CN=$FAKE_DOMAIN" 2>/dev/null
    
    cat >> /etc/hysteria/config.yaml <<EOF
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
EOF
fi

# ==========================================================
# 4. 服务启动 (Systemd)
# ==========================================================

echo -e "${YELLOW}[4/5] 配置系统服务...${PLAIN}"
cat > /etc/systemd/system/hysteria-server.service <<EOF
[Unit]
Description=Hysteria 2 Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hysteria-server >/dev/null 2>&1
systemctl restart hysteria-server

# ==========================================================
# 5. 生成分享链接与输出 (Output)
# ==========================================================
echo -e "${YELLOW}[5/5] 生成分享链接...${PLAIN}"

# 构造 hy2:// 链接
# 格式: hy2://password@host:port?insecure=1&sni=domain#name
# 如果是自签模式，host是IP，sni是伪装域名，insecure=1
# 如果是自有域名，host是域名，sni是域名(或留空)，insecure=0

if [[ "$CERT_MODE" == "2" ]]; then
    # 自有域名：Host=Domain, SNI=Domain, Insecure=0
    LINK_HOST="$CUSTOM_DOMAIN"
    LINK_SNI="$CUSTOM_DOMAIN"
    LINK_INSECURE="0"
else
    # 自签模式：Host=IP, SNI=FakeDomain, Insecure=1
    LINK_HOST="$PUBLIC_IP"
    LINK_SNI="$FAKE_DOMAIN"
    LINK_INSECURE="1"
fi

# URL 编码备注名
NODE_NAME="Hy2-${LINK_HOST}"
HY2_LINK="hy2://${PASSWORD}@${LINK_HOST}:${PORT}/?insecure=${LINK_INSECURE}&sni=${LINK_SNI}#${NODE_NAME}"

echo -e ""
echo -e "${GREEN}==============================================${PLAIN}"
echo -e "${GREEN}          Hysteria 2 安装完成！               ${PLAIN}"
echo -e "${GREEN}==============================================${PLAIN}"
echo -e ""
echo -e "配置信息:"
echo -e "  IP / Host    : ${CYAN}${LINK_HOST}${PLAIN}"
echo -e "  Port         : ${CYAN}${PORT}${PLAIN}"
echo -e "  Password     : ${CYAN}${PASSWORD}${PLAIN}"
echo -e "  SNI (伪装)   : ${CYAN}${LINK_SNI}${PLAIN}"
echo -e "  允许不安全(Insecure) : ${CYAN}${LINK_INSECURE}${PLAIN}"
echo -e ""
echo -e "${YELLOW}--- v2rayN / Nekobox / 客户端 导入链接 ---${PLAIN}"
echo -e "${CYAN}${HY2_LINK}${PLAIN}"
echo -e "${YELLOW}------------------------------------------${PLAIN}"
echo -e ""
echo -e "配置文件: /etc/hysteria/config.yaml"
if [[ "$CERT_MODE" == "2" ]]; then
    echo -e "证书模式: ${GREEN}ACME (自动管理)${PLAIN}"
else
    echo -e "证书模式: ${YELLOW}Self-signed (自签)${PLAIN}"
fi
echo -e ""