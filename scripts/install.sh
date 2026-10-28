#!/usr/bin/env bash
# =============================================================================
#  3x-ui 一键部署脚本（新手版 v1.0.0）
#
#  作用：在全新 VPS 上自动完成
#    1. 安装依赖、校准时间、开启 BBR 加速
#    2. 安装 3x-ui 面板（官方安装脚本，非交互模式）
#    3. 生成随机强密码的面板账号 + 随机端口 + 随机访问路径
#    4. 创建一条 VLESS + REALITY + XTLS-Vision 节点（无需域名、无需证书）
#    5. 配置防火墙（只放行 SSH / 443 / 面板端口）
#    6. 输出面板地址、账号密码、节点链接、二维码，并保存到 /root/3xui-info.txt
#
#  用法：
#    bash install.sh                 # 全自动
#    bash install.sh --dry-run       # 只打印计划，不改系统（可在任意机器跑）
#    bash install.sh --dest www.apple.com:443 --sni www.apple.com
#    bash install.sh --port 8443 --email phone
#    bash install.sh --no-firewall --force
#    bash install.sh --help
#
#  说明：仅支持 systemd 的 Linux（Debian/Ubuntu 优先，也兼容 RHEL 系与 Arch）。
#  许可证：MIT（本脚本）；3x-ui 本体为 GPL-3.0，版权归 MHSanaei 及贡献者。
# =============================================================================
set -Eeuo pipefail

SCRIPT_VERSION="1.0.0"
UPSTREAM_INSTALL_URL="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
RAW_BASE="https://raw.githubusercontent.com/JAX290/3x-ui-oneclick/main"
INSTALL_RESULT="/etc/x-ui/install-result.env"
STATE_FILE="/etc/x-ui/oneclick.env"
INFO_FILE="/root/3xui-info.txt"

# ---------------------------- 默认参数 ---------------------------------------
VLESS_PORT="443"
DEST="www.microsoft.com:443"
SNI="www.microsoft.com"
PANEL_PORT=""
PANEL_USER=""
PANEL_PASS=""
PANEL_PATH=""
CLIENT_EMAIL="user1"
CLIENT_REMARK="oneclick-reality"
SERVER_IP=""
DO_FIREWALL="1"
DO_BBR="1"
DO_CLIENTS="1"
DO_NOADS="1"
DRY_RUN="0"
FORCE="0"
REINSTALL="0"

# ---------------------------- 输出工具 ---------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
    C_BLU=$'\033[36m'; C_BLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_BLD=""; C_DIM=""; C_RST=""
fi

msg()  { printf '%s\n' "$*"; }
step() { printf '\n%s\n' "${C_BLU}${C_BLD}==> $*${C_RST}"; }
ok()   { printf '%s\n' "${C_GRN}  ✓ $*${C_RST}"; }
warn() { printf '%s\n' "${C_YEL}  ! $*${C_RST}" >&2; }
err()  { printf '%s\n' "${C_RED}  ✗ $*${C_RST}" >&2; }
die()  { err "$*"; exit 1; }

on_error() {
    local line="${1:-?}"
    printf '\n' >&2
    err "脚本在第 ${line} 行出错中断。"
    err "排查建议："
    err "  1) 查看日志： tail -n 50 /var/log/3xui-oneclick.log"
    err "  2) 面板状态： systemctl status x-ui --no-pager"
    err "  3) 重跑脚本是安全的：已安装的部分会被跳过。"
    err "  4) 仍失败请把上面的日志贴到 GitHub Issues。"
    exit 1
}
trap 'on_error $LINENO' ERR

# ---------------------------- 参数解析 ---------------------------------------
usage() {
    cat <<'EOF'
3x-ui 一键部署脚本（新手版）

用法: bash install.sh [选项]

选项:
  --dest HOST:PORT      REALITY 伪装目标（默认 www.microsoft.com:443）
  --sni NAME            伪装目标的域名，必须与 dest 的主机名一致
  --port PORT           节点监听端口（默认 443）
  --panel-port PORT     面板端口（默认随机 20000-60000）
  --email NAME          客户端名称/邮箱标识（默认 user1）
  --server-ip IP        强制指定服务器公网 IP（NAT 机型需要）
  --no-firewall         不修改防火墙（你自己在云控制台放行端口）
  --no-bbr              不开 BBR
  --no-clients          不下载客户端安装包、不建下载页
  --keep-sponsors       保留面板里的赞助广告（默认会关掉）
  --force               面板已安装时仍继续（会复用已有配置）
  --reinstall           卸载后重装面板
  --dry-run             只打印将要执行的计划，不改动系统
  -h, --help            显示本帮助

示例:
  bash install.sh
  bash install.sh --dest www.apple.com:443 --sni www.apple.com --port 8443
  bash install.sh --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest)       DEST="${2:?--dest 需要参数}"; shift 2 ;;
        --dest=*)     DEST="${1#*=}"; shift ;;
        --sni)        SNI="${2:?--sni 需要参数}"; shift 2 ;;
        --sni=*)      SNI="${1#*=}"; shift ;;
        --port)       VLESS_PORT="${2:?--port 需要参数}"; shift 2 ;;
        --port=*)     VLESS_PORT="${1#*=}"; shift ;;
        --panel-port) PANEL_PORT="${2:?--panel-port 需要参数}"; shift 2 ;;
        --panel-port=*) PANEL_PORT="${1#*=}"; shift ;;
        --email)      CLIENT_EMAIL="${2:?--email 需要参数}"; shift 2 ;;
        --email=*)    CLIENT_EMAIL="${1#*=}"; shift ;;
        --server-ip)  SERVER_IP="${2:?--server-ip 需要参数}"; shift 2 ;;
        --server-ip=*) SERVER_IP="${1#*=}"; shift ;;
        --no-firewall) DO_FIREWALL="0"; shift ;;
        --no-bbr)      DO_BBR="0"; shift ;;
        --no-clients)  DO_CLIENTS="0"; shift ;;
        --keep-sponsors) DO_NOADS="0"; shift ;;
        --force)       FORCE="1"; shift ;;
        --reinstall)   REINSTALL="1"; FORCE="1"; shift ;;
        --dry-run)     DRY_RUN="1"; shift ;;
        -h|--help)     usage; exit 0 ;;
        *) die "未知参数: $1（用 --help 查看用法）" ;;
    esac
