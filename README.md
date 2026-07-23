# Ubuntu 22.04 稳定版安装器

该分支用于在 Ubuntu 22.04 64 位系统上快速安装并配置：

- OpenSSH Server
- Tailscale
- RustDesk

## 快速安装

打开终端，执行：

```bash
git clone   --branch STABLE-IN-22.04   --single-branch   https://github.com/RainCatStar-lit/Remote-in-ANY-network.git

cd Remote-in-ANY-network

sudo bash install.sh
```

如果当前网络需要使用本机代理，例如 127.0.0.1:10808，则再执行：

```bash
sudo bash install.sh   --proxy http://127.0.0.1:10808
```

安装器会自动处理软件安装、服务启动、Tailscale 安装方式回退、RustDesk 配置和连接信息输出。

## 登录 Tailscale

安装过程中，终端会显示 Tailscale 登录链接，例如：

```text
https://login.tailscale.com/a/1a12345678900
```

在浏览器中打开该链接，并登录与其他设备相同的 Tailscale 账户。

登录完成后，终端会显示当前设备的 Tailscale IP，例如：

```text
100.x.x.x
```

后续 SSH 和 RustDesk 连接都使用该 Tailscale IP。

## 下一步

完成安装后，返回项目引导页查看设备连接方法：

https://github.com/RainCatStar-lit/Remote-in-ANY-network/tree/guide
