# 05 · 常见问题（FAQ）

> 按「你遇到的现象」查，不用从头读。

---

## A. 安装阶段

### A1. `bash: command not found` 或提示语法错误

用错了 shell。确认第一行是 `bash <(...)` 而不是 `sh`。若仍报错，改用：

```bash
curl -Ls https://raw.githubusercontent.com/JAX290/3x-ui-oneclick/main/scripts/install.sh -o /root/install.sh
bash /root/install.sh
```

### A2. `curl: (35) Connection reset` / `(7) Failed to connect`

GitHub 直连失败。见 [02-connect-vps.md](02-connect-vps.md) 第 6 节的三个方案（镜像 / 本地下载上传 / 官方脚本）。

### A3. `This machine has already installed 3x-ui`

之前装过。想继续建节点：`bash /root/install.sh --force`；想重装：`bash /root/install.sh --reinstall`；只想看信息：`bash /root/info.sh`。

### A4. `Port 443 is already in use`

443 被别的程序占用（比如自带的 web 服务）。换端口：

```bash
bash /root/install.sh --port 8443
```

并记得放行 8443（系统和云控制台两层）。

### A5. 安装到一半断线 / 关了窗口

重跑同一条命令即可，脚本是幂等的（已装的会跳过）。如果卡在「面板已安装」提示，用 `--force`。

### A6. 提示内存不足 / 安装很慢卡住

512MB 机器建议先加 swap：

```bash
fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

然后重跑。

---

## B. 面板打不开

### B1. 浏览器一直转圈 / 超时

按顺序查：

```bash
systemctl status x-ui --no-pager          # 服务在不在跑
ss -lntp | grep -E ':(你的面板端口)'       # 端口在不在监听
ufw status                                # 系统防火墙放行了没
```

- 服务没跑：`systemctl restart x-ui`，还不行看 `journalctl -u x-ui -n 50 --no-pager`
- 端口没监听：面板端口被改过，用 `x-ui setting -show true` 查实际端口
- ufw 没放行：`ufw allow 面板端口/tcp`
- 都正常：**云厂商安全组**没放行（去控制台加规则）

### B2. 忘了面板端口 / 路径 / 密码

```bash
cat /etc/x-ui/install-result.env      # 安装时生成，全是明文
# 或
x-ui setting -show true
```

密码忘了想重置：

```bash
x-ui          # 进菜单，选「重置面板用户名和密码」
```

### B3. 面板能打开但提示密码错误

用户名密码区分大小写，注意别把 `l`（小写L）看成 `1`、`0` 看成 `O`。复制 `install-result.env` 里的值最稳。

### B4. 不敢把面板暴露在公网

用 SSH 隧道，把面板端口只绑在本机：

```bash
# 在你自己的电脑上执行（不要关这个窗口）
ssh -L 30000:127.0.0.1:30000 root@你的服务器IP
```

然后浏览器访问 `http://127.0.0.1:30000/面板路径`。看完关掉窗口即断开。

```bash
# 更彻底：让面板只监听本机（改完记得重启）
x-ui setting -listenIP 127.0.0.1
systemctl restart x-ui
```

---

## C. 节点连不上

### C1. 客户端显示「已连接」但网页打不开

这是「连上了但没网」，见下面 D 节。

### C2. 客户端一直「连接中」/ 超时

1. 服务器上确认端口在监听：`ss -lntp | grep :443`
2. 服务器上自测握手：
   ```bash
   openssl s_client -connect 127.0.0.1:443 -servername www.microsoft.com </dev/null 2>/dev/null | openssl x509 -noout -subject
   ```
   没输出 → 伪装目标不可达，换一个（`--dest www.apple.com:443 --sni www.apple.com`）
3. 云安全组放行了吗？
4. 客户端和服务器**时间**是否准确（手机时间手动改过也会失败）

### C3. 昨天能用，今天突然全挂

大概率 **IP 被墙**。判断：

```bash
# 在你自己电脑上
ping 你的服务器IP        # 通不通
ssh root@你的服务器IP    # 还能不能连
```

