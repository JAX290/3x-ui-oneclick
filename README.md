# 3x-ui 一键部署（完全新手版）

> 在一台**全新 VPS** 上，用**一条命令**装好代理面板和一条可直接扫码使用的节点。
> 不需要域名，不需要证书，不需要会写代码。

---

## 这个仓库是什么

它**不是**一个新协议，而是一个「安装封装 + 新手说明书」：

- 底层用的是开源项目 [3x-ui](https://github.com/MHSanaei/3x-ui)（Xray 的网页管理面板）
- 本仓库提供：一键脚本（自动装 + 自动配 + 自动出链接二维码）+ 从买 VPS 到手机上网的完整中文教程
- 上游源码已 fork 到本账号：[**JAX290/3x-ui**](https://github.com/JAX290/3x-ui)，想自己改代码或跟版本可以基于它

如果你只想快点用上，看下面「30 秒开始」；如果完全没接触过服务器，从 [docs/01-buy-vps.md](docs/01-buy-vps.md) 开始按顺序读。

---

## 它能帮你做到什么

| 你原本要做的 | 脚本自动做了 |
|---|---|
| 装依赖、校时、调内核参数 | 自动装 curl/jq/chrony 等，开启 BBR |
| 装面板、记默认密码 | 官方脚本非交互安装，随机强密码 |
| 改面板端口、改访问路径 | 随机端口（2 万–6 万）+ 随机路径 |
| 学 Xray 配置、生成密钥 | 自动生成 x25519 密钥、UUID、shortId |
| 手动建 VLESS + REALITY 入站 | 调面板 API 自动建好 |
| 自己拼 `vless://` 链接 | 直接输出链接 + 终端二维码 |
| 配防火墙 | 自动放行 SSH / 节点端口 / 面板端口 |
| 客户端装不上（连不上 GitHub） | 自动把 APK/EXE 搬到服务器，生成下载页 |
| 记一堆参数 | 全部写进 `/root/3xui-info.txt`，随时 `bash /root/info.sh` 回看 |

---

## 30 秒开始

### 前提

- 一台 **KVM** 架构的 VPS（不要 OpenVZ），Debian 12 / Ubuntu 22.04 及以上
- 至少 512MB 内存、5GB 硬盘
- 有 root 权限（云厂商默认就是 root）
- **不需要**域名，**不需要**备案

### 三步

**第 1 步：连上服务器**（Windows 用 PowerShell，Mac 用「终端」）

```bash
ssh root@你的服务器IP
```

**第 2 步：粘贴这一条命令**

```bash
bash <(curl -Ls https://raw.githubusercontent.com/JAX290/3x-ui-oneclick/main/scripts/install.sh)
```

**第 3 步：等 3–5 分钟，按屏幕提示扫码**

脚本结束时屏幕上会显示面板地址、账号密码、节点链接和二维码。

> 如果第 2 步提示下载失败（国内网络访问 GitHub 不稳定），看 [docs/02-connect-vps.md](docs/02-connect-vps.md) 最后的「下载失败怎么办」。

---

## 装完之后你会看到什么

```
============================================================
  部署完成！
============================================================

【 面板 】  浏览器打开，用来管理节点
  地址  : http://203.0.113.10:51234/tFdCpPw2z3IZDn
  用户名: Q87UemrOG9Lb
  密码  : PPV5rvcAL5umkksC7i

【 节点链接 】  手机/电脑客户端里“从剪贴板导入”
  vless://1111...@203.0.113.10:443?type=tcp&security=reality&...

【 二维码 】  手机客户端扫码直接导入
  ██████████████████
  ██  ▄▄▄▄▄  ██  ▄▄ ...
```

这些信息同时保存在服务器 `/root/3xui-info.txt`（仅 root 可读）。

---

## 装完怎么用

1. 手机/电脑装一个客户端 → 见 [docs/04-client-setup.md](docs/04-client-setup.md)
2. 把上面那条 `vless://` 链接复制过去，或直接扫码
3. 打开客户端开关，浏览器访问 `https://www.google.com` 验证

> **手机/电脑连不上 GitHub 下不了客户端？** 部署时脚本已经把 APK/EXE 搬到你的服务器上并开了下载页，
> 浏览器打开脚本最后打印的地址（形如 `http://你的IP/`）按系统点下载即可，详见 [docs/04](docs/04-client-setup.md)。

---

## 服务器上常用的几条命令

| 想做什么 | 命令 |
|---|---|
| 再看一次面板地址/链接/二维码 | `bash /root/info.sh` |
| 重启面板（改配置后） | `systemctl restart x-ui` |
| 看面板运行状态 | `systemctl status x-ui --no-pager` |
| 打开官方管理菜单 | `x-ui` |
| 更新客户端安装包（APK/EXE） | `bash /root/fetch-clients.sh --force` |
| 看安装日志 | `cat /var/log/3xui-oneclick.log` |
| 卸载 | `bash /root/uninstall.sh` |

> 以上脚本在部署时会自动放到 `/root`；没装过也可以直接用仓库里的完整地址运行（见 docs/03）。

---

## 目录

| 文档 | 适合谁 | 内容 |
|---|---|---|
| [docs/01-buy-vps.md](docs/01-buy-vps.md) | 还没买服务器 | 配置怎么选、机房怎么选、避坑 |
| [docs/02-connect-vps.md](docs/02-connect-vps.md) | 不会连服务器 | Windows/Mac 连 SSH、下载失败怎么办 |
| [docs/03-oneclick.md](docs/03-oneclick.md) | 准备部署 | 一键命令详解、参数、手动兜底 |
| [docs/04-client-setup.md](docs/04-client-setup.md) | 装客户端 | 手机/电脑各平台导入与验证 |
| [docs/05-faq.md](docs/05-faq.md) | 出问题了 | 打不开面板 / 连不上 / 没网 / 很慢 |
| [docs/06-maintain.md](docs/06-maintain.md) | 长期使用 | 备份、升级、加设备、换端口 |

---

## 脚本参数（进阶，可不看）

```bash
bash /root/install.sh --help
```

| 参数 | 作用 |
|---|---|
| `--dry-run` | 只打印计划，不改系统（可以先看看它要干什么） |
| `--dest HOST:PORT` | 换 REALITY 伪装目标（默认 `www.microsoft.com:443`） |
| `--sni NAME` | 伪装目标的域名，通常与 dest 主机名一致 |
| `--port 8443` | 换节点端口（默认 443） |
| `--panel-port 30000` | 指定面板端口 |
| `--email phone` | 客户端名字（多设备时用得上） |
| `--no-firewall` | 不碰防火墙（自己在云控制台放行） |
| `--no-clients` | 不下载客户端安装包、不开下载页（省流量/时间） |
| `--force` | 面板已装过时继续配置 |
| `--reinstall` | 卸载重装 |

---

## 安全提醒（请务必看）

1. **面板端口和路径是随机的，但仍建议只在可信网络打开**；更安全的方式是 SSH 隧道：
   `ssh -L 面板端口:127.0.0.1:面板端口 root@服务器IP`，然后访问 `http://127.0.0.1:面板端口/路径`
2. **节点链接等于钥匙**，发出去别人就能白用你的流量。不要发群里，不要截图带链接。
3. 一台 VPS 只给自己和信任的人用；不要拿它做违法的事。
4. 云厂商的「安全组」和系统防火墙是两层，两边都要放行端口。
5. 请遵守你所在地区的法律法规；本仓库只提供技术工具，使用后果由使用者自负。

---

## 已知限制

- 只支持 **systemd** 的 Linux（Debian/Ubuntu/RHEL 系/Arch）；Alpine、Windows 请走官方安装方式
- 需要能访问 GitHub 下载安装脚本（失败会自动换镜像；全失败时见 docs/02 的离线方案）
- 脚本创建的是 **VLESS + REALITY** 单协议节点。需要 Hysteria2/TUIC 等，装完后在面板里手动加（面板自带）
- 上游 3x-ui 更新很快，脚本按 v3.11.0 的接口编写；如果面板 API 有变动导致「自动创建节点」失败，脚本会打印手动兜底步骤（两步搞定），不影响安装本身

---

## 验证状态（请先读）

| 项目 | 状态 |
|---|---|
| 脚本语法（`bash -n`） | ✅ 通过（GitHub Actions 每次推送自动跑） |
| `--dry-run` 计划输出 | ✅ 通过（CI 在 Ubuntu 上实测） |
| 入站 JSON 结构 | ✅ 已按 3x-ui v3.11.0 的 schema（前端 zod 定义 / OpenAPI）逐字段校验 |
| 客户端包清单解析 | ✅ CI 实测解析成功：v2rayNG 2.3.11 / sing-box 1.14.4 / v2rayN 7.25.6 / Clash Verge 2.5.8（共 317MB） |
| 真实 VPS 端到端 | ⚠️ 首次发布，尚未在真机上跑通完整流程 |

说明：安装步骤依据 3x-ui 官方非交互安装文档（`XUI_NONINTERACTIVE=1` + `/etc/x-ui/install-result.env`）；
建节点走面板自带 API（Bearer Token / 登录 Cookie + CSRF 两条路径）。若上游接口变动导致「自动创建节点」失败，
脚本会明确提示并打印手动兜底步骤（在面板里点几下即可），**不会把服务器搞坏**。

跑通之后欢迎在 Issue 里报一下系统版本，我会把已验证的环境补到这里。

---

## 许可证

- 本仓库的脚本与文档：MIT
- 3x-ui 本体：GPL-3.0（版权归 MHSanaei 及贡献者）
- Xray-core：MPL-2.0

本项目与 3x-ui 官方无隶属关系，仅为个人使用的安装封装。
