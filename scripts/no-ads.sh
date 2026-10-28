#!/usr/bin/env bash
# =============================================================================
#  去掉 3x-ui 面板上的赞助广告（新手版 v1.0.0）
#
#  原理：3x-ui v3.x 的面板会从 GitHub 拉取赞助商列表
#        (MHSanaei/sponsors 仓库) 并在「登录页 / 仪表盘 / 页面顶部」展示。
#        本脚本把该域名在这个服务内解析到 127.0.0.1，使请求立即失败；
#        面板前端的逻辑是「拉取失败 = 不显示」，于是广告全部消失。
#
#  做法：给 x-ui 服务加一个 systemd drop-in，把它的 /etc/hosts 换成一个
#        「屏蔽 raw.githubusercontent.com」的副本 —— 只影响 x-ui 这个服务，
#        不影响系统其它程序，也不改全局 hosts。
#
#  用法：
#    bash no-ads.sh              # 关闭广告（可重复执行）
#    bash no-ads.sh --dry-run    # 只看会做什么
#    bash no-ads.sh --restore    # 恢复官方行为（广告回来）
#    bash no-ads.sh --global     # 兜底：直接改系统 /etc/hosts（不推荐）
#    bash no-ads.sh --help
#
#  副作用：面板里的「更新面板」按钮会失效（它也要从 raw.githubusercontent.com
#          取 update.sh）。用 x-ui 菜单更新、或重跑本站的 install.sh 不受影响。
# =============================================================================
set -Eeuo pipefail

SCRIPT_VERSION="1.0.0"
DROPIN_DIR="/etc/systemd/system/x-ui.service.d"
DROPIN_FILE="${DROPIN_DIR}/no-ads.conf"
HOSTS_OVERRIDE="/etc/x-ui/hosts-noads"
GLOBAL_MARK="3x-ui-no-ads"
BLOCK_HOSTS=("127.0.0.1 raw.githubusercontent.com" "::1 raw.githubusercontent.com")

MODE="apply"; GLOBAL="0"
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_RED=$'\033[31m'
    C_BLU=$'\033[36m'; C_BLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
    C_GRN=""; C_YEL=""; C_RED=""; C_BLU=""; C_BLD=""; C_DIM=""; C_RST=""
fi
msg()  { printf '%s\n' "$*"; }
step() { printf '\n%s\n' "${C_BLU}${C_BLD}==> $*${C_RST}"; }
ok()   { printf '%s\n' "${C_GRN}  ✓ $*${C_RST}"; }
warn() { printf '%s\n' "${C_YEL}  ! $*${C_RST}" >&2; }
err()  { printf '%s\n' "${C_RED}  ✗ $*${C_RST}" >&2; }
die()  { err "$*"; exit 1; }

usage() {
    cat <<'EOF'
去掉 3x-ui 面板广告（新手版）

用法: bash no-ads.sh [选项]

选项:
  --dry-run    只打印将要做的修改，不执行
  --restore    恢复（删除屏蔽，广告会重新出现）
  --global     兜底模式：直接写系统 /etc/hosts（会影响整台机器访问 raw.githubusercontent.com）
  -h, --help   显示帮助

默认模式只影响 x-ui 服务本身，不改全局配置，随时可用 --restore 撤销。
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) MODE="dryrun"; shift ;;
        --restore) MODE="restore"; shift ;;
        --global) GLOBAL="1"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

[[ "$MODE" == "dryrun" ]] || [[ $EUID -eq 0 ]] || die "请用 root 运行：sudo -i 后重新执行。"

# ---------------------------- dry-run（先于任何检查） ------------------------
if [[ "$MODE" == "dryrun" ]]; then
    step "Dry-run：只打印计划，不做任何修改"
    msg "  1) 生成 ${HOSTS_OVERRIDE}"
    msg "     内容 = 当前 /etc/hosts + 下面两行："
    for l in "${BLOCK_HOSTS[@]}"; do msg "       ${l}"; done
    msg "  2) 写入 systemd drop-in：${DROPIN_FILE}"
    msg "     [Service]"
    msg "     BindReadOnlyPaths=${HOSTS_OVERRIDE}:/etc/hosts"
    msg "  3) systemctl daemon-reload && systemctl restart x-ui"
    msg "  4) 请求面板 /sponsors 验证广告是否消失（拉取失败 = 前端不渲染）"
    msg ""
    msg "  可加 --global 改用「直接写系统 /etc/hosts」的兜底方案；--restore 撤销。"
    exit 0