done

# dest 与 sni 一致性检查
DEST_HOST="${DEST%%:*}"
if [[ "$DEST_HOST" != "$SNI" ]]; then
    warn "dest 的主机名 (${DEST_HOST}) 与 sni (${SNI}) 不一致，这不推荐。"
    warn "REALITY 要求 SNI 与目标站点证书匹配，建议写成一样，例如："
    warn "  --dest ${DEST_HOST}:443 --sni ${DEST_HOST}"
fi

# ---------------------------- 生成随机值 -------------------------------------
rand_alnum() { # $1=长度
    local n="${1:-16}"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 $((n * 2)) 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c "$n"
    else
        tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$n"
    fi
}

rand_hex() { # $1=字节数
    local n="${1:-8}"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex "$n"
    else
        od -An -tx1 -N "$n" /dev/urandom | tr -d ' \n'
    fi
}

gen_uuid() {
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    elif command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr 'A-Z' 'a-z'
    else
        local h; h=$(rand_hex 16)
        printf '%s-%s-4%s-%s%s-%s\n' \
            "${h:0:8}" "${h:8:4}" "${h:13:3}" \
            "$(printf '%x' $(( (16#${h:16:1} & 3) | 8 )))" "${h:17:3}" "${h:20:12}"
    fi
}

PANEL_USER="${PANEL_USER:-$(rand_alnum 12)}"
PANEL_PASS="${PANEL_PASS:-$(rand_alnum 18)}"
PANEL_PATH="${PANEL_PATH:-$(rand_alnum 14)}"
if [[ -z "$PANEL_PORT" ]]; then
    PANEL_PORT="$(( (RANDOM % 40000) + 20000 ))"
fi
[[ "$PANEL_PORT" =~ ^[0-9]+$ ]] || die "面板端口必须是数字"
[[ "$VLESS_PORT" =~ ^[0-9]+$ ]] || die "节点端口必须是数字"
[[ "$CLIENT_EMAIL" =~ ^[A-Za-z0-9_.@-]+$ ]] || die "客户端名称只能包含字母数字和 _ . @ -"

detect_public_ip() {
    if [[ -n "$SERVER_IP" ]]; then echo "$SERVER_IP"; return 0; fi
    local ip="" url
    for url in https://api.ipify.org https://ifconfig.me/ip https://ipinfo.io/ip https://api64.ipify.org; do
        ip=$(curl -4 -fsS --max-time 6 "$url" 2>/dev/null | tr -d '[:space:]' || true)
        if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then echo "$ip"; return 0; fi
    done
    echo ""
}

# ---------------------------- dry-run ----------------------------------------
if [[ "$DRY_RUN" == "1" ]]; then
    step "Dry-run 模式：只打印计划，不会改动这台机器"
    msg "脚本版本      : ${SCRIPT_VERSION}"
    msg "面板端口      : ${PANEL_PORT}"
    msg "面板路径      : /${PANEL_PATH}/"
    msg "面板账号      : ${PANEL_USER}"
    msg "面板密码      : ${PANEL_PASS}"
    msg "节点协议      : VLESS + REALITY + XTLS-Vision (TCP)"
    msg "节点端口      : ${VLESS_PORT}"
    msg "伪装目标 dest : ${DEST}"
    msg "SNI           : ${SNI}"
    msg "客户端名称    : ${CLIENT_EMAIL}"
    msg "防火墙        : $([[ "$DO_FIREWALL" == 1 ]] && echo '自动配置 ufw/firewalld' || echo '跳过')"
    msg "BBR           : $([[ "$DO_BBR" == 1 ]] && echo '开启' || echo '跳过')"
    msg "公网 IP       : ${SERVER_IP:-（运行时自动探测）}"
    msg ""
    msg "正式执行时，会依次：装依赖 → 校时 → BBR → 装 3x-ui → 建节点 → 配防火墙 → 打印二维码"
    exit 0
