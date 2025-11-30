#!/bin/bash

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

# 1. 调用官方脚本进行基础卸载
# ----------------------------------------------------------------
echo -e "${YELLOW}[1/4] 调用官方程序卸载二进制与服务...${PLAIN}"
bash <(curl -fsSL https://get.hy2.sh/) --remove > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}核心程序卸载完成。${PLAIN}"
else
    echo -e "${RED}官方脚本执行出错，尝试强制清理...${PLAIN}"
fi

# 2. 清理配置文件与证书 (官方脚本提示需要手动删除的部分)
# ----------------------------------------------------------------
echo -e "${YELLOW}[2/4] 清理配置文件与证书 (/etc/hysteria)...${PLAIN}"
if [ -d "/etc/hysteria" ]; then
    rm -rf /etc/hysteria
    echo -e "${GREEN}配置目录已删除。${PLAIN}"
else
    echo -e "配置目录不存在，跳过。"
fi

# 3. 清理残留的 Systemd 链接 (官方脚本提示需要手动删除的部分)
# ----------------------------------------------------------------
echo -e "${YELLOW}[3/4] 清理 Systemd 残留链接...${PLAIN}"
rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server.service
rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server@*.service
systemctl daemon-reload
echo -e "${GREEN}Systemd 缓存已刷新。${PLAIN}"

# 4. 删除 hysteria 用户 (官方脚本提示需要手动删除的部分)
# ----------------------------------------------------------------
echo -e "${YELLOW}[4/4] 删除专用系统用户 (hysteria)...${PLAIN}"
if id "hysteria" &>/dev/null; then
    userdel -r hysteria >/dev/null 2>&1
    echo -e "${GREEN}用户已删除。${PLAIN}"
else
    echo -e "用户不存在，跳过。"
fi

# 5. 完成
# ----------------------------------------------------------------
echo -e ""
echo -e "${GREEN}==============================================${PLAIN}"
echo -e "${GREEN}      Hysteria 2 已彻底从服务器移除           ${PLAIN}"
echo -e "${GREEN}==============================================${PLAIN}"
echo -e ""