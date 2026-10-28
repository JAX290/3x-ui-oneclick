# 02 · 连上服务器

> 目标：在你自己的电脑上打开一个「能往服务器里敲命令」的窗口。
> 会用 SSH 的可以跳到 [03-oneclick.md](03-oneclick.md)。

---

## 1. Windows 怎么连（Win10 / Win11 自带工具）

1. 按 `Win + X` → 选 **终端** 或 **Windows PowerShell**
2. 输入（把 IP 换成你邮件里的）：

   ```powershell
   ssh root@203.0.113.10
   ```

3. 第一次连接会问：

   ```
   Are you sure you want to continue connecting (yes/no/[fingerprint])?
   ```

   输入 `yes` 回车。

4. 提示 `root@203.0.113.10's password:` 时，**粘贴你的密码然后回车**。

   > ⚠️ 输入密码时屏幕上**什么都不显示**（不是卡住），直接粘贴+回车即可。
   > PowerShell 里粘贴用**鼠标右键**，不是 Ctrl+V。

5. 看到类似下面的提示符就成功了：

   ```
   root@debian:~#
   ```

---

## 2. macOS 怎么连

1. 打开「启动台」→ 搜索 **终端**（Terminal）
2. 输入同样的命令：

   ```bash
   ssh root@203.0.113.10
   ```

3. 第一次同样输 `yes`，然后输入密码（macOS 上粘贴用 `Cmd + V`）。

---

## 3. 手机能不能连（应急用）

可以，装 **Termius**（iOS/Android 都有）或 **JuiceSSH**，新建 Host 填 IP、端口 22、用户名 root、密码。手机上操作不便，建议还是用电脑。

---

## 4. 连不上时对照排查

| 现象 | 原因 | 怎么办 |
|---|---|---|
| `Connection timed out` | IP 不通 / 被墙 / 服务器关机 | 去商家控制台看机器是否运行；换 IP |
| `Connection refused` | SSH 服务没开 / 端口不对 | 看邮件里的端口是不是 2222 等；控制台 VNC 登录检查 |
| `Permission denied (publickey)` | 商家只允许密钥登录 | 用商家给的私钥：`ssh -i 私钥文件 root@IP` |
| `Permission denied`（输密码后） | 密码错 / 用户名不是 root | 复制密码时别带空格；有的商家用户名是 `ubuntu` 或 `debian` |
| 卡在 `Are you sure...` | 没输入 yes | 输入 `yes` 回车 |
| 中文乱码 | 终端编码 | 一般不影响命令执行，忽略 |

如果实在进不去，用商家控制台的 **VNC / 紧急控制台** 登录，先改回密码登录：

```bash
# 在 VNC 里执行
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh
passwd root
```

---

## 5. 连上之后先做两件事

### ① 确认有外网

```bash
curl -I https://www.google.com
```

出现 `HTTP/2 200` 之类的响应就正常。**卡住或超时说明这个 IP 已经被墙**，先去商家后台换 IP（见 01 文档）。

### ② 记下系统版本

```bash
cat /etc/os-release | head -3
```

输出里 `Debian` / `Ubuntu` 和版本号，脚本需要它。

---

## 6. 下载失败怎么办（国内网络常见）

一键命令的第一步是「从 GitHub 下载安装脚本」。国内直连 `raw.githubusercontent.com` 有时会被重置，表现为：

```
curl: (35) OpenSSL SSL_connect: Connection reset by peer
# 或
curl: (7) Failed to connect
```

### 方案 A：换镜像地址（最快）

把命令里的域名换掉，三种任选：

```bash
# 1) gh-proxy 镜像
bash <(curl -Ls https://gh-proxy.com/https://raw.githubusercontent.com/JAX290/3x-ui-oneclick/main/scripts/install.sh)

# 2) ghfast 镜像
bash <(curl -Ls https://ghfast.top/https://raw.githubusercontent.com/JAX290/3x-ui-oneclick/main/scripts/install.sh)
```

> 脚本内部在下载「3x-ui 官方安装脚本」时也会自动尝试多个镜像，所以只要本仓库的 `install.sh` 能下载下来，后面通常没问题。

### 方案 B：本地下载再上传（最稳）

1. 用浏览器打开仓库页面 → `scripts/install.sh` → 右上角 **Download raw file**
2. 在你电脑的下载目录里打开 PowerShell，把文件传到服务器：

   ```powershell
   scp .\install.sh root@203.0.113.10:/root/
   ```

   macOS / Linux：

   ```bash
   scp ~/Downloads/install.sh root@203.0.113.10:/root/
   ```

3. 回到服务器的 SSH 窗口：

   ```bash
   bash /root/install.sh
   ```

### 方案 C：直接用官方安装脚本装，再手动建节点

如果 GitHub 怎么都连不上，可以先按 3x-ui 官方文档安装：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

装完看 [03-oneclick.md](03-oneclick.md) 最后的「手动兜底」在面板里建节点。

---

下一步 → [03-oneclick.md](03-oneclick.md)
