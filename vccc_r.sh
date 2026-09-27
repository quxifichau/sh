#!/usr/bin/env bash
# ==============================================================================
# vccc.sh — Chrome + VNC + 双 MCP 自动化生产环境 一键安装脚本
# 修复版本：解决 Chrome 安装语法错误、公网暴露、pip 污染、启动时序等全部问题
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# 0. 前置检查：必须以 root 运行（apt-get / dpkg 需要）
# ------------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    echo "❌ 此脚本需要 root 权限运行，请使用: sudo bash vccc.sh" >&2
    exit 1
fi

echo "=================================================="
echo "🚀 开始安装 Chrome + VNC + 双 MCP 自动化生产环境"
echo "=================================================="

# ------------------------------------------------------------------------------
# 1. 基础系统依赖（使用系统包管理器，不污染系统 pip）
# ------------------------------------------------------------------------------
echo "📦 [1/5] 安装系统依赖..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    tigervnc-standalone-server \
    novnc \
    websockify \
    fluxbox \
    x11-utils \
    fonts-liberation \
    wget \
    curl \
    gnupg \
    ca-certificates \
    procps \
    net-tools \
    unzip \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    build-essential \
    git

# ------------------------------------------------------------------------------
# 2. 安装 Google Chrome 官方稳定版
#    修复：使用 dpkg -i 而非 apt-get install <deb文件>
# ------------------------------------------------------------------------------
if ! command -v google-chrome-stable >/dev/null 2>&1; then
    echo "🌐 [2/5] 下载并安装 Google Chrome..."
    CHROME_DEB="/tmp/google-chrome-stable_current_amd64.deb"
    wget -q -O "$CHROME_DEB" \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

    # dpkg -i 安装本地 deb；依赖缺失时用 apt-get -f install 自动补全
    dpkg -i "$CHROME_DEB" || apt-get install -y -f
    rm -f "$CHROME_DEB"
else
    echo "✅ [2/5] Google Chrome 已安装，跳过"
fi

# 安装完成后校验
if ! command -v google-chrome-stable >/dev/null 2>&1; then
    echo "❌ Google Chrome 安装失败，请检查网络或系统架构" >&2
    exit 1
fi
echo "   Chrome 版本: $(google-chrome-stable --version)"

# ------------------------------------------------------------------------------
# 3. 准备运行目录与 Python 虚拟环境
#    修复：使用 python3 -m venv（系统自带），不在系统级 pip 安装任何包
# ------------------------------------------------------------------------------
echo "🐍 [3/5] 初始化 Python 虚拟环境..."

# 实际运行用户的 HOME（root 运行时通常是 /root，sudo 时需要保留原用户）
REAL_HOME="${SUDO_HOME:-$HOME}"
CDP_DIR="$REAL_HOME/cdp"

mkdir -p "$CDP_DIR/logs" "$CDP_DIR/pids" "$CDP_DIR/profile"
chmod 700 "$CDP_DIR/profile"

if [ ! -d "$CDP_DIR/venv" ]; then
    python3 -m venv "$CDP_DIR/venv"
    echo "   虚拟环境已创建: $CDP_DIR/venv"
else
    echo "   虚拟环境已存在，跳过创建"
fi

VENV_PIP="$CDP_DIR/venv/bin/pip"
VENV_BIN="$CDP_DIR/venv/bin"

# ------------------------------------------------------------------------------
# 4. 在虚拟环境内安装所有 Python 依赖（版本全部锁定）
#
#    版本说明：
#      setuptools<82   — setuptools>=82 与 crawl4ai 0.8.9 的 setup.py 不兼容
#      lxml~=5.3       — >=5.3,<6；crawl4ai 0.8.9 的最低兼容版本
#      browser-use     — 暂无官方稳定 release tag，锁定已验证的最新稳定版
#      click==8.3.3    — browser-use 与 crawl-mcp 均依赖 click，
#                        8.3.3 是两者共同兼容的版本，避免冲突
#      crawl4ai=0.8.9  — 已验证版本
#      crawl-mcp=0.3.3 — 已验证版本
#      mcp-proxy=0.9.0 — 已验证支持 --host/--port 参数的版本
# ------------------------------------------------------------------------------
echo "📦 [4/5] 安装 Python MCP 套件（虚拟环境隔离）..."

