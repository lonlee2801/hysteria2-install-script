#!/bin/bash

# =========================================================
#  Hysteria 2 One-Click Installer
#  支持：自动安装 / 权限修复 / 带宽设置 / 端口跳跃 / 链接生成
# =========================================================

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

echo -e "${GREEN}=== Hysteria 2 一键安装脚本 ===${PLAIN}"

# 1. 核心安装 (调用官方脚本)
# ----------------------------------------------------------------
echo -e "${YELLOW}[1/6] 正在调用官方脚本安装 Hysteria 2...${PLAIN}"
# 如果 curl 报错，尝试先安装 curl
if ! command -v curl &> /dev/null; then
    apt update && apt install -y curl || yum install -y curl
fi

bash <(curl -fsSL https://get.hy2.sh/)
if [ $? -ne 0 ]; then
    echo -e "${RED}官方脚本安装失败，请检查网络连接。${PLAIN}"
    exit 1
fi

# 2. 用户交互配置
# ----------------------------------------------------------------
echo -e "${YELLOW}[2/6] 开始配置参数...${PLAIN}"

# --- 2.1 基础端口 ---
read -p "请输入主监听端口 [默认 443]: " PORT
PORT=${PORT:-443}

# --- 2.2 密码 ---
read -p "请输入认证密码 [回车随机生成]: " PASSWORD
if [[ -z "$PASSWORD" ]]; then
    PASSWORD=$(openssl rand -hex 8)
    echo -e "已生成随机密码: ${GREEN}$PASSWORD${PLAIN}"
fi

# --- 2.3 带宽设置 (Bandwidth) ---
echo -e "${YELLOW}--- 带宽设置 (单位: Mbps) ---${PLAIN}"
read -p "请输入服务器上传速度 (即客户端下载) [默认 100]: " BW_UP
BW_UP=${BW_UP:-100}

read -p "请输入服务器下载速度 (即客户端上传) [默认 50]: " BW_DOWN
BW_DOWN=${BW_DOWN:-50}

# --- 2.4 端口跳跃 (Port Hopping) ---
echo -e "${YELLOW}--- 端口跳跃 (Port Hopping) ---${PLAIN}"
echo -e "作用: 应对运营商针对单一端口的限速或阻断 (QoS)。"
read -p "是否开启端口跳跃? (y/n) [默认 n]: " ENABLE_HOPPING
ENABLE_HOPPING=${ENABLE_HOPPING:-n}

LISTEN_CONF=":$PORT"
MPORT_PARAM=""
HOP_MSG="禁用"

if [[ "$ENABLE_HOPPING" == "y" || "$ENABLE_HOPPING" == "Y" ]]; then
    read -p "请输入跳跃起始端口 (Start) [默认 20000]: " HOP_START
    HOP_START=${HOP_START:-20000}
    
    read -p "请输入跳跃结束端口 (End) [默认 30000]: " HOP_END
    HOP_END=${HOP_END:-30000}
    
    if [[ $HOP_END -le $HOP_START ]]; then
        echo -e "${RED}错误：结束端口必须大于起始端口!${PLAIN}"
        exit 1
    fi

    # 配置监听格式: ":443,:20000-30000"
    LISTEN_CONF=":$PORT,:$HOP_START-$HOP_END"
    # 链接参数: "&mport=20000-30000"
    MPORT_PARAM="&mport=$HOP_START-$HOP_END"
    HOP_MSG="${GREEN}启用 ($HOP_START-$HOP_END)${PLAIN}"
    
    echo -e "端口跳跃已设置为: $HOP_START 至 $HOP_END"
fi

# --- 2.5 证书模式 ---
echo -e "${YELLOW}--- 证书模式 ---${PLAIN}"
echo -e "  1) 自签证书 (推荐，使用 IP 直连，更稳定)"
echo -e "  2) 自有域名 (ACME，自动申请真实证书)"
read -p "请选择 [默认 1]: " CERT_MODE
CERT_MODE=${CERT_MODE:-1}

# 3. 生成配置文件与证书
# ----------------------------------------------------------------
echo -e "${YELLOW}[3/6] 生成配置与证书...${PLAIN}"

CONFIG_FILE="/etc/hysteria/config.yaml"

if [[ "$CERT_MODE" == "2" ]]; then
    # === ACME 模式 ===
    read -p "请输入你的域名 (确保已解析到本机 IP): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then echo -e "${RED}域名不能为空!${PLAIN}"; exit 1; fi
    
cat << EOF > $CONFIG_FILE
listen: $LISTEN_CONF

acme:
  domains:
    - $DOMAIN
  email: admin@$DOMAIN

auth:
  type: password
  password: "$PASSWORD"

bandwidth:
  up: $BW_UP mbps
  down: $BW_DOWN mbps

ignoreClientBandwidth: false
EOF

    LINK_HOST=$DOMAIN
    LINK_SNI=$DOMAIN
    LINK_INSECURE=0

else
    # === 自签模式 (默认) ===
    read -p "请输入伪装域名 [默认 bing.com]: " BING_DOMAIN
    BING_DOMAIN=${BING_DOMAIN:-bing.com}

    echo -e "正在生成 ECC 自签证书..."
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout /etc/hysteria/server.key \
        -out /etc/hysteria/server.crt \
        -subj "/CN=$BING_DOMAIN" \
        -days 36500

    # 权限修复
    echo -e "正在修复证书权限..."
    chown hysteria:hysteria /etc/hysteria/server.key
    chown hysteria:hysteria /etc/hysteria/server.crt

cat << EOF > $CONFIG_FILE
listen: $LISTEN_CONF

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: "$PASSWORD"

masquerade:
  type: proxy
  proxy:
    url: https://$BING_DOMAIN
    rewriteHost: true

bandwidth:
  up: $BW_UP mbps
  down: $BW_DOWN mbps

ignoreClientBandwidth: false
EOF

    PUBLIC_IP=$(curl -s4 ifconfig.me)
    LINK_HOST=$PUBLIC_IP
    LINK_SNI=$BING_DOMAIN
    LINK_INSECURE=1
fi

# 4. 服务管理
# ----------------------------------------------------------------
echo -e "${YELLOW}[4/6] 重启服务并设置开机自启...${PLAIN}"
systemctl enable hysteria-server.service
systemctl restart hysteria-server.service

sleep 2
if systemctl is-active --quiet hysteria-server.service; then
    echo -e "${GREEN}Hysteria 2 服务启动成功!${PLAIN}"
else
    echo -e "${RED}服务启动失败! 请查看错误日志: journalctl -u hysteria-server.service -e${PLAIN}"
    # 尝试打印最后的日志帮助除错
    journalctl -u hysteria-server.service -n 10 --no-pager
    exit 1
fi

# 5. 生成分享链接
# ----------------------------------------------------------------
echo -e "${YELLOW}[5/6] 生成客户端连接信息...${PLAIN}"

# 拼接完整的 hy2:// 链接
HY2_LINK="hy2://${PASSWORD}@${LINK_HOST}:${PORT}/?insecure=${LINK_INSECURE}&sni=${LINK_SNI}${MPORT_PARAM}#Hy2-${LINK_HOST}"

# 6. 最终输出
# ----------------------------------------------------------------
echo -e ""
echo -e "${GREEN}==============================================${PLAIN}"
echo -e "${GREEN}         Hysteria 2 安装与配置完成            ${PLAIN}"
echo -e "${GREEN}==============================================${PLAIN}"
echo -e ""
echo -e "地址 (Host)      : ${PLAIN}${LINK_HOST}${PLAIN}"
echo -e "端口 (Port)      : ${PLAIN}${PORT}${PLAIN}"
echo -e "密码 (Auth)      : ${PLAIN}${PASSWORD}${PLAIN}"
echo -e "带宽限制         : ${PLAIN}Up:${BW_UP}m / Down:${BW_DOWN}m${PLAIN}"
echo -e "端口跳跃 (Hop)   : ${PLAIN}${HOP_MSG}${PLAIN}"
echo -e "伪装域名 (SNI)   : ${PLAIN}${LINK_SNI}${PLAIN}"
echo -e ""
echo -e "${YELLOW}--- 客户端导入链接 (复制下方内容) ---${PLAIN}"
echo -e "${GREEN}${HY2_LINK}${PLAIN}"
echo -e "${YELLOW}------------------------------------${PLAIN}"
echo -e ""
echo -e "${RED}⚠️ 重要提示 (防火墙设置):${PLAIN}"
echo -e "1. 请务必在服务器安全组放行 UDP 端口: ${GREEN}${PORT}${PLAIN}"
if [[ "$ENABLE_HOPPING" == "y" || "$ENABLE_HOPPING" == "Y" ]]; then
    echo -e "2. 由于开启了端口跳跃，你还必须放行 UDP 端口范围: ${GREEN}${HOP_START} - ${HOP_END}${PLAIN}"
    echo -e "   (例如: AWS设置: Type=Custom UDP, Port range=${HOP_START}-${HOP_END}, Source=0.0.0.0/0)"
fi
echo -e ""