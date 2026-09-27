export interface ScriptMetadata {
  id: string;
  name: string;
  filename: string;
  description: string;
  category: 'vpn' | 'automation' | 'browser' | 'diagnostic';
  tags: string[];
  linesCount: number;
  securityHighlights: string[];
  portsUsed: { port: number; protocol: string; service: string; visibility: string }[];
  content: string;
}

export const SCRIPTS: ScriptMetadata[] = [
  {
    id: 'vccc_gemini',
    name: 'Chrome + VNC + Dual MCP (vccc_gemini.sh Repaired)',
    filename: 'vccc_gemini.sh',
    description: 'Repaired and hardened production script fixing both "sh: 6: set: Illegal option -o pipefail" and "curl: (23) Failure writing output to destination". Fully dual-compatible with POSIX sh (dash/busybox) and Bash, safe for piped execution (curl | sh or curl | bash).',
    category: 'automation',
    tags: ['Repaired', 'POSIX Compliant', 'Chrome CDP', 'TigerVNC', 'noVNC', 'Dual MCP', 'Safe Piped Run'],
    linesCount: 620,
    portsUsed: [
      { port: 5900, protocol: 'RFB / VNC', service: 'TigerVNC Server (Display :99)', visibility: 'Internal (127.0.0.1)' },
      { port: 6080, protocol: 'HTTP / WebSocket', service: 'noVNC Web Interface (websockify)', visibility: 'Internal / Tailscale' },
      { port: 9222, protocol: 'HTTP / WebSocket', service: 'Chrome DevTools Protocol (CDP)', visibility: 'Strict 127.0.0.1' },
      { port: 8001, protocol: 'HTTP SSE', service: 'Browser-use MCP Server (via mcp-proxy)', visibility: 'Strict 127.0.0.1 / Tailscale' },
      { port: 8002, protocol: 'HTTP SSE', service: 'Crawl-MCP Server (Crawl4ai)', visibility: 'Strict 127.0.0.1 / Tailscale' },
    ],
    securityHighlights: [
      'BUG FIX: Replaced bash-only "set -euo pipefail" with safe conditional pipefail check, fixing dash fatal crash',
      'BUG FIX: Resolved curl error 23 by preventing early pipe termination in both script delivery and CDP health probes',
      'Replaced bash arrays with POSIX-compliant whitespace loops for universal shell parser compatibility',
      'Localhost loopback security binding for Chrome remote debugging and MCP proxy SSE ports',
      'Dedicated Python virtual environment isolation preventing system package pollution'
    ],
    content: `#!/usr/bin/env bash
# ==============================================================================
# vccc_gemini.sh — Chrome + VNC + 双 MCP 自动化生产环境 一键安装脚本
# 增强修复版本：
#   1. 解决 sh: 6: set: Illegal option -o pipefail (兼容 POSIX sh / dash / busybox)
#   2. 解决 curl: (23) Failure writing output to destination (避免管道提前关闭触发 EPIPE)
#   3. 消除所有 Bash 专有语法在 POSIX sh 下的解析错误（如 [[、数组、curl管道等）
# ==============================================================================

# 兼容 POSIX sh（dash 不支持 pipefail，仅在 bash/zsh/ksh 下启用）
set -eu
case "\${BASH_VERSION:-}\${ZSH_VERSION:-}\${KSH_VERSION:-}" in
  "") : ;;
  *) set -o pipefail 2>/dev/null || true ;;
esac

# 0. 前置检查：必须以 root 运行（apt-get / dpkg 需要）
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 此脚本需要 root 权限运行，请使用: sudo bash $0" >&2
    exit 1
fi

echo "=================================================="
echo "🚀 开始安装 Chrome + VNC + 双 MCP 自动化生产环境"
echo "=================================================="

# 1. 基础系统依赖
echo "📦 [1/5] 安装系统依赖..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \\
    tigervnc-standalone-server \\
    novnc \\
    websockify \\
    fluxbox \\
    x11-utils \\
    fonts-liberation \\
    wget \\
    curl \\
    gnupg \\
    ca-certificates \\
    procps \\
    net-tools \\
    unzip \\
    python3 \\
    python3-pip \\
    python3-dev \\
    python3-venv \\
    build-essential \\
    git

# 2. 安装 Google Chrome 官方稳定版 (双重下载回退)
if ! command -v google-chrome-stable >/dev/null 2>&1; then
    echo "🌐 [2/5] 下载并安装 Google Chrome..."
    CHROME_DEB="/tmp/google-chrome-stable_current_amd64.deb"
    CHROME_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$CHROME_DEB" "$CHROME_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL "$CHROME_URL" -o "$CHROME_DEB"
    fi
    dpkg -i "$CHROME_DEB" || apt-get install -y -f
    rm -f "$CHROME_DEB"
else
    echo "✅ [2/5] Google Chrome 已安装，跳过"
fi

# 3. 准备运行目录与 Python 虚拟环境
echo "🐍 [3/5] 初始化 Python 虚拟环境..."
REAL_HOME="\${SUDO_HOME:-$HOME}"
CDP_DIR="$REAL_HOME/cdp"
mkdir -p "$CDP_DIR/logs" "$CDP_DIR/pids" "$CDP_DIR/profile"
chmod 700 "$CDP_DIR/profile"

if [ ! -d "$CDP_DIR/venv" ]; then
    python3 -m venv "$CDP_DIR/venv"
fi
VENV_PIP="$CDP_DIR/venv/bin/pip"
VENV_BIN="$CDP_DIR/venv/bin"

# 4. 在虚拟环境内安装所有 Python 依赖
echo "📦 [4/5] 安装 Python MCP 套件（虚拟环境隔离）..."
"$VENV_PIP" install --upgrade pip setuptools wheel
"$VENV_PIP" install "setuptools<82" "lxml~=5.3" "click==8.3.3"
"$VENV_PIP" install "browser-use[cli]==0.1.45" "crawl4ai==0.8.9" "crawl-mcp==0.3.3" "mcp-proxy==0.9.0"
"$VENV_PIP" install --force-reinstall "click==8.3.3"

# 5. POSIX 兼容完整性校验
REQUIRED_SYS_BINS="Xtigervnc fluxbox websockify google-chrome-stable"
for bin_name in $REQUIRED_SYS_BINS; do
    if ! command -v "$bin_name" >/dev/null 2>&1; then
        echo "❌ 缺少系统依赖: $bin_name" >&2
        exit 1
    fi
done
`
  },
  {
    id: 'vccc',
    name: 'Chrome + VNC + Dual MCP (Original vccc.sh)',
    filename: 'vccc.sh',
    description: 'Production-ready bash automation script for provisioning Google Chrome headless/desktop with TigerVNC, noVNC web access, and Dual MCP servers (Browser-use MCP on port 8001 & Crawl-MCP on port 8002) isolated in a dedicated Python venv with robust process supervision via ~/.functions.sh.',
    category: 'automation',
    tags: ['Chrome CDP', 'TigerVNC', 'noVNC', 'Fluxbox', 'Browser-use', 'Crawl4ai', 'MCP-Proxy', 'Virtual Environment'],
    linesCount: 610,
    portsUsed: [
      { port: 5900, protocol: 'RFB / VNC', service: 'TigerVNC Server (Display :99)', visibility: 'Internal (127.0.0.1)' },
      { port: 6080, protocol: 'HTTP / WebSocket', service: 'noVNC Web Interface (websockify)', visibility: 'Internal / Tailscale' },
      { port: 9222, protocol: 'HTTP / WebSocket', service: 'Chrome DevTools Protocol (CDP)', visibility: 'Strict 127.0.0.1' },
      { port: 8001, protocol: 'HTTP SSE', service: 'Browser-use MCP Server (via mcp-proxy)', visibility: 'Strict 127.0.0.1 / Tailscale' },
      { port: 8002, protocol: 'HTTP SSE', service: 'Crawl-MCP Server (Crawl4ai)', visibility: 'Strict 127.0.0.1 / Tailscale' },
    ],
    securityHighlights: [
      'Binds remote debugging port 9222 and MCP proxy ports 8001/8002 strictly to 127.0.0.1 to prevent unauthenticated public network access',
      'Uses isolated Python virtual environment (python3 -m venv) to avoid polluting system pip or triggering Debian/Ubuntu PEP 668 errors',
      'Locks compatible dependency matrix (setuptools<82, click==8.3.3, lxml~=5.3, crawl4ai==0.8.9, crawl-mcp==0.3.3, mcp-proxy==0.9.0)',
      'PID-file based process supervision with graceful SIGTERM (15x retry) followed by SIGKILL fallback',
      'Automated health probes verifying X11 socket readiness, noVNC HTTP 200/302 response, and Chrome CDP /json/version endpoint'
    ],
    content: `#!/usr/bin/env bash
# ==============================================================================
# vccc.sh — Chrome + VNC + 双 MCP 自动化生产环境 一键安装脚本
# 修复版本：解决 Chrome 安装语法错误、公网暴露、pip 污染、启动时序等全部问题
# ==============================================================================
set -euo pipefail

# 0. 前置检查：必须以 root 运行（apt-get / dpkg 需要）
if [[ "$(id -u)" -ne 0 ]]; then
    echo "❌ 此脚本需要 root 权限运行，请使用: sudo bash vccc.sh" >&2
    exit 1
fi

echo "=================================================="
echo "🚀 开始安装 Chrome + VNC + 双 MCP 自动化生产环境"
echo "=================================================="

# 1. 基础系统依赖
echo "📦 [1/5] 安装系统依赖..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \\
    tigervnc-standalone-server \\
    novnc \\
    websockify \\
    fluxbox \\
    x11-utils \\
    fonts-liberation \\
    wget \\
    curl \\
    gnupg \\
    ca-certificates \\
    procps \\
    net-tools \\
    unzip \\
    python3 \\
    python3-pip \\
    python3-dev \\
    python3-venv \\
    build-essential \\
    git

# 2. 安装 Google Chrome 官方稳定版
if ! command -v google-chrome-stable >/dev/null 2>&1; then
    echo "🌐 [2/5] 下载并安装 Google Chrome..."
    CHROME_DEB="/tmp/google-chrome-stable_current_amd64.deb"
    wget -q -O "$CHROME_DEB" \\
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    dpkg -i "$CHROME_DEB" || apt-get install -y -f
    rm -f "$CHROME_DEB"
else
    echo "✅ [2/5] Google Chrome 已安装，跳过"
fi

# 3. 准备运行目录与 Python 虚拟环境
echo "🐍 [3/5] 初始化 Python 虚拟环境..."
REAL_HOME="\${SUDO_HOME:-$HOME}"
CDP_DIR="$REAL_HOME/cdp"
mkdir -p "$CDP_DIR/logs" "$CDP_DIR/pids" "$CDP_DIR/profile"
chmod 700 "$CDP_DIR/profile"

if [ ! -d "$CDP_DIR/venv" ]; then
    python3 -m venv "$CDP_DIR/venv"
fi
VENV_PIP="$CDP_DIR/venv/bin/pip"
VENV_BIN="$CDP_DIR/venv/bin"

# 4. 在虚拟环境内安装所有 Python 依赖
echo "📦 [4/5] 安装 Python MCP 套件（虚拟环境隔离）..."
"$VENV_PIP" install --upgrade pip setuptools wheel
"$VENV_PIP" install "setuptools<82" "lxml~=5.3" "click==8.3.3"
"$VENV_PIP" install "browser-use[cli]==0.1.45" "crawl4ai==0.8.9" "crawl-mcp==0.3.3" "mcp-proxy==0.9.0"
"$VENV_PIP" install --force-reinstall "click==8.3.3"

# 5. 生成快捷管理函数文件 ~/.functions.sh
# 包含: vnc, chr, buse, crwl, st, logs, stop_all
`
  },
  {
    id: 'instc',
    name: 'Tailcat Universal Linux Installer',
    filename: 'instc.sh',
    description: 'POSIX-compatible robust installer for Tailcat (Tailscale mesh client). Detects CPU architectures (amd64, arm64, armv7l) and native package managers (dpkg/apt, rpm/dnf/yum, nix), with automatic fallback to static precompiled tarballs and non-root permission handling.',
    category: 'vpn',
    tags: ['Tailscale', 'Tailcat', 'Mesh VPN', 'Cross-Arch', 'Multi-Distro', 'POSIX sh'],
    linesCount: 220,
    portsUsed: [
      { port: 41641, protocol: 'UDP', service: 'Tailscale WireGuard tunnel port', visibility: 'Mesh VPN' }
    ],
    securityHighlights: [
      'Full POSIX sh compatibility with conditional pipefail activation on Bash/Zsh/Ksh',
      'Automatic architecture mapping from uname -m to canonical Go and Linux package tags',
      'Smart GitHub release redirect scraper bypassing unauthenticated GitHub API rate limits',
      'Temporary directory isolation via mktemp -d with guaranteed trap EXIT/INT/TERM cleanup',
      'Dual permission mode: system-wide install to /usr/local/bin if root/sudo, or automatic user-level fallback to ~/.local/bin'
    ],
    content: `#!/bin/sh
# 兼容 POSIX sh（dash/busybox ash 等）：若被 sh 直接调用也能正常运行。
# 注意：dash 不支持 pipefail，故仅在 bash/zsh/ksh 下启用。
set -eu
case "\${BASH_VERSION:-}\${ZSH_VERSION:-}\${KSH_VERSION:-}" in
  "") : ;;
  *) set -o pipefail ;;
esac

# 1. 架构检测与映射
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    GOARCH="amd64"
    PKG_ARCH="amd64"
    ;;
  aarch64|arm64)
    GOARCH="arm64"
    PKG_ARCH="arm64"
    ;;
  armv7l)
    GOARCH="arm"
    PKG_ARCH="armv7"
    ;;
  *)
    echo "[-] 不受支持的 CPU 架构: $ARCH" >&2
    exit 1
    ;;
esac

echo "[+] 检测到系统架构: $ARCH (包资产标识: $PKG_ARCH)"

# 2. 检查权限 (非 root 自动尝试加 sudo)
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "[!] 警告: 当前为普通用户且未检测到 sudo，系统级安装可能会失败"
  fi
fi

# 3. 辅助函数：网络下载 (curl 或 wget 备选)
download_file() {
  url="$1"
  dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --progress-bar "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "$dest" "$url"
  else
    echo "[-] 缺少 curl 或 wget，无法下载安装包" >&2
    exit 1
  fi
}
`
  },
  {
    id: 'vcpc',
    name: 'Playwright CDP + Crawl4ai Automation Setup',
    filename: 'vcpc.sh',
    description: 'Lightweight setup script for headless Chrome with remote debugging, Playwright CLI with dedicated CDP endpoint configuration, Astral uv Python package manager, and custom Crawl4ai connection patch.',
    category: 'automation',
    tags: ['Playwright', 'Chrome CDP', 'Astral uv', 'Crawl4ai', 'VNC', 'Web Scraping'],
    linesCount: 74,
    portsUsed: [
      { port: 9222, protocol: 'HTTP/CDP', service: 'Chrome DevTools Protocol (0.0.0.0 / 127.0.0.1)', visibility: 'Internal' },
      { port: 6080, protocol: 'HTTP', service: 'noVNC (websockify)', visibility: 'Internal' },
      { port: 5900, protocol: 'VNC', service: 'TigerVNC', visibility: 'Internal' }
    ],
    securityHighlights: [
      'Playwright CLI integration configuring ~/.playwright/cli.config.json to attach directly to live Chrome CDP session',
      'Uses Astral uv (fast Python package manager) for instant setup of crawl4ai',
      'In-place configuration patching of crawl4ai async_configs.py to connect to custom CDP URL'
    ],
    content: `apt-get update && apt-get install -y tigervnc-standalone-server novnc websockify fluxbox x11-utils fonts-liberation
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
wget -O /tmp/google-chrome-stable_current_amd64.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
dpkg -i /tmp/google-chrome-stable_current_amd64.deb
apt-get install -y -f
rm -rf ~/cdp
mkdir -p ~/cdp

npm install -g @playwright/cli@latest
mkdir -p ~/.playwright
cat > ~/.playwright/cli.config.json <<'PWCF'
{
  "browser": {
    "cdpEndpoint": "http://127.0.0.1:9222"
  }
}
PWCF

curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
pip install crawl4ai
npx skills add brettdavies/crawl4ai-skill --skill crawl4ai --yes

f="$(python3 -c 'import crawl4ai,os;print(os.path.dirname(crawl4ai.__file__))')/async_configs.py"
sed -i \\
  -e 's/browser_mode: str = "dedicated"/browser_mode: str = "custom"/' \\
  -e 's|cdp_url: str = None|cdp_url: str = "http://127.0.0.1:9222"|' \\
  "$f"
`
  },
  {
    id: 'chktcsys',
    name: 'Tailcat System & Toolchain Probe',
    filename: 'chktcsys.sh',
    description: 'System diagnostic script that inspects CPU architecture and evaluates available system tooling (Docker, Nix, Go toolchain, dpkg/apt, rpm/dnf/yum) to recommend the optimal Tailcat installation route.',
    category: 'diagnostic',
    tags: ['Architecture Probe', 'Toolchain Check', 'Docker', 'Nix', 'Go', 'Diagnostics'],
    linesCount: 32,
    portsUsed: [],
    securityHighlights: [
      'Read-only non-destructive system environment probe',
      'Detects containerized (Docker), declarative (Nix), source-based (Go), and binary package management environments'
    ],
    content: `#!/usr/bin/env bash  
set -e  
  
ARCH=$(uname -m)  
case "$ARCH" in  
  x86_64) GOARCH=amd64 ;;  
  aarch64) GOARCH=arm64 ;;  
  armv7l) GOARCH=arm ;;  
  *) echo "未知架构: $ARCH"; exit 1 ;;  
esac  
echo "检测到架构: $ARCH -> $GOARCH"  
  
if command -v docker >/dev/null 2>&1; then  
  echo "检测到 Docker，可直接使用镜像:"  
  echo "  docker pull ghcr.io/tailscale/tailcat:latest"  
elif command -v nix >/dev/null 2>&1; then  
  echo "检测到 Nix:"  
  echo "  nix profile install nixpkgs#tailcat"  
elif command -v go >/dev/null 2>&1; then  
  echo "检测到 Go 工具链 ($(go version)):"  
  echo "  go install github.com/tailscale/tailcat/cmd/tailcat@latest"  
elif command -v dpkg >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then  
  echo "检测到 dpkg/apt，下载对应 .deb 并安装:"  
  echo "  dpkg -i tailcat_*_\${GOARCH}.deb"  
elif command -v rpm >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then  
  echo "检测到 rpm/dnf/yum，下载对应 .rpm 并安装:"  
  echo "  rpm -i tailcat_*_\${GOARCH}.rpm"  
else  
  echo "无匹配包管理器/工具链，回退到静态二进制 tar.gz:"  
  echo "  下载 tailcat_{version}_linux_\${GOARCH}.tar.gz 并解压"  
fi
`
  }
];

