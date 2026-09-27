#!/usr/bin/env bash
# ==============================================================================
# vccc_geminiv2_fixed.sh — Chrome + VNC + 双 MCP 自动化生产环境 一键安装修复脚本 (V2 完美修复版)
# ==============================================================================

set -eu
case "${BASH_VERSION:-}${ZSH_VERSION:-}${KSH_VERSION:-}" in
  "") : ;;
  *) set -o pipefail 2>/dev/null || true ;;
esac

# ------------------------------------------------------------------------------
# 0. 前置检查：必须以 root 运行（apt-get / dpkg 需要）
# ------------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 此脚本需要 root 权限运行，请使用: sudo bash $0" >&2
    exit 1
fi

echo "=================================================="
echo "🚀 开始安装 Chrome + VNC + 双 MCP 自动化生产环境 (v2 Fixed)"
echo "=================================================="

# 精确解析目标运行用户的 HOME
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER="$SUDO_USER"
    USER_HOME=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
    REAL_HOME="${USER_HOME:-$HOME}"
    TARGET_GROUP=$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")
else
    TARGET_USER="root"
    REAL_HOME="$HOME"
    TARGET_GROUP="root"
fi

CDP_DIR="$REAL_HOME/cdp"
echo "📂 部署基准目录: $CDP_DIR (归属用户: $TARGET_USER)"

# ------------------------------------------------------------------------------
# 1. 基础系统依赖
# ------------------------------------------------------------------------------
echo "📦 [1/5] 安装系统依赖..."
export DEBIAN_FRONTEND=noninteractive

# 保证启用 universe 源（避免极简镜像缺失 tigervnc / novnc）
if command -v add-apt-repository >/dev/null 2>&1; then
    add-apt-repository -y universe 2>/dev/null || true
fi

apt-get update -y

BASE_PACKAGES="tigervnc-standalone-server novnc websockify fluxbox x11-utils fonts-liberation wget curl gnupg ca-certificates procps net-tools psmisc unzip build-essential git"
apt-get install -y $BASE_PACKAGES 2>/dev/null || apt-get install -y --fix-missing $BASE_PACKAGES

# 检查 Python 是否满足 >= 3.11（browser-use 与 crawl-mcp 的强制硬性需求）
SYS_PY="python3"
NEED_PY_UPGRADE=0
if command -v python3 >/dev/null 2>&1; then
    PY_MAJOR=$(python3 -c 'import sys; print(sys.version_info.major)' 2>/dev/null || echo "0")
    PY_MINOR=$(python3 -c 'import sys; print(sys.version_info.minor)' 2>/dev/null || echo "0")
    if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 11 ]; }; then
        NEED_PY_UPGRADE=1
    fi
else
    NEED_PY_UPGRADE=1
fi

if [ "$NEED_PY_UPGRADE" -eq 1 ]; then
    echo "   [!] 检测到系统默认 Python 低于 3.11，正在补充安装 Python 3.11..."
    apt-get install -y software-properties-common 2>/dev/null || true
    add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null || true
    apt-get update -y
    apt-get install -y python3.11 python3.11-venv python3.11-dev 2>/dev/null || true
    if command -v python3.11 >/dev/null 2>&1; then
        SYS_PY="python3.11"
    fi
fi

# 安装系统 Python 开发包与 Playwright 底层库
PY_VER=$($SYS_PY -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "3")
apt-get install -y \
    "$SYS_PY" \
    python3-pip \
    python3-dev \
    python3-venv \
    "python${PY_VER}-venv" \
    "python${PY_VER}-dev" \
    libnss3 libatk-bridge2.0-0 libxss1 libgbm1 libxshmfence-dev \
    libxrandr2 libxcomposite1 libxcursor1 libxdamage1 libxi6 2>/dev/null || true

# 适配 noVNC 文件路径双向软链接
if [ -d /usr/share/novnc ]; then
    [ -f /usr/share/novnc/vnc.html ] && [ ! -f /usr/share/novnc/index.html ] && ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html 2>/dev/null || true
    [ -f /usr/share/novnc/index.html ] && [ ! -f /usr/share/novnc/vnc.html ] && ln -sf /usr/share/novnc/index.html /usr/share/novnc/vnc.html 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 2. 安装 Google Chrome / Chromium（适配 amd64 与 arm64）