fi

[[ -d /run/systemd/system ]] || die "本脚本要求 systemd。"

PANEL_PORT=""; WEB_BASE_PATH=""; API_TOKEN=""
load_panel() {
    if [[ -f /etc/x-ui/install-result.env ]]; then
        # shellcheck disable=SC1091
        . /etc/x-ui/install-result.env
        PANEL_PORT="${XUI_PANEL_PORT:-}"
        WEB_BASE_PATH="${XUI_WEB_BASE_PATH:-}"
        API_TOKEN="${XUI_API_TOKEN:-}"
    fi
    if [[ -z "$PANEL_PORT" ]] && command -v x-ui >/dev/null 2>&1; then
        local show
        show=$(x-ui setting -show true 2>/dev/null || true)
        PANEL_PORT=$(printf '%s\n' "$show" | grep -Eo 'port: [0-9]+' | head -1 | awk '{print $2}')
        WEB_BASE_PATH=$(printf '%s\n' "$show" | grep -Eo 'webBasePath: .+' | head -1 | awk '{print $2}' | sed 's#^/##; s#/$##')
    fi
    WEB_BASE_PATH="${WEB_BASE_PATH#/}"; WEB_BASE_PATH="${WEB_BASE_PATH%/}"
    if [[ -n "$WEB_BASE_PATH" ]]; then
        PANEL_BASE="http://127.0.0.1:${PANEL_PORT}/${WEB_BASE_PATH}"
    else
        PANEL_BASE="http://127.0.0.1:${PANEL_PORT}"
    fi
}

check_sponsors() { # 返回 0=已无广告
    [[ -n "$PANEL_PORT" ]] || return 2
    local resp i
    for i in $(seq 1 20); do
        resp=$(curl -sS --max-time 5 "${PANEL_BASE}/sponsors" 2>/dev/null || true)
        [[ -n "$resp" ]] && break
        sleep 1
    done
    local success count
    success=$(printf '%s' "$resp" | jq -r '.success // false' 2>/dev/null || echo false)
    count=$(printf '%s' "$resp" | jq -r '.obj.sponsors | length' 2>/dev/null || echo "?")
    if [[ "$success" != "true" ]]; then
        ok "面板 /sponsors 已返回空（拉取失败 → 前端不渲染广告）"
        return 0
    fi
    if [[ "$count" == "0" ]]; then
        ok "面板 /sponsors 返回 0 条赞助"
        return 0
    fi
    warn "面板 /sponsors 仍返回 ${count} 条赞助，屏蔽可能没生效"
    return 1
}

# ---------------------------- 恢复 -------------------------------------------
restore_all() {
    step "恢复官方行为"
    if [[ -f "$DROPIN_FILE" ]]; then
        rm -f "$DROPIN_FILE"
        ok "已删除 drop-in: ${DROPIN_FILE}"
    else
        ok "没有 drop-in，跳过"
    fi
    rmdir "$DROPIN_DIR" 2>/dev/null || true
    if [[ -f /etc/hosts ]] && grep -q "$GLOBAL_MARK" /etc/hosts; then
        sed -i "/$GLOBAL_MARK/d" /etc/hosts
        ok "已删除 /etc/hosts 里的屏蔽行"
    fi
    systemctl daemon-reload 2>/dev/null || true
    systemctl restart x-ui 2>/dev/null || warn "重启 x-ui 失败，请手动 systemctl restart x-ui"
    rm -f "$HOSTS_OVERRIDE" 2>/dev/null || true
    ok "已恢复（浏览器 Ctrl+Shift+R 硬刷新后，广告会重新出现）"
    exit 0
}

if [[ "$MODE" == "restore" ]]; then
    restore_all
fi

# ---------------------------- 检查 -------------------------------------------
command -v systemctl >/dev/null 2>&1 || die "没有 systemctl"
systemctl list-unit-files 2>/dev/null | grep -q '^x-ui\.service' || \
    systemctl cat x-ui >/dev/null 2>&1 || die "没找到 x-ui 服务，请先安装 3x-ui。"