- SSH 也连不上 → IP 被封，去商家后台换 IP（多数商家支持，可能收费）
- SSH 能连但代理不通 → 端口被封，换端口重试（`--port 8443`）

### C4. 二维码扫不出来

终端字符二维码对手机摄像头不友好。改用复制链接方式，或调大终端字体、换深色背景。

### C5. iOS 提示「不受信任的开发者」/ 装不上

Shadowrocket/sing-box 需要非国区 App Store 账号。sing-box 用美区账号免费下载。

### C6. 导入后「订阅」列表里空的 / 没有可用节点

**最常见的原因：把单条配置当成了订阅。**

| 类型 | 长什么样 | 正确用法 |
|---|---|---|
| 单条配置（脚本给的就是这个） | `vless://uuid@IP:443?...` | 配置页 → `+` → **从剪贴板导入**（或扫码） |
| 订阅 | `http://IP:端口/路径/sub/xxxx` | 订阅页 → 添加上面的 http 地址 |

v2rayNG 的「订阅」只认 http(s) 地址，`vless://` 粘进去必然是空的。

正确步骤：删掉误建的订阅条目 → 配置页 `+` → 从剪贴板导入 → 列表出现备注为
`oneclick-reality` 的节点 → 选中 → 点右下角 `V` 启动。

如果「配置」列表也没有，依次检查：

1. `bash /root/info.sh` 重新复制，`vless://` 到 `#oneclick-reality` 必须是**一整行**
2. v2rayNG 版本要新（REALITY 需要 1.8+）
3. 手动添加兜底（`+` → 手动输入 → VLESS）：
   地址=服务器 IP、端口=443、UUID=info 里的值、流控=`xtls-rprx-vision`、
   传输=`RAW`（旧版叫 tcp）、安全=`reality`、SNI=`www.microsoft.com`、公钥/shortId 填 info 里的值、指纹=`chrome`

### C7. 点启动提示「无效的配置」

v2rayNG 的这个报错意思是「解析出来的配置不完整」。最常见的原因是**链接里的服务器地址为空**：

```text
vless://uuid@:443?...        ← @ 后面直接是冒号（地址为空）
vless://uuid@0.0.0.0:443     ← 地址不可用
vless://uuid@127.0.0.1:443   ← 地址指向本机
vless://uuid@localhost:443   ← 同上（面板不知道公网 IP 时的默认值）
```

原因：早期版本的脚本优先采用了面板生成的分享链接，而面板如果不知道公网 IP，生成的地址会是 `localhost` 或空。

**修复**（新版脚本已改为自己拼链接）：在服务器上重新生成一条正确链接：

```bash
get(){ awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"");print;exit}' /etc/x-ui/oneclick.env; }
UUID=$(get UUID); SID=$(get SHORT_ID); PBK=$(get PUBLIC_KEY); SNI=$(get SNI)
IP=$(get SERVER_IP); PORT=$(get VLESS_PORT); NAME=$(get CLIENT_REMARK)
LINK="vless://${UUID}@${IP}:${PORT}?type=tcp&security=reality&encryption=none&pbk=${PBK}&fp=chrome&sni=${SNI}&sid=${SID}&spx=%2F&flow=xtls-rprx-vision#${NAME:-node}"
echo "$LINK"
command -v qrencode >/dev/null && qrencode -t ANSIUTF8 -m 1 "$LINK"
```

然后在 v2rayNG 里**删掉旧配置**，重新扫码/粘贴导入。

**顺手让面板里的链接也正确**（否则你在面板点「二维码/分享链接」拿到的还是 `localhost`）：

> 面板 → 入站 → `oneclick-reality` → 编辑 → 找到「分享地址 / Share Address」→ 填你的公网 IP（如 `216.36.85.213`）→ 保存

新版脚本创建入站时已经自动写入这个字段（`shareAddr` + `shareAddrStrategy=custom`），不会再出现。

---

## D. 能连上但没网 / 部分网站打不开

### D1. 完全没网

1. 服务器本身能不能上外网：`curl -I https://www.google.com`
   - 不能 → 这台机器的 IP 没外网或被墙，换 IP