# ------------------------------------------------------------------------------
ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)

if ! command -v google-chrome-stable >/dev/null 2>&1 && ! command -v google-chrome >/dev/null 2>&1; then
    echo "🌐 [2/5] 下载并安装浏览器 (系统架构: $ARCH)..."
    if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "x86_64" ]; then
        CHROME_DEB="/tmp/google-chrome-stable_current_amd64.deb"
        CHROME_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"

        if command -v curl >/dev/null 2>&1; then
            curl -fsSL "$CHROME_URL" -o "$CHROME_DEB"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O "$CHROME_DEB" "$CHROME_URL"
        fi

        if [ -f "$CHROME_DEB" ]; then
            apt-get install -y "$CHROME_DEB" 2>/dev/null || (dpkg -i "$CHROME_DEB" 2>/dev/null || apt-get install -y -f)
            rm -f "$CHROME_DEB"
        fi
    fi

    # ARM64 架构或 deb 安装失败时，通过 apt 安装 Chromium 并做软链别名
    if ! command -v google-chrome-stable >/dev/null 2>&1; then
        echo "   [+] 正在通过 apt 安装 Chromium..."
        apt-get install -y chromium-browser 2>/dev/null || apt-get install -y chromium 2>/dev/null || true
        if command -v chromium-browser >/dev/null 2>&1; then
            ln -sf "$(command -v chromium-browser)" /usr/bin/google-chrome-stable
            ln -sf "$(command -v chromium-browser)" /usr/bin/google-chrome 2>/dev/null || true
        elif command -v chromium >/dev/null 2>&1; then
            ln -sf "$(command -v chromium)" /usr/bin/google-chrome-stable
            ln -sf "$(command -v chromium)" /usr/bin/google-chrome 2>/dev/null || true
        fi
    fi
else
    echo "✅ [2/5] Chrome/Chromium 已就绪，跳过安装"
fi

if ! command -v google-chrome-stable >/dev/null 2>&1 && ! command -v google-chrome >/dev/null 2>&1; then
    echo "❌ 浏览器安装失败，请检查网络或系统架构" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 3. 准备运行目录与 Python 虚拟环境
# ------------------------------------------------------------------------------
echo "🐍 [3/5] 初始化 Python 虚拟环境..."

mkdir -p "$CDP_DIR/logs" "$CDP_DIR/pids" "$CDP_DIR/profile"
chmod 700 "$CDP_DIR/profile"

VENV_DIR="$CDP_DIR/venv"
VENV_BIN="$VENV_DIR/bin"
VENV_PY="$VENV_BIN/python3"
VENV_PIP="$VENV_BIN/pip"

VENV_HEALTHY=0
if [ -x "$VENV_PY" ] && [ -x "$VENV_PIP" ]; then
    if "$VENV_PY" -m pip --version >/dev/null 2>&1; then
        VENV_HEALTHY=1
    fi
fi

if [ "$VENV_HEALTHY" -eq 1 ]; then
    echo "   [✓] 虚拟环境健康且已就绪: $VENV_DIR"
else
    if [ -d "$VENV_DIR" ]; then
        echo "   [!] 检测到已有虚拟环境不完整，清理并重建..."
        rm -rf "$VENV_DIR"
    fi

    echo "   [+] 正在创建 Python 虚拟环境: $VENV_DIR (使用 $SYS_PY)"
    if ! "$SYS_PY" -m venv "$VENV_DIR" 2>/dev/null; then
        "$SYS_PY" -m venv --without-pip "$VENV_DIR" || {
            echo "❌ 无法创建 Python 虚拟环境" >&2
            exit 1
        }
    fi
fi

# 确保 pip 存在并可用
if [ ! -x "$VENV_PIP" ] || ! "$VENV_PY" -m pip --version >/dev/null 2>&1; then
    echo "   [+] 虚拟环境中注入 pip..."
    "$VENV_PY" -m ensurepip --upgrade --default-pip 2>/dev/null || true

    if [ ! -x "$VENV_PIP" ] || ! "$VENV_PY" -m pip --version >/dev/null 2>&1; then
        GET_PIP_TMP="/tmp/get-pip-$$.py"
        curl -fsSL https://bootstrap.pypa.io/get-pip.py -o "$GET_PIP_TMP" 2>/dev/null || \
            wget -q -O "$GET_PIP_TMP" https://bootstrap.pypa.io/get-pip.py 2>/dev/null || true
        if [ -f "$GET_PIP_TMP" ]; then
            "$VENV_PY" "$GET_PIP_TMP" --no-warn-script-location 2>/dev/null || true
            rm -f "$GET_PIP_TMP"
        fi
    fi

    if [ ! -x "$VENV_PIP" ] && "$VENV_PY" -m pip --version >/dev/null 2>&1; then
        cat > "$VENV_PIP" << 'PIPW_EOF'