fi

# ---------------------------- 环境检查 ---------------------------------------
step "[1/7] 检查运行环境"

[[ "$(uname -s)" == "Linux" ]] || die "本脚本只能在 Linux 上运行（当前：$(uname -s)）。请在 VPS 上执行。"
[[ $EUID -eq 0 ]] || die "请用 root 运行： sudo -i 然后重新执行，或加 sudo。"
[[ -d /run/systemd/system ]] || die "本脚本要求 systemd（常见云镜像都满足）。"

if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"; OS_VER="${VERSION_ID:-unknown}"
else
    OS_ID="unknown"; OS_VER="unknown"
fi

PKG=""
case "$OS_ID" in
    debian|ubuntu|armbian|linuxmint|pop) PKG="apt" ;;
    fedora|centos|rhel|almalinux|rocky|ol|amzn|virtuozzo) PKG="dnf" ;;
    arch|manjaro|parch) PKG="pacman" ;;
    alpine) die "Alpine 请改用官方安装脚本，本脚本暂不覆盖。" ;;
    *) warn "未识别的系统 ${OS_ID} ${OS_VER}，将尝试按 apt 处理。"; PKG="apt" ;;
esac

VIRT="$(systemd-detect-virt 2>/dev/null || echo unknown)"
if [[ "$VIRT" == "openvz" || "$VIRT" == "lxc" ]]; then
    warn "检测到 ${VIRT} 容器：3x-ui 可用，但部分内核功能（如 BBR）可能受限。"
fi

MEM_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
if [[ "$MEM_MB" -gt 0 && "$MEM_MB" -lt 300 ]]; then
    warn "内存只有 ${MEM_MB} MB，3x-ui + Xray 可能吃紧，建议至少 512MB。"
fi

if command -v x-ui >/dev/null 2>&1 || [[ -d /usr/local/x-ui ]]; then
    if [[ "$REINSTALL" == "1" ]]; then
        step "[1/7] 检测到已安装 3x-ui，按你的要求先卸载"
        msg "（只删除 3x-ui 本体与配置，不影响系统其他软件）"
        systemctl stop x-ui 2>/dev/null || true
        systemctl disable x-ui 2>/dev/null || true
        bash <(curl -Ls "$UPSTREAM_INSTALL_URL") uninstall >/dev/null 2>&1 || {
            rm -f /etc/systemd/system/x-ui.service
            rm -rf /usr/local/x-ui /etc/x-ui /usr/bin/x-ui
            systemctl daemon-reload || true
        }
    elif [[ "$FORCE" != "1" ]]; then
        die "这台机器已经装过 3x-ui。
  想查看现有节点信息： bash /root/info.sh
  想覆盖重装：       bash /root/install.sh --reinstall
  只想继续建节点：   bash /root/install.sh --force
（如果确认是误报，也可以直接加 --force）"
    else
        warn "检测到已安装 3x-ui，--force 模式：跳过安装步骤，只做配置。"
        SKIP_INSTALL="1"
    fi
fi
SKIP_INSTALL="${SKIP_INSTALL:-0}"

mkdir -p /var/log
LOG_FILE=/var/log/3xui-oneclick.log
# 让所有输出同时进日志（终端仍可见）
exec > >(tee -a "$LOG_FILE") 2>&1

PUBLIC_IP="$(detect_public_ip)"
[[ -n "$PUBLIC_IP" ]] || warn "没能自动探测公网 IP，稍后请用 --server-ip 指定，或在云控制台查看。"
ok "系统 ${OS_ID} ${OS_VER} / ${VIRT} / 内存 ${MEM_MB}MB"
ok "公网 IP：${PUBLIC_IP:-未知}"

# ---------------------------- 依赖 -------------------------------------------
step "[2/7] 安装依赖（curl jq qrencode openssl chrony ufw）"

pkg_install() {
    local pkgs_apt="$1" pkgs_dnf="$2" pkgs_pac="$3"
    case "$PKG" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq || warn "apt-get update 有警告，继续"
            # shellcheck disable=SC2086
            apt-get install -y -qq $pkgs_apt
            ;;
        dnf)
            # shellcheck disable=SC2086
            dnf install -y -q $pkgs_dnf
            ;;
        pacman)
            # shellcheck disable=SC2086
            pacman -Sy --noconfirm --needed $pkgs_pac
            ;;
    esac
}

pkg_install \
    "curl jq qrencode openssl ca-certificates chrony ufw iproute2 tar procps" \
    "curl jq qrencode openssl ca-certificates chrony tar iproute procps-ng" \
    "curl jq qrencode openssl ca-certificates chrony tar iproute2 procps-ng ufw"

for c in curl jq openssl; do
    command -v "$c" >/dev/null 2>&1 || die "依赖 $c 安装失败，请手动安装后重试。"
done
ok "依赖就绪"
command -v qrencode >/dev/null 2>&1 || warn "qrencode 没装上，稍后不会打印二维码（链接仍然可用）。"

