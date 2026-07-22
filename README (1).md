# Ubuntu / Windows 远程访问快速部署

支持：

- Ubuntu 22.04
- Windows 10 1809 及以上、Windows 11

脚本安装并设置开机自启：OpenSSH、Tailscale、RustDesk。当前不支持 Debian。

## 1. Ubuntu 22.04

```bash
curl -fsSL \
  https://raw.githubusercontent.com/RainCatStar-lit/Ubuntu-tailscale-remote-access/main/install.sh \
  -o /tmp/remote-access-install.sh && \
sudo bash /tmp/remote-access-install.sh
```

网络需要本机代理时：

```bash
sudo bash /tmp/remote-access-install.sh \
  --proxy http://127.0.0.1:10808
```

## 2. Windows 10/11

在 **Git Bash** 中运行，不要使用 WSL：

```bash
curl -fsSL \
  https://raw.githubusercontent.com/RainCatStar-lit/Ubuntu-tailscale-remote-access/main/install.sh \
  -o install.sh && \
bash install.sh
```

按提示批准管理员权限。

## 3. 登录 Tailscale

安装过程中打开终端给出的登录链接。两台设备必须登录同一个 Tailnet。

![Tailscale 登录](docs/images/tailscale-login.png)

查看本机 Tailscale IP：

```bash
tailscale ip -4
```

## 4. 设置 RustDesk

打开 RustDesk：

```text
设置 -> 安全 -> 启用直接 IP 访问
```

无人值守密码由用户手动设置，脚本不保存任何密码。

![RustDesk 直接 IP](docs/images/rustdesk-direct-ip.png)

## 5. 连接

始终使用 Tailscale 分配的 `100.x.x.x` 地址，不使用校园网 IP。

```bash
ssh 用户名@100.x.x.x
```

RustDesk：

```text
100.x.x.x:21118
```

## 6. 日志

Ubuntu：

```text
/var/log/Ubuntu-tailscale-remote-access/install-YYYYMMDD-HHMMSS.log
```

查看最新日志：

```bash
sudo less "$(ls -1t /var/log/Ubuntu-tailscale-remote-access/install-*.log | head -n 1)"
```

Windows：

```text
C:\ProgramData\Ubuntu-tailscale-remote-access\logs\install-YYYYMMDD-HHMMSS.log
```

安装成功或失败时，终端都会显示本次日志路径。Tailscale 登录链接不会写入日志。
