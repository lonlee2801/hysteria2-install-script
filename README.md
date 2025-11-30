# hysteria2-install-script
A fast and easy-to-use installation script for Hysteria 2. / Hysteria 2 一键安装与配置脚本。


# Hysteria 2 One-Click Installer Script
# Hysteria 2 一键安装与配置脚本

[![Hysteria 2](https://img.shields.io/badge/Hysteria-v2-blue.svg)](https://github.com/apernet/hysteria)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Language-Bash-orange.svg)](install.sh)

这是一个为 Linux 服务器设计的高效、安全且易于使用的 [Hysteria 2](https://github.com/apernet/hysteria) 部署脚本。它专为简化复杂的配置过程而生，支持自动生成分享链接，一键导入客户端。

## ✨ 功能特性 (Features)

- 🚀 **智能架构识别**：自动检测 `amd64` 或 `arm64` 架构。
- 🔄 **始终最新**：自动抓取 GitHub 官方最新 Release 版本进行安装。
- 🔒 **双模式证书支持**：
    - **自签模式 (推荐)**：无需域名，使用 IP 直连，自动生成自签证书与伪装 SNI。
    - **ACME 模式**：支持自有域名，利用 Hysteria 内置 ACME 自动申请 Let's Encrypt 真实证书。
- 🔑 **安全增强**：默认生成 16 位高强度随机密码，拒绝弱口令。
- 🔗 **一键分享**：安装结束后自动生成标准的 `hy2://` 链接，支持 v2rayN、Nekobox 等主流客户端直接导入。
- ⚙️ **系统级服务**：集成 Systemd，支持开机自启、崩溃重启。

---

## 🛠️ 快速开始 (Quick Start)

### 1. 运行安装脚本
以 **root** 用户身份在终端执行以下命令：

```bash
bash <(curl -fsSL [https://raw.githubusercontent.com/lonlee2801/hysteria2-install-script/main/install.sh](https://raw.githubusercontent.com/lonlee2801/hysteria2-install-script/main/install.sh))