load_panel
if [[ -n "$PANEL_PORT" ]]; then
    ok "面板：127.0.0.1:${PANEL_PORT}/${WEB_BASE_PATH}"
else
    warn "没读到面板端口，最后会跳过在线验证（不影响屏蔽本身）"
fi

# ---------------------------- 全局模式 ---------------------------------------
if [[ "$GLOBAL" == "1" ]]; then
    step "兜底模式：直接修改系统 /etc/hosts"
    warn "这会让整台机器都无法访问 raw.githubusercontent.com（包括以后跑本站脚本）。"
    cp -a /etc/hosts "/etc/hosts.bak.$(date +%s)" 2>/dev/null || true
    if grep -q "$GLOBAL_MARK" /etc/hosts; then
        ok "已经屏蔽过，跳过"
    else
        {
            echo ""
            echo "# 3x-ui 广告屏蔽 ${GLOBAL_MARK}"
            for l in "${BLOCK_HOSTS[@]}"; do echo "${l} # ${GLOBAL_MARK}"; done
        } >>/etc/hosts
        ok "已写入 /etc/hosts"
    fi
    systemctl restart x-ui 2>/dev/null || true
    check_sponsors || true
    msg ""
    msg "恢复： bash no-ads.sh --restore"
    exit 0
fi

# ---------------------------- 方案 A：drop-in ---------------------------------
step "屏蔽赞助域名（仅对 x-ui 服务生效）"

mkdir -p /etc/x-ui
{
    echo "# 由 3x-ui-oneclick 的 no-ads.sh 生成；原文件备份见 /etc/hosts"
    grep -v "raw.githubusercontent.com" /etc/hosts 2>/dev/null || true
    echo ""
    echo "# 3x-ui 广告屏蔽"
    for l in "${BLOCK_HOSTS[@]}"; do echo "$l"; done
} >"${HOSTS_OVERRIDE}.tmp"
mv -f "${HOSTS_OVERRIDE}.tmp" "$HOSTS_OVERRIDE"
chmod 644 "$HOSTS_OVERRIDE"
ok "已生成 ${HOSTS_OVERRIDE}"

mkdir -p "$DROPIN_DIR"
cat >"$DROPIN_FILE" <<CONF
# 由 3x-ui-oneclick 的 no-ads.sh 生成：把服务内的 /etc/hosts 换成屏蔽赞助域名的版本
# 撤销： bash no-ads.sh --restore
[Service]
BindReadOnlyPaths=${HOSTS_OVERRIDE}:/etc/hosts
CONF
ok "已写入 drop-in：${DROPIN_FILE}"

step "重启 x-ui 并验证"
systemctl daemon-reload
if ! systemctl restart x-ui 2>/dev/null; then
    warn "重启失败，可能是不支持 BindReadOnlyPaths，正在回滚..."
    rm -f "$DROPIN_FILE"; rmdir "$DROPIN_DIR" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    systemctl restart x-ui 2>/dev/null || true
    die "已回滚，面板保持原样。可改用 --global 模式。"
fi

sleep 3
if ! systemctl is-active --quiet x-ui; then
    warn "x-ui 没有起来，正在回滚 drop-in..."
    rm -f "$DROPIN_FILE"; rmdir "$DROPIN_DIR" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    systemctl restart x-ui 2>/dev/null || true
    die "已回滚。请检查 journalctl -u x-ui -n 50，或改用 --global 模式。"
fi
ok "x-ui 运行中"

if [[ -z "$PANEL_PORT" ]]; then
    warn "没读到面板端口，无法在线验证。屏蔽配置已写入，请自行打开面板确认（Ctrl+Shift+R）。"
    exit 0
fi

if check_sponsors; then
    msg ""
    printf '%s\n' "${C_GRN}${C_BLD}广告已关闭。${C_RST}"
    msg "${C_DIM}浏览器请按 Ctrl+Shift+R 强制刷新（前端有 1 小时缓存）。${C_RST}"
    msg "${C_DIM}恢复： bash /root/no-ads.sh --restore${C_RST}"
else
    warn "已验证失败，可尝试： bash /root/no-ads.sh --global"
    exit 1
fi
msg ""
