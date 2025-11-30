#!/bin/bash

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# --- 检查 Root ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：必须使用 root 权限运行此脚本！${PLAIN}"
    exit 1
fi

echo -e "${GREEN}=== Hysteria 2 一键安装脚本 ===${PLAIN}"

# ==========================================================
# 1. 基础依赖与内核安装
# ==========================================================
echo -e "${YELLOW}[1/7] 安装依赖并调用官方脚本...${PLAIN}"

# 安装常用工具和 iptables 持久化工具
if [ -x "$(command -v apt)" ]; then
    apt update -q
    # 预先配置 iptables-persistent 避免交互弹窗
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    apt install -y curl wget iptables iptables-persistent netfilter-persistent openssl
elif [ -x "$(command -v yum)" ]; then
    yum install -y curl wget iptables iptables-services openssl
fi

# 安装 Hysteria 2 官方内核
bash <(curl -fsSL https://get.hy2.sh/)
if [ $? -ne 0 ]; then
    echo -e "${RED}官方安装脚本执行失败，请检查网络。${PLAIN}"
    exit 1
fi

# ==========================================================
# 2. 交互式配置 (Interactive Config)
# ==========================================================
echo -e "${YELLOW}[2/7] 开始配置参数...${PLAIN}"

# --- 2.1 基础监听 ---
read -p "请输入 VPN 监听端口 (UDP) [默认 443]: " PORT
PORT=${PORT:-443}

# --- 2.2 密码验证 ---
read -p "请输入认证密码 [回车随机生成]: " PASSWORD
if [[ -z "$PASSWORD" ]]; then
    PASSWORD=$(openssl rand -hex 8)
    echo -e "已生成随机密码: ${GREEN}$PASSWORD${PLAIN}"
fi

# --- 2.3 带宽控制 ---
echo -e "${YELLOW}--- 带宽设置 (单位: Mbps) ---${PLAIN}"
echo -e "提示: 建议填写服务器物理带宽的 80-90%"
read -p "服务器上传速度 (即客户端下载) [默认 100]: " BW_UP
BW_UP=${BW_UP:-100}
read -p "服务器下载速度 (即客户端上传) [默认 100]: " BW_DOWN
BW_DOWN=${BW_DOWN:-100}

# --- 2.4 端口跳跃 (Port Hopping) ---
echo -e "${YELLOW}--- 端口跳跃 (Port Hopping) ---${PLAIN}"
echo -e "原理: 使用 iptables 将端口范围转发到主端口，对抗运营商 QoS。"
read -p "是否开启端口跳跃? (y/n) [默认 n]: " ENABLE_HOPPING
ENABLE_HOPPING=${ENABLE_HOPPING:-n}

if [[ "$ENABLE_HOPPING" =~ ^[yY]$ ]]; then
    read -p "跳跃起始端口 [默认 20000]: " HOP_START
    HOP_START=${HOP_START:-20000}
    read -p "跳跃结束端口 [默认 50000]: " HOP_END
    HOP_END=${HOP_END:-50000}
    
    if [[ $HOP_END -le $HOP_START ]]; then
        echo -e "${RED}错误：结束端口必须大于起始端口!${PLAIN}"
        exit 1
    fi
    HOP_MSG="${GREEN}启用 ($HOP_START-$HOP_END)${PLAIN}"
else
    HOP_MSG="禁用"
fi

# --- 2.5 伪装设置 (Masquerade) ---
echo -e "${YELLOW}--- 伪装设置 (Masquerade) ---${PLAIN}"
echo -e "作用: 抵抗主动探测，让服务器看起来像一个正常的网站。"
read -p "是否配置伪装? (y/n) [默认 y]: " ENABLE_MASQ
ENABLE_MASQ=${ENABLE_MASQ:-y}

MASQ_CONF=""
if [[ "$ENABLE_MASQ" =~ ^[yY]$ ]]; then
    read -p "请输入伪装目标网址 [默认 https://www.bing.com]: " MASQ_URL
    MASQ_URL=${MASQ_URL:-https://www.bing.com}
    
    # 构建基础 Proxy 伪装配置
    MASQ_CONF=$(cat <<EOF
masquerade:
  type: proxy
  proxy:
    url: $MASQ_URL
    rewriteHost: true
EOF
)

    # 询问是否开启 TCP 监听 (做戏做全套)
    echo -e "是否开启 ${CYAN}TCP HTTP/HTTPS${PLAIN} 监听? (伪装网站)"
    echo -e "注意: 这会占用服务器的 TCP 80 和 443 端口。如果你安装了 Nginx/Apache，请选 n。"
    read -p "开启 TCP 伪装监听? (y/n) [默认 n]: " ENABLE_FULL_MASQ
    
    if [[ "$ENABLE_FULL_MASQ" =~ ^[yY]$ ]]; then
        # 追加 listenHTTP/HTTPS 配置
        MASQ_CONF=$(cat <<EOF
masquerade:
  type: proxy
  proxy:
    url: $MASQ_URL
    rewriteHost: true
  listenHTTP: :80
  listenHTTPS: :443
  forceHTTPS: true
EOF
)
    fi
fi

# --- 2.6 证书模式 ---
echo -e "${YELLOW}--- 证书模式 ---${PLAIN}"
echo -e "  1) 自签证书 (推荐 IP 直连，防封效果好)"
echo -e "  2) 自有域名 (ACME，需提前解析域名)"
read -p "请选择 [默认 1]: " CERT_MODE
CERT_MODE=${CERT_MODE:-1}


# ==========================================================
# 3. 生成配置文件
# ==========================================================
echo -e "${YELLOW}[3/7] 生成 config.yaml...${PLAIN}"
CONFIG_FILE="/etc/hysteria/config.yaml"

# 准备基础变量
DOMAIN_CONF=""
TLS_CONF=""
LINK_SNI=""
LINK_INSECURE=""

if [[ "$CERT_MODE" == "2" ]]; then
    # === ACME 模式 ===
    read -p "请输入你的域名: " DOMAIN
    if [[ -z "$DOMAIN" ]]; then echo -e "${RED}域名不能为空!${PLAIN}"; exit 1; fi
    
    DOMAIN_CONF=$(cat <<EOF
acme:
  domains:
    - $DOMAIN
  email: admin@$DOMAIN
EOF
)
    LINK_HOST=$DOMAIN
    LINK_SNI=$DOMAIN
    LINK_INSECURE=0
else
    # === 自签模式 ===
    read -p "请输入伪装域名 (SNI) [默认 www.bing.com]: " BING_DOMAIN
    BING_DOMAIN=${BING_DOMAIN:-www.bing.com}
    
    # 生成 ECC 证书
    echo "生成自签证书..."
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout /etc/hysteria/server.key \
        -out /etc/hysteria/server.crt \
        -subj "/CN=$BING_DOMAIN" \
        -days 36500 2>/dev/null

    # 修复权限
    chown hysteria:hysteria /etc/hysteria/server.key
    chown hysteria:hysteria /etc/hysteria/server.crt

    TLS_CONF=$(cat <<EOF
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
EOF
)
    LINK_HOST=$(curl -s4 ifconfig.me)
    LINK_SNI=$BING_DOMAIN
    LINK_INSECURE=1
fi

# 写入配置文件 (注意缩进)
cat > $CONFIG_FILE <<EOF
listen: :$PORT

$DOMAIN_CONF
$TLS_CONF

auth:
  type: password
  password: $PASSWORD

bandwidth:
  up: $BW_UP mbps
  down: $BW_DOWN mbps

ignoreClientBandwidth: false

$MASQ_CONF
EOF

# ==========================================================
# 4. 配置端口跳跃 (IPTables)
# ==========================================================
echo -e "${YELLOW}[4/7] 配置端口转发规则...${PLAIN}"

MPORT_PARAM=""

if [[ "$ENABLE_HOPPING" =~ ^[yY]$ ]]; then
    # 自动获取默认网卡接口名
    ETH=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
    echo -e "检测到网卡: ${CYAN}$ETH${PLAIN}"
    
    # 清理可能存在的旧规则 (防止重复叠加)
    iptables -t nat -D PREROUTING -i $ETH -p udp --dport $HOP_START:$HOP_END -j REDIRECT --to-ports $PORT 2>/dev/null
    
    # 添加新规则
    iptables -t nat -A PREROUTING -i $ETH -p udp --dport $HOP_START:$HOP_END -j REDIRECT --to-ports $PORT
    
    # 持久化规则
    if [ -x "$(command -v netfilter-persistent)" ]; then
        netfilter-persistent save
    elif [ -x "$(command -v service)" ]; then
        service iptables save 2>/dev/null
    fi
    
    MPORT_PARAM="&mport=$HOP_START-$HOP_END"
    echo -e "${GREEN}端口跳跃规则已应用: $HOP_START-$HOP_END -> $PORT${PLAIN}"
fi

# ==========================================================
# 5. 启动服务
# ==========================================================
echo -e "${YELLOW}[5/7] 启动服务...${PLAIN}"
systemctl enable hysteria-server.service
systemctl restart hysteria-server.service

sleep 2
# 检查状态
if systemctl is-active --quiet hysteria-server.service; then
    echo -e "${GREEN}服务启动成功!${PLAIN}"
else
    echo -e "${RED}服务启动失败! 日志如下:${PLAIN}"
    journalctl -u hysteria-server.service -n 10 --no-pager
    exit 1
fi

# ==========================================================
# 6. 生成链接
# ==========================================================
HY2_LINK="hy2://${PASSWORD}@${LINK_HOST}:${PORT}/?insecure=${LINK_INSECURE}&sni=${LINK_SNI}${MPORT_PARAM}#Hy2-${LINK_HOST}"

# ==========================================================
# 7. 最终输出
# ==========================================================
echo -e ""
echo -e "${GREEN}==============================================${PLAIN}"
echo -e "${GREEN}      Hysteria 2 安装完成 (Ultimate)          ${PLAIN}"
echo -e "${GREEN}==============================================${PLAIN}"
echo -e ""
echo -e "IP / 域名    : ${CYAN}${LINK_HOST}${PLAIN}"
echo -e "端口 (Port)  : ${CYAN}${PORT}${PLAIN}"
echo -e "密码 (Auth)  : ${CYAN}${PASSWORD}${PLAIN}"
echo -e "伪装域名     : ${CYAN}${LINK_SNI}${PLAIN}"
echo -e "端口跳跃     : ${PLAIN}${HOP_MSG}${PLAIN}"
echo -e ""
echo -e "${YELLOW}--- 客户端导入链接 (复制整行) ---${PLAIN}"
echo -e "${GREEN}${HY2_LINK}${PLAIN}"
echo -e "${YELLOW}---------------------------------${PLAIN}"
echo -e ""
echo -e "${RED}⚠️  防火墙设置提醒:${PLAIN}"
echo -e "1. 必须放行 UDP 端口: ${GREEN}${PORT}${PLAIN}"
if [[ "$ENABLE_HOPPING" =~ ^[yY]$ ]]; then
    echo -e "2. 必须放行 UDP 端口范围: ${GREEN}${HOP_START} - ${HOP_END}${PLAIN}"
fi
if [[ "$ENABLE_FULL_MASQ" =~ ^[yY]$ ]]; then
    echo -e "3. 若开启了 TCP 伪装，建议放行 TCP 端口: ${GREEN}80, 443${PLAIN}"
fi
echo -e ""
echo -e "${YELLOW}Cloudflare 用户请注意：必须将小黄云(Proxy)关闭，仅使用 DNS！${PLAIN}"
echo -e ""