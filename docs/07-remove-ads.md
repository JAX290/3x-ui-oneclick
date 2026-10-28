# 07 · 去掉面板广告（赞助位）

> 3x-ui 从 v3.x 开始，在**登录页、仪表盘、部分页面顶部**放了赞助商广告位。
> 本仓库的部署脚本**默认已经帮你关掉**，这一页讲原理、验证和恢复。

---

## 1. 确认是否已关闭

浏览器打开面板（登录页就能看出），按 `Ctrl + Shift + R` 强刷。看不到广告条即已关闭。

服务器上也能验证：

```bash
bash /root/no-ads.sh --dry-run     # 看当前状态与将要做的事
```

或直接看接口返回值：

```bash
# 把端口/路径换成你自己的（bash /root/info.sh 里有）
curl -s http://127.0.0.1:面板端口/面板路径/sponsors
# 已关闭：{"success":false}  或  {"success":true,"obj":{"sponsors":[]}}
# 未关闭：{"success":true,"obj":{"sponsors":[{...}]}}
```

---

## 2. 手动关闭（已部署过的机器）

```bash
bash /root/no-ads.sh
```

如果没有这个文件，从仓库拉一份：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/JAX290/3x-ui-oneclick/main/scripts/no-ads.sh)
```

关闭后会重启一次 `x-ui`（几秒钟，客户端会短暂断开重连）。然后浏览器 `Ctrl + Shift + R`。

---

## 3. 原理（不用懂也能跳过）

- 面板的广告来自后端从 `raw.githubusercontent.com` 拉取的一个赞助商列表 JSON；
- 拉不到时，后端返回空、前端就不渲染广告位（这是官方的降级逻辑）；
- 脚本给 `x-ui` 服务加了一个 systemd drop-in，把这个服务的 `/etc/hosts`
  换成一个「屏蔽该域名」的副本（`BindReadOnlyPaths`）。

**只影响 x-ui 这一个服务**，不改系统全局 hosts，不碰你的节点流量，不影响其它软件。

---

## 4. 副作用（已知）

| 影响 | 说明 |
|---|---|
| 面板里的「更新面板」按钮 | 会失效（它也要从同一个域名取 `update.sh`）。用 `x-ui` 菜单更新，或重跑 `install.sh`，都不受影响 |
| 其它一切 | 不受影响：系统访问 GitHub、我们的脚本、Xray 代理都照常 |

---

## 5. 恢复官方行为

```bash
bash /root/no-ads.sh --restore
```

删除 drop-in → 重启 → 广告回来。面板更新按钮同时恢复。

---

## 6. 兜底模式（drop-in 不生效时）

极少数系统不支持 `BindReadOnlyPaths`，脚本会自动回滚并提示。此时可以：

```bash
bash /root/no-ads.sh --global
```

代价：**整台机器**都无法访问 `raw.githubusercontent.com`（以后跑本站脚本、或手动 `curl` GitHub raw 都会失败，但 `api.github.com` / `github.com` 正常）。
恢复：`bash /root/no-ads.sh --restore`。

---

## 7. 常见问题

**Q：执行了，但刷新后广告还在？**
前端有 1 小时缓存 + 浏览器缓存。`Ctrl + Shift + R`；还不行就退出登录重新登录一次。

**Q：会不会影响节点速度/稳定性？**
不会。这只是屏蔽面板自身的一个 HTTP 请求，和 Xray 转发流量无关。

**Q：升级 3x-ui 后还要重跑吗？**
drop-in 放在 `/etc/systemd/system/x-ui.service.d/`，**升级不会覆盖**，一般无需重跑。
如果升级后广告回来了，重跑一次 `bash /root/no-ads.sh` 即可。

**Q：卸载 3x-ui 时会不会残留？**
`bash /root/uninstall.sh` 会顺带清理 drop-in 和 hosts 覆盖文件。

**Q：这么做合适吗？**
3x-ui 是 GPL-3.0 开源项目，赞助位是作者的收入来源之一。这里只是在你自己的服务器上关闭展示，
属于本机配置行为；**请不要把「去广告版」再分发或用于商业转售**。如果觉得项目好用，可以去项目主页赞助作者。

---

返回 → [README](../README.md)