# ---------------------------- 时间同步 ---------------------------------------
step "[3/7] 校准系统时间（REALITY 对时间很敏感）"
systemctl enable --now chrony >/dev/null 2>&1 || systemctl enable --now chronyd >/dev/null 2>&1 || true
timedatectl set-ntp true >/dev/null 2>&1 || true
sleep 2
if command -v chronyc >/dev/null 2>&1; then
    chronyc makestep >/dev/null 2>&1 || true
fi
ok "当前时间：$(date '+%F %T %Z')"

# ---------------------------- BBR --------------------------------------------
if [[ "$DO_BBR" == "1" ]]; then
    step "[4/7] 开启 BBR 加速（提升长距离传输速度）"
    cat > /etc/sysctl.d/99-3xui-oneclick.conf <<'SYSCTL'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYSCTL
    if sysctl --system >/dev/null 2>&1; then
        CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)
        if [[ "$CC" == "bbr" ]]; then ok "BBR 已生效"; else warn "BBR 未生效（当前：${CC}），可能是容器内核限制，不影响使用。"; fi
    else
        warn "sysctl 写入失败，跳过 BBR。"
    fi
else
    step "[4/7] 跳过 BBR（--no-bbr）"
fi

# ---------------------------- 安装 3x-ui -------------------------------------
step "[5/7] 安装 3x-ui 面板（官方脚本，非交互）"

install_upstream() {
    local tmp=/tmp/3xui-install.sh
    local urls=(
        "$UPSTREAM_INSTALL_URL"
        "https://gh-proxy.com/https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
        "https://cdn.jsdelivr.net/gh/MHSanaei/3x-ui@master/install.sh"
        "https://raw.gitmirror.com/mhsanaei/3x-ui/master/install.sh"
    )
    local u
    for u in "${urls[@]}"; do
        msg "  下载安装脚本：${u}"
        if curl -fsSL --max-time 60 "$u" -o "$tmp" && [[ -s "$tmp" ]]; then
            if head -n 1 "$tmp" | grep -q '^#!'; then
                ok "安装脚本已就绪（$(wc -c <"$tmp") 字节）"
                return 0
            fi
        fi
        warn "该地址不可用，换下一个"
    done
    return 1
}

if [[ "$SKIP_INSTALL" != "1" ]]; then
    install_upstream || die "无法下载 3x-ui 安装脚本。请检查 VPS 是否能访问 GitHub，或手动执行官方命令安装后再跑本脚本 --force。"

    msg "  开始安装（3-5 分钟，请勿关闭窗口）..."
    XUI_NONINTERACTIVE=1 \
    XUI_USERNAME="$PANEL_USER" \
    XUI_PASSWORD="$PANEL_PASS" \
    XUI_PANEL_PORT="$PANEL_PORT" \
    XUI_WEB_BASE_PATH="$PANEL_PATH" \
    XUI_SSL_MODE=none \
    XUI_SERVER_IP="$PUBLIC_IP" \
    XUI_ENABLE_FAIL2BAN=true \
    bash /tmp/3xui-install.sh v3.11.0 || {
        warn "指定版本 v3.11.0 安装失败，改用最新版重试..."
        XUI_NONINTERACTIVE=1 \
        XUI_USERNAME="$PANEL_USER" \
        XUI_PASSWORD="$PANEL_PASS" \
        XUI_PANEL_PORT="$PANEL_PORT" \
        XUI_WEB_BASE_PATH="$PANEL_PATH" \
        XUI_SSL_MODE=none \
        XUI_SERVER_IP="$PUBLIC_IP" \
        XUI_ENABLE_FAIL2BAN=true \
        bash /tmp/3xui-install.sh || die "3x-ui 安装失败，见上面的日志。"
    }
else
    ok "已有安装，跳过安装步骤"
fi

systemctl is-active --quiet x-ui || {
    warn "x-ui 服务未运行，尝试启动..."
    systemctl start x-ui || die "x-ui 启动失败： journalctl -u x-ui -n 50 --no-pager"
}
ok "x-ui 服务运行中"

# ---------------------------- 读取面板信息 -----------------------------------
step "[6/7] 读取面板信息并创建节点"

PANEL_PORT_ACTUAL=""; WEB_BASE_PATH=""; API_TOKEN=""
if [[ -f "$INSTALL_RESULT" ]]; then
    # shellcheck disable=SC1090
    . "$INSTALL_RESULT"
    PANEL_PORT_ACTUAL="${XUI_PANEL_PORT:-}"
    WEB_BASE_PATH="${XUI_WEB_BASE_PATH:-}"
    API_TOKEN="${XUI_API_TOKEN:-}"
    PANEL_USER="${XUI_USERNAME:-$PANEL_USER}"
    PANEL_PASS="${XUI_PASSWORD:-$PANEL_PASS}"
fi

