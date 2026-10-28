#!/usr/bin/env bash
# =============================================================================
#  客户端安装包一键搬运 + 下载页（新手版 v1.0.0）
#
#  作用：把 Android 的 APK、Windows 的 EXE/ZIP 等客户端，从 GitHub 下载到你的
#        VPS 上，并启动一个静态下载页面。这样手机/电脑即使连不上 GitHub，
#        也能直接访问 http://你的VPS_IP/ 下载客户端。
#
#  用法：
#    bash fetch-clients.sh                # 下载常用包（约 320MB）+ 启动下载页
#    bash fetch-clients.sh --dry-run      # 只查询版本/大小，不下载
#    bash fetch-clients.sh --all          # 额外包含 universal/arm64/dmg 等
#    bash fetch-clients.sh --port 8080    # 换下载页端口（默认优先 80）
#    bash fetch-clients.sh --no-service   # 只下载，不启动网页服务
#    bash fetch-clients.sh --force        # 重新下载已存在的文件
#    bash fetch-clients.sh --help
#
#  注意：下载页是公开的（只含安装包，不含节点信息）。
# =============================================================================
set -Eeuo pipefail

SCRIPT_VERSION="1.0.0"
WEB_ROOT="${WEB_ROOT:-/var/www/clients}"
SERVICE_NAME="3xui-clients"
UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
STATE_FILE="/etc/x-ui/clients.env"
INFO_FILE="/root/3xui-info.txt"
MIRRORS=("" "https://gh-proxy.com/" "https://ghfast.top/" "https://ghproxy.net/")

DO_ALL="0"; FORCE="0"; NO_SERVICE="0"; DRY_RUN="0"; PORT="${CLIENTS_PORT:-}"
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
客户端安装包下载页（新手版）

用法: bash fetch-clients.sh [选项]

选项:
  --all            额外下载 universal APK、arm64 Windows、macOS dmg、Hiddify 等
  --port PORT      下载页监听端口（默认优先 80，被占用则 8080/随机）
  --dir PATH       存放目录（默认 /var/www/clients）
  --no-service     只下载文件，不启动网页服务、不开防火墙
  --force          已存在的文件也重新下载
  --dry-run        只查询最新版本和体积，不下载
  -h, --help       显示帮助

下载页地址会在结束时打印（形如 http://1.2.3.4/）。
节点链接不放在下载页上，避免泄露。
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all) DO_ALL="1"; shift ;;
        --port) PORT="${2:?--port 需要参数}"; shift 2 ;;
        --port=*) PORT="${1#*=}"; shift ;;
        --dir) WEB_ROOT="${2:?--dir 需要参数}"; shift 2 ;;
        --dir=*) WEB_ROOT="${1#*=}"; shift ;;
        --no-service) NO_SERVICE="1"; shift ;;
        --force) FORCE="1"; shift ;;
        --dry-run) DRY_RUN="1"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

# ---------------------------- 基础检查 ---------------------------------------
[[ "$(uname -s)" == "Linux" ]] || die "只能在 Linux 上运行。"
[[ $EUID -eq 0 ]] || die "请用 root 运行：sudo -i 后重新执行。"

if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
else
    OS_ID="unknown"
fi

PKG="apt"
case "$OS_ID" in
    debian|ubuntu|armbian|linuxmint|pop) PKG="apt" ;;
    fedora|centos|rhel|almalinux|rocky|ol|amzn|virtuozzo) PKG="dnf" ;;
    arch|manjaro|parch) PKG="pacman" ;;
esac

need_pkg() { # $1=apt名 $2=dnf名 $3=pac名 $4=命令名
    command -v "$4" >/dev/null 2>&1 && return 0
    warn "缺少 $4，尝试安装..."
    case "$PKG" in
        apt)  DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$1" ;;
        dnf)  dnf install -y -q "$2" ;;
        pacman) pacman -Sy --noconfirm --needed "$3" ;;
    esac
    command -v "$4" >/dev/null 2>&1
}

need_pkg jq jq jq jq || die "jq 安装失败"
need_pkg curl curl curl curl || die "curl 安装失败"
need_pkg python3 python3 python python3 || die "python3 安装失败（下载页需要它）"
command -v qrencode >/dev/null 2>&1 || need_pkg qrencode qrencode qrencode qrencode || true

