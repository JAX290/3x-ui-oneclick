# 03 · 一键部署

> 目标：在服务器上执行一条命令，拿到面板地址 + 节点链接 + 二维码。

---

## 1. 一条命令

```bash
bash <(curl -Ls https://raw.githubusercontent.com/JAX290/3x-ui-oneclick/main/scripts/install.sh)
```

**执行前建议先看一眼它要做什么**（不改系统，安全）：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/JAX290/3x-ui-oneclick/main/scripts/install.sh) --dry-run
```

---

## 2. 脚本内部做了什么（共 7 步）

| 步骤 | 内容 | 大约耗时 |
|---|---|---|
| 1 | 检查系统/内存/架构，探测公网 IP | 5 秒 |
| 2 | 装依赖：curl、jq、qrencode、chrony、ufw | 30–90 秒 |
| 3 | 校准时间（REALITY 对时间敏感） | 5 秒 |
| 4 | 开启 BBR 加速 | 2 秒 |
| 5 | 用官方脚本装 3x-ui（非交互） | 60–180 秒 |
| 6 | 调面板 API 生成密钥、建 VLESS+REALITY 节点 | 5 秒 |
| 7 | 配置防火墙，输出信息 + 二维码 | 5 秒 |

全程无需输入，**不要中途关窗口**。中途 Ctrl+C 或断线会停在一半，重跑脚本是安全的（已装的部分会跳过）。

---

## 3. 执行过程中会看到什么

```
==> [1/7] 检查运行环境
  ✓ 系统 debian 12 / kvm / 内存 986MB
  ✓ 公网 IP：203.0.113.10

==> [2/7] 安装依赖（curl jq qrencode openssl chrony ufw）
  ✓ 依赖就绪
...
==> [5/7] 安装 3x-ui 面板（官方脚本，非交互）
  下载安装脚本：https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh
  ✓ 安装脚本已就绪（93977 字节）
  开始安装（3-5 分钟，请勿关闭窗口）...
```

最后是「部署完成」汇总（见 README 示例）。

---

## 4. 成功之后必须做的 3 件事

### ① 保存信息

所有信息都在服务器上：

```bash
cat /root/3xui-info.txt
```

复制到你的密码管理器/记事本。**丢了也不至于报废**，随时可以 `bash /root/info.sh` 再看。

### ② 用手机扫码试一下

装客户端（见 [04-client-setup.md](04-client-setup.md)），扫码 → 打开开关 → 浏览器访问 `https://www.google.com`。

### ③ 去云控制台放行端口

脚本会在系统里用 ufw/firewalld 放行，但**云厂商安全组是另一层**：

在商家控制台找到「安全组 / 防火墙」，放行：

- TCP 22（SSH，或商家给你的自定义端口）
- TCP 443（节点端口，如果你改了 `--port` 就放行那个）
- TCP 面板端口（脚本输出的那个 5 位数）

> 很多商家默认「全部放行」，那就跳过这步。如果扫码连不上，先怀疑这里。

---

## 5. 常用参数

```bash
# 换伪装目标（目标站要支持 TLS1.3 + HTTP/2，且你的 VPS 能访问）
bash /root/install.sh --dest www.apple.com:443 --sni www.apple.com

# 443 被占用时换端口
bash /root/install.sh --port 8443

# 给第二台设备单独建一个客户端（同一个面板，多一条链接）
bash /root/install.sh --force --email pad

# 面板已装过，只想重建节点
bash /root/install.sh --force

# 完全重装
bash /root/install.sh --reinstall

# 不碰防火墙
bash /root/install.sh --no-firewall
```

完整参数：`bash /root/install.sh --help`

---

## 6. 装完怎么验证「真的通了」

在**服务器**上：

```bash
# 1. 面板服务在跑
systemctl status x-ui --no-pager | head -5

# 2. Xray 在跑
x-ui status

# 3. 443 端口在监听
ss -lntp | grep :443

# 4. REALITY 握手自测（应返回伪装站的证书）
openssl s_client -connect 127.0.0.1:443 -servername www.microsoft.com </dev/null 2>/dev/null | openssl x509 -noout -subject
```

第 4 条输出了 `subject=CN=...` 之类，说明 REALITY 工作正常。

在**你的电脑**上（连上代理后）：

- 浏览器打开 `https://www.google.com` → 能开
- 打开 `https://ip.sb` → 显示的 IP 是你的 VPS IP

---

## 7. 手动兜底：万一自动建节点失败

脚本会明确提示「自动创建失败」，并把参数打出来。这时只需要在面板里点几下（**2 分钟**）：

1. 浏览器打开面板 → 左侧「入站」→ 右上角「添加入站」
   - 备注：`oneclick-reality`
   - 协议：`vless`
   - 监听端口：`443`
   - 传输协议：`tcp`
   - 安全：`reality`
2. Reality 区域：
   - **目标(dest)**：`www.microsoft.com:443`
   - **SNI**：`www.microsoft.com`
   - **私钥/公钥**：点「获取」自动生成
   - **shortId**：点「获取」自动生成
   - **流控**：`xtls-rprx-vision`
3. 点「添加」，然后在入站列表里点这条入站的「客户端」→ 添加客户端（名字随便，如 `user1`）→ 保存
4. 点客户端旁的二维码图标，扫码导入

> 面板 3.x 的界面按钮文字可能略有差异，但字段名就是上面这些。

---

## 8. 想再加一个协议（可选）

装完后你想加 Hysteria2（UDP，移动网络更稳）或 TUIC：

面板 → 入站 → 添加入站 → 协议选 `hysteria` 或 `tuic` → 端口填 `8443`：

- 需要证书：面板「设置 → 证书」里可以申请或上传；没有域名就选「自签」
- 自签证书客户端要勾「跳过证书验证（allowInsecure）」

然后记得放行 **UDP 8443**。

---

## 9. 执行出错的排查顺序

```bash
# 1. 看脚本日志
tail -n 50 /var/log/3xui-oneclick.log

# 2. 看面板服务
systemctl status x-ui --no-pager
journalctl -u x-ui -n 50 --no-pager

# 3. 看 Xray 日志（面板里也有）
ls -l /usr/local/x-ui/
```

常见原因：

| 报错关键词 | 原因 | 处理 |
|---|---|---|
| `Unsupported CPU architecture` | 不支持的架构 | 换 KVM 标准镜像 |
| `Port 443 is already in use` | 端口被占用 | `--port 8443` |
| `curl: (35)` / `(7)` | 下载不了 GitHub | 见 02 文档第 6 节 |
| `login failed` | 面板路径/端口与记录不一致 | 用 `x-ui setting -show true` 查实际值 |
| `dependency ... failed` | 包管理器报错 | 先 `apt update`，或重跑 |

如果最后还是不行：在 GitHub 仓库提 Issue，**附上 `/var/log/3xui-oneclick.log` 最后 30 行**。

---

下一步 → [04-client-setup.md](04-client-setup.md)