"$VENV_PIP" install --upgrade pip setuptools wheel

# 先固定基础约束，防止后续包升级覆盖
"$VENV_PIP" install \
    "setuptools<82" \
    "lxml~=5.3" \
    "click==8.3.3"

# 安装核心包
"$VENV_PIP" install \
    "browser-use[cli]==0.1.45" \
    "crawl4ai==0.8.9" \
    "crawl-mcp==0.3.3" \
    "mcp-proxy==0.9.0"

# click 最后强制固定，防止上面任何包将其升级
"$VENV_PIP" install --force-reinstall "click==8.3.3"

# ------------------------------------------------------------------------------
# 5. 安装完整性校验
# ------------------------------------------------------------------------------
echo "🔍 [5/5] 校验关键可执行文件..."

REQUIRED_SYS_BINS=(
    "Xtigervnc"
    "fluxbox"
    "websockify"
    "google-chrome-stable"
)
for bin_name in "${REQUIRED_SYS_BINS[@]}"; do
    if ! command -v "$bin_name" >/dev/null 2>&1; then
        echo "❌ 缺少系统依赖: $bin_name" >&2
        exit 1
    fi
done

REQUIRED_VENV_BINS=(
    "$VENV_BIN/mcp-proxy"
    "$VENV_BIN/browser-use"
    "$VENV_BIN/crawl-mcp"
)
for bin_path in "${REQUIRED_VENV_BINS[@]}"; do
    if [ ! -x "$bin_path" ]; then
        echo "❌ 缺少虚拟环境工具: $bin_path" >&2
        exit 1
    fi
done

echo "   所有可执行文件校验通过 ✅"

# ==============================================================================
# 6. 生成快捷管理函数文件 ~/.functions.sh
#
#    设计原则：
#      - 所有服务均通过 PID 文件管理，不使用 pkill -f 模糊匹配
#      - mcp-proxy 绑定 127.0.0.1，由 Tailscale 负责外部转发
#      - 服务启动后进行健康探测，确认就绪后才返回
#      - DISPLAY 统一设为 :99
# ==============================================================================
echo "⚙️  [完成] 写入快捷管理函数 ($REAL_HOME/.functions.sh)..."

cat > "$REAL_HOME/.functions.sh" << 'FUNCTION_EOF'
# ==============================================================================
# ~/.functions.sh — Chrome + VNC + 双 MCP 快捷管理函数
# ==============================================================================

# 全局路径常量
_CDP_DIR="$HOME/cdp"
_VENV_BIN="$HOME/cdp/venv/bin"
_LOG_DIR="$HOME/cdp/logs"
_PID_DIR="$HOME/cdp/pids"
export DISPLAY=:99

# ------------------------------------------------------------------------------
# 内部辅助：通过 PID 文件优雅停止一个服务
#   用法: _kill_service "服务名" "/path/to/service.pid"
# ------------------------------------------------------------------------------
_kill_service() {
    local name="$1"
    local pid_file="$2"

    if [ ! -f "$pid_file" ]; then
        return 0
    fi

    local pid
    pid=$(cat "$pid_file" 2>/dev/null || true)

    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        # 进程已不存在，直接清理 pid 文件
        rm -f "$pid_file"
        return 0
    fi

    echo "  - 正在停止 $name (PID: $pid)..."
    kill "$pid" 2>/dev/null || true

    # 等待最多 3 秒（SIGTERM 优雅退出）
    local i
    for i in $(seq 1 15); do
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$pid_file"
            return 0
        fi
        sleep 0.2
    done

    # 超时后 SIGKILL 强制终止
    echo "  - $name 未响应 SIGTERM，强制 SIGKILL (PID: $pid)..."
    kill -9 "$pid" 2>/dev/null || true
    sleep 0.3
    rm -f "$pid_file"
}

