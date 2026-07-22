# Ubuntu Tailscale Remote Access — Windows 测试分支

分支：`TEST-IN-WINDOWS`

该分支提供 Windows 10/11 x64 的本地安装包和一键安装脚本。安装过程不依赖 Windows Update，因此不会再卡在 `Add-WindowsCapability`。

## 一键安装

1. 下载或克隆 `TEST-IN-WINDOWS` 分支，确认 `windows/packages/` 中有三个 MSI 安装包。
2. 解压后双击：

```text
install-windows.cmd
```

3. 接受管理员权限提示。脚本会依次安装：

```text
Win32-OpenSSH
Tailscale
RustDesk
```

4. 软件安装完成后，脚本会在命令行执行：

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" login
```

浏览器会打开 Tailscale 登录页。请登录与 Ubuntu 设备相同的 Tailscale 账户。

## Tailscale IP

Tailscale IP 由系统自动分配，不需要手动设置。登录成功后执行：

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" ip -4
```

会得到类似：

```text
100.82.36.17
```

在 Ubuntu 上连接 Windows：

```bash
ssh Windows用户名@100.82.36.17
```

RustDesk 直接连接地址：

```text
100.82.36.17:21118
```

## RustDesk 需要手动完成一次设置

打开 RustDesk：

```text
设置 → 安全 → 解锁安全设置
```

开启：

```text
启用直接 IP 访问
设置永久密码
```

脚本会先校验安装包 SHA-256，并创建仅允许 Tailscale 地址段 `100.64.0.0/10` 访问 TCP 22 和 TCP 21118 的防火墙规则。

## 查看状态

管理员 PowerShell：

```powershell
Get-Service sshd,Tailscale,RustDesk -ErrorAction SilentlyContinue
Get-NetTCPConnection -State Listen |
  Where-Object LocalPort -In 22,10808,21118 |
  Sort-Object LocalPort
```

查看 Tailscale 设备：

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" status
```

## 日志

```text
C:\ProgramData\Ubuntu-tailscale-remote-access\logs\
```

## 本分支内置的软件版本

```text
Tailscale 1.98.9 x64 MSI
RustDesk 1.4.9 x64 MSI
Win32-OpenSSH 9.8.3.0 x64 MSI
```

Win32-OpenSSH 9.8.3.0 的 GitHub 发布标签为 Preview。本分支用于测试；正式使用前应在目标 Windows 版本上验证。

安装包来源：

- Tailscale 官方稳定软件包服务器
- RustDesk 官方 GitHub Release
- Microsoft PowerShell/Win32-OpenSSH 官方 GitHub Release

安装包哈希记录在：

```text
windows/packages/SHA256SUMS.txt
```

## 卸载本项目配置

以管理员身份运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\reset-windows.ps1
```

默认只删除项目创建的防火墙规则。加 `-RemovePrograms` 才卸载三个软件：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\windows\reset-windows.ps1 `
  -RemovePrograms
```
