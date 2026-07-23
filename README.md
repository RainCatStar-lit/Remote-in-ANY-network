# Remote in ANY Network

通过 **Tailscale、RustDesk 和 OpenSSH**，在校园网、受限局域网、不同运营商网络或异地网络之间建立远程桌面与 SSH 连接。

无需公网 IP，也无需在路由器上配置端口转发。设备只要能够访问互联网，并登录到同一个 Tailscale 账户，就可以通过 Tailscale 分配的虚拟地址互相连接。

---

## 使用的工具

| 工具 | 用途 | 官方网站 |
|---|---|---|
| Tailscale | 在不同网络中的设备之间建立加密虚拟网络，并分配可互通的虚拟 IP | https://tailscale.com/download |
| RustDesk | 远程查看和控制设备桌面 | https://rustdesk.com/ |
| OpenSSH | SSH 终端、SFTP、VS Code Remote SSH 等远程开发连接 | https://www.openssh.com/ |

Windows OpenSSH 安装说明：

https://learn.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse

---

## 安装方式

可以选择 **手动安装**，也可以进入对应系统分支使用 **快速安装**。

### 手动安装

分别从上述官方网站安装：

1. Tailscale
2. RustDesk
3. OpenSSH Server

手动安装适合以下情况：

- 希望自行选择软件版本；
- 不希望执行自动化脚本；
- 当前系统不在快速安装脚本的支持范围内；
- 需要自行控制代理、防火墙和服务配置。

安装后确认：

- Tailscale 已运行；
- OpenSSH Server 已运行；
- RustDesk 已安装，并允许直接 IP 访问；
- 所有相关服务已设置为开机启动。

### 快速安装

请选择与系统对应的稳定分支，并按照分支内 README 操作：

| 系统 | 稳定分支 |
|---|---|
| Ubuntu 22.04 | [STABLE-IN-22.04](https://github.com/RainCatStar-lit/Remote-in-ANY-network/tree/STABLE-IN-22.04) |
| Windows 10 / 11 64 位 | [STABLE-IN-WINDOWS](https://github.com/RainCatStar-lit/Remote-in-ANY-network/tree/STABLE-IN-WINDOWS) |

开发和测试版本：

| 系统 | 测试分支 |
|---|---|
| Ubuntu 22.04 | [TEST-IN-22.04](https://github.com/RainCatStar-lit/Remote-in-ANY-network/tree/TEST-IN-22.04) |
| Windows 10 / 11 64 位 | [TEST-IN-WINDOWS](https://github.com/RainCatStar-lit/Remote-in-ANY-network/tree/TEST-IN-WINDOWS) |

普通用户优先使用稳定分支。测试分支用于验证新功能、代理处理、安装包更新和兼容性修改。

---

# 安装完成后的操作

## 1. 所有设备登录同一个 Tailscale 账户

在所有需要互相连接的设备上登录同一个 Tailscale 账户。

例如：

```text
Ubuntu 工作站   ─┐
Windows 笔记本   ├─ 同一个 Tailscale 账户
其他远程设备     ─┘
```

Tailscale 登录入口：

https://login.tailscale.com

---

## 2. 在管理页面确认设备

打开 Tailscale 设备管理页面：

https://login.tailscale.com/admin/machines

确认所有设备已经出现，并处于在线状态。

每台设备会获得一个虚拟 IP，通常类似：

```text
100.x.x.x
```

这个地址由 Tailscale 自动分配，不需要手动修改系统网卡。

建议给设备设置容易识别的名称，例如：

```text
rcstation
windows-laptop
ubuntu-px4
lab-workstation
```

---

## 3. 查看 Tailscale IP

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

查看完整状态：

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

VS Code Remote SSH 也可以直接使用相同的 Tailscale IP。

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

部分版本需要显式填写端口：

```text
100.80.20.10:21118
```

应使用目标设备的 Tailscale IP，不要使用校园网、家庭路由器或公网分配的地址。

---

## 常用端口

| 服务 | 默认端口 | 用途 |
|---|---:|---|
| OpenSSH | 22 | SSH、SFTP、远程开发 |
| 常见本地代理 | 10808 | v2rayN 等工具的 HTTP / Mixed 代理示例 |
| RustDesk 直接 IP | 21118 | RustDesk 直接连接 |

实际端口以本机软件配置为准。

Ubuntu 检查监听端口：

```bash
sudo ss -lntup | grep -E ':(22|10808|21118)\b'
```

Windows PowerShell 检查监听端口：

```powershell
Get-NetTCPConnection -State Listen |
  Where-Object LocalPort -In 22,10808,21118 |
  Sort-Object LocalPort
```

---

## 安全建议

- 只使用 Tailscale IP 或 Tailscale 设备名连接；
- 不要在路由器上把 SSH 22 或 RustDesk 21118 直接映射到公网；
- 为 RustDesk 设置强永久密码；
- 定期检查 Tailscale 管理页面中的设备列表；
- 不再使用的设备应及时从 Tailnet 中移除；
- 不要把 Tailscale Auth Key、GitHub Token 或远程控制密码写入仓库；
- Windows 防火墙规则建议仅允许 `100.64.0.0/10` 地址段访问远程服务。

---

## 分支结构

```text
guide
├─ 项目用途
├─ 工具官网
├─ 手动安装
├─ 稳定分支入口
└─ 安装完成后的连接指引

STABLE-IN-22.04
└─ Ubuntu 22.04 稳定快速安装

STABLE-IN-WINDOWS
└─ Windows 10 / 11 稳定快速安装

TEST-IN-22.04
└─ Ubuntu 新功能和兼容性测试

TEST-IN-WINDOWS
└─ Windows 新功能和安装包测试
```

稳定分支只保留运行所需的安装器、脚本、安装包校验信息和简短使用说明。通用工具介绍、手动安装和连接说明统一放在 `guide` 分支。

---

## 支持范围

当前重点支持：

- Ubuntu 22.04
- Windows 10 / Windows 11 64 位
- Tailscale 跨网络连接
- OpenSSH 远程终端
- RustDesk 直接 IP 连接
- 本机 HTTP / Mixed 代理场景

其他系统建议使用手动安装方式。
