#!/usr/bin/env bash
# =============================================================================
#  3x-ui 信息查看脚本（新手版）
#
#  作用：随时查看面板地址/账号/节点链接/二维码，不需要记任何参数。
#  用法：bash info.sh
# =============================================================================
set -uo pipefail

INSTALL_RESULT="/etc/x-ui/install-result.env"
STATE_FILE="/etc/x-ui/oneclick.env"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_GRN=$'\033[32m'; C_BLU=$'\033[36m'; C_BLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
    C_GRN=""; C_BLU=""; C_BLD=""; C_DIM=""; C_RST=""
fi
msg() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "  ! $*" >&2; }

if [[ $EUID -ne 0 ]]; then
    warn "建议用 root 运行： sudo bash info.sh"
fi

PANEL_PORT=""; WEB_BASE_PATH=""; API_TOKEN=""; PANEL_USER=""; PANEL_PASS=""
if [[ -f "$INSTALL_RESULT" ]]; then
    # shellcheck disable=SC1090
    . "$INSTALL_RESULT"
    PANEL_PORT="${XUI_PANEL_PORT:-}"
    WEB_BASE_PATH="${XUI_WEB_BASE_PATH:-}"
    API_TOKEN="${XUI_API_TOKEN:-}"
    PANEL_USER="${XUI_USERNAME:-}"
    PANEL_PASS="${XUI_PASSWORD:-}"
fi
if [[ -z "$PANEL_PORT" ]] && command -v x-ui >/dev/null 2>&1; then
    SHOW=$(x-ui setting -show true 2>/dev/null || true)
    PANEL_PORT=$(printf '%s\n' "$SHOW" | grep -Eo 'port: [0-9]+' | head -1 | awk '{print $2}')
    WEB_BASE_PATH=$(printf '%s\n' "$SHOW" | grep -Eo 'webBasePath: .+' | head -1 | awk '{print $2}' | sed 's#^/##; s#/$##')
    [[ -z "$API_TOKEN" ]] && API_TOKEN=$(x-ui setting -getApiToken 2>/dev/null | grep -Eo 'apiToken: .+' | head -1 | awk '{print $2}')
fi
[[ -n "$PANEL_PORT" ]] || { warn "找不到面板配置，可能还没安装。先运行 bash install.sh"; exit 1; }
WEB_BASE_PATH="${WEB_BASE_PATH#/}"; WEB_BASE_PATH="${WEB_BASE_PATH%/}"
[[ "$WEB_BASE_PATH" == "/" ]] && WEB_BASE_PATH=""

CLIENT_EMAIL=""; REMARK=""; VLESS_PORT=""; DEST=""; SNI=""; UUID=""; SHORT_ID=""; PUB=""; IP=""
if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
    CLIENT_EMAIL="${CLIENT_EMAIL:-}"
    REMARK="${CLIENT_REMARK:-}"
    VLESS_PORT="${VLESS_PORT:-}"
    DEST="${DEST:-}"
    SNI="${SNI:-}"
    UUID="${UUID:-}"
    SHORT_ID="${SHORT_ID:-}"
    PUB="${PUBLIC_KEY:-}"
    IP="${SERVER_IP:-}"
fi
# shellcheck disable=SC2153
[[ -n "${SERVER_IP:-}" ]] && IP="${SERVER_IP}"

if [[ -z "$IP" ]]; then
    IP=$(curl -4 -fsS --max-time 6 https://api.ipify.org 2>/dev/null | tr -d '[:space:]' || true)
fi

if [[ -n "$WEB_BASE_PATH" ]]; then
    PANEL_BASE="http://127.0.0.1:${PANEL_PORT}/${WEB_BASE_PATH}"
else
    PANEL_BASE="http://127.0.0.1:${PANEL_PORT}"
fi

msg ""
printf '%s\n' "${C_GRN}${C_BLD}======== 3x-ui 当前配置 ========${C_RST}"
printf '%s\n' "${C_BLD}【面板】${C_RST}"
msg "  地址  : ${C_BLU}http://${IP:-服务器IP}:${PANEL_PORT}/${WEB_BASE_PATH}${C_RST}"
[[ -n "$PANEL_USER" ]] && msg "  用户名: ${PANEL_USER}"
[[ -n "$PANEL_PASS" ]] && msg "  密码  : ${PANEL_PASS}"
msg "  服务  : $(systemctl is-active x-ui 2>/dev/null || echo unknown)"
msg ""

# 实时拉取节点链接（面板运行时会覆盖旧链接）
LINK=""
if [[ -n "$API_TOKEN" && -n "$CLIENT_EMAIL" ]]; then
    NO_PROXY="127.0.0.1,localhost" link_json=$(curl -sS --max-time 10 \
        -H "Authorization: Bearer ${API_TOKEN}" \
        "${PANEL_BASE}/panel/api/clients/links/${CLIENT_EMAIL}" 2>/dev/null || true)
    if [[ -n "${link_json:-}" ]]; then
        LINK=$(printf '%s' "$link_json" | jq -r '.obj[0] // empty' 2>/dev/null || true)
    fi
fi
if [[ -z "$LINK" && -n "$UUID" && -n "$PUB" && -n "$IP" ]]; then
    LINK="vless://${UUID}@${IP}:${VLESS_PORT}?type=tcp&security=reality&encryption=none&pbk=${PUB}&fp=chrome&sni=${SNI}&sid=${SHORT_ID}&spx=%2F&flow=xtls-rprx-vision#${REMARK:-node}"
fi

if [[ -n "$LINK" ]]; then
    printf '%s\n' "${C_BLD}【节点】${C_RST}"
    [[ -n "$DEST" ]] && msg "  伪装目标: ${DEST}"
    [[ -n "$SNI" ]] && msg "  SNI     : ${SNI}"
    msg "  链接    : ${LINK}"
    msg ""
    if command -v qrencode >/dev/null 2>&1; then
        printf '%s\n' "${C_BLD}【二维码】${C_RST}"
        qrencode -t ANSIUTF8 -m 1 "$LINK" || warn "二维码生成失败"
        msg ""
    fi
else
    warn "没拿到节点链接。可能是还没建节点，或面板路径/端口改过了。"
    msg "  到面板里看：${PANEL_BASE}/"
fi

if [[ -f /root/3xui-info.txt ]]; then
    msg "${C_DIM}完整信息文件： /root/3xui-info.txt${C_RST}"
fi
msg "${C_DIM}常用： systemctl restart x-ui（重启）  bash uninstall.sh（卸载）${C_RST}"
msg ""
