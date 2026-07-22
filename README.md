# 智能安装

同一个小脚本自动识别 **Ubuntu 22.04** 或 **Windows 10/11 x64**，显示识别结果并进行两次确认，然后自动选择对应分支安装：

- Ubuntu 22.04 → `TEST-IN-22.04`
- Windows 10/11 x64 → `TEST-IN-WINDOWS`

用户只需要下载一个文件：

```text
SmartInstaller.cmd
```

> Windows 与 Ubuntu 没有共同保证预装的单一脚本解释器，因此该文件采用 Batch/Bash 兼容结构，并在 Windows 部分调用系统自带 PowerShell。用户仍然只下载同一个文件。

## Windows

下载 `SmartInstaller.cmd` 后双击运行。

流程：

1. 请求管理员权限。
2. 识别 Windows 版本和架构。
3. 显示目标分支 `TEST-IN-WINDOWS`。
4. 进行两次确认。
5. 自动检测本机常用代理端口：`10808`、`10809`、`7890`、`7897`。
6. 下载并校验所需 MSI。
7. 安装 Tailscale、Win32-OpenSSH 和 RustDesk。
8. 打开 Tailscale 登录流程；使用与 Ubuntu 相同的账户登录。
9. 显示 Tailscale IP、SSH 地址和 RustDesk 直接连接地址。

缓存目录：

```text
C:\ProgramData\Ubuntu-tailscale-remote-access\smart-installer\
```

日志目录：

```text
C:\ProgramData\Ubuntu-tailscale-remote-access\logs\
```

## Ubuntu 22.04

下载同一个 `SmartInstaller.cmd`，在文件所在目录执行：

```bash
bash SmartInstaller.cmd
```

流程：

1. 识别 Ubuntu 22.04。
2. 显示目标分支 `TEST-IN-22.04`。
3. 进行两次确认。
4. 自动检测本机常用代理端口。
5. 下载对应分支的 `install.sh`。
6. 使用 `sudo` 启动完整安装。
7. 登录 Tailscale 后显示本机 `100.x.x.x` 地址及相关端口。

缓存目录：

```text
~/.cache/ubuntu-tailscale-remote-access/smart-installer/
```

## 两次确认

第一次确认系统识别和目标分支是否正确：

```text
Is the detected system correct and do you want to continue? [y/N]
```

第二次必须输入：

```text
INSTALL
```

任意一次未确认都会立即退出，不执行安装。

## 连接

两台设备必须登录同一个 Tailscale 账户。安装完成后使用脚本显示的 Tailscale IP：

```text
SSH:       ssh 用户名@100.x.x.x
RustDesk:  100.x.x.x:21118
```

RustDesk 被控端仍需手动进入安全设置，启用直接 IP 访问并设置永久密码。

## 安全说明

脚本不保存账号密码、Tailscale Auth Key 或 RustDesk 永久密码。Windows 安装包使用 `TEST-IN-WINDOWS` 分支中的 SHA-256 清单校验。
