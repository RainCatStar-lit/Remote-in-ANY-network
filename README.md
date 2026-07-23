# Ubuntu Tailscale Remote Access

使用 Tailscale、OpenSSH 和 RustDesk，在不同网络之间连接 Ubuntu 22.04 或 Windows 10/11 工作站。

`main` 分支只保留快速入口和说明。QuickInstaller 检测当前系统，然后从对应测试分支下载所需脚本和安装包，不需要下载整个分支 ZIP。

## 支持的系统

| 当前系统 | 自动选择的分支 | 安装内容 |
|---|---|---|
| Ubuntu 22.04 x64 | `TEST-IN-22.04` | OpenSSH、Tailscale、RustDesk、开机启动和连接摘要 |
| Windows 10/11 x64 | `TEST-IN-WINDOWS` | Win32-OpenSSH、Tailscale、RustDesk、防火墙和连接摘要 |

其他系统会停止，不会继续修改系统。

## Ubuntu 22.04 快速安装

下载小型入口脚本：

```bash
curl -fsSL \
  https://raw.githubusercontent.com/RainCatStar-lit/Remote-in-ANY-network/main/QuickInstaller.sh \
  -o /tmp/QuickInstaller.sh
```

校园网需要本机代理时：

```bash
sudo bash /tmp/QuickInstaller.sh \
  --proxy http://127.0.0.1:10808
```

可以直连 GitHub 时：

```bash
sudo bash /tmp/QuickInstaller.sh
```

QuickInstaller 只先下载 `TEST-IN-22.04/install.sh`。该安装器再按步骤获取 Linux 模块，不会克隆整个仓库。

常用参数：

```text
--no-rustdesk     不安装 RustDesk
--keep-wayland    保留 Wayland
--keep-sleep      保留休眠设置
--skip-login      暂不登录 Tailscale
```

## Windows 10/11 快速安装

从 `main` 分支只下载：

```text
QuickInstaller.cmd
```

双击运行并接受管理员权限提示。脚本会：

1. 检测 64 位 Windows 10/11。
2. 自动选择 `TEST-IN-WINDOWS`。
3. 下载分支安装器和 SHA-256 清单。
4. 仅下载当前缺少的软件包；已缓存且哈希正确的 MSI 不会重复下载。
5. 安装软件并执行：

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" login
```

浏览器打开后，登录与另一台设备相同的 Tailscale 账户。

PowerShell 也可以直接运行：

```powershell
$Url = "https://raw.githubusercontent.com/RainCatStar-lit/Remote-in-ANY-network/main/QuickInstaller.ps1"
$File = "$env:TEMP\RCS-QuickInstaller.ps1"
Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $File
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $File
```

使用本机代理：

```powershell
PowerShell.exe -NoProfile -ExecutionPolicy Bypass `
  -File $File `
  -Proxy "http://127.0.0.1:10808"
```

## 登录后查看 Tailscale IP

Ubuntu：

```bash
tailscale ip -4 2>/dev/null || sudo /snap/bin/tailscale ip -4
```

Windows：

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" ip -4
```

输出类似：

```text
100.82.36.17
```

该地址由 Tailscale 自动分配，不需要手动修改网卡 IP。

## 连接方式

SSH：

```text
ssh 用户名@100.x.x.x
```

RustDesk 直接 IP：

```text
100.x.x.x:21118
```

RustDesk 安装完成后仍需打开一次：

```text
设置 → 安全 → 解锁安全设置
启用直接 IP 访问
设置永久密码
```

## 查看端口

Ubuntu：

```bash
sudo ss -lntup | grep -E ':(22|10808|21118)\b'
```

Windows 管理员 PowerShell：

```powershell
Get-NetTCPConnection -State Listen |
  Where-Object LocalPort -In 22,10808,21118 |
  Sort-Object LocalPort
```

端口用途：

```text
22       OpenSSH
10808    常见本机 HTTP/Mixed 代理端口
21118    RustDesk 直接 IP
```

## 日志

Ubuntu：

```text
/var/log/ubuntu-tailscale-remote-access/
```

Windows：

```text
C:\ProgramData\Ubuntu-tailscale-remote-access\logs\
```

Windows 下载缓存：

```text
C:\ProgramData\Ubuntu-tailscale-remote-access\quick-installer\
```

## 分支结构

```text
main
  QuickInstaller.sh
  QuickInstaller.cmd
  QuickInstaller.ps1
  README.md

TEST-IN-22.04
  Ubuntu 22.04 完整安装器和 Linux 模块

TEST-IN-WINDOWS
  Windows 完整安装器、MSI 和 SHA-256 清单
```

## 安全说明

防火墙规则只允许 Tailscale 地址段 `100.64.0.0/10` 访问 SSH 和 RustDesk 直接连接端口。不要在路由器上转发 TCP 22 或 TCP 21118，也不要把 RustDesk 永久密码写入脚本或仓库。
