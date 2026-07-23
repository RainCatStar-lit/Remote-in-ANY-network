# Windows 稳定版安装

该分支用于在 **Windows 10 / Windows 11 64 位系统**上快速安装并配置：

- Win32-OpenSSH
- Tailscale
- RustDesk

## 快速安装

下载当前分支的完整 ZIP 文件并解压，然后双击：

```text
install-windows.cmd
```

根据系统提示授予管理员权限。

安装器将自动完成：

- 校验本地安装包；
- 安装并启用 Win32-OpenSSH；
- 安装 Tailscale；
- 安装 RustDesk；
- 创建仅允许 Tailscale 地址段访问的防火墙规则；
- 启动 Tailscale 登录流程；
- 显示 Tailscale IP、SSH 连接命令和相关端口状态。
- 完成 Tailscale 登录

安装过程中，PowerShell 会显示一个 Tailscale 登录链接，例如：

```text
https://login.tailscale.com/a/1a12345678900
```

在浏览器中打开该链接，并登录与其他设备相同的 Tailscale 账户。

登录完成后，当前 Windows 设备会加入同一个 Tailscale 网络，并获得一个类似下面的虚拟 IP：

```text
100.x.x.x
```

后续 SSH 和 RustDesk 连接都使用该 Tailscale IP。

## 下一步

完成安装后，可返回项目引导页：

- 为其他设备安装对应客户端；
- 查看 Tailscale 设备管理方式；
- 使用 SSH 建立远程终端连接；
- 使用 RustDesk 建立远程桌面连接。

项目引导页：

https://github.com/RainCatStar-lit/Remote-in-ANY-network/tree/guide