# 兜底：从 x-ui 自身读配置
if [[ -z "$PANEL_PORT_ACTUAL" ]] && command -v x-ui >/dev/null 2>&1; then
    SHOW=$(x-ui setting -show true 2>/dev/null || true)
    PANEL_PORT_ACTUAL=$(printf '%s\n' "$SHOW" | grep -Eo 'port: [0-9]+' | head -1 | awk '{print $2}')
    WEB_BASE_PATH=$(printf '%s\n' "$SHOW" | grep -Eo 'webBasePath: .+' | head -1 | awk '{print $2}' | sed 's#^/##; s#/$##')
    [[ -z "$API_TOKEN" ]] && API_TOKEN=$(x-ui setting -getApiToken 2>/dev/null | grep -Eo 'apiToken: .+' | head -1 | awk '{print $2}')
fi
[[ -n "$PANEL_PORT_ACTUAL" ]] || PANEL_PORT_ACTUAL="$PANEL_PORT"
WEB_BASE_PATH="${WEB_BASE_PATH#/}"; WEB_BASE_PATH="${WEB_BASE_PATH%/}"
if [[ "$WEB_BASE_PATH" == "/" ]]; then WEB_BASE_PATH=""; fi

if [[ -n "$WEB_BASE_PATH" ]]; then
    PANEL_BASE="http://127.0.0.1:${PANEL_PORT_ACTUAL}/${WEB_BASE_PATH}"
else
    PANEL_BASE="http://127.0.0.1:${PANEL_PORT_ACTUAL}"
fi

# 等面板就绪
for _ in $(seq 1 30); do
    if curl -fsS --max-time 3 "$PANEL_BASE/" -o /dev/null 2>/dev/null; then break; fi
    sleep 1
done

COOKIE_JAR=$(mktemp)
CSRF=""
AUTH_MODE="token"

if [[ -z "$API_TOKEN" ]]; then
    warn "没有拿到 API Token，改用账号密码登录面板 API"
    AUTH_MODE="cookie"
    LOGIN_BODY=$(jq -n --arg u "$PANEL_USER" --arg p "$PANEL_PASS" '{username:$u,password:$p}')
    LOGIN_RESP=$(curl -sS --max-time 10 -c "$COOKIE_JAR" -X POST \
        -H 'Content-Type: application/json' -d "$LOGIN_BODY" "$PANEL_BASE/login" || true)
    [[ "$(printf '%s' "$LOGIN_RESP" | jq -r '.success // false' 2>/dev/null)" == "true" ]] || \
        die "登录面板 API 失败，无法自动创建节点。请手动打开面板创建（方法见 docs/03-oneclick.md 最后的“手动兜底”）。"
    CSRF=$(curl -sS --max-time 10 -b "$COOKIE_JAR" "$PANEL_BASE/csrf-token" 2>/dev/null | jq -r '.obj // empty' || true)
    ok "登录成功"
fi

api() { # $1=GET|POST  $2=路径  [$3=JSON body]
    local method="$1" path="$2" body="${3:-}"
    local -a args=(-sS --max-time 30 -X "$method")
    if [[ "$AUTH_MODE" == "token" ]]; then
        args+=(-H "Authorization: Bearer ${API_TOKEN}")
    else
        args+=(-b "$COOKIE_JAR")
        if [[ -n "$CSRF" ]]; then
            args+=(-H "X-CSRF-Token: ${CSRF}")
        fi
    fi
    if [[ -n "$body" ]]; then
        args+=(-H 'Content-Type: application/json' -d "$body")
    fi
    curl "${args[@]}" "${PANEL_BASE}${path}" || true
}

# 生成 REALITY 密钥与 UUID（优先用面板自带的生成接口）
PRIV=""; PUB=""; UUID=""
KEY_RESP=$(api GET "/panel/api/server/getNewX25519Cert")
PRIV=$(printf '%s' "$KEY_RESP" | jq -r '.obj.privateKey // empty' 2>/dev/null || true)
PUB=$(printf '%s' "$KEY_RESP" | jq -r '.obj.publicKey // empty' 2>/dev/null || true)

if [[ -z "$PRIV" || -z "$PUB" ]]; then
    warn "面板接口生成密钥失败，改用本机 xray 生成"
    XRAY_BIN=$(find /usr/local/x-ui/bin -maxdepth 1 -type f -name 'xray*' 2>/dev/null | head -1 || true)
    if [[ -n "$XRAY_BIN" ]]; then
        KEYOUT=$("$XRAY_BIN" x25519 2>/dev/null || true)
        PRIV=$(printf '%s\n' "$KEYOUT" | sed -n 's/.*[Pp]rivate[ Kk]ey[: ]*//p' | head -1 | tr -d '[:space:]')
        PUB=$(printf '%s\n' "$KEYOUT" | sed -n 's/.*[Pp]ublic[ Kk]ey[: ]*//p' | head -1 | tr -d '[:space:]')
        if [[ -z "$PUB" ]]; then
            PUB=$(printf '%s\n' "$KEYOUT" | sed -n 's/.*[Pp]assword[: ]*//p' | head -1 | tr -d '[:space:]')
        fi
    fi
fi
[[ -n "$PRIV" && -n "$PUB" ]] || die "生成 REALITY 密钥失败，请手动在面板创建节点。"