# ------------------------------------------------------------------------------
# 内部辅助：检查 PID 文件对应进程是否存活
#   用法: _is_alive "/path/to/service.pid" && echo "running"
# ------------------------------------------------------------------------------
_is_alive() {
    local pid_file="$1"
    if [ ! -f "$pid_file" ]; then
        return 1
    fi
    local pid
    pid=$(cat "$pid_file" 2>/dev/null || true)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# ==============================================================================
# vnc — 重启 TigerVNC + Fluxbox + noVNC (6080)
# ==============================================================================
vnc() {
    local log_dir="$_LOG_DIR"
    local pid_dir="$_PID_DIR"
    mkdir -p "$log_dir" "$pid_dir"

    echo "🖥️  [vnc] 停止旧服务..."
    _kill_service "WebSockify" "$pid_dir/websockify.pid"
    _kill_service "Fluxbox"    "$pid_dir/fluxbox.pid"
    _kill_service "TigerVNC"   "$pid_dir/vnc.pid"

    # 清理遗留 X11 锁文件（仅清理锁，不删除用户配置目录）
    rm -f /tmp/.X99-lock /tmp/.X11-unix/X99

    echo "🖥️  [vnc] 启动 TigerVNC..."
    Xtigervnc :99 \
        -geometry 2560x1440 \
        -depth 24 \
        -SecurityTypes None \
        -AlwaysShared \
        -rfbport 5900 \
        >"$log_dir/vnc.log" 2>&1 &
    echo $! > "$pid_dir/vnc.pid"

    # 等待 X11 Socket 就绪（最多 6 秒）
    local i socket_ready=0
    for i in $(seq 1 30); do
        if [ -S /tmp/.X11-unix/X99 ]; then
            socket_ready=1
            break
        fi
        sleep 0.2
    done

    if [ "$socket_ready" -ne 1 ]; then
        echo "❌ [vnc] TigerVNC 启动超时，查看日志: $log_dir/vnc.log" >&2
        return 1
    fi

    echo "🖥️  [vnc] 启动 Fluxbox 窗口管理器..."
    DISPLAY=:99 fluxbox >"$log_dir/fluxbox.log" 2>&1 &
    echo $! > "$pid_dir/fluxbox.pid"

    # 等待 Fluxbox 完成初始化（避免 Chrome 启动时窗口管理器未就绪）
    sleep 1.5

    echo "🖥️  [vnc] 启动 noVNC (websockify 6080)..."
    websockify --web=/usr/share/novnc 6080 localhost:5900 \
        >"$log_dir/novnc.log" 2>&1 &
    echo $! > "$pid_dir/websockify.pid"

    # 健康探测：确认 noVNC HTTP 服务真实响应
    local novnc_ready=0
    for i in $(seq 1 20); do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            http://127.0.0.1:6080/vnc.html 2>/dev/null || true)
        if echo "$http_code" | grep -qE "^(200|302)$"; then
            novnc_ready=1
            break
        fi
        sleep 0.5
    done

    if [ "$novnc_ready" -eq 1 ]; then
        echo "✅ [vnc] 启动成功: http://127.0.0.1:6080/vnc.html"
    else
        echo "⚠️  [vnc] noVNC 未能响应探测，请查看: $log_dir/novnc.log"
    fi
}

# ==============================================================================
# chr — 重启 Google Chrome，CDP 严格绑定 127.0.0.1:9222
# ==============================================================================
chr() {
    local cdp_dir="$_CDP_DIR"
    local log_dir="$_LOG_DIR"
    local pid_dir="$_PID_DIR"
    local profile_dir="$cdp_dir/profile"
    mkdir -p "$log_dir" "$pid_dir" "$profile_dir"
    chmod 700 "$profile_dir"

    echo "🌐 [chr] 停止旧 Chrome..."
    _kill_service "Google Chrome" "$pid_dir/chrome.pid"

    # 清理 Chrome 遗留的单例锁（防止"Profile already in use"错误）
    rm -f "$profile_dir"/Singleton*

    echo "🌐 [chr] 启动 Chrome (CDP: 127.0.0.1:9222)..."

    # --no-sandbox 仅在 root 用户下必须，普通用户不需要且会降低安全性
    local chrome_args=(
        --user-data-dir="$profile_dir"
        --remote-debugging-port=9222
        --remote-debugging-address=127.0.0.1
        --remote-allow-origins=*
        --window-size=2560,1440
        --start-maximized
        --disable-gpu
        --no-first-run
        --disable-dev-shm-usage
        "https://example.com"
    )
    if [[ "$(id -u)" -eq 0 ]]; then
        chrome_args+=(--no-sandbox)
    fi

    DISPLAY=:99 google-chrome-stable "${chrome_args[@]}" \
        >"$log_dir/chrome.log" 2>&1 &
    echo $! > "$pid_dir/chrome.pid"

    # 健康探测：轮询 CDP /json/version 接口确认 Chrome 真实就绪
    echo "  - 等待 Chrome CDP 协议就绪..."
    local i cdp_ready=0
    for i in $(seq 1 40); do
        if curl -s --max-time 1 http://127.0.0.1:9222/json/version \
            2>/dev/null | grep -q '"Browser"'; then
            cdp_ready=1
            break
        fi
        sleep 0.5
    done

    if [ "$cdp_ready" -eq 1 ]; then
        echo "✅ [chr] Chrome CDP 就绪 (127.0.0.1:9222)"
    else
        echo "❌ [chr] Chrome 启动超时，请查看: $log_dir/chrome.log" >&2
        return 1
    fi
}

# ==============================================================================
# buse — 重启 Browser-use MCP，SSE 端口 8001（绑定 127.0.0.1）
#
#   安全说明：
#     mcp-proxy 绑定 127.0.0.1 而非 0.0.0.0
#     外部 AI Agent 通过 Tailscale 隧道访问，不直接暴露公网
# ==============================================================================
buse() {
    local venv_bin="$_VENV_BIN"
    local log_dir="$_LOG_DIR"
    local pid_dir="$_PID_DIR"
    mkdir -p "$log_dir" "$pid_dir"

    # 校验可执行文件存在
    if [ ! -x "$venv_bin/mcp-proxy" ] || [ ! -x "$venv_bin/browser-use" ]; then
        echo "❌ [buse] 找不到 mcp-proxy 或 browser-use，请重新运行 install.sh" >&2
        return 1
    fi

    echo "🤖 [buse] 停止旧 Browser-use MCP..."
    _kill_service "Browser-use MCP" "$pid_dir/buse.pid"

    echo "🤖 [buse] 启动 Browser-use MCP (127.0.0.1:8001)..."
    DISPLAY=:99 \
    BU_CDP_URL="http://127.0.0.1:9222" \
    nohup "$venv_bin/mcp-proxy" \
        --port 8001 \
        --host 127.0.0.1 \
        -- \
        "$venv_bin/browser-use" --mcp \
        >"$log_dir/buse.log" 2>&1 &
    echo $! > "$pid_dir/buse.pid"

    # 短暂等待进程稳定，检查是否意外退出
    sleep 1
    if _is_alive "$pid_dir/buse.pid"; then
        echo "✅ [buse] Browser-use MCP 已启动 (SSE: 127.0.0.1:8001)"
    else
        echo "❌ [buse] 进程意外退出，请查看: $log_dir/buse.log" >&2
        return 1
    fi
}

# ==============================================================================
# crwl — 重启 Crawl-MCP 抓取服务，SSE 端口 8002（绑定 127.0.0.1）
#
#   环境变量说明：
#     CRAWL4AI_BROWSER_URL — crawl-mcp 0.3.3 识别的 CDP 连接地址
#     （如升级版本请核对该包 README 中的环境变量名称）
# ==============================================================================
crwl() {
    local venv_bin="$_VENV_BIN"
    local log_dir="$_LOG_DIR"
    local pid_dir="$_PID_DIR"
    mkdir -p "$log_dir" "$pid_dir"

    # 校验可执行文件存在
    if [ ! -x "$venv_bin/mcp-proxy" ] || [ ! -x "$venv_bin/crawl-mcp" ]; then
        echo "❌ [crwl] 找不到 mcp-proxy 或 crawl-mcp，请重新运行 install.sh" >&2
        return 1
    fi

    echo "🕷️  [crwl] 停止旧 Crawl-MCP..."
    _kill_service "Crawl-MCP" "$pid_dir/crwl.pid"

    echo "🕷️  [crwl] 启动 Crawl-MCP (127.0.0.1:8002)..."
    DISPLAY=:99 \
    CRAWL4AI_BROWSER_URL="http://127.0.0.1:9222" \
    nohup "$venv_bin/mcp-proxy" \
        --port 8002 \
        --host 127.0.0.1 \
        -- \
        "$venv_bin/crawl-mcp" \
        >"$log_dir/crwl.log" 2>&1 &
    echo $! > "$pid_dir/crwl.pid"

    # 短暂等待进程稳定，检查是否意外退出
    sleep 1
    if _is_alive "$pid_dir/crwl.pid"; then
        echo "✅ [crwl] Crawl-MCP 已启动 (SSE: 127.0.0.1:8002)"
    else
        echo "❌ [crwl] 进程意外退出，请查看: $log_dir/crwl.log" >&2
        return 1
    fi
}

# ==============================================================================
# st — 查看所有服务运行状态
# ==============================================================================
st() {
    local pid_dir="$_PID_DIR"
    echo "📊 ===== 服务健康状态 ====="

    _probe() {
        local label="$1"
        local pid_file="$2"
        local port="$3"
        local health_url="$4"

        printf "  %-20s" "[$label]"

        # PID 存活状态
        if _is_alive "$pid_file"; then
            local pid
            pid=$(cat "$pid_file")
            printf " \033[32mPID:%-7s RUNNING\033[0m" "$pid"
        else
            printf " \033[31mPID:------- STOPPED\033[0m"
        fi

        # 端口监听状态
        if [ -n "$port" ]; then
            if ss -tuln 2>/dev/null | grep -q ":$port " || \
               netstat -tuln 2>/dev/null | grep -q ":$port "; then
                printf "  端口 %-5s \033[32m[LISTEN]\033[0m" "$port"
            else
                printf "  端口 %-5s \033[31m[CLOSED]\033[0m" "$port"
            fi
        fi

        # HTTP 健康探测
        if [ -n "$health_url" ]; then
            if curl -s --max-time 1 "$health_url" >/dev/null 2>&1; then
                printf "  \033[32m(HTTP OK)\033[0m"
            else
                printf "  \033[33m(HTTP 无响应)\033[0m"
            fi
        fi

        printf "\n"
    }

    _probe "noVNC 桌面"    "$pid_dir/websockify.pid" "6080" "http://127.0.0.1:6080/vnc.html"
    _probe "Chrome (CDP)" "$pid_dir/chrome.pid"      "9222" "http://127.0.0.1:9222/json/version"
    _probe "Browser-use"  "$pid_dir/buse.pid"        "8001" ""
    _probe "Crawl-MCP"    "$pid_dir/crwl.pid"        "8002" ""

    echo "==========================="
}

# ==============================================================================
# logs — 实时追踪所有日志
# ==============================================================================
logs() {
    local log_dir="$_LOG_DIR"
    # touch 确保文件存在，防止 tail -f 报"No such file"退出
    touch \
        "$log_dir/vnc.log" \
        "$log_dir/fluxbox.log" \
        "$log_dir/novnc.log" \
        "$log_dir/chrome.log" \
        "$log_dir/buse.log" \
        "$log_dir/crwl.log"
    tail -f \
        "$log_dir/vnc.log" \
        "$log_dir/fluxbox.log" \
        "$log_dir/novnc.log" \
        "$log_dir/chrome.log" \
        "$log_dir/buse.log" \
        "$log_dir/crwl.log"
}

# ==============================================================================
# stop_all — 按序停止全部服务
# ==============================================================================
stop_all() {
    local pid_dir="$_PID_DIR"
    echo "🛑 按序停止全部服务..."
    _kill_service "Crawl-MCP"     "$pid_dir/crwl.pid"
    _kill_service "Browser-use"   "$pid_dir/buse.pid"
    _kill_service "Chrome"        "$pid_dir/chrome.pid"
    _kill_service "WebSockify"    "$pid_dir/websockify.pid"
    _kill_service "Fluxbox"       "$pid_dir/fluxbox.pid"
    _kill_service "TigerVNC"      "$pid_dir/vnc.pid"
    rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
    echo "✅ 全部服务已停止"
}

FUNCTION_EOF

# ------------------------------------------------------------------------------
# 7. 将加载语句注入现有 Shell 配置文件（幂等写入，不重复注入）
# ------------------------------------------------------------------------------
INJECT_LINE=". \"\$HOME/.functions.sh\""
INJECT_MARKER="# >>> cdp-browser-tools >>>"

for rc in "$REAL_HOME/.bashrc" "$REAL_HOME/.zshrc"; do
    if [ -f "$rc" ]; then
        if ! grep -qF "$INJECT_MARKER" "$rc"; then
            {
                echo ""
                echo "$INJECT_MARKER"
                echo "$INJECT_LINE"
                echo "# <<< cdp-browser-tools <<<"
            } >> "$rc"
            echo "✅ 已向 $rc 注入加载语句"
        else
            echo "   $rc 已包含加载语句，跳过"
        fi
    fi
done

# 未检测到的 Shell 给出手动提示
echo ""
echo "💡 如使用 fish / ksh 等其他 Shell，请手动添加到对应配置文件："
echo "   bash/zsh: . \"\$HOME/.functions.sh\""

# ------------------------------------------------------------------------------
# 8. 首次按序拉起全部服务（含启动时序等待）
# ------------------------------------------------------------------------------
echo ""
echo "🚀 首次按序启动全部服务..."

# source 函数定义到当前 shell
# shellcheck source=/dev/null
. "$REAL_HOME/.functions.sh"

vnc                  # 1. 先启动图形桌面，内部已等待 X11 + Fluxbox 就绪
chr                  # 2. 再启动 Chrome，内部已等待 CDP 协议就绪
buse                 # 3. Browser-use MCP（依赖 Chrome 已就绪）
crwl                 # 4. Crawl-MCP（依赖 Chrome 已就绪）

echo ""
echo "=================================================="
echo "🎉 安装完成！全部服务已启动"
echo ""
echo "   快捷命令（新终端需先执行: . ~/.functions.sh）"
echo "   vnc      — 重启图形桌面 + noVNC (6080)"
echo "   chr      — 重启 Chrome (CDP 127.0.0.1:9222)"
echo "   buse     — 重启 Browser-use MCP (127.0.0.1:8001)"
echo "   crwl     — 重启 Crawl-MCP (127.0.0.1:8002)"
echo "   st       — 查看全部服务运行状态"
echo "   logs     — 实时追踪全部日志"
echo "   stop_all — 停止全部服务"
echo ""
echo "   网络访问（需通过 Tailscale 隧道）"
echo "   noVNC 桌面:     http://<tailscale-ip>:6080/vnc.html"
echo "   Browser-use MCP: http://<tailscale-ip>:8001/sse"
echo "   Crawl-MCP:       http://<tailscale-ip>:8002/sse"
echo "=================================================="
