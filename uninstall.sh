#!/bin/bash

# =========================================================
#  Hysteria 2 彻底卸载脚本 (Ultimate Uninstaller)
#  功能：卸载程序 / 删除配置 / 清理用户 / 移除 iptables 转发
# =========================================================

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查 Root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：必须使用 root 权限运行此脚本！${PLAIN}"
    exit 1
fi

echo -e "${RED}=================================================${PLAIN}"
echo -e "${RED}    即将彻底卸载 Hysteria 2 并清除所有数据    ${PLAIN}"
echo -e "${RED}=================================================${PLAIN}"
read -p "确认继续吗? [y/n]: " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${YELLOW}已取消。${PLAIN}"
    exit 0
fi

# =========================================================
# 1. 智能检测配置 (为了清理 iptables)
# =========================================================
LOCAL_PORT=""
if [ -f "/etc/hysteria/config.yaml" ]; then
    # 提取 listen 端口 (例如 :443 -> 443)
    # 逻辑：查找 listen 行，去掉空格，去掉冒号
    LOCAL_PORT=$(grep "^listen:" /etc/hysteria/config.yaml | awk '{print $2}' | tr -d ':')
    
    if [[ ! -z "$LOCAL_PORT" ]]; then
        echo -e "${YELLOW}[信息] 检测到当前监听端口为: ${LOCAL_PORT}${PLAIN}"
    fi
fi

# =========================================================
# 2. 清理 IPTables 端口跳跃规则
# =========================================================
echo -e "${YELLOW}[1/5] 检查并清理端口跳跃规则 (iptables)...${PLAIN}"

if [[ ! -z "$LOCAL_PORT" ]]; then
    # 查找 nat 表中所有转发到该端口的规则
    # 逻辑：遍历所有包含 "REDIRECT --to-ports 端口" 的规则并删除
    COUNT=0
    iptables -t nat -S PREROUTING | grep "REDIRECT --to-ports $LOCAL_PORT" | while read -r rule; do
        # 移除规则开头的 "-A " (Append)，只保留参数
        rule_params=${rule#"-A "}
        # 执行删除 (-D)
        iptables -t nat -D $rule_params
        echo -e "  已删除规则: iptables -t nat -D $rule_params"
        ((COUNT++))
    done
    
    # 保存更改
    if [ -x "$(command -v netfilter-persistent)" ]; then
        netfilter-persistent save >/dev/null 2>&1
    elif [ -x "$(command -v service)" ]; then
        service iptables save >/dev/null 2>&1
    fi
    
    echo -e "${GREEN}iptables 清理完毕。${PLAIN}"
else
    echo -e "未检测到端口配置或规则，跳过 iptables 清理。"
fi

# =========================================================
# 3. 调用官方卸载逻辑
# =========================================================
echo -e "${YELLOW}[2/5] 调用官方程序卸载核心...${PLAIN}"
bash <(curl -fsSL https://get.hy2.sh/) --remove > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}二进制文件与服务已移除。${PLAIN}"
else
    echo -e "${RED}官方卸载步骤可能遇到问题，尝试强制清理...${PLAIN}"
    # 强制停止服务
    systemctl stop hysteria-server >/dev/null 2>&1
    systemctl disable hysteria-server >/dev/null 2>&1
    rm -f /usr/local/bin/hysteria
fi

# =========================================================
# 4. 清理配置文件
# =========================================================
echo -e "${YELLOW}[3/5] 删除配置文件与证书...${PLAIN}"
rm -rf /etc/hysteria
echo -e "${GREEN}目录 /etc/hysteria 已删除。${PLAIN}"

# =========================================================
# 5. 清理 Systemd 残留
# =========================================================
echo -e "${YELLOW}[4/5] 清理 Systemd 链接...${PLAIN}"
rm -f /etc/systemd/system/hysteria-server.service
rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server.service
systemctl daemon-reload

# =========================================================
# 6. 删除用户
# =========================================================
echo -e "${YELLOW}[5/5] 删除 hysteria 用户...${PLAIN}"
if id "hysteria" &>/dev/null; then
    userdel -r hysteria >/dev/null 2>&1
    echo -e "${GREEN}用户已删除。${PLAIN}"
else
    echo -e "用户不存在，跳过。"
fi

# =========================================================
# 完成
# =========================================================
echo -e ""
echo -e "${GREEN}==============================================${PLAIN}"
echo -e "${GREEN}   Hysteria 2 及所有相关规则已彻底移除        ${PLAIN}"
echo -e "${GREEN}==============================================${PLAIN}"
echo -e ""