#!/bin/sh
exec "$(dirname "$0")/python3" -m pip "$@"
PIPW_EOF
        chmod +x "$VENV_PIP"
    fi
fi

echo "   [✓] Python 虚拟环境就绪: $VENV_DIR"

# ------------------------------------------------------------------------------
# 4. 在虚拟环境内安装 Python 依赖（锁定 mcp<2.0.0 防止崩溃）
# ------------------------------------------------------------------------------
echo "📦 [4/5] 安装 Python MCP 套件（虚拟环境隔离）..."

"$VENV_PY" -m pip install --upgrade pip setuptools wheel

# 关键修复：锁定 mcp<2.0.0，杜绝 request_ctx 导入错误
"$VENV_PY" -m pip install \
    "setuptools<82" \
    "lxml~=5.3" \
    "click==8.3.3" \
    "mcp>=1.17.0,<2.0.0"

# 安装核心 MCP 套件
"$VENV_PY" -m pip install \
    "browser-use[cli]==0.1.45" \
    "crawl4ai==0.8.9" \
    "crawl-mcp==0.3.3" \
    "mcp-proxy==0.9.0" \
    "mcp>=1.17.0,<2.0.0"

# 强制重装固化冲突库版本
"$VENV_PY" -m pip install --force-reinstall "click==8.3.3" "mcp>=1.17.0,<2.0.0"

# 补齐 Playwright Chromium 驱动
echo "   [+] 补齐 Playwright 浏览器组件..."
"$VENV_PY" -m playwright install chromium 2>/dev/null || true

# ------------------------------------------------------------------------------
# 5. 校验可执行文件
# ------------------------------------------------------------------------------
echo "🔍 [5/5] 校验关键可执行文件..."

for bin_name in Xtigervnc fluxbox websockify; do
    if ! command -v "$bin_name" >/dev/null 2>&1; then
        echo "❌ 缺少系统依赖: $bin_name" >&2
        exit 1
    fi
done

if ! command -v google-chrome-stable >/dev/null 2>&1 && ! command -v google-chrome >/dev/null 2>&1; then
    echo "❌ 缺少 Chrome/Chromium 可执行程序" >&2
    exit 1
fi

for bin_path in "$VENV_BIN/mcp-proxy" "$VENV_BIN/browser-use" "$VENV_BIN/crawl-mcp"; do
    if [ ! -x "$bin_path" ]; then
        echo "❌ 缺少虚拟环境工具: $bin_path" >&2
        exit 1
    fi
done

echo "   所有可执行文件校验通过 ✅"

# 修正文件权限
if [ "$TARGET_USER" != "root" ]; then
    chown -R "$TARGET_USER:$TARGET_GROUP" "$CDP_DIR" 2>/dev/null || true
fi

# ==============================================================================
# 6. 生成快捷管理函数文件 ~/.functions.sh
# ==============================================================================
echo "⚙️  [完成] 写入快捷管理函数 ($REAL_HOME/.functions.sh)..."

cat > "$REAL_HOME/.functions.sh" << 'FUNCTION_EOF'
# ==============================================================================
# ~/.functions.sh — Chrome + VNC + 双 MCP 快捷管理函数
# ==============================================================================

_CDP_DIR="__ACTUAL_CDP_DIR__"
_VENV_BIN="$_CDP_DIR/venv/bin"
_LOG_DIR="$_CDP_DIR/logs"
_PID_DIR="$_CDP_DIR/pids"
export DISPLAY=:99
export ANONYMIZED_TELEMETRY=false

