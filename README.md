# Ubuntu / Windows 远程访问

使用 Tailscale + OpenSSH + RustDesk。支持 Ubuntu 22.04、Windows 10/11。
脚本不创建或保存任何密码。

## 1. Windows 上传文件

在 Windows 的 Git Bash 中：

```bash
git clone https://github.com/RainCatStar-lit/Ubuntu-tailscale-remote-access.git
cd Ubuntu-tailscale-remote-access
```

将新版文件覆盖到该目录，然后：

```bash
git add .
git commit -m "Improve Tailscale proxy and fallback handling"
git push origin main
```

## 2. Ubuntu 清理旧测试环境

必须在本机桌面执行，不要通过 Tailscale SSH 执行：

```bash
sudo bash reset-ubuntu.sh
```

完整清理 RustDesk 和系统设置：

```bash
sudo bash reset-ubuntu.sh --full
```

## 3. 从 GitHub 拉取

先直接下载；若 GitHub 解析失败，自动改用本机 `10808` 代理：

```bash
URL=https://raw.githubusercontent.com/RainCatStar-lit/Ubuntu-tailscale-remote-access/main/install.sh
curl -fsSL "$URL" -o /tmp/install.sh || \
curl -x http://127.0.0.1:10808 -fsSL "$URL" -o /tmp/install.sh
```

运行：

```bash
sudo bash /tmp/install.sh --proxy http://127.0.0.1:10808
```

脚本先尝试 Tailscale 官方 APT 仓库，失败后使用 Snap；若控制平面不能直连，会把代理写入 Tailscale 后台服务。

## 4. 登录与连接

打开终端显示的 Tailscale 登录地址。完成后统一使用 `100.x.x.x`：

```bash
ssh 用户名@100.x.x.x
```

RustDesk：

```text
100.x.x.x:21118
```

RustDesk 中手动启用“直接 IP 访问”，并自行设置无人值守密码。

## 5. 日志

```text
Ubuntu: /var/log/ubuntu-tailscale-remote-access/install-*.log
Windows: C:\ProgramData\Ubuntu-tailscale-remote-access\logs\install-*.log
```
