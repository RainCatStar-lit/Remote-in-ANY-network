# Ubuntu / Windows Tailscale Remote Access

用于快速部署以下远程访问链路：

```text
Tailscale：提供跨校园网、跨 NAT 的私有 IP
OpenSSH ：提供终端连接
RustDesk：通过 Tailscale IP 直接访问图形桌面
```

脚本不内置、不生成、不上传任何账号密码或 Tailscale Auth Key。

## 支持范围

- Ubuntu 20.04 及以上版本，重点适配 Ubuntu 22.04
- Debian 系发行版，需要 `apt` 和 `systemd`
- Windows 10 1809 及以上版本、Windows 11
- Windows 运行 `install.sh` 需要 **Git Bash**，不要在 WSL 中运行

## Linux 一键部署

```bash
curl -fsSL \
  https://raw.githubusercontent.com/RainCatStar-lit/Ubuntu-tailscale-remote-access/main/install.sh \
  -o /tmp/remote-access-install.sh && \
sudo bash /tmp/remote-access-install.sh
```

脚本会暂停并显示 Tailscale 登录链接。使用浏览器登录后，脚本继续完成检查并显示 Tailscale IP。

## Windows 一键部署

以普通方式打开 **Git Bash**，执行：

```bash
curl -fsSL \
  https://raw.githubusercontent.com/RainCatStar-lit/Ubuntu-tailscale-remote-access/main/install.sh \
  -o install.sh && \
bash install.sh
```

脚本会自动请求管理员权限。Windows 不原生执行 `.sh`，所以这里使用 Git Bash；不要在 WSL 中运行。

## 脚本执行内容

脚本会自动：

1. 检测 Windows 或 Linux 及系统版本。
2. 安装并启用 OpenSSH Server。
3. 安装并启用 Tailscale。
4. 安装 RustDesk，并尽可能启用系统服务。
5. 设置相关服务开机自启。
6. 关闭工作站接通电源时的自动睡眠。
7. 将 SSH 和 RustDesk 直连端口限制为 Tailnet 访问。
8. Linux 使用 GDM 时切换到 X11，以支持登录界面的远程访问。
9. 引导用户登录 Tailscale，并显示最终连接地址。
10. 保存本次安装的完整终端输出日志。

## 安装日志

每次运行都会创建独立日志文件，便于故障排查和分发反馈。脚本只记录终端输出，不主动记录密码、Tailscale Auth Key 或 RustDesk 永久密码。

Linux：

```text
/var/log/Ubuntu-tailscale-remote-access/install-YYYYMMDD-HHMMSS.log
```

查看最新日志：

```bash
ls -1t /var/log/Ubuntu-tailscale-remote-access/install-*.log | head -n 1
sudo less "$(ls -1t /var/log/Ubuntu-tailscale-remote-access/install-*.log | head -n 1)"
```

Windows：

```text
C:\ProgramData\Ubuntu-tailscale-remote-access\logs\install-YYYYMMDD-HHMMSS.log
```

安装结束时，脚本会再次显示本次日志的完整路径。日志可能包含系统版本、主机名和 Tailscale IP，公开提交前应先检查。

## Tailscale 登录

运行脚本后，终端会出现登录链接。打开链接，使用两台设备共同加入的同一 Tailscale 账户或 Tailnet 登录。

<!-- 将图片保存为 docs/images/tailscale-login.png -->
![Tailscale 登录示意图](docs/images/tailscale-login.png)

登录完成后查看本机地址：

```bash
tailscale ip -4
```

输出类似：

```text
100.88.12.34
```

## RustDesk 必须手动完成的一项设置

脚本不会配置任何密码。打开 RustDesk，进入：

```text
设置 -> 安全 -> 启用直接 IP 访问
```

如需无人值守访问，再由设备所有者手动设置永久密码。

<!-- 将图片保存为 docs/images/rustdesk-direct-ip.png -->
![RustDesk 直接 IP 访问设置](docs/images/rustdesk-direct-ip.png)

RustDesk 直接访问端口默认为：

```text
21118
```

## 使用 Tailscale IP 连接

所有远程功能均使用 Tailscale 分配的 `100.x.x.x` 地址，**不要使用校园网 IP**。

### SSH

```bash
ssh 用户名@100.88.12.34
```

例如：

```bash
ssh rcs@100.88.12.34
```

### RustDesk

在 RustDesk 连接框输入：

```text
100.88.12.34:21118
```

这种方式不依赖 RustDesk 公共 ID 路由完成寻址，适合存在客户端隔离、NAT 或远程控制平台限制的校园网。

## Linux 完成后重启

脚本修改了 GDM 的显示服务器设置时，需要重启：

```bash
sudo reboot
```

## 快速检查

Linux：

```bash
systemctl is-enabled ssh tailscaled
systemctl is-active ssh tailscaled
tailscale status
tailscale ip -4
```

Windows PowerShell：

```powershell
Get-Service sshd, Tailscale, RustDesk
tailscale status
tailscale ip -4
```

从另一台设备测试：

```bash
tailscale ping 100.88.12.34
ssh 用户名@100.88.12.34
```

## 安全说明

- 仓库和脚本中不应提交密码、Auth Key、订阅链接或私钥。
- Tailscale 登录由用户在官方登录页面完成。
- SSH 使用系统现有账户认证；建议后续配置 SSH 公钥。
- RustDesk 永久密码由用户本人在客户端中设置。
- Windows 防火墙规则只允许 Tailscale 地址段访问 TCP 22 和 TCP 21118。
- Linux 已启用 UFW 时，脚本只允许 `tailscale0` 访问这两个端口。

## 官方参考

- [Tailscale Linux 安装](https://tailscale.com/kb/1031/install-linux)
- [Tailscale Windows 安装](https://tailscale.com/kb/1022/install-windows)
- [Microsoft OpenSSH Server for Windows](https://learn.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse)
- [RustDesk Linux 客户端](https://rustdesk.com/docs/zh-cn/client/linux/)
- [RustDesk 客户端配置](https://rustdesk.com/docs/zh-cn/self-host/client-configuration/advanced-settings/)