UUID_RESP=$(api GET "/panel/api/server/getNewUUID")
UUID=$(printf '%s' "$UUID_RESP" | jq -r '.obj.uuid // empty' 2>/dev/null || true)
if [[ -z "$UUID" ]]; then UUID="$(gen_uuid)"; fi
SHORT_ID="$(rand_hex 8)"
SUB_ID="$(rand_alnum 16)"

ok "REALITY 密钥已生成"
ok "UUID：${UUID}"

# 组装入站 JSON
INBOUND_JSON=$(cat <<JSON
{
  "enable": true,
  "remark": "${CLIENT_REMARK}",
  "listen": "",
  "port": ${VLESS_PORT},
  "protocol": "vless",
  "expiryTime": 0,
  "total": 0,
  "settings": {
    "clients": [
      {
        "id": "${UUID}",
        "email": "${CLIENT_EMAIL}",
        "flow": "xtls-rprx-vision",
        "limitIp": 0,
        "totalGB": 0,
        "expiryTime": 0,
        "enable": true,
        "tgId": 0,
        "subId": "${SUB_ID}",
        "comment": "",
        "reset": 0
      }
    ],
    "decryption": "none",
    "encryption": "none",
    "fallbacks": []
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "show": false,
      "xver": 0,
      "target": "${DEST}",
      "serverNames": ["${SNI}"],
      "privateKey": "${PRIV}",
      "minClientVer": "",
      "maxClientVer": "",
      "maxTimediff": 0,
      "shortIds": ["${SHORT_ID}"],
      "mldsa65Seed": "",
      "settings": {
        "publicKey": "${PUB}",
        "fingerprint": "chrome",
        "serverName": "${SNI}",
        "spiderX": "/",
        "mldsa65Verify": ""
      }
    }
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls", "quic", "fakedns"],
    "metadataOnly": false,
    "routeOnly": false
  }
}
JSON
)

# 幂等：同名入站已存在则跳过
EXISTING_ID=$(api GET "/panel/api/inbounds/list" | jq -r --arg r "$CLIENT_REMARK" '.obj[]? | select(.remark==$r) | .id' 2>/dev/null | head -1 || true)
if [[ -n "$EXISTING_ID" ]]; then
    warn "已存在同名入站（id=${EXISTING_ID}，remark=${CLIENT_REMARK}），跳过创建。"
    warn "如需新建一个，请加参数 --email 换个名字。"
else
    ADD_RESP=$(api POST "/panel/api/inbounds/add" "$INBOUND_JSON")
    if [[ "$(printf '%s' "$ADD_RESP" | jq -r '.success // false' 2>/dev/null)" == "true" ]]; then
        ok "节点已创建：VLESS + REALITY :${VLESS_PORT}"
    else
        ADD_MSG=$(printf '%s' "$ADD_RESP" | jq -r '.msg // empty' 2>/dev/null || true)
        warn "自动创建失败：${ADD_MSG:-响应异常}"
        warn "已把完整参数写到 ${INFO_FILE}，你可以照 docs/03-oneclick.md 的“手动兜底”在面板里两分钟创建。"
        AUTO_FAIL="1"
    fi
fi

# 取分享链接
LINK=""
if [[ "${AUTO_FAIL:-0}" != "1" ]]; then
    LINK=$(api GET "/panel/api/clients/links/${CLIENT_EMAIL}" | jq -r '.obj[0] // empty' 2>/dev/null || true)
fi
if [[ -z "$LINK" ]]; then
    LINK="vless://${UUID}@${PUBLIC_IP}:${VLESS_PORT}?type=tcp&security=reality&encryption=none&pbk=${PUB}&fp=chrome&sni=${SNI}&sid=${SHORT_ID}&spx=%2F&flow=xtls-rprx-vision#${CLIENT_REMARK}"
fi

# ---------------------------- 防火墙 -----------------------------------------
step "[7/7] 配置防火墙"

if [[ "$DO_FIREWALL" != "1" ]]; then
    warn "已跳过防火墙（--no-firewall）。请自行在云控制台/安全组放行："
    warn "  TCP 22(SSH) / TCP ${VLESS_PORT} / TCP ${PANEL_PORT_ACTUAL}"
else
    SSH_PORT=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}' || true)
    SSH_PORT="${SSH_PORT:-22}"

    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${SSH_PORT}/tcp" >/dev/null 2>&1 || true
        if [[ "$SSH_PORT" != "22" ]]; then ufw allow 22/tcp >/dev/null 2>&1 || true; fi
        ufw allow "${VLESS_PORT}/tcp" >/dev/null 2>&1 || true
        ufw allow "${PANEL_PORT_ACTUAL}/tcp" >/dev/null 2>&1 || true
        ufw --force enable >/dev/null 2>&1 || warn "ufw 启用失败，请手动检查。"
        ok "ufw 已启用：放行 ${SSH_PORT} / ${VLESS_PORT} / ${PANEL_PORT_ACTUAL}"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${SSH_PORT}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port="${VLESS_PORT}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port="${PANEL_PORT_ACTUAL}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        ok "firewalld 已放行 ${SSH_PORT} / ${VLESS_PORT} / ${PANEL_PORT_ACTUAL}"
    else
        warn "系统里没有 ufw/firewalld，跳过。请在云厂商安全组放行端口。"
    fi
    warn "注意：云厂商的“安全组/防火墙”是另一层，需要去控制台放行同样端口。"
