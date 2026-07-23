# Windows vendor packages

运行以下命令下载并生成 SHA-256 清单：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\windows\download-packages.ps1 `
  -Proxy http://127.0.0.1:10808
```

预期文件：

```text
tailscale-setup-1.98.9-amd64.msi
rustdesk-1.4.9-x86_64.msi
OpenSSH-Win64-v9.8.3.0.msi
SHA256SUMS.txt
```

这些二进制文件应在创建 `STABLE-IN-WINDOWS` 分支时提交到仓库。单个文件必须低于 GitHub 的普通 Git 文件大小限制。
