#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "🚀 开始安装 Chrome + VNC + 双 MCP 自动化生产环境"
echo "=================================================="

# 1. 基础系统与编译依赖
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    tigervnc-standalone-server novnc websockify fluxbox x11-utils fonts-liberation \
    wget curl gnupg ca-certificates procps net-tools unzip \
    python3 python3-pip python3-dev build-essential git

# 2. 安装 Google Chrome 官方稳定版
if ! command -v google-chrome-stable >/dev/null 2>&1; then
    echo "🌐 [1/4] 下载并安装 Google Chrome..."
    CHROME_DEB="/tmp/google-chrome-stable_current_amd64.deb"
    wget -q -O "$CHROME_DEB" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    apt-get install -y "$CHROME_DEB"
    rm -f "$CHROME_DEB"
fi

# 3. 准备运行目录与 Python 独立虚拟环境 (使用 virtualenv)
CDP_DIR="$HOME/cdp"
mkdir -p "$CDP_DIR/logs" "$CDP_DIR/profile"
chmod 700 "$CDP_DIR/profile"

python3 -m pip install --upgrade pip setuptools wheel virtualenv
if [ ! -d "$CDP_DIR/venv" ]; then
    echo "🐍 [2/4] 初始化独立 Python 虚拟环境..."
    virtualenv "$CDP_DIR/venv"
fi

VENV_PIP="$CDP_DIR/venv/bin/pip"
VENV_BIN="$CDP_DIR/venv/bin"

echo "📦 [3/4] 整合安装 Browser-use + Crawl-MCP 核心组件及精准版本..."
"$VENV_PIP" install --upgrade pip
"$VENV_PIP" install "setuptools<82"
"$VENV_PIP" install "lxml~=5.3"
"$VENV_PIP" install "browser-use[cli]"
"$VENV_PIP" install "crawl4ai==0.8.9"
"$VENV_PIP" install "crawl-mcp==0.3.3"
"$VENV_PIP" install mcp-proxy

# 修复 click 冲突，保障 browser-use 稳定
"$VENV_PIP" install --force-reinstall "click==8.3.3"

# 4. 生成极简快捷管理函数 (~/.functions.sh)
echo "⚙️  [4/4] 写入快捷管理函数 (~/.functions.sh)..."
cat > "$HOME/.functions.sh" << 'FUNCTION'
# 1. 重启 VNC 图形桌面服务 (6080)
vnc() {
    local log_dir="$HOME/cdp/logs"
    mkdir -p "$log_dir"

    pkill -f websockify 2>/dev/null || true
    pkill -f fluxbox 2>/dev/null || true
    pkill -f Xtigervnc 2>/dev/null || true

    for _ in {1..10}; do
        pgrep -f Xtigervnc >/dev/null 2>&1 || break
        sleep 0.2
    done
    pkill -9 -f Xtigervnc 2>/dev/null || true
    rm -f /tmp/.X99-lock /tmp/.X11-unix/X99

    nohup Xtigervnc :99 -geometry 2560x1440 -depth 24 -SecurityTypes None -AlwaysShared -rfbport 5900 >/dev/null 2>&1 &

    local ready=0
    for _ in {1..30}; do
        if [ -S /tmp/.X11-unix/X99 ]; then ready=1; break; fi
        sleep 0.2
    done

    if [ "$ready" -ne 1 ]; then
        echo "❌ [vnc] TigerVNC 启动超时！" >&2
        return 1
    fi

    DISPLAY=:99 nohup fluxbox >/dev/null 2>&1 &
    nohup websockify --web=/usr/share/novnc 6080 localhost:5900 >"$log_dir/vnc.log" 2>&1 &

    echo "✅ [vnc] 重启成功: http://localhost:6080/vnc.html"
}

# 2. 重启 Chrome 浏览器 (127.0.0.1:9222)
chr() {
    local cdp_dir="$HOME/cdp"
    local log_dir="$cdp_dir/logs"
    local profile_dir="$cdp_dir/profile"
    mkdir -p "$log_dir" "$profile_dir"
    chmod 700 "$profile_dir"

    pkill -f google-chrome-stable 2>/dev/null || true
    for _ in {1..10}; do
        pgrep -f google-chrome-stable >/dev/null 2>&1 || break
        sleep 0.2
    done
    pkill -9 -f google-chrome-stable 2>/dev/null || true

    rm -f "$profile_dir"/Singleton*

    DISPLAY=:99 nohup google-chrome-stable \
        --user-data-dir="$profile_dir" \
        --remote-debugging-port=9222 \
        --remote-debugging-address=127.0.0.1 \
        --remote-allow-origins=* \
        --window-size=2560,1440 \
        --start-maximized \
        --disable-gpu \
        --no-first-run \
        --no-sandbox \
        --disable-dev-shm-usage \
        "https://example.com" >"$log_dir/chrome.log" 2>&1 &

    echo "✅ [chr] 重启成功 (CDP 监听: 127.0.0.1:9222)"
}

# 3. 重启 Browser-use 官方 MCP (8001)
buse() {
    local venv_bin="$HOME/cdp/venv/bin"
    local log_dir="$HOME/cdp/logs"
    mkdir -p "$log_dir"

    pkill -f "mcp-proxy.*8001" 2>/dev/null || true
    for _ in {1..5}; do
        pgrep -f "mcp-proxy.*8001" >/dev/null 2>&1 || break
        sleep 0.2
    done

    DISPLAY=:99 BU_CDP_URL="http://127.0.0.1:9222" \
    nohup "$venv_bin/mcp-proxy" --port 8001 --host 0.0.0.0 -- \
    "$venv_bin/browser-use" --mcp >"$log_dir/buse.log" 2>&1 &

    echo "✅ [buse] 重启成功 (SSE 监听: 8001)"
}

# 4. 重启 Crawl-MCP 抓取服务 (8002)
crwl() {
    local venv_bin="$HOME/cdp/venv/bin"
    local log_dir="$HOME/cdp/logs"
    mkdir -p "$log_dir"

    pkill -f "mcp-proxy.*8002" 2>/dev/null || true
    for _ in {1..5}; do
        pgrep -f "mcp-proxy.*8002" >/dev/null 2>&1 || break
        sleep 0.2
    done

    CRAWL4AI_BROWSER_URL="http://127.0.0.1:9222" \
    nohup "$venv_bin/mcp-proxy" --port 8002 --host 0.0.0.0 -- \
    "$venv_bin/crawl-mcp" >"$log_dir/crwl.log" 2>&1 &

    echo "✅ [crwl] 重启成功: crawl-mcp 已挂载至 SSE 端口 8002"
}
FUNCTION

# 5. 安全注入当前存在的 Shell 配置
INJECT_LINE='[ -f "$HOME/.functions.sh" ] && . "$HOME/.functions.sh"'

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ]; then
        if ! grep -qF "$INJECT_LINE" "$rc"; then
            {
                echo ""
                echo "# >>> cdp-browser-tools >>>"
                echo "$INJECT_LINE"
                echo "# <<< cdp-browser-tools <<<"
            } >> "$rc"
            echo "✅ 已向 $rc 写入安全加载语句"
        fi
    fi
done

# 6. 首次拉起全部四个后台服务
echo "🚀 首次拉起全部四个后台服务..."
. "$HOME/.functions.sh"
vnc
chr
buse
crwl

echo "=================================================="
echo "🎉 安装完成且所有后台服务已全部启动！"
echo "💡 当前终端立即使用快捷命令，请执行: . ~/.functions.sh"
echo "   日常重启单个服务直接执行: vnc | chr | buse | crwl"
echo "=================================================="
