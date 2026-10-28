# 04 · 手机 / 电脑客户端配置

> 目标：把脚本给的那条 `vless://` 链接变成「一键上网」。
> 全程不需要懂协议，扫码或粘贴即可。

---

## 1. 先选一个客户端

| 你的设备 | 推荐客户端 | 获取方式 | 备注 |
|---|---|---|---|
| iPhone / iPad | **Shadowrocket**（小火箭） | App Store（需美区账号，付费约 $2.99） | 最省心 |
| iPhone / iPad | **sing-box**（SFI） | App Store（免费） | 免费首选，界面偏极客 |
| iPhone / iPad | **Stash** | App Store（付费） | 规则强大 |
| Android | **v2rayNG** | [GitHub](https://github.com/2dust/v2rayNG/releases) / Google Play | 最常用 |
| Android | **sing-box**（SFA） | [GitHub](https://github.com/SagerNet/sing-box/releases) / Play | 同一个项目官方客户端 |
| Android | **Hiddify** | [GitHub](https://github.com/hiddify/hiddify-app/releases) | 界面友好，适合新手 |
| Windows | **v2rayN** | [GitHub](https://github.com/2dust/v2rayN/releases) | 经典、轻量 |
| Windows | **Clash Verge Rev** | [GitHub](https://github.com/clash-verge-rev/clash-verge-rev/releases) | 界面现代，规则模式强 |
| macOS | **Clash Verge Rev** | 同上 | 支持 Apple Silicon |
| macOS | **sing-box** | App Store / GitHub | 官方 |

> 只选一个即可。**新手推荐**：Windows 用 v2rayN 或 Clash Verge Rev，Android 用 v2rayNG 或 Hiddify，iOS 用 Shadowrocket 或 sing-box。

---

## 2. 导入节点的两种方式

### 方式 A：扫码（最快）

1. 服务器上脚本结束时显示了一个二维码（或 `bash /root/info.sh` 再看）
2. 打开客户端 → 右上角 `+` / 「扫描二维码」
3. 对准屏幕扫码 → 自动添加

> 二维码在 SSH 终端里是由字符拼成的，手机上扫屏幕即可。扫不出来就调大终端字号、提高对比度，或直接用方式 B。

### 方式 B：复制链接

1. 复制服务器上的整条链接（从 `vless://` 开头到结尾，**一行，不能断**）：

   ```bash
   bash /root/info.sh          # 会打印链接
   # 或
   grep '^ 链接' /root/3xui-info.txt
   ```

2. 用任意方式把这段文字发到自己手机（微信文件传输助手、邮件、备忘录都行）
3. 客户端里选「从剪贴板导入」

---

## 3. 各平台具体步骤

### Android · v2rayNG

1. 安装后打开 → 右上角 `+` → **从剪贴板导入**
2. 回到首页，点右下角灰色圆圈变蓝（启动）
3. 第一次会请求 VPN 权限 → 允许
4. 浏览器打开 `https://ip.sb`，显示的 IP 应是你的 VPS IP

### Android · Hiddify

1. 打开 → 右上角 `+` → **从剪贴板添加**
2. 首页点「点击连接」→ 允许 VPN
3. 设置里可开「TUN 模式」获得更好的兼容性

### iOS · Shadowrocket

1. 打开 → 右上角 `+` → 类型选 `VLESS`（通常扫码会自动识别，不用手选）
2. 若扫码：首页左上角扫码图标
3. 首页把开关打开 → 首次会安装 VPN 配置 → 允许
4. 全局路由选「配置」或「代理」

### iOS · sing-box

1. 打开 → 「配置」→ 右上角 `+` → **从剪贴板导入**
2. 选中该配置 → 返回首页 → 打开开关
3. 允许添加 VPN 配置

### Windows · v2rayN

1. 解压后运行 `v2rayN.exe`
2. 左上角「服务器」→ **从剪贴板导入批量 URL**
3. 托盘图标右键 → **系统代理** → 自动配置系统代理
4. 浏览器验证 `https://ip.sb`

> 需要全局代理（比如某些软件不走系统代理）时：设置 → 参数设置 → 开启 **TUN 模式**（需要管理员权限）。

### Windows / macOS · Clash Verge Rev

1. 安装打开 → 「配置」→ 新建 → 类型选 **Remote** 或直接粘贴链接
2. 更简单：复制 `vless://` 链接 → 「配置」页右上角「导入」→ 从剪贴板
3. 回到「代理」页选中该节点 → 打开「系统代理」开关
4. 需要全局时打开 **TUN 模式**

---

## 4. 验证是否真的生效

| 检查 | 期望结果 |
|---|---|
| 浏览器打开 `https://ip.sb` | 显示 VPS 的 IP（不是你家宽带 IP） |
| 打开 `https://www.google.com` | 正常加载 |
| 打开 `https://www.youtube.com` | 能进首页 |

如果 IP 变了但网页打不开 → 看 [05-faq.md](05-faq.md) 的「能连上但没网」。

---

## 5. 分流模式怎么选

| 模式 | 含义 | 适合 |
|---|---|---|
| 全局（Global） | 所有流量都走代理 | 第一次调试、确定能用 |
| 规则（Rule） | 国内直连、国外走代理 | 日常使用（省流量、国内网站更快） |
| 直连（Direct） | 都不走 | 临时关代理 |

新手先用**全局**验证通不通，再用**规则**日常用。v2rayN / Clash Verge Rev 自带规则集，选「规则」即可。

---

## 6. 多设备怎么办

一条链接默认可以多设备同时用（面板里 `limitIp` 默认为 0，不限制）。

如果想让每台设备流量分开统计、或者想单独踢掉某台：

```bash
# 在服务器上，为第二台设备单独建一个客户端
bash /root/install.sh --force --email ipad
```

然后会用新生成的链接（`bash /root/info.sh` 可切换查看）。面板「客户端」页可以分别看到每台的流量。

---

## 7. 常见导入问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 扫码提示「无法识别的链接」 | 二维码被终端截断 | 用复制链接方式 |
| 导入成功但连不上 | 端口没放行 / IP 被墙 | 见 05 FAQ |
| iOS 提示「VPN 配置安装失败」 | 没允许 | 设置 → 通用 → VPN与设备管理 里允许 |
| Clash Verge 导入后没有节点 | 链接格式不被 YAML 解析 | 用 v2rayN / sing-box，或在面板开订阅（Clash 格式） |
| 电脑能用、手机不能用 | 手机网络限制 UDP/443 | 换 Wi-Fi 试；或加 Hysteria2 节点 |

---

下一步 → [05-faq.md](05-faq.md)
