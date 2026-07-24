# macOS 稳定版安装器

该分支用于在 **macOS（Apple Silicon / Intel）** 上快速安装并配置：

- macOS 内置 OpenSSH
- Tailscale
- RustDesk

## 快速安装

打开“终端”，执行：

```bash
git clone \
  --branch STABLE-IN-MACOS \
  --single-branch \
  https://github.com/RainCatStar-lit/Remote-in-ANY-network.git

cd Remote-in-ANY-network

chmod +x install-macos.command
./install-macos.command
```

安装器会自动识别处理器架构，并完成 OpenSSH、Tailscale 和 RustDesk 的安装与基础配置。

## 完成 Tailscale 登录

安装过程中会启动 Tailscale。

按照界面提示：

1. 允许添加 VPN 配置；
2. 登录与其他设备相同的 Tailscale 账户；
3. 确认当前 Mac 在 Tailscale 中显示为在线。

登录完成后，当前设备会获得一个类似下面的 Tailscale IP：

```text
100.x.x.x
```

后续 SSH 和 RustDesk 连接都使用该地址。

## 完成 RustDesk 权限设置

首次打开 RustDesk 时，进入：

```text
系统设置
→ 隐私与安全性
```

为 RustDesk 开启：

- 屏幕与系统音频录制；
- 辅助功能；
- 输入监控（系统提示时）。

修改权限后，请完全退出并重新打开 RustDesk。

## 下一步

完成安装后，返回项目引导页查看设备连接方法：

https://github.com/RainCatStar-lit/Remote-in-ANY-network/tree/guide
