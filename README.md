# Remote in ANY Network

使用 **Tailscale、RustDesk 和 OpenSSH**，在校园网、受限局域网、异地网络或不同运营商网络之间建立远程桌面与 SSH 连接。

无需公网 IP，无需在路由器上配置端口转发。设备只要能够访问互联网并登录到同一个 Tailscale 账户，就可以通过 Tailscale 分配的虚拟 IP 互相连接。

---

## 项目用途

本项目用于解决以下场景：

- Windows 笔记本远程控制 Ubuntu 工作站桌面；
- 在外部网络中通过 SSH 连接实验室、宿舍或办公室设备；
- 在校园网、公司网络等受限环境中建立设备间连接；
- 避免直接向公网暴露 SSH、RustDesk 或其他远程服务端口；
- 为 Ubuntu 22.04 和 Windows 10/11 提供可复用的快速安装流程。

项目结构：

```text
Tailscale：建立跨网络虚拟局域网
RustDesk：远程桌面
OpenSSH：远程终端、文件传输和开发连接
```

---

## 使用的工具

| 工具 | 用途 | 官方网站 |
|---|---|---|
| **Tailscale** | 为不同网络中的设备建立加密虚拟网络，并分配可互通的虚拟 IP | [tailscale.com/download](https://tailscale.com/download) |
| **RustDesk** | 远程查看和控制设备桌面 | [rustdesk.com](https://rustdesk.com/) |
| **OpenSSH** | SSH 终端、SFTP、VS Code Remote SSH 等远程开发连接 | [openssh.com](https://www.openssh.com/) |

Windows OpenSSH 说明：
[Microsoft OpenSSH 文档](https://learn.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse)

---

## 安装方式

可以选择 **手动安装**，也可以进入对应系统分支使用 **快速安装**。

### 方式一：手动安装

分别从上述官方网站安装：

1. Tailscale
2. RustDesk
3. OpenSSH Server

适合以下情况：

- 希望自行选择软件版本；
- 不希望执行自动化脚本；
- 当前系统不在自动安装脚本的测试范围内；
- 需要手动控制防火墙、代理或服务配置。

### 方式二：快速安装

| 系统 | 使用分支 | 说明 |
|---|---|---|
| **Ubuntu 22.04** | [`TEST-IN-22.04`](https://github.com/RainCatStar-lit/Remote-in-ANY-network/tree/TEST-IN-22.04) | 自动安装并配置 Tailscale、OpenSSH 和 RustDesk |
| **Windows 10 / 11 64 位** | [`TEST-IN-WINDOWS`](https://github.com/RainCatStar-lit/Remote-in-ANY-network/tree/TEST-IN-WINDOWS) | 提供快速安装器、本地安装入口及 Windows 安装包 |
| **其他系统** | 手动安装 | 按各工具官方文档安装 |

`main` 分支用于项目总览、统一说明和分支入口。

---

## Ubuntu 22.04 快速安装

克隆 Ubuntu 分支：

```bash
git clone --branch TEST-IN-22.04 \
  https://github.com/RainCatStar-lit/Remote-in-ANY-network.git

cd Remote-in-ANY-network
sudo bash install.sh
```

使用本机 HTTP 或 Mixed 代理时，例如代理端口为 `10808`：

```bash
sudo bash install.sh \
  --proxy http://127.0.0.1:10808
```

仅测试 Tailscale 和 SSH，不安装 RustDesk、不修改休眠和 Wayland：

```bash
sudo bash install.sh \
  --proxy http://127.0.0.1:10808 \
  --no-rustdesk \
  --keep-wayland \
  --keep-sleep
```

安装程序会优先尝试 Tailscale 官方软件源；官方软件源不可用时自动回退到 Snap。

安装完成后会显示：

```text
Tailscale IPv4
SSH 连接命令
RustDesk 直接 IP 地址
SSH、代理和 RustDesk 相关端口状态
安装日志位置
```

---

## Windows 10 / 11 快速安装

进入 Windows 分支：

[打开 `TEST-IN-WINDOWS`](https://github.com/RainCatStar-lit/Remote-in-ANY-network/tree/TEST-IN-WINDOWS)

### 快速安装器

下载以下两个文件，并放在同一目录：

```text
quick-install.cmd
quick-install.ps1
```

双击：

```text
quick-install.cmd
```

快速安装器会下载 `TEST-IN-WINDOWS` 分支内容，并启动管理员安装程序。

### 完整本地安装

也可以下载整个 Windows 分支 ZIP，解压后双击：

```text
install-windows.cmd
```

该方式直接使用分支中提供的安装文件，不依赖 Windows Update 安装 OpenSSH。

安装完成后，Tailscale 会给出登录入口。按照浏览器提示登录即可。

---

# 安装完成后的操作

## 1. 所有设备登录同一个 Tailscale 账户

在所有需要互相连接的设备上登录 **同一个 Tailscale 账户**。

例如：

```text
Ubuntu 工作站   ─┐
Windows 笔记本   ├─ 登录同一个 Tailscale 账户
其他远程设备     ─┘
```

Tailscale 登录入口：
[login.tailscale.com](https://login.tailscale.com/)

---

## 2. 在管理页面确认设备

打开 Tailscale 管理页面：

[login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines)

确认所有设备已经出现，并处于在线状态。

每台设备会获得一个虚拟 IP，通常类似：

```text
100.x.x.x
```

这个地址由 Tailscale 自动分配，不需要手动修改系统网卡。

建议为设备设置容易识别的名称，例如：

```text
rcstation
windows-laptop
ubuntu-px4
lab-workstation
```

---

## 3. 查看设备的 Tailscale IP

### Ubuntu

APT 版本：

```bash
tailscale ip -4
```

Snap 版本：

```bash
sudo /snap/bin/tailscale ip -4
```

兼容写法：

```bash
tailscale ip -4 2>/dev/null \
  || sudo /snap/bin/tailscale ip -4
```

### Windows PowerShell

```powershell
& "$env:ProgramFiles\Tailscale\tailscale.exe" ip -4
```

查看完整设备状态：

```powershell
& "$env:ProgramFiles\Tailscale\tailscale.exe" status
```

---

## 4. 使用 Tailscale IP 建立 SSH 连接

假设目标设备的 Tailscale IP 为：

```text
100.80.20.10
```

连接 Ubuntu：

```bash
ssh Ubuntu用户名@100.80.20.10
```

连接 Windows：

```bash
ssh Windows用户名@100.80.20.10
```

例如：

```bash
ssh rcs@100.80.20.10
```

目标设备必须已经安装并启动 OpenSSH Server。

VS Code Remote SSH 也可以直接使用同一个地址。

---

## 5. 使用 Tailscale IP 建立 RustDesk 连接

在被控设备的 RustDesk 中完成：

```text
设置
→ 安全
→ 解锁安全设置
→ 启用直接 IP 访问
→ 设置永久密码
```

在控制端 RustDesk 中输入目标设备的 Tailscale IP：

```text
100.80.20.10
```

部分 RustDesk 版本需要显式填写端口：

```text
100.80.20.10:21118
```

RustDesk 连接使用的是目标设备的 **Tailscale IP**，不是校园网、家庭路由器或公网分配的地址。

---

## 连接结构

```text
Windows 笔记本 ─┐
Ubuntu 工作站  ─┼─ Tailscale 虚拟网络 ─ SSH / RustDesk
其他设备       ─┘
```

设备可以位于：

- 同一局域网；
- 不同局域网；
- 校园网或受限网络；
- 家庭网络与实验室网络；
- 不同城市或不同运营商网络。

---

## 常用端口

| 服务 | 默认端口 | 用途 |
|---|---:|---|
| OpenSSH | `22` | SSH、SFTP、远程开发 |
| 常见本地代理 | `10808` | v2rayN 等工具的 HTTP / Mixed 代理示例 |
| RustDesk 直接 IP | `21118` | RustDesk 直接连接 |

实际端口以本机软件配置为准。

检查 Ubuntu 监听端口：

```bash
sudo ss -lntup | grep -E ':(22|10808|21118)\b'
```

检查 Windows 监听端口：

```powershell
Get-NetTCPConnection -State Listen |
  Where-Object LocalPort -In 22,10808,21118 |
  Sort-Object LocalPort
```

---

## 安全建议

- 只使用 Tailscale IP 或 Tailscale 设备名连接；
- 不要在路由器上把 SSH `22` 或 RustDesk `21118` 直接映射到公网；
- 为 RustDesk 设置强永久密码；
- 定期检查 Tailscale 管理页面中的设备列表；
- 不再使用的设备应及时从 Tailnet 中移除；
- 不要把 Tailscale Auth Key、GitHub Token 或远程控制密码写入仓库；
- Windows 防火墙规则建议仅允许 `100.64.0.0/10` 地址段访问远程服务。

---

## 分支说明

```text
main
├─ 项目总览与统一使用说明
│
├─ TEST-IN-22.04
│  └─ Ubuntu 22.04 快速安装、代理处理和安装日志
│
└─ TEST-IN-WINDOWS
   └─ Windows 10 / 11 快速安装器与本地安装包
```

---

## 当前测试范围

已重点测试：

- Ubuntu 22.04
- Windows 10 / Windows 11 64 位
- Tailscale 跨网络连接
- OpenSSH 远程终端
- RustDesk 直接 IP 连接
- 本机 HTTP / Mixed 代理场景

其他 Linux 发行版暂不保证自动安装脚本可用，建议使用手动安装方式。

---

## 仓库地址

```text
https://github.com/RainCatStar-lit/Remote-in-ANY-network
```
