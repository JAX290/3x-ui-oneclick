#!/usr/bin/env bash
# =============================================================================
#  3x-ui 卸载脚本（新手版）
#
#  作用：停掉并删除 3x-ui 面板、Xray 内核、配置与数据库。
#  警告：数据库删除后节点信息不可恢复，请在执行前备份 /etc/x-ui/x-ui.db
#
#  用法：bash uninstall.sh           # 会二次确认
#        bash uninstall.sh -y        # 不确认，直接卸
#        bash uninstall.sh --keep-db # 保留数据库（只删程序）
# =============================================================================
set -Eeuo pipefail

ASSUME_YES="0"
KEEP_DB="0"
for a in "$@"; do
    case "$a" in
        -y|--yes) ASSUME_YES="1" ;;
        --keep-db) KEEP_DB="1" ;;
        -h|--help)
            echo "用法: bash uninstall.sh [-y] [--keep-db]"
            exit 0 ;;
        *) echo "未知参数: $a" >&2; exit 1 ;;
    esac
done

err() { printf '\033[31m  ✗ %s\033[0m\n' "$*" >&2; }
ok()  { printf '\033[32m  ✓ %s\033[0m\n' "$*"; }
msg() { printf '%s\n' "$*"; }

[[ $EUID -eq 0 ]] || { err "请用 root 运行： sudo bash uninstall.sh"; exit 1; }

msg ""
msg "将要删除："
msg "  · 3x-ui 服务与 /usr/local/x-ui（含 Xray 内核）"
msg "  · 管理命令 /usr/bin/x-ui"
msg "  · 配置与数据库 $([[ "$KEEP_DB" == "1" ]] && echo '（保留）' || echo '/etc/x-ui（含节点和账号，删除后不可恢复）')"
msg ""

if [[ "$ASSUME_YES" != "1" ]]; then
    printf '确认卸载？输入 yes 继续：'
    read -r answer
    [[ "$answer" == "yes" ]] || { msg "已取消。"; exit 0; }
fi

msg ""
msg "==> 停止服务"
systemctl stop x-ui 2>/dev/null || true
systemctl disable x-ui 2>/dev/null || true
ok "服务已停止"

msg "==> 删除程序文件"
rm -rf /usr/local/x-ui
rm -f /usr/bin/x-ui /etc/systemd/system/x-ui.service
rm -rf /var/log/x-ui
rm -f /etc/systemd/system/x-ui.service.d/no-ads.conf
rmdir /etc/systemd/system/x-ui.service.d 2>/dev/null || true
rm -f /etc/x-ui/hosts-noads
if [[ -f /etc/hosts ]] && grep -q '3x-ui-no-ads' /etc/hosts; then
    sed -i '/3x-ui-no-ads/d' /etc/hosts
fi
systemctl daemon-reload 2>/dev/null || true
ok "程序文件已删除"

if [[ "$KEEP_DB" == "1" ]]; then
    ok "已保留 /etc/x-ui（账号、节点、订阅都还在）"
else
    msg "==> 删除配置与数据库"
    rm -rf /etc/x-ui
    ok "配置已删除"
fi

msg ""
msg "卸载完成。"
[[ "$KEEP_DB" == "1" ]] && msg "数据库仍在 /etc/x-ui/x-ui.db，重装后会被自动识别。"
msg "留着 ufw/BBR/chrony 不影响系统，想关掉可以： ufw disable"
msg ""
