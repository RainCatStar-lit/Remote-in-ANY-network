# Ubuntu 22.04 Stable Installer

分支：`STABLE-IN-22.04`

该分支用于在 Ubuntu 22.04 上快速安装并配置 OpenSSH、Tailscale 和 RustDesk。

## 安装

克隆稳定分支：

```bash
git clone --branch STABLE-IN-22.04 \
  https://github.com/RainCatStar-lit/Remote-in-ANY-network.git

cd Remote-in-ANY-network
```

直接安装：

```bash
sudo bash install.sh
```

使用本机 HTTP / Mixed 代理，例如端口为 `10808`：

```bash
sudo bash install.sh \
  --proxy http://127.0.0.1:10808
```

安装程序会：

- 安装并启用 OpenSSH；
- 优先通过官方仓库安装 Tailscale，失败时回退到 Snap；
- 安装 RustDesk；
- 设置相关服务开机启动；
- 显示 Tailscale IP、SSH 命令和相关端口；
- 将安装日志写入 `/var/log/ubuntu-tailscale-remote-access/`。

## 安装完成后

根据浏览器提示登录 Tailscale，并确保其他设备使用同一个 Tailscale 账户。

查看地址：

```bash
tailscale ip -4 2>/dev/null \
  || sudo /snap/bin/tailscale ip -4
```

RustDesk 还需要在图形界面中启用直接 IP 访问并设置永久密码。

完整连接说明：

https://github.com/RainCatStar-lit/Remote-in-ANY-network/tree/guide