export const SERVICE_DEFINITIONS = [
  {
    id: 'vnc',
    name: 'TigerVNC & Fluxbox',
    command: 'vnc',
    port: 5900,
    webPort: 6080,
    healthEndpoint: 'http://127.0.0.1:6080/vnc.html',
    description: 'X11 virtual display :99 running TigerVNC and Fluxbox lightweight window manager bridged to noVNC websocket.',
    role: 'Virtual Desktop Display Layer'
  },
  {
    id: 'chr',
    name: 'Google Chrome (CDP)',
    command: 'chr',
    port: 9222,
    healthEndpoint: 'http://127.0.0.1:9222/json/version',
    description: 'Google Chrome stable running on DISPLAY=:99 with remote debugging protocol listening on 127.0.0.1:9222.',
    role: 'Browser Automation Host'
  },
  {
    id: 'buse',
    name: 'Browser-use MCP',
    command: 'buse',
    port: 8001,
    healthEndpoint: 'http://127.0.0.1:8001/sse',
    description: 'Model Context Protocol (MCP) server wrapping browser-use agent, bridged via mcp-proxy over Server-Sent Events (SSE).',
    role: 'AI Agent Browser Controller'
  },
  {
    id: 'crwl',
    name: 'Crawl-MCP (Crawl4ai)',
    command: 'crwl',
    port: 8002,
    healthEndpoint: 'http://127.0.0.1:8002/sse',
    description: 'Model Context Protocol server for high-speed LLM-friendly web scraping and extraction powered by crawl4ai.',
    role: 'AI Scraping & Markdown Extraction'
  }
];