_kill_service() {
    local name="$1"
    local pid_file="$2"

    if [ ! -f "$pid_file" ]; then
        return 0
    fi

    local pid
    pid=$(cat "$pid_file" 2>/dev/null || true)

    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$pid_file"
        return 0
    fi

    echo "  - 正在停止 $name (PID: $pid)..."
    kill "$pid" 2>/dev/null || true

    local i
    for i in $(seq 1 15); do
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$pid_file"
            return 0
        fi
        sleep 0.2
    done

    echo "  - $name 未响应 SIGTERM，强制 SIGKILL (PID: $pid)..."
    kill -9 "$pid" 2>/dev/null || true
    sleep 0.3
    rm -f "$pid_file"
}

_is_alive() {
    local pid_file="$1"
    if [ ! -f "$pid_file" ]; then
        return 1
    fi
    local pid
    pid=$(cat "$pid_file" 2>/dev/null || true)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

vnc() {
    local log_dir="$_LOG_DIR"
    local pid_dir="$_PID_DIR"
    mkdir -p "$log_dir" "$pid_dir"

    echo "🖥️  [vnc] 停止旧服务..."
    _kill_service "WebSockify" "$pid_dir/websockify.pid"
    _kill_service "Fluxbox"    "$pid_dir/fluxbox.pid"
    _kill_service "TigerVNC"   "$pid_dir/vnc.pid"

    # 清理残留进程与 X11 锁文件
    pkill -9 -f "Xtigervnc :99" 2>/dev/null || true
    pkill -9 -f "websockify.*6080" 2>/dev/null || true
    rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
    mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix 2>/dev/null || true

    echo "🖥️  [vnc] 启动 TigerVNC..."
    Xtigervnc :99 \
        -geometry 2560x1440 \
        -depth 24 \
        -SecurityTypes None \
        -AlwaysShared \
        -rfbport 5900 \
        >"$log_dir/vnc.log" 2>&1 &
    echo $! > "$pid_dir/vnc.pid"

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

    sleep 1

    echo "🖥️  [vnc] 启动 noVNC (websockify 6080)..."
    websockify --web=/usr/share/novnc 6080 localhost:5900 \
        >"$log_dir/novnc.log" 2>&1 &
    echo $! > "$pid_dir/websockify.pid"

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

chr() {
    local cdp_dir="$_CDP_DIR"
    local log_dir="$_LOG_DIR"
    local pid_dir="$_PID_DIR"
    local profile_dir="$cdp_dir/profile"
    mkdir -p "$log_dir" "$pid_dir" "$profile_dir"
    chmod 700 "$profile_dir"

    echo "🌐 [chr] 停止旧 Chrome..."
    _kill_service "Google Chrome" "$pid_dir/chrome.pid"
    pkill -9 -f "remote-debugging-port=9222" 2>/dev/null || true
    rm -f "$profile_dir"/Singleton*

    echo "🌐 [chr] 启动 Chrome (CDP: 127.0.0.1:9222)..."

    local chrome_bin="google-chrome-stable"
    if ! command -v "$chrome_bin" >/dev/null 2>&1; then
        chrome_bin="google-chrome"
    fi

    local chrome_sandbox=""
    if [ "$(id -u)" -eq 0 ]; then
        chrome_sandbox="--no-sandbox"
    fi

    DISPLAY=:99 "$chrome_bin" \
        --user-data-dir="$profile_dir" \
        --remote-debugging-port=9222 \
        --remote-debugging-address=127.0.0.1 \
        --remote-allow-origins=* \
        --window-size=2560,1440 \
        --start-maximized \
        --disable-gpu \
        --no-first-run \
        --no-default-browser-check \
        --password-store=basic \
        --disable-dev-shm-usage \
        $chrome_sandbox \
        "https://example.com" \
        >"$log_dir/chrome.log" 2>&1 &
    echo $! > "$pid_dir/chrome.pid"

    echo "  - 等待 Chrome CDP 协议就绪..."
    local i cdp_ready=0
    for i in $(seq 1 60); do
        local cdp_resp
        cdp_resp=$(curl -s --max-time 1 http://127.0.0.1:9222/json/version 2>/dev/null || true)
        if echo "$cdp_resp" | grep -q '"Browser"'; then
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

buse() {
    local venv_bin="$_VENV_BIN"
    local log_dir="$_LOG_DIR"
    local pid_dir="$_PID_DIR"
    mkdir -p "$log_dir" "$pid_dir"

    if [ ! -x "$venv_bin/mcp-proxy" ] || [ ! -x "$venv_bin/browser-use" ]; then
        echo "❌ [buse] 找不到 mcp-proxy 或 browser-use，请重新运行安装脚本" >&2
        return 1
    fi

    echo "🤖 [buse] 停止旧 Browser-use MCP..."
    _kill_service "Browser-use MCP" "$pid_dir/buse.pid"
    pkill -9 -f "mcp-proxy.*--port 8001" 2>/dev/null || true

    echo "🤖 [buse] 启动 Browser-use MCP (0.0.0.0:8001)..."
    DISPLAY=:99 \
    BU_CDP_URL="http://127.0.0.1:9222" \
    nohup "$venv_bin/mcp-proxy" \
        --port 8001 \
        --host 0.0.0.0 \
        -- \
        "$venv_bin/browser-use" --mcp \
        >"$log_dir/buse.log" 2>&1 &
    echo $! > "$pid_dir/buse.pid"

    local ready=0
    for i in $(seq 1 15); do
        if _is_alive "$pid_dir/buse.pid"; then
            if (command -v ss >/dev/null 2>&1 && ss -tuln 2>/dev/null | grep -qE ":8001[[:space:]]") || \
               (command -v netstat >/dev/null 2>&1 && netstat -tuln 2>/dev/null | grep -qE ":8001[[:space:]]"); then
                ready=1
                break
            fi
        else
            break
        fi
        sleep 0.5
    done

    if [ "$ready" -eq 1 ] || _is_alive "$pid_dir/buse.pid"; then
        echo "✅ [buse] Browser-use MCP 已启动 (SSE: 0.0.0.0:8001)"
    else
        echo "❌ [buse] 进程意外退出，请查看: $log_dir/buse.log" >&2
        return 1
    fi
}

crwl() {
    local venv_bin="$_VENV_BIN"
    local log_dir="$_LOG_DIR"
    local pid_dir="$_PID_DIR"
    mkdir -p "$log_dir" "$pid_dir"

    if [ ! -x "$venv_bin/mcp-proxy" ] || [ ! -x "$venv_bin/crawl-mcp" ]; then
        echo "❌ [crwl] 找不到 mcp-proxy 或 crawl-mcp，请重新运行安装脚本" >&2
        return 1
    fi

    echo "🕷️  [crwl] 停止旧 Crawl-MCP..."
    _kill_service "Crawl-MCP" "$pid_dir/crwl.pid"
    pkill -9 -f "mcp-proxy.*--port 8002" 2>/dev/null || true

    echo "🕷️  [crwl] 启动 Crawl-MCP (0.0.0.0:8002)..."
    DISPLAY=:99 \
    CRAWL4AI_BROWSER_URL="http://127.0.0.1:9222" \
    nohup "$venv_bin/mcp-proxy" \
        --port 8002 \
        --host 0.0.0.0 \
        -- \
        "$venv_bin/crawl-mcp" \
        >"$log_dir/crwl.log" 2>&1 &
    echo $! > "$pid_dir/crwl.pid"

    local ready=0
    for i in $(seq 1 15); do
        if _is_alive "$pid_dir/crwl.pid"; then
            if (command -v ss >/dev/null 2>&1 && ss -tuln 2>/dev/null | grep -qE ":8002[[:space:]]") || \
               (command -v netstat >/dev/null 2>&1 && netstat -tuln 2>/dev/null | grep -qE ":8002[[:space:]]"); then
                ready=1
                break
            fi
        else
            break
        fi
        sleep 0.5
    done

    if [ "$ready" -eq 1 ] || _is_alive "$pid_dir/crwl.pid"; then
        echo "✅ [crwl] Crawl-MCP 已启动 (SSE: 0.0.0.0:8002)"
    else
        echo "❌ [crwl] 进程意外退出，请查看: $log_dir/crwl.log" >&2
        return 1
    fi
}

st() {
    local pid_dir="$_PID_DIR"
    echo "📊 ===== 服务健康状态 ====="

    _probe() {
        local label="$1"
        local pid_file="$2"
        local port="$3"
        local health_url="$4"

        printf "  %-20s" "[$label]"

        if _is_alive "$pid_file"; then
            local pid
            pid=$(cat "$pid_file")
            printf " \033[32mPID:%-7s RUNNING\033[0m" "$pid"
        else
            printf " \033[31mPID:------- STOPPED\033[0m"
        fi

        if [ -n "$port" ]; then
            if (command -v ss >/dev/null 2>&1 && ss -tuln 2>/dev/null | grep -qE ":$port[[:space:]]") || \
               (command -v netstat >/dev/null 2>&1 && netstat -tuln 2>/dev/null | grep -qE ":$port[[:space:]]"); then
                printf "  端口 %-5s \033[32m[LISTEN]\033[0m" "$port"
            else
                printf "  端口 %-5s \033[31m[CLOSED]\033[0m" "$port"
            fi
        fi

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

logs() {
    local log_dir="$_LOG_DIR"
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

stop_all() {
    local pid_dir="$_PID_DIR"
    echo "🛑 按序停止全部服务..."
    _kill_service "Crawl-MCP"     "$pid_dir/crwl.pid"
    _kill_service "Browser-use"   "$pid_dir/buse.pid"
    _kill_service "Chrome"        "$pid_dir/chrome.pid"
    _kill_service "WebSockify"    "$pid_dir/websockify.pid"
    _kill_service "Fluxbox"       "$pid_dir/fluxbox.pid"
    _kill_service "TigerVNC"      "$pid_dir/vnc.pid"
    pkill -9 -f "remote-debugging-port=9222" 2>/dev/null || true
    pkill -9 -f "mcp-proxy.*--port 8001" 2>/dev/null || true
    pkill -9 -f "mcp-proxy.*--port 8002" 2>/dev/null || true
    pkill -9 -f "Xtigervnc :99" 2>/dev/null || true
    pkill -9 -f "websockify.*6080" 2>/dev/null || true
    rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
    echo "✅ 全部服务已停止"
}

FUNCTION_EOF

# 固化实际目录路径
sed -i "s|__ACTUAL_CDP_DIR__|$CDP_DIR|g" "$REAL_HOME/.functions.sh"
chmod 644 "$REAL_HOME/.functions.sh"

if [ "$REAL_HOME" != "$HOME" ]; then
    cp -f "$REAL_HOME/.functions.sh" "$HOME/.functions.sh" 2>/dev/null || true
fi

if [ "$TARGET_USER" != "root" ]; then
    chown "$TARGET_USER:$TARGET_GROUP" "$REAL_HOME/.functions.sh" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 7. 将加载语句注入 Shell 配置文件
# ------------------------------------------------------------------------------
INJECT_LINE=". \"$REAL_HOME/.functions.sh\""
INJECT_MARKER="# >>> cdp-browser-tools >>>"

TARGET_RCS="$REAL_HOME/.bashrc $REAL_HOME/.zshrc"
if [ "$REAL_HOME" != "$HOME" ]; then
    TARGET_RCS="$TARGET_RCS $HOME/.bashrc $HOME/.zshrc"
fi

for rc in $TARGET_RCS; do
    [ ! -f "$rc" ] && touch "$rc" 2>/dev/null || true
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

# ------------------------------------------------------------------------------
# 8. 首次按序拉起全部服务
# ------------------------------------------------------------------------------
echo ""
echo "🚀 首次按序启动全部服务..."

. "$REAL_HOME/.functions.sh"

vnc                  # 1. 图形桌面
chr                  # 2. Chrome (CDP 9222)
buse                 # 3. Browser-use MCP
crwl                 # 4. Crawl-MCP

echo ""
echo "=================================================="
echo "🎉 安装完成！全部服务已启动并跑通"
echo ""
echo "   快捷管理命令（已自动注入 bash/zsh）:"
echo "   vnc      — 重启图形桌面 + noVNC (6080)"
echo "   chr      — 重启 Chrome (CDP 127.0.0.1:9222)"
echo "   buse     — 重启 Browser-use MCP (0.0.0.0:8001)"
echo "   crwl     — 重启 Crawl-MCP (0.0.0.0:8002)"
echo "   st       — 查看全部服务运行状态"
echo "   logs     — 实时追踪全部日志"
echo "   stop_all — 停止全部服务"
echo ""
echo "   网络访问端点:"
echo "   noVNC 桌面:      http://<IP>:6080/vnc.html"
echo "   Browser-use MCP: http://<IP>:8001/sse"
echo "   Crawl-MCP:       http://<IP>:8002/sse"
echo "=================================================="