fi

# ---------------------------- 自检 -------------------------------------------
step "自检"

XRAY_STATE=$(api GET "/panel/api/server/status" | jq -r '.obj.xray.state // "unknown"' 2>/dev/null || true)
if [[ "$XRAY_STATE" == "running" ]]; then ok "Xray 内核运行中"; else warn "Xray 状态：${XRAY_STATE}，请到面板查看。"; fi

if ss -lntp 2>/dev/null | grep -qE "[:.]${VLESS_PORT}[[:space:]]"; then
    ok "已监听 TCP ${VLESS_PORT}"
else
    warn "没有检测到 TCP ${VLESS_PORT} 监听，可能是端口被占用或 Xray 未启动。"
fi

# REALITY 握手自测（未认证的 TLS 握手应返回伪装站证书）
HS=$(timeout 8 openssl s_client -connect "127.0.0.1:${VLESS_PORT}" -servername "$SNI" </dev/null 2>/dev/null | sed -n 's/^subject=//p' | head -1 || true)
if [[ -n "$HS" ]]; then
    ok "REALITY 握手正常（返回证书：${HS}）"
else
    warn "REALITY 握手自测没拿到证书，通常是伪装目标不可达；换一个 --dest 试试。"
fi

# ---------------------------- 落地辅助脚本 -----------------------------------
# 把 info.sh / uninstall.sh / install.sh 放到 /root，方便以后直接运行
install_helpers() {
    local f tmp url ok_any=0
    for f in install.sh info.sh uninstall.sh fetch-clients.sh no-ads.sh; do
        tmp="/root/.${f}.tmp"
        if [[ -f "/root/$f" ]]; then
            ok_any=1
            continue
        fi
        for url in \
            "${RAW_BASE}/scripts/${f}" \
            "https://gh-proxy.com/${RAW_BASE}/scripts/${f}" \
            "https://ghfast.top/${RAW_BASE}/scripts/${f}"; do
            if curl -fsSL --max-time 30 "$url" -o "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
                mv -f "$tmp" "/root/$f"
                ok_any=1
                break
            fi
        done
        rm -f "$tmp"
    done
    chmod +x /root/install.sh /root/info.sh /root/uninstall.sh /root/fetch-clients.sh /root/no-ads.sh 2>/dev/null || true
    if [[ "$ok_any" == "1" ]]; then
        ok "辅助脚本已放到 /root（info.sh / install.sh / uninstall.sh）"
    else
        warn "辅助脚本下载失败，不影响节点使用；需要时手动下载到 /root 即可。"
    fi
}
install_helpers

# ---------------------------- 关闭面板广告 -----------------------------------
ADS_OFF="0"
if [[ "$DO_NOADS" == "1" ]]; then
    step "关闭面板里的赞助广告"
    if [[ -x /root/no-ads.sh ]]; then
        if bash /root/no-ads.sh; then
            ADS_OFF="1"
        else
            warn "广告屏蔽没成功（不影响节点使用），可稍后重跑 bash /root/no-ads.sh"
        fi
    else
        warn "没找到 /root/no-ads.sh，跳过广告屏蔽"
    fi
else
    step "按参数保留面板赞助广告（--keep-sponsors）"
fi

# ---------------------------- 客户端安装包 -----------------------------------
CLIENTS_URL=""
if [[ "$DO_CLIENTS" == "1" ]]; then
    step "下载客户端安装包到本机（约 320MB，可加 --no-clients 跳过）"
    if [[ -x /root/fetch-clients.sh ]]; then
        if bash /root/fetch-clients.sh; then
            if [[ -f /etc/x-ui/clients.env ]]; then
                # shellcheck disable=SC1091
                . /etc/x-ui/clients.env
                CLIENTS_URL="${CLIENTS_URL:-}"
            fi
        else
            warn "客户端下载页没配置成功（不影响节点使用），可稍后重跑 bash /root/fetch-clients.sh"
        fi
    else
        warn "没找到 /root/fetch-clients.sh，跳过客户端下载"
    fi
else
    step "按参数跳过客户端下载（--no-clients）"
fi

# ---------------------------- 保存与输出 -------------------------------------
mkdir -p /etc/x-ui
umask 077
cat > "$STATE_FILE" <<STATE
CLIENT_EMAIL=${CLIENT_EMAIL}
CLIENT_REMARK=${CLIENT_REMARK}
VLESS_PORT=${VLESS_PORT}
DEST=${DEST}
SNI=${SNI}
UUID=${UUID}
SHORT_ID=${SHORT_ID}
PUBLIC_KEY=${PUB}
SERVER_IP=${PUBLIC_IP}
LINK=${LINK}
STATE

