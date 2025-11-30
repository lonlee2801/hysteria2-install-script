# Hysteria 2 一键安装脚本

[![Hysteria 2](https://img.shields.io/badge/Hysteria-v2-blue.svg)](https://github.com/apernet/hysteria)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Language-Bash-orange.svg)](install.sh)

这是一个基于 **Hysteria 2 官方内核** 的全功能一键部署脚本。它专为追求高性能和高稳定性的用户设计，集成了带宽管理、端口跳跃（Port Hopping）和自动证书配置功能。

## ✨ 核心特性 (Features)
- 🔄 **始终最新**：自动抓取 GitHub 官方最新 Release 版本进行安装。
- ⚡ **带宽控制**：支持自定义服务端上/下行带宽，发挥 Brutal 协议的最大加速效果（网页秒开）。
- 🦘 **端口跳跃 (Port Hopping)**：一键配置端口跳跃范围，有效对抗运营商针对单一 UDP 端口的限速 (QoS) 和阻断。
- 🔒 **双模式证书支持**：
    - **自签模式 (推荐)**：无需域名，使用 IP 直连，自动生成自签证书与伪装 SNI。
    - **ACME 模式**：支持自有域名，利用 Hysteria 内置 ACME 自动申请 Let's Encrypt 真实证书。
- 🔑 **安全增强**：默认生成 16 位高强度随机密码，拒绝弱口令。
- 🔗 **一键分享**：安装结束后自动生成标准的 `hy2://` 链接，支持 v2rayN、Nekobox 等主流客户端直接导入。
- ⚙️ **系统级服务**：集成 Systemd，支持开机自启、崩溃重启。
---

## 🚀 快速安装 (Quick Start)

推荐使用 **Debian 10+** / **Ubuntu 20.04+** 系统。请以 **root** 用户身份运行：
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lonlee2801/hysteria2-install-script/main/install.sh)


## 🗑️ 卸载 (Uninstall)

调用官方卸载逻辑，并清理相关文件：
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lonlee2801/hysteria2-install-script/main/uninstall.sh)
