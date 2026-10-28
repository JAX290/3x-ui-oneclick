# 06 · 日常运维

> 装好之后长期用得上的一些操作。全部在服务器上执行。

---

## 1. 每天会用到的三条

```bash
bash /root/info.sh                 # 看面板地址 / 节点链接 / 二维码
systemctl status x-ui        # 看面板和 Xray 是否健康
x-ui                         # 官方管理菜单（启动/停止/改端口/改密码/升级）
```

---

## 2. 备份与恢复（重要）

面板里的节点、账号、流量统计全在 **`/etc/x-ui/x-ui.db`** 这一个文件里。

### 备份

```bash
# 服务器上打包（数据库 + 安装信息）
tar czf /root/3xui-backup-$(date +%F).tar.gz /etc/x-ui /root/3xui-info.txt

# 下载到你电脑（在本地 PowerShell / 终端执行）
scp root@服务器IP:/root/3xui-backup-*.tar.gz .
```

建议**每月备份一次**，或每次改完配置备份一次。

### 恢复 / 迁移到新服务器

```bash
# 新机器先跑一遍一键脚本（或只装 3x-ui）
bash /root/install.sh --dry-run          # 先看计划

# 上传备份并解压覆盖
scp 3xui-backup-xxxx.tar.gz root@新IP:/root/
# 服务器上：
systemctl stop x-ui
tar xzf /root/3xui-backup-xxxx.tar.gz -C /
systemctl start x-ui
```

> 注意：数据库里存的是**旧面板的端口/路径/账号**。恢复后面板会按旧配置启动，用旧的访问方式登录，再按需修改。

---

## 3. 升级

```bash
# 先备份
cp /etc/x-ui/x-ui.db /root/x-ui.db.bak

# 方式一：管理菜单
x-ui              # 选「更新面板」

# 方式二：官方脚本（重跑即升级）
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

升级只替换程序，不会动数据库。升级后刷新面板页面（`Ctrl+F5`）。

> 大版本升级前，看一眼 [上游 Release](https://github.com/MHSanaei/3x-ui/releases) 有没有不兼容说明。

---

## 4. 加一台设备 / 加一个用户

### 同一账号多用（最简单）

同一条链接可以在多台设备导入，默认不限 IP。缺点：流量混在一起统计。

### 每台设备独立（推荐）

```bash
bash /root/install.sh --force --email ipad
```

会新建一个客户端（同一个入站下），并输出新链接。之后：

```bash
bash /root/info.sh          # 默认看 user1
# 看指定客户端：
CLIENT_EMAIL=ipad bash /root/info.sh
```

面板「客户端」页可以分别看到每台设备的流量、在线状态、最后在线时间。

---

## 5. 修改面板端口 / 访问路径

```bash
# 改端口（改成 30000）
x-ui setting -port 30000

# 改访问路径（改成 mysecret）
x-ui setting -webBasePath mysecret

# 重启生效
systemctl restart x-ui
```

改完记得：`ufw allow 30000/tcp`，云安全组也要放行新端口。

改完信息文件会过期，重新生成：

```bash
bash /root/info.sh    # 会自动从 x-ui 读取最新端口/路径
```

---

## 6. 换 REALITY 伪装目标

如果某天发现握手失败、或目标站不可达，换一个（要求：支持 TLS 1.3 + HTTP/2，且你的 VPS 能访问）：

```bash
# 1. 先测目标站是否可用
curl -I --max-time 5 https://www.apple.com
openssl s_client -connect www.apple.com:443 -tls1_3 </dev/null 2>/dev/null | grep 'Protocol'

# 2. 在面板里改：入站 → 编辑 → 目标(dest) / SNI → 保存
#    注意：改了 dest/SNI 后，客户端链接里的 sni 也要跟着改，需要重新扫码
```

常见可用目标：`www.microsoft.com`、`www.apple.com`、`www.bing.com`、`dl.google.com`、`www.cloudflare.com`。

---

## 7. 加 Hysteria2（移动网络/晚高峰救星）

面板 → 入站 → 添加入站：

| 字段 | 值 |
|---|---|
| 协议 | `hysteria`（Hysteria2） |
| 端口 | `8443`（UDP） |
| 证书 | 面板「设置 → 证书」里生成自签，或上传已有证书 |
| 密码 | 自动生成 |
| 混淆/带宽 | 默认 |

保存后在客户端「客户端」里加人，扫码导入。客户端需勾选「跳过证书验证」（自签证书）。

放行 UDP：

```bash
ufw allow 8443/udp
```

云安全组同样要加 **UDP 8443**。

> Hysteria2 基于 QUIC/UDP，在丢包严重的移动网络里通常比 TCP 的 REALITY 快很多；但部分公司网络会封 UDP，所以建议**两个都留着**，随时切换。

---

## 8. 订阅链接（多设备一键同步）

面板 → 设置 → 订阅：

- 默认每个客户端都有 `subId`，链接形如：
  `http://你的IP:面板端口/面板路径/sub/客户端subId`
- 在客户端里「添加订阅」填这个地址，以后改配置只需在服务器点「更新订阅」

好处：换节点、加节点不用重新扫码。坏处：**订阅地址泄露 = 节点泄露**，面板里可以随时重置 subId。

---

## 9. Telegram 机器人（可选）

面板 → 设置 → Telegram 机器人：

1. 找 @BotFather 建 bot，拿 token
2. 面板里填 token，设置管理员 chat id
3. 之后可以在 Telegram 里查看流量、重启 Xray、开关节点

适合不想天天登录面板的人。配置错误不影响节点使用。

---

## 10. 日常安全检查清单

每月花 2 分钟：

- [ ] `ufw status` —— 只放行了必要端口？（22 / 节点端口 / 面板端口）
- [ ] 面板路径没有被改成 `/` 或常见词
- [ ] 客户端列表里没有陌生设备
- [ ] `df -h` 磁盘没满（日志会增长）
- [ ] 备份文件是最新的
- [ ] 系统更新：`apt update && apt upgrade -y`（内核更新后需重启，选在空闲时段）

---

## 11. 日志在哪

| 日志 | 位置 |
|---|---|
| 一键脚本日志 | `/var/log/3xui-oneclick.log` |
| 面板服务日志 | `journalctl -u x-ui -n 100 --no-pager` |
| Xray 运行日志 | 面板 → 日志，或 `/var/log/x-ui/` |

日志变大可清理：

```bash
truncate -s 0 /var/log/3xui-oneclick.log
journalctl --vacuum-size=50M
```

---

## 12. 彻底卸载

```bash
bash /root/uninstall.sh            # 二次确认
bash /root/uninstall.sh -y         # 直接卸
bash /root/uninstall.sh --keep-db  # 保留数据库，方便以后重装
```

卸载不会动系统里的 ufw/BBR/chrony（它们对系统无害）。想还原：

```bash
ufw disable
rm -f /etc/sysctl.d/99-3xui-oneclick.conf
```

---

## 13. 去掉面板广告（赞助位）

部署脚本默认已关闭。想恢复或重新关闭：

```bash
bash /root/no-ads.sh --restore    # 恢复官方（广告回来）
bash /root/no-ads.sh              # 再次关闭
```

原理、副作用和兜底方案见 [07-remove-ads.md](07-remove-ads.md)。

---

返回 → [README](../README.md)
