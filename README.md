# Ubuntu 22.04 远程工作站快速部署

使用 **Tailscale + SSH + RustDesk** 连接 Ubuntu 工作站。

适用于校园网设备隔离、不同网段、没有公网 IP、不能做端口映射等场景。

## 连接方式

```text
Windows 笔记本
├── SSH ────────────────┐
└── RustDesk 直接 IP ───┤
                         │ Tailscale
                         ▼
Ubuntu 22.04 工作站
```

两台设备登录同一个 Tailscale 账户后，Ubuntu 会获得一个固定的 `100.x.x.x` 地址。

后续统一使用这个地址：

```text
SSH：      ssh 用户名@100.x.x.x
RustDesk： 100.x.x.x:21118
```

不需要公网 IP、路由器端口转发或 RustDesk 公共 ID。

---

## 一、Ubuntu 工作站

### 1. 安装 SSH

```bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
systemctl is-active ssh
```

正常应输出：

```text
active
```

### 2. 安装 Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled
sudo tailscale up
```

浏览器完成登录后查看工作站地址：

```bash
tailscale ip -4
```

记录输出，例如：

```text
100.80.20.15
```

无法在线安装时，可在其他设备下载 Tailscale 的 Ubuntu `.deb`，复制到工作站后执行：

```bash
sudo apt install ./tailscale_*.deb
sudo systemctl enable --now tailscaled
sudo tailscale up
```

### 3. 安装 RustDesk

将 RustDesk Ubuntu `.deb` 放到下载目录，然后执行：

```bash
cd ~/Downloads
sudo apt install ./rustdesk*.deb
```

如果存在 RustDesk 服务，启用开机启动：

```bash
sudo systemctl enable --now rustdesk.service 2>/dev/null || true
```

打开 RustDesk：

```bash
rustdesk
```

在 RustDesk 设置中完成：

1. 设置永久访问密码。
2. 开启无人值守访问。
3. 开启直接 IP 访问。
4. 保持直接访问端口为 `21118`。

### 4. 禁止工作站自动休眠

```bash
sudo systemctl mask \
  sleep.target \
  suspend.target \
  hibernate.target \
  hybrid-sleep.target
```

屏幕可以关闭，但主机不能进入挂起状态。

### 5. 防火墙设置

只有 UFW 已启用时才需要执行：

```bash
sudo ufw status
sudo ufw allow in on tailscale0 to any port 22 proto tcp
sudo ufw allow in on tailscale0 to any port 21118 proto tcp
```

不需要在路由器中开放任何端口。

---

## 二、Windows 笔记本

安装：

- Tailscale
- RustDesk

Tailscale 登录与 Ubuntu 相同的账户。

### 1. 测试 Tailscale

PowerShell 执行：

```powershell
tailscale ping 100.80.20.15
```

将地址替换成 Ubuntu 的 Tailscale IP。

### 2. SSH 连接

```powershell
ssh rcs@100.80.20.15
```

替换：

- `rcs`：Ubuntu 用户名
- `100.80.20.15`：Ubuntu 的 Tailscale IP

首次连接输入：

```text
yes
```

然后输入 Ubuntu 登录密码。

### 3. RustDesk 连接

在 Windows RustDesk 中输入：

```text
100.80.20.15:21118
```

然后输入 Ubuntu RustDesk 设置的永久密码。

这里使用的是 Tailscale IP 直连，不依赖 RustDesk 公共 ID 或公共中继。

---

## 三、快速验收

Ubuntu 执行：

```bash
systemctl is-active ssh
systemctl is-active tailscaled
tailscale status
tailscale ip -4
sudo ss -lntp | grep -E '(:22|:21118)'
```

Windows 执行：

```powershell
tailscale ping 100.80.20.15
ssh rcs@100.80.20.15
```

随后使用 RustDesk 连接：

```text
100.80.20.15:21118
```

以下三项都成功，即部署完成：

```text
1. Tailscale 可以 ping 通工作站
2. SSH 可以登录 Ubuntu
3. RustDesk 可以打开 Ubuntu 桌面
```

---

## 四、常见问题

### Tailscale 能 ping，SSH 不能连接

Ubuntu 检查：

```bash
systemctl status ssh --no-pager
sudo ss -lntp | grep ':22'
sudo ufw status
```

### RustDesk 公共 ID 无法连接

不要使用公共 ID，直接填写：

```text
Ubuntu的Tailscale-IP:21118
```

### RustDesk 黑屏

先注销 Ubuntu，在登录界面点击齿轮并选择：

```text
Ubuntu on Xorg
```

登录后检查：

```bash
echo "$XDG_SESSION_TYPE"
```

正常应输出：

```text
x11
```

### 重启后无法连接

Ubuntu 检查服务是否开机启动：

```bash
systemctl is-enabled ssh
systemctl is-enabled tailscaled
systemctl is-enabled rustdesk.service 2>/dev/null || true
```

---

## 最小软件清单

| 设备 | 必需软件 |
|---|---|
| Ubuntu 工作站 | OpenSSH Server、Tailscale、RustDesk |
| Windows 笔记本 | Tailscale、RustDesk |