2. 面板里节点是否启用（入站列表里是绿色）
3. 客户端选的是「全局」还是「规则」——先用**全局**排除规则问题

### D2. Google 能开，YouTube 卡 / 某些站打不开

- 线路问题：换机房或换协议（加 Hysteria2/TUIC）
- MTU 问题：客户端里把 MTU 改成 `1280` 试试
- DNS 污染：客户端开启「远程 DNS」/ DoH

### D3. 国内网站变慢

用了「全局」模式。切成「规则」模式，国内直连。

### D4. 速度只有几十 KB/s

按可能性排序：

1. **VPS 带宽本身小**（很多便宜机 100Mbps 共享，晚高峰掉速）
2. **线路绕路**：`ping` 延迟高、`traceroute` 绕美国
3. **TCP 拥塞**：确认 BBR 开了 `sysctl net.ipv4.tcp_congestion_control` 输出 `bbr`
4. **移动网络丢包**：加一条 Hysteria2（UDP）节点通常立竿见影

---

## E. 安全 / 维护

### E1. 怎么备份？换服务器怎么迁移？

```bash
# 备份（数据库 + 配置 + 安装信息）
tar czf /root/3xui-backup-$(date +%F).tar.gz /etc/x-ui /root/3xui-info.txt

# 下载到本地
scp root@服务器IP:/root/3xui-backup-*.tar.gz .
```

迁移：新机器装好后解压覆盖 `/etc/x-ui`，再 `systemctl restart x-ui`。

### E2. 怎么升级 3x-ui？

```bash
x-ui          # 菜单里选「更新面板」
# 或
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) 
```

升级前先备份 `/etc/x-ui/x-ui.db`。

### E3. 链接被别人拿去了怎么办？

面板 → 客户端 → 删掉旧客户端，新建一个，重新扫码。旧链接立即失效。

### E4. 想看每台设备用了多少流量？

面板首页有总流量；「客户端」页每行显示该客户端的上下行与配额。

### E5. 怎么限制只有自己能用？

面板 → 客户端 → 设置 `IP 限制`（`limitIp`）= 1~2，配合 fail2ban，别人拿去也用不了。

### E6. 需要限制每月流量吗？

面板 → 客户端 → 设置「总流量」与「到期时间」，超额自动停用。

---

## G. 客户端下载页打不开 / 页面空白

按顺序查：

```bash
bash /root/info.sh                          # 1. 看【客户端下载页】那行的地址和端口
systemctl status 3xui-clients --no-pager    # 2. 服务在不在跑
systemctl restart 3xui-clients              # 3. 重启一下
ls -lh /var/www/clients                     # 4. 文件到底下下来没有
ufw status | grep -E '80|8080'              # 5. 系统防火墙放行了吗
```

- 地址对了、服务也在跑 → 云厂商安全组没放行该端口
- 文件目录是空的 → 下载失败，重跑 `bash /root/fetch-clients.sh --force`（会自动换镜像）
- 换端口：`bash /root/fetch-clients.sh --port 8080`，然后重新看 `info.sh`

> 下载页是公开的，只放安装包、不含节点信息；不想长期开着可以 `systemctl disable --now 3xui-clients`。

---

## H. 面板上的广告（赞助位）

3x-ui v3.x 在登录页/仪表盘有赞助商广告位。本仓库默认部署时已屏蔽。

- 广告又出现了 / 想重新关闭：`bash /root/no-ads.sh`，然后浏览器 `Ctrl + Shift + R`
- 想让广告回来：`bash /root/no-ads.sh --restore`
- 关掉后「更新面板」按钮不可用（副作用已知）：改用 `x-ui` 菜单更新，或重跑 `install.sh`
- 详见 [07-remove-ads.md](07-remove-ads.md)

---

## F. 还是搞不定

1. 收集信息：
   ```bash
   tail -n 50 /var/log/3xui-oneclick.log
   systemctl status x-ui --no-pager | head -20
   ```
2. 去仓库提 Issue（**贴日志，别贴你的链接和密码**）。
3. 或者用官方方式重装：
   ```bash
   bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
   ```

---

返回 → [README](../README.md)
