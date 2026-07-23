# Ubuntu / Windows 远程访问部署

本项目使用以下组件建立远程访问：

- Tailscale：提供稳定的虚拟专网地址 `100.x.x.x`
- OpenSSH：通过 Tailscale IP 提供标准 SSH 登录
- RustDesk：通过 Tailscale IP 进行远程桌面直连

当前重点测试环境为 **Ubuntu 22.04**。Windows 10/11 安装入口保留。
脚本不会创建、保存或上传 Tailscale Auth Key、SSH 密码或 RustDesk 无人值守密码。

## 功能

- 自动安装并启用 OpenSSH
- 优先尝试 Tailscale 官方 APT 仓库
- APT 仓库不可用时自动切换到 Snap
- 支持本机 HTTP/Mixed 代理，例如 `http://127.0.0.1:10808`
- 显式提供代理时优先使用代理，不再先进行多轮直连等待
- Tailscale 控制面无法直连时，自动给 `tailscaled` 服务设置代理
- 自动安装 RustDesk并配置开机启动
- 可选禁用休眠并切换到 Xorg
- 安装结束后显示 Tailscale IP、SSH命令、RustDesk地址和相关端口状态
- 全程记录安装日志

## 仓库结构

```text
install.sh
reset-ubuntu.sh
scripts/
  linux/
    common.sh
    01-base.sh
    02-ssh.sh
    03-tailscale.sh
    04-rustdesk.sh
    05-system.sh
    06-login-summary.sh
    07-verify.sh
  windows/
    install.ps1
tests/
  check.sh
```

## Ubuntu 22.04 快速安装

当前测试分支：

```text
TEST-IN-22.04
```

下载入口脚本：

```bash
BRANCH="TEST-IN-22.04"
BASE_URL="https://raw.githubusercontent.com/RainCatStar-lit/Remote-in-ANY-network/${BRANCH}"

curl -x http://127.0.0.1:10808 \
  -fsSL "${BASE_URL}/install.sh" \
  -o /tmp/install.sh

bash -n /tmp/install.sh
```

完整安装：

```bash
sudo bash /tmp/install.sh \
  --branch TEST-IN-22.04 \
  --proxy http://127.0.0.1:10808
```

仅测试 SSH 和 Tailscale：

```bash
sudo bash /tmp/install.sh \
  --branch TEST-IN-22.04 \
  --proxy http://127.0.0.1:10808 \
  --no-rustdesk \
  --keep-wayland \
  --keep-sleep
```

本地完整仓库中运行时，模块会优先从本地 `scripts/` 读取，不依赖 Raw GitHub。

## 安装参数

```text
--proxy URL          HTTP/Mixed代理，例如 http://127.0.0.1:10808
--branch NAME        下载模块所使用的GitHub分支
--repo-base URL      指定完整Raw模块地址，优先级高于--branch
--rustdesk-deb PATH  使用本地RustDesk .deb包
--no-rustdesk        跳过RustDesk
--keep-wayland       保留Wayland
--keep-sleep         不修改休眠和挂起设置
--skip-login         安装Tailscale但暂不登录
```

代理 URL 应使用：

```text
http://127.0.0.1:10808
```

不要写成：

```text
https://127.0.0.1:10808
```

## Tailscale登录

安装过程中会在终端显示浏览器授权地址。打开地址并批准当前设备。
授权地址不会写入安装日志。

登录成功后，安装程序会突出显示：

```text
Tailscale IPv4: 100.x.x.x
SSH command:    ssh 用户名@100.x.x.x
RustDesk:       100.x.x.x:21118
```

手动查看：

```bash
tailscale status 2>/dev/null || sudo /snap/bin/tailscale status
tailscale ip -4 2>/dev/null || sudo /snap/bin/tailscale ip -4
ip address show tailscale0
```

Snap版不提供Tailscale SSH。本项目始终使用普通OpenSSH通过Tailscale网络连接。

## 端口检查

本项目重点检查以下端口：

| 用途 | 端口 | 说明 |
|---|---:|---|
| OpenSSH | TCP 22 | 安装完成后应处于监听状态 |
| 本机代理 | TCP 10808 | 示例端口，实际取决于v2rayN等代理软件配置 |
| RustDesk直接IP访问 | TCP 21118 | 需在RustDesk中手动启用“直接IP访问”后检查 |

查看相关端口：

```bash
sudo ss -lntup | grep -E ':(22|10808|21118)\b'
```

查看全部监听端口：

```bash
sudo ss -lntup
```

安装程序会自动从 `--proxy` 中解析代理端口。例如传入
`http://127.0.0.1:10808` 时，结果摘要会检查 `10808` 是否正在监听。

## RustDesk设置

安装程序只负责安装和自启动。桌面用户仍需手动完成：

1. 打开RustDesk。
2. 进入“设置 → 安全”。
3. 启用“直接IP访问”。
4. 自行设置无人值守密码。

连接地址：

```text
100.x.x.x:21118
```

## 日志

Ubuntu：

```text
/var/log/ubuntu-tailscale-remote-access/install-YYYYMMDD-HHMMSS.log
```

查看最新日志：

```bash
LOG="$(sudo sh -c 'ls -1t /var/log/ubuntu-tailscale-remote-access/install-*.log | head -n 1')"
echo "$LOG"
sudo tail -n 150 "$LOG"
```

查看服务日志：

```bash
sudo journalctl -u tailscaled.service -n 100 --no-pager
sudo journalctl -u snap.tailscale.tailscaled.service -n 100 --no-pager
```

## 清理测试环境

不要通过即将被删除的Tailscale或RustDesk连接执行清理。

仅清理Tailscale及脚本状态：

```bash
sudo bash reset-ubuntu.sh
```

同时清理RustDesk和系统设置：

```bash
sudo bash reset-ubuntu.sh --full
```

同时删除安装日志：

```bash
sudo bash reset-ubuntu.sh --full --purge-logs
```

OpenSSH会被保留。

## 静态检查

```bash
bash tests/check.sh
```

预期：

```text
Static checks passed
```

## 在Linux端提交到GitHub测试分支

```bash
sudo apt-get update
sudo apt-get install -y git unzip

cd ~
git clone --branch TEST-IN-22.04 \
  https://github.com/RainCatStar-lit/Remote-in-ANY-network.git
cd Ubuntu-tailscale-remote-access
```

把新版文件覆盖到仓库后：

```bash
git config core.autocrlf false
bash tests/check.sh

git add --all
git status --short
git commit -m "Improve proxy fallback, IP summary and port checks"
git push origin TEST-IN-22.04
```

GitHub要求认证时，使用已配置的SSH密钥或Personal Access Token。不要把令牌写入脚本或提交到仓库。

## 合并到main前

测试通过后，可以把测试分支合并到main。合并后建议把 `install.sh` 中默认分支由
`TEST-IN-22.04` 改为 `main`，或者运行时显式使用：

```bash
sudo bash install.sh --branch main
```