cat > "$INFO_FILE" <<INFO
================ 3x-ui 部署信息（请妥善保存） ================
生成时间: $(date '+%F %T %Z')

【1】面板（只在浏览器里用）
  地址  : http://${PUBLIC_IP:-服务器IP}:${PANEL_PORT_ACTUAL}/${WEB_BASE_PATH}
  用户名: ${PANEL_USER}
  密码  : ${PANEL_PASS}
  提示  : 面板用的是 http，建议只在受信任网络打开；
          更安全的做法是 SSH 隧道：ssh -L ${PANEL_PORT_ACTUAL}:127.0.0.1:${PANEL_PORT_ACTUAL} root@${PUBLIC_IP:-服务器IP}
          然后本机访问 http://127.0.0.1:${PANEL_PORT_ACTUAL}/${WEB_BASE_PATH}

【2】节点（手机/电脑用这个）
  协议  : VLESS + REALITY + XTLS-Vision
  地址  : ${PUBLIC_IP:-服务器IP}
  端口  : ${VLESS_PORT}
  UUID  : ${UUID}
  公钥  : ${PUB}
  SNI   : ${SNI}
  shortId: ${SHORT_ID}
  链接  : ${LINK}

【3】客户端下载（手机/电脑连不上 GitHub 用这个）
  地址  : ${CLIENTS_URL:-（未启用；运行 bash /root/fetch-clients.sh 可开启）}
  内容  : Android APK / Windows EXE-ZIP / macOS dmg（不含节点信息）
  更新  : bash /root/fetch-clients.sh --force

【4】可视化视图
  以上信息随时可看: bash /root/info.sh
  面板详情: x-ui → 用里面的菜单

【5】面板广告
  状态  : $([[ "${ADS_OFF:-0}" == "1" ]] && echo "已关闭（登录页/仪表盘的赞助位已屏蔽）" || echo "未关闭（默认会关闭，可运行 bash /root/no-ads.sh）")
  恢复  : bash /root/no-ads.sh --restore
=============================================================
INFO
umask 022
chmod 600 "$INFO_FILE" "$STATE_FILE"
rm -f "$COOKIE_JAR"

# 终端汇总
msg ""
printf '%s\n' "${C_GRN}${C_BLD}============================================================${C_RST}"
printf '%s\n' "${C_GRN}${C_BLD}  部署完成！${C_RST}"
printf '%s\n' "${C_GRN}${C_BLD}============================================================${C_RST}"
msg ""
printf '%s\n' "${C_BLD}【 面板 】${C_RST}  ${C_DIM}浏览器打开，用来管理节点${C_RST}"
msg "  地址  : ${C_BLU}http://${PUBLIC_IP:-服务器IP}:${PANEL_PORT_ACTUAL}/${WEB_BASE_PATH}${C_RST}"
msg "  用户名: ${PANEL_USER}"
msg "  密码  : ${PANEL_PASS}"
msg ""
printf '%s\n' "${C_BLD}【 节点链接 】${C_RST}  ${C_DIM}这是“单条配置”，不是订阅：客户端里选「从剪贴板导入 / 扫码」，别粘到“订阅”里${C_RST}"
msg "  ${LINK}"
msg ""
if [[ "${AUTO_FAIL:-0}" != "1" ]] && command -v qrencode >/dev/null 2>&1; then
    printf '%s\n' "${C_BLD}【 二维码 】${C_RST}  ${C_DIM}手机客户端扫码直接导入${C_RST}"
    msg ""
    if ! qrencode -t ANSIUTF8 -m 1 "$LINK"; then
        warn "二维码生成失败（链接仍然可用）。"
    fi
    msg ""
fi
msg "${C_DIM}以上信息已保存到 ${INFO_FILE}（仅 root 可读）。${C_RST}"
if [[ -n "$CLIENTS_URL" ]]; then
    msg ""
    printf '%s\n' "${C_BLD}【 客户端下载页 】${C_RST}  ${C_DIM}手机/电脑浏览器打开，直接下 APK/EXE${C_RST}"
    msg "  ${C_BLU}${CLIENTS_URL}${C_RST}"
fi
if [[ "${ADS_OFF:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}面板广告：已关闭（要用官方的赞助位可执行 bash /root/no-ads.sh --restore）${C_RST}"
fi
msg "${C_DIM}下次想看： bash /root/info.sh    卸载： bash /root/uninstall.sh${C_RST}"
msg ""
if [[ "${AUTO_FAIL:-0}" == "1" ]]; then
    printf '%s\n' "${C_YEL}${C_BLD}节点没有自动创建成功，请按下面两步手动补：${C_RST}"
    msg "  1) 打开面板 → 入站列表 → 添加入站"
    msg "     协议 vless / 端口 ${VLESS_PORT} / 传输 tcp / 安全 reality"
    msg "     目标(dest) ${DEST} / SNI ${SNI} / 流控 xtls-rprx-vision"
    msg "     私钥与短ID 用面板里的“获取/生成”按钮重新生成即可"
    msg "  2) 在客户端里添加，或回到这里跑： bash /root/install.sh --force（换成 --email 别的名字）"
fi
msg ""
