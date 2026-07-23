# Windows Stable Installer

分支：`STABLE-IN-WINDOWS`

该分支用于在 Windows 10 / 11 64 位系统上快速安装 Win32-OpenSSH、Tailscale 和 RustDesk。

## 安装

进入分支页面：

https://github.com/RainCatStar-lit/Remote-in-ANY-network/tree/STABLE-IN-WINDOWS

推荐方式：下载整个分支 ZIP，解压后双击：

```text
install-windows.cmd
```

也可以把以下两个文件放在同一目录后运行快速安装器：

```text
quick-install.cmd
quick-install.ps1
```

接受管理员权限提示后，安装器会：

- 校验本地安装包；
- 安装并启用 Win32-OpenSSH；
- 安装 Tailscale；
- 安装 RustDesk；
- 创建仅允许 Tailscale 地址段访问的防火墙规则；
- 打开 Tailscale 登录流程；
- 显示 Tailscale IP、SSH 命令和相关端口。

## 安装完成后

在浏览器中登录与其他设备相同的 Tailscale 账户。

PowerShell 查看地址：

```powershell
& "$env:ProgramFiles\Tailscale\tailscale.exe" ip -4
```

RustDesk 还需要在图形界面中启用直接 IP 访问并设置永久密码。

完整连接说明：

https://github.com/RainCatStar-lit/Remote-in-ANY-network/tree/guide