# ---------------------------- 公网 IP ----------------------------------------
detect_ip() {
    local ip url
    for url in https://api.ipify.org https://ifconfig.me/ip https://ipinfo.io/ip; do
        ip=$(curl -4 -fsS --max-time 6 "$url" 2>/dev/null | tr -d '[:space:]' || true)
        [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && { echo "$ip"; return 0; }
    done
    echo ""
}
PUBLIC_IP="$(detect_ip)"

# ---------------------------- 清单 -------------------------------------------
# 格式: 分类|友好文件名|仓库|资源正则|说明|是否仅 --all
ENTRIES=(
  "android|v2rayNG-android-arm64.apk|2dust/v2rayNG|^v2rayNG_[0-9.]+_arm64-v8a\.apk$|Android 主流客户端（64 位，推荐）|0"
  "android|v2rayNG-android-armv7.apk|2dust/v2rayNG|^v2rayNG_[0-9.]+_armeabi-v7a\.apk$|Android 老款 32 位手机|0"
  "android|sing-box-android-arm64.apk|SagerNet/sing-box|^SFA-[0-9.]+-arm64-v8a\.apk$|sing-box 官方客户端（备选）|0"
  "windows|v2rayN-windows-64.zip|2dust/v2rayN|^v2rayN-windows-64\.zip$|Windows 10/11 免安装，解压即用|0"
  "windows|ClashVerge-windows-x64-setup.exe|clash-verge-rev/clash-verge-rev|^Clash\.Verge_[0-9.]+_x64-setup\.exe$|Windows 图形界面，规则模式强|0"
  "android|v2rayNG-android-universal.apk|2dust/v2rayNG|^v2rayNG_[0-9.]+_universal\.apk$|通用 APK（体积大，含全部架构）|1"
  "android|sing-box-android-universal.apk|SagerNet/sing-box|^SFA-[0-9.]+-universal\.apk$|通用 APK（体积大）|1"
  "android|Hiddify-android-arm64.apk|hiddify/hiddify-app|^Hiddify-Android-arm64\.apk$|Hiddify 客户端（界面友好）|1"
  "windows|v2rayN-windows-arm64.zip|2dust/v2rayN|^v2rayN-windows-arm64\.zip$|Windows ARM64 设备|1"
  "windows|Hiddify-windows-x64-setup.exe|hiddify/hiddify-app|^Hiddify-Windows-Setup-x64\.exe$|Hiddify 客户端（备选）|1"
  "macos|ClashVerge-macos-arm64.dmg|clash-verge-rev/clash-verge-rev|^Clash\.Verge_[0-9.]+_aarch64\.dmg$|macOS Apple 芯片|1"
  "macos|ClashVerge-macos-x64.dmg|clash-verge-rev/clash-verge-rev|^Clash\.Verge_[0-9.]+_x64\.dmg$|macOS Intel 芯片|1"
)

CATEGORY_TITLE_android="Android 手机"
CATEGORY_TITLE_windows="Windows 电脑"
CATEGORY_TITLE_macos="macOS 电脑"

# 每个仓库只查一次 latest release
declare -A REPO_JSON=()
fetch_repo_json() { # $1=repo
    local repo="$1"
    [[ -n "${REPO_JSON[$repo]:-}" ]] && { printf '%s' "${REPO_JSON[$repo]}"; return 0; }
    local data
    local -a auth=()
    [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    data=$(curl -fsS --max-time 30 "${auth[@]}" -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: 3xui-oneclick' \
        "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null || true)
    if [[ -z "$data" ]] || [[ "$(printf '%s' "$data" | jq -r '.tag_name // empty' 2>/dev/null)" == "" ]]; then
        return 1
    fi
    REPO_JSON[$repo]="$data"
    printf '%s' "$data"
}

download_with_mirror() { # $1=url $2=outfile
    local url="$1" out="$2" p
    for p in "${MIRRORS[@]}"; do
        if curl -fL --progress-bar --retry 2 --connect-timeout 20 --max-time 900 \
            -o "${out}.part" "${p}${url}" 2>/dev/null; then
            if [[ -s "${out}.part" ]]; then
                mv -f "${out}.part" "$out"
                return 0
            fi
        fi
        rm -f "${out}.part"
    done
    return 1
}

# ---------------------------- 逐个解析/下载 ----------------------------------
step "查询最新版本（GitHub API）"
mkdir -p "$WEB_ROOT"
MANIFEST="$(mktemp)"
FAILED=0
TOTAL_BYTES=0

for entry in "${ENTRIES[@]}"; do
    IFS='|' read -r cat target repo pattern desc all_only <<<"$entry"
    if [[ "$all_only" == "1" && "$DO_ALL" != "1" ]]; then
        continue
    fi
    json="$(fetch_repo_json "$repo")" || { warn "$repo 查询失败，跳过"; FAILED=$((FAILED + 1)); continue; }
    tag="$(printf '%s' "$json" | jq -r '.tag_name // "unknown"')"

    read -r asset_name asset_url asset_size <<<"$(printf '%s' "$json" | jq -r --arg p "$pattern" '
        [.assets[]? | select(.name | test($p))] | sort_by(.name) | last
        | if . == null then "NONE NONE 0" else "\(.name) \(.browser_download_url) \(.size)" end')"

    if [[ "$asset_name" == "NONE" || -z "$asset_url" ]]; then
        warn "$repo 里没有匹配 $pattern 的资源（跳过 $target）"
        FAILED=$((FAILED + 1))
        continue
    fi
    size_mb=$(( (asset_size + 1048575) / 1048576 ))
    TOTAL_BYTES=$((TOTAL_BYTES + asset_size))

    if [[ "$DRY_RUN" == "1" ]]; then
        printf '  %-38s %-10s %4s MB  <- %s\n' "$target" "$tag" "$size_mb" "$asset_name"
        continue
    fi

    if [[ -f "$WEB_ROOT/$target" && "$FORCE" != "1" ]]; then
        ok "$target 已存在，跳过（--force 可重下）"
        printf '%s|%s|%s|%s|%s\n' "$target" "$cat" "$tag" "$size_mb" "$desc" >>"$MANIFEST"
        continue
    fi

    msg "  下载 ${asset_name}（${size_mb} MB）→ ${target}"
    if download_with_mirror "$asset_url" "$WEB_ROOT/$target"; then
        chmod 644 "$WEB_ROOT/$target"
        ok "完成 ${target}"
        printf '%s|%s|%s|%s|%s\n' "$target" "$cat" "$tag" "$size_mb" "$desc" >>"$MANIFEST"
    else
        warn "${target} 下载失败（GitHub 与镜像都不通？）"
        FAILED=$((FAILED + 1))
    fi
done

if [[ "$DRY_RUN" == "1" ]]; then
    msg ""
    ok "预计总大小：$(( TOTAL_BYTES / 1048576 )) MB（未下载任何文件）"
    rm -f "$MANIFEST"
    exit 0
fi

if [[ ! -s "$MANIFEST" ]]; then
    rm -f "$MANIFEST"
    die "一个文件都没下载成功。请检查 VPS 能否访问 api.github.com / github.com。"
fi

# ---------------------------- 生成下载页 -------------------------------------
step "生成下载页"

SERVICE_PORT=""
pick_port() {
    local p
    for p in "$@"; do
        if ! (echo >"/dev/tcp/127.0.0.1/${p}") 2>/dev/null; then
            echo "$p"; return 0
        fi
    done
    echo "$(( (RANDOM % 20000) + 40000 ))"
}

if [[ -n "$PORT" ]]; then
    SERVICE_PORT="$PORT"
elif [[ "$NO_SERVICE" == "1" ]]; then
    SERVICE_PORT=""
else
    SERVICE_PORT="$(pick_port 80 8080 8888)"
fi

if [[ -n "$PUBLIC_IP" && -n "$SERVICE_PORT" ]]; then
    if [[ "$SERVICE_PORT" == "80" ]]; then
        PAGE_URL="http://${PUBLIC_IP}/"
    else
        PAGE_URL="http://${PUBLIC_IP}:${SERVICE_PORT}/"
    fi
else
    PAGE_URL=""
fi

{
cat <<'HTML_HEAD'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>客户端下载</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 24px 16px 64px; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI",
         "PingFang SC", "Microsoft YaHei", sans-serif; line-height: 1.6; background: #f5f6f8; color: #1f2328; }
  @media (prefers-color-scheme: dark) { body { background: #16181d; color: #e6e8eb; } .card { background: #1f2229 !important; } th { background: #262a33 !important; } td { border-color: #2f3440 !important; } a { color: #6cb6ff !important; } }
  .wrap { max-width: 860px; margin: 0 auto; }
  h1 { font-size: 22px; margin: 0 0 4px; }
  .sub { color: #6b7280; font-size: 14px; margin-bottom: 20px; }
  .card { background: #fff; border-radius: 12px; padding: 16px 18px; margin: 16px 0;
          box-shadow: 0 1px 2px rgba(0,0,0,.06), 0 4px 16px rgba(0,0,0,.04); }
  h2 { font-size: 16px; margin: 0 0 10px; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  th, td { text-align: left; padding: 8px 6px; border-bottom: 1px solid #e5e7eb; }
  th { background: #fafbfc; font-weight: 600; font-size: 13px; color: #6b7280; }
  tr:last-child td { border-bottom: none; }
  a.dl { display: inline-block; padding: 4px 10px; border-radius: 6px; background: #2563eb;
         color: #fff !important; text-decoration: none; font-size: 13px; white-space: nowrap; }
  .meta { color: #6b7280; font-size: 12px; }
  .note { font-size: 13px; color: #6b7280; }
  code { background: rgba(127,127,127,.15); padding: 1px 5px; border-radius: 4px; font-size: 13px; }
  .tag { display: inline-block; font-size: 11px; padding: 1px 6px; border-radius: 999px;
         background: rgba(37,99,235,.12); color: #2563eb; margin-left: 4px; }
</style>
</head>
<body>
<div class="wrap">
  <h1>客户端下载</h1>
  <div class="sub">这些文件直接来自这台服务器，不需要访问 GitHub。装好后用节点链接/二维码导入即可。</div>
HTML_HEAD

for cat in android windows macos; do
    if ! grep -q "|${cat}|" "$MANIFEST"; then continue; fi
    var="CATEGORY_TITLE_${cat}"
    title="${!var}"
    printf '  <div class="card">\n    <h2>%s</h2>\n    <table>\n      <tr><th>客户端</th><th>版本</th><th>大小</th><th>下载</th></tr>\n' "$title"
    while IFS='|' read -r fname fcat ftag fsize fdesc; do
        [[ "$fcat" == "$cat" ]] || continue
        printf '      <tr><td>%s<div class="meta">%s</div></td><td class="meta">%s</td><td class="meta">%s MB</td><td><a class="dl" href="%s">下载</a></td></tr>\n' \
            "$fname" "$fdesc" "$ftag" "$fsize" "$fname"
    done <"$MANIFEST"
    printf '    </table>\n  </div>\n'
done

cat <<'HTML_FOOT'
  <div class="card">
    <h2>iPhone / iPad <span class="tag">需 App Store</span></h2>
    <p class="note">iOS 客户端只能从 App Store 安装，服务器无法提供安装包：</p>
    <ul class="note">
      <li><b>Shadowrocket（小火箭）</b>：付费约 $2.99，需要非中国区 Apple ID</li>
      <li><b>sing-box</b>：免费，同样需要非中国区 Apple ID</li>
      <li><b>Stash</b>：付费，规则强大</li>
    </ul>
    <p class="note">导入方式：复制 <code>vless://</code> 开头的节点链接，打开 App 后会自动识别剪贴板。</p>
  </div>
  <div class="card">
    <h2>怎么用</h2>
    <ol class="note">
      <li>按手机/电脑系统下载对应客户端并安装（Android 装 APK 需要允许「安装未知来源应用」）</li>
      <li>回到部署信息里的节点链接 / 二维码，导入客户端</li>
      <li>打开客户端开关，浏览器访问 <code>ip.sb</code> 验证 IP 已变成服务器 IP</li>
    </ol>
    <p class="note">本页只提供客户端安装包，<b>不含任何节点信息</b>。</p>
  </div>
  <div class="note" style="text-align:center;margin-top:24px">由 3x-ui-oneclick 生成 · 文件版本见上表</div>
</div>
</body>
</html>
HTML_FOOT
} >"$WEB_ROOT/index.html"

chmod 755 "$WEB_ROOT"
chmod 644 "$WEB_ROOT/index.html"
ok "下载页已生成：$WEB_ROOT/index.html"

# ---------------------------- 启动服务 ---------------------------------------
start_service() {
    cat >"$UNIT_FILE" <<UNIT
[Unit]
Description=3x-ui client download page (static)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 -m http.server --bind 0.0.0.0 --directory ${WEB_ROOT} ${SERVICE_PORT}
Restart=always
RestartSec=3
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true
    sleep 1
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        ok "下载页服务已启动（${SERVICE_NAME}，端口 ${SERVICE_PORT}）"
    else
        warn "服务启动失败：journalctl -u ${SERVICE_NAME} -n 30 --no-pager"
    fi

    # 防火墙
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${SERVICE_PORT}/tcp" >/dev/null 2>&1 || true
        ok "ufw 已放行 ${SERVICE_PORT}/tcp"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${SERVICE_PORT}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        ok "firewalld 已放行 ${SERVICE_PORT}/tcp"
    fi
}

if [[ "$NO_SERVICE" == "1" ]]; then
    warn "按参数跳过网页服务（--no-service），文件在 ${WEB_ROOT}"
else
    step "启动下载页服务"
    start_service
fi

# ---------------------------- 记录与输出 -------------------------------------
mkdir -p /etc/x-ui
{
    echo "CLIENTS_PORT=${SERVICE_PORT}"
    echo "CLIENTS_URL=${PAGE_URL}"
    echo "CLIENTS_DIR=${WEB_ROOT}"
} >"$STATE_FILE"
chmod 600 "$STATE_FILE" 2>/dev/null || true

if [[ -f "$INFO_FILE" ]]; then
    if ! grep -q '【4】客户端下载' "$INFO_FILE" 2>/dev/null; then
        {
            echo ""
            echo "【4】客户端下载（手机/电脑连不上 GitHub 时用这个）"
            echo "  地址  : ${PAGE_URL:-（未启动网页服务，文件在 ${WEB_ROOT}）}"
            echo "  内容  : Android APK / Windows EXE-ZIP / macOS dmg（不含节点信息）"
            echo "  更新  : bash /root/fetch-clients.sh --force"
            echo ""
        } >>"$INFO_FILE"
        chmod 600 "$INFO_FILE" 2>/dev/null || true
    fi
fi

rm -f "$MANIFEST"

msg ""
printf '%s\n' "${C_GRN}${C_BLD}============================================================${C_RST}"
printf '%s\n' "${C_GRN}${C_BLD}  客户端下载页已就绪${C_RST}"
printf '%s\n' "${C_GRN}${C_BLD}============================================================${C_RST}"
if [[ -n "$PAGE_URL" ]]; then
    msg ""
    msg "  手机/电脑浏览器打开： ${C_BLU}${PAGE_URL}${C_RST}"
    msg ""
    if command -v qrencode >/dev/null 2>&1 && [[ "$NO_SERVICE" != "1" ]]; then
        msg "${C_DIM}扫码直接打开下载页：${C_RST}"
        qrencode -t ANSIUTF8 -m 1 "$PAGE_URL" || true
        msg ""
    fi
else
    msg "  文件已下载到：${WEB_ROOT}"
    msg "  （未启动网页服务，可用 --no-service 之外的参数重跑一次开启）"
fi
msg "${C_DIM}文件清单：${C_RST}"
if [[ -s "$STATE_FILE" ]]; then :; fi
ls -lh "$WEB_ROOT" 2>/dev/null | awk 'NR>1 {printf "  %-40s %s\n", $9, $5}'
if [[ "$FAILED" -gt 0 ]]; then
    warn "有 ${FAILED} 个资源没下载成功（GitHub 或镜像不通），其余可用。"
fi
msg ""
msg "${C_DIM}重跑更新： bash /root/fetch-clients.sh --force${C_RST}"
msg "${C_DIM}停止服务： systemctl disable --now ${SERVICE_NAME}${C_RST}"
msg ""
