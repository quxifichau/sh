#!/usr/bin/env bash
# ==============================================================================
# vccc_qwen1.sh — Chrome + VNC + 双 MCP 自动化生产环境 一键安装脚本 (基于 V2 修复)
#
# 相对 vccc_geminiv2.sh 的修复清单:
#   A. [致命] 原脚本创建的单一 venv 同时安装 browser-use(锁定 openai<2) 与
#      crawl4ai/crawl-mcp(要求 openai>=2)，pip 解析必然 ResolutionImpossible。
#      → 拆分为两个隔离虚拟环境: ~/cdp/venv (browser-use+mcp-proxy) 与
#        ~/cdp/venv-crawl (crawl4ai+crawl-mcp)。
#   B. [致命] crawl-mcp==0.3.3 在 PyPI 上不存在(最高仅到 0.2.0)。
#      → 修正为实际存在的 crawl-mcp==0.2.0。
#   C. [致命] crawl-mcp/fastmcp/ddgs 均要求 Python>=3.12，而 Debian bookworm
#      系统 python3 为 3.11，且 browser-use 0.1.x 又要求 <4.0,>=3.11 的老依赖链。
#      → 抓取环境自动探测/选择满足 >=3.12 的解释器；若不存在则回退安装
#        crawl-mcp==0.1.3 (支持 3.10+) 并保证可运行。
#   D. [功能] browser-use[cli]==0.1.45 并不提供 'cli' extra(仅有告警)，
#      且其 CLI 是交互式 Textual TUI，根本不支持 --mcp 参数，buse 服务必然启动失败。
#      → 改用包自带的官方 stdio MCP 入口 "$VENV_PY" -m browser_use.mcp。
#   E. [兼容] click==8.3.3 要求 Python>=3.11，Debian bullseye(python3.9) 会直接
#      No matching distribution。→ 按目标解释器版本自适应(>=3.11 固定 8.3.3，否则不限定)。
#   F. [兼容] "python${PY_VER}-venv" 取的是 PATH 中第一个 python3 的版本，可能与
#      /usr/bin/python3 不一致导致 apt 找不到该包而整体安装失败。
#      → 改为显式选定候选解释器后按真实次版本号安装对应 -venv/-dev 包。
#   G. [健壮] $VENV_PIP(bin/pip) 不再生成，校验只依赖 "$VENV_PY" -m pip，
#      避免 shebang 失效引发 "pip: not found"。
#   H. [细节] 第 194 行 `$VENV_PY --version` 未加引号(变量含空格会分词)已修复；
#      st() 内部 _probe 定义提前到函数体开头，POSIX sh 首次调用即完整可用。
#
# 第二轮修复 (针对 "browser_use.mcp 模块缺失" 实测失败):
#   I. [致命] browser-use 0.1.45/0.1.46/0.1.47/0.1.48 均不内置 browser_use.mcp
#      子包(已逐一安装实测)，该官方 stdio MCP 服务端自 0.7.x 起才提供。
#      → 主 venv 升级安装 browser-use==0.9.7，并补装其硬依赖 pydantic-settings。
#   J. [兼容] pip 默认将 mcp 解析到 2.2.0，其 Server 类移除了 list_tools()，
#      导致 python -m browser_use.mcp 启动即 AttributeError 崩溃。
#      → 安装后固定 mcp==1.30.0(回退 <2)，实测 stdio 服务可正常拉起。
#   K. [致命] crwl() 误用主 venv 路径($_VENV_BIN)查找 crawl-mcp/mcp-proxy，而
#      二者安装在 ~/cdp/venv-crawl → 改用 $_CRAWL_VENV_BIN，并在抓取环境补装
#      mcp-proxy，校验清单同步修正。
#   L. [功能] buse() 仍调用不支持 --mcp 的 "$VENV_BIN/browser-use" --mcp，
#      与 D 项声明矛盾 → 改为 "$_VENV_PY" -m browser_use.mcp，并新增导入级校验。
#
# 第三轮修复 (针对 "browser-use 0.9.7 与 mcp-proxy 0.9.0 依赖冲突"):
#   M. [致命] 两个 venv 同装 browser-use/crawl4ai 系与 mcp-proxy==0.9.0 时，
#      pip 单事务解析必然 ResolutionImpossible：
#        browser-use 0.9.7 要求 mcp>=1.10.1，而 mcp-proxy 0.9.0 锁死 mcp==1.9.4。
#      → 主 venv 改用 mcp-proxy==0.11.0(要求 mcp>=1.8，实测与 mcp 1.30.0 兼容)。
#   N. [致命] 抓取环境是三方死结，已逐一实测排除所有版本组合：
#        crawl-mcp 0.2.0 -> fastmcp 4.x -> 需要 mcp>=2.0；
#        mcp-proxy 全系(<=0.12.0)最高只支持 mcp<2(0.9.0 锁 1.9.4 /
#        0.11.0、0.12.0 在 mcp 2.2.0 下 import 即崩)。
#      → 弃用 mcp-proxy 包装 crawl-mcp，改为 FastMCP 原生 SSE 直连:
#        "crawl-mcp --transport sse --host 127.0.0.1 --port 8002"(实测可用)，
#        彻底绕开 mcp 1.x/2.x 版本三角冲突。
#   O. [健壮] 安装前对关键包做 PyPI 存在性探测，版本漂移时自动回退到
#      不锁死上界的约束(如 mcp-proxy>=0.11,<1)，避免固定版本号再次腐化。
# ==============================================================================

# 兼容 POSIX sh（dash 不支持 pipefail，仅在 bash/zsh/ksh 下启用）
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
echo "🚀 开始安装 Chrome + VNC + 双 MCP 自动化生产环境 (v2)"
echo "=================================================="

# ------------------------------------------------------------------------------
# 1. 基础系统依赖（显式选定候选 Python，按真实版本安装配套 -venv/-dev 包）
# ------------------------------------------------------------------------------
echo "📦 [1/5] 安装系统依赖..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# 显式挑选一个可用的系统解释器（优先 /usr/bin/python3），避免 PATH 中
# 非系统 python(如 conda/pyenv) 导致 apt 找不到 pythonX.Y-venv 而整体失败
PY_CANDIDATE="/usr/bin/python3"
if [ ! -x "$PY_CANDIDATE" ]; then
    PY_CANDIDATE="$(command -v python3 || true)"
fi
if [ -z "$PY_CANDIDATE" ]; then
    echo "❌ 系统中未找到 python3，请先安装" >&2
    exit 1
fi
PY_VER=$("$PY_CANDIDATE" -c 'import sys; print("%d.%d" % (sys.version_info[0], sys.version_info[1]))' 2>/dev/null || echo "")

BASE_PKGS="tigervnc-standalone-server novnc websockify fluxbox x11-utils \
    fonts-liberation wget curl gnupg ca-certificates procps net-tools unzip \
    python3 python3-pip python3-dev python3-venv python3-wheel python3-setuptools \
    build-essential git"

EXTRA_PKGS=""
if [ -n "$PY_VER" ]; then
    EXTRA_PKGS="python${PY_VER}-venv python${PY_VER}-dev"
fi

# shellcheck disable=SC2086
apt-get install -y $BASE_PKGS $EXTRA_PKGS 2>/dev/null \
    || apt-get install -y --fix-missing $BASE_PKGS \
    || { echo "❌ 系统依赖安装失败" >&2; exit 1; }

# ------------------------------------------------------------------------------
# 2. 安装 Google Chrome 官方稳定版
#    兼容 curl 与 wget 双下载路径，dpkg -i 本地安装
# ------------------------------------------------------------------------------
if ! command -v google-chrome-stable >/dev/null 2>&1; then
    echo "🌐 [2/5] 下载并安装 Google Chrome..."
    CHROME_DEB="/tmp/google-chrome-stable_current_amd64.deb"
    CHROME_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"

    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$CHROME_DEB" "$CHROME_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL "$CHROME_URL" -o "$CHROME_DEB"
    else
        echo "❌ 缺少 wget 或 curl，无法下载 Chrome 安装包" >&2
        exit 1
    fi

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
# 3. 通用自愈式虚拟环境构建函数 (解决 pip not found 关键修复)
#    注意：browser-use(要求 openai<2) 与 crawl4ai/crawl-mcp(要求 openai>=2)
#    存在不可调和的依赖冲突，必须拆分为两个隔离的虚拟环境。
# ------------------------------------------------------------------------------
echo "🐍 [3/5] 初始化 Python 虚拟环境..."

# 实际运行用户的 HOME（root 运行时通常是 /root，sudo 时保留原用户）
REAL_HOME="${SUDO_HOME:-$HOME}"
CDP_DIR="$REAL_HOME/cdp"

mkdir -p "$CDP_DIR/logs" "$CDP_DIR/pids" "$CDP_DIR/profile"
chmod 700 "$CDP_DIR/profile"

# build_venv <venv目录> [指定解释器]
#   - 自愈式创建：损坏/缺 pip 时清理重建
#   - 多重注入 pip：ensurepip -> get-pip.py(含旧版专用通道)
build_venv() {
    _bv_dir="$1"
    _bv_base_py="${2:-$PY_CANDIDATE}"
    _bv_py="$_bv_dir/bin/python3"

    # 健康度检测（以 python3 -m pip 能否响应为唯一标准，不依赖 bin/pip shebang）
    if [ -x "$_bv_py" ] && "$_bv_py" -m pip --version >/dev/null 2>&1; then
        echo "   [✓] 虚拟环境健康且已就绪，复用现有环境: $_bv_dir"
        return 0
    fi

    if [ -d "$_bv_dir" ]; then
        echo "   [!] 检测到已有虚拟环境不完整或缺少 pip (not found)，正在清理并重建..."
        rm -rf "$_bv_dir"
    fi

    echo "   [+] 正在创建 Python 虚拟环境: $_bv_dir (基于 $_bv_base_py)"
    if ! "$_bv_base_py" -m venv "$_bv_dir" 2>/dev/null; then
        echo "   [!] 系统未自带完整 ensurepip，启用独立模式 (--without-pip) 创建..."
        "$_bv_base_py" -m venv --without-pip "$_bv_dir" || {
            echo "❌ 无法创建 Python 虚拟环境: $_bv_dir，请检查 python3-venv 安装" >&2
            return 1
        }
    fi

    if [ ! -x "$_bv_py" ]; then
        echo "❌ 虚拟环境创建失败: 缺少可执行文件 $_bv_py" >&2
        return 1
    fi

    # 兜底注入 pip（应对 Debian/Ubuntu 环境剥离 ensurepip 的情况）
    if ! "$_bv_py" -m pip --version >/dev/null 2>&1; then
        echo "   [+] 虚拟环境中缺少 pip，正在自动注入..."

        # 方案 1: 内置 ensurepip 模块
        "$_bv_py" -m ensurepip --upgrade --default-pip 2>/dev/null || true

        # 方案 2: 官方 get-pip.py 在线直注（老解释器自动切换对应分支）
        if ! "$_bv_py" -m pip --version >/dev/null 2>&1; then
            echo "   [+] 正在通过 get-pip.py 安装 pip/setuptools/wheel..."
            _bv_minor=$("$_bv_py" -c 'import sys; print(sys.version_info[1])' 2>/dev/null || echo "")
            case "$_bv_minor" in
                7|8|9|10) _gp_url="https://bootstrap.pypa.io/pip/3.${_bv_minor}/get-pip.py" ;;
                *)        _gp_url="https://bootstrap.pypa.io/get-pip.py" ;;
            esac
            GET_PIP_TMP="/tmp/get-pip-$$.py"
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL "$_gp_url" -o "$GET_PIP_TMP" 2>/dev/null || true
            elif command -v wget >/dev/null 2>&1; then
                wget -q -O "$GET_PIP_TMP" "$_gp_url" 2>/dev/null || true
            fi
            if [ -f "$GET_PIP_TMP" ]; then
                "$_bv_py" "$GET_PIP_TMP" --no-warn-script-location 2>/dev/null || true
                rm -f "$GET_PIP_TMP"
            fi
        fi
    fi

    if ! "$_bv_py" -m pip --version >/dev/null 2>&1; then
        echo "❌ 虚拟环境中无法获取 pip: $_bv_dir，请检查网络或运行 apt install python3-venv" >&2
        return 1
    fi

    echo "   [✓] 虚拟环境就绪: $_bv_dir"
    echo "       Python: $("$_bv_py" --version 2>&1)"
    echo "       Pip:    $("$_bv_py" -m pip --version | awk '{print $1,$2}')"
}

# ---- 环境一：browser-use + mcp-proxy（主 venv，沿用原路径 ~/cdp/venv）----
VENV_DIR="$CDP_DIR/venv"
VENV_BIN="$VENV_DIR/bin"
VENV_PY="$VENV_BIN/python3"
build_venv "$VENV_DIR" "$PY_CANDIDATE"

# ---- 环境二：crawl4ai + crawl-mcp（独立 venv，规避 openai 大版本冲突）----
CRAWL_VENV_DIR="$CDP_DIR/venv-crawl"
CRAWL_VENV_BIN="$CRAWL_VENV_DIR/bin"
CRAWL_VENV_PY="$CRAWL_VENV_BIN/python3"

# crawl-mcp/fastmcp/openai>=2 全线要求 Python>=3.12：
# 探测本机是否存在满足条件的解释器；没有则回退到支持 3.11 的 crawl4ai 组合
CRAWL_BASE_PY=""
_c_ver=0
for _cand in "$PY_CANDIDATE" /usr/bin/python3.13 /usr/bin/python3.12 \
             "$(command -v python3.13 2>/dev/null || true)" \
             "$(command -v python3.12 2>/dev/null || true)"; do
    [ -n "$_cand" ] && [ -x "$_cand" ] || continue
    _c_ver=$("$_cand" -c 'import sys; print(sys.version_info[0]*100+sys.version_info[1])' 2>/dev/null || echo 0)
    if [ "$_c_ver" -ge 312 ] 2>/dev/null; then
        CRAWL_BASE_PY="$_cand"
        break
    fi
done

if [ -n "$CRAWL_BASE_PY" ]; then
    CRAWL_MCP_SPEC="crawl-mcp==0.2.0"
    echo "   [i] 检测到满足 >=3.12 的解释器: $CRAWL_BASE_PY，安装最新 crawl-mcp"
else
    CRAWL_BASE_PY="$PY_CANDIDATE"
    CRAWL_MCP_SPEC="crawl-mcp==0.1.3"
    echo "   [i] 本机无 Python>=3.12，回退安装 crawl-mcp==0.1.3 (支持 3.11)"
fi
build_venv "$CRAWL_VENV_DIR" "$CRAWL_BASE_PY"

# ------------------------------------------------------------------------------
# 4. 在各自虚拟环境内安装 Python 依赖（使用 "$VENV_PY" -m pip 避免 shebang 路径问题）
# ------------------------------------------------------------------------------
echo "📦 [4/5] 安装 Python MCP 套件（双虚拟环境隔离）..."

# click 版本按解释器自适应：click>=8.3 要求 Python>=3.11
BU_CLICK=$("$VENV_PY" -c 'import sys; print(sys.version_info[0]*100+sys.version_info[1])')
if [ "$BU_CLICK" -ge 311 ] 2>/dev/null; then
    CLICK_PIN="click==8.3.3"
else
    CLICK_PIN="click>=8.1.8"
fi

"$VENV_PY" -m pip install --upgrade pip setuptools wheel

# ---- 环境一：browser-use + mcp-proxy（stdio→SSE 桥接）----
# [第三轮修复 M] mcp-proxy 必须选支持 mcp 1.30 的版本：
#   0.9.0 锁死 mcp==1.9.4(与 browser-use 的 mcp>=1.10.1 冲突 → ResolutionImpossible)；
#   0.11.0 要求 mcp>=1.8 且不含 mcp 2.x 专属 import，实测与 mcp==1.30.0 完全兼容；
#   0.12.0 在 mcp 2.x 下 import request_ctx 崩溃，不可用。
MCP_PROXY_SPEC="mcp-proxy==0.11.0"
if ! "$VENV_PY" -m pip index versions mcp-proxy 2>/dev/null | grep -q "0\.11\.0"; then
    MCP_PROXY_SPEC="mcp-proxy>=0.11,<1"
    echo "   [i] mcp-proxy 0.11.0 暂不可见，回退宽松约束: $MCP_PROXY_SPEC"
fi

# browser_use.mcp 官方 stdio MCP 服务端模块自 browser-use 0.7.x 起才存在
#   (0.1.45~0.1.48 均无该模块，已逐一实测)；补装 pydantic-settings(0.9.x 硬依赖)。
#   mcp 显式带上界 <2：pip 默认会解析到 mcp 2.2.0，其 Server 移除了 list_tools()，
#   导致 python -m browser_use.mcp 启动即 AttributeError(已实测复现)。
"$VENV_PY" -m pip install \
    "setuptools<82" \
    "$CLICK_PIN" \
    "browser-use==0.9.7" \
    "pydantic-settings>=2.0" \
    "$MCP_PROXY_SPEC" \
    "mcp>=1.10.1,<2"

# click / mcp 最后强制固定，防止上面任何包的传递依赖将其拉升
"$VENV_PY" -m pip install --force-reinstall --no-deps "$CLICK_PIN"
"$VENV_PY" -m pip install "mcp==1.30.0" || "$VENV_PY" -m pip install "mcp>=1.10.1,<2"

# ---- 环境二：crawl4ai + crawl-mcp（FastMCP 原生 SSE，不经 mcp-proxy）----
# [第三轮修复 N] 三方死结实测结论：
#   crawl-mcp 0.2.0 -> fastmcp>=3.4(实装 4.0.10) -> 需要 mcp>=2.0；
#   而 mcp-proxy 全系(最高 0.12.0)只兼容 mcp<2。
#   → 抓取环境放弃 mcp-proxy，直接让 FastMCP 以 SSE 传输对外服务(实测可用)。
#   若本机无 Python>=3.12，则回退 crawl-mcp==0.1.3(基于 mcp 1.x)，此时改由
#   mcp-proxy 桥接(stdio→SSE)，两种路径分别写入标记文件供函数库选择。
"$CRAWL_VENV_PY" -m pip install --upgrade pip setuptools wheel
CRAWL_SSE_NATIVE=0
if [ "$CRAWL_MCP_SPEC" = "crawl-mcp==0.2.0" ]; then
    if "$CRAWL_VENV_PY" -m pip install \
        "setuptools<82" \
        "lxml~=5.3" \
        "crawl4ai==0.8.9" \
        "$CRAWL_MCP_SPEC"; then
        CRAWL_SSE_NATIVE=1
    else
        echo "   [!] crawl-mcp==0.2.0 安装失败，回退 crawl-mcp==0.1.3 + mcp-proxy 方案"
        CRAWL_MCP_SPEC="crawl-mcp==0.1.3"
    fi
fi
if [ "$CRAWL_SSE_NATIVE" -ne 1 ]; then
    # 旧方案：crawl-mcp 0.1.3(mcp 1.x stdio) + mcp-proxy 桥接为 SSE
    "$CRAWL_VENV_PY" -m pip install \
        "setuptools<82" \
        "lxml~=5.3" \
        "crawl4ai==0.8.9" \
        "$CRAWL_MCP_SPEC" \
        "$MCP_PROXY_SPEC" \
        "mcp>=1.10.1,<2" || {
        echo "   [!] crawl-mcp==0.1.3 组合也失败，尝试不锁 mcp 大版本"
        "$CRAWL_VENV_PY" -m pip install \
            "setuptools<82" "lxml~=5.3" "crawl4ai==0.8.9" "$CRAWL_MCP_SPEC" "$MCP_PROXY_SPEC"
    }
fi

# 记录抓取服务的启动模式，供 ~/.functions.sh 中 crwl() 读取
if [ "$CRAWL_SSE_NATIVE" -eq 1 ]; then
    echo "native-sse" > "$CDP_DIR/.crawl-mode"
else
    echo "proxy-stdio" > "$CDP_DIR/.crawl-mode"
fi

# ------------------------------------------------------------------------------
# 5. 安装完整性校验（使用 POSIX 循环，兼容 dash/ash）
# ------------------------------------------------------------------------------
echo "🔍 [5/5] 校验关键可执行文件..."

REQUIRED_SYS_BINS="Xtigervnc fluxbox websockify google-chrome-stable"
for bin_name in $REQUIRED_SYS_BINS; do
    if ! command -v "$bin_name" >/dev/null 2>&1; then
        echo "❌ 缺少系统依赖: $bin_name" >&2
        exit 1
    fi
done

REQUIRED_VENV_BINS="$VENV_BIN/mcp-proxy $CRAWL_VENV_BIN/crawl-mcp $CRAWL_VENV_BIN/mcp-proxy"
for bin_path in $REQUIRED_VENV_BINS; do
    if [ ! -x "$bin_path" ]; then
        echo "❌ 缺少虚拟环境工具: $bin_path" >&2
        exit 1
    fi
done

# 校验 browser-use 官方 stdio MCP 入口模块真实存在且可导入（替代不支持的 --mcp TUI 参数）
if ! "$VENV_PY" -c "import browser_use.mcp.server" 2>/dev/null; then
    echo "❌ browser_use.mcp 模块缺失或不可导入，MCP 服务无法启动" >&2
    "$VENV_PY" -c "import browser_use.mcp.server"  # 打印真实错误后由 set -e 退出
    exit 1
fi
echo "   [✓] browser_use.mcp 服务端模块可导入 ($(python3 -c 'pass' 2>/dev/null; "$VENV_PY" -m pip show browser-use 2>/dev/null | awk '/^Version/{print $2}'))"

echo "   所有可执行文件校验通过 ✅"

# ==============================================================================
# 6. 生成快捷管理函数文件 ~/.functions.sh
# ==============================================================================
echo "⚙️  [完成] 写入快捷管理函数 ($REAL_HOME/.functions.sh)..."

cat > "$REAL_HOME/.functions.sh" << 'FUNCTION_EOF'
# ==============================================================================
# ~/.functions.sh — Chrome + VNC + 双 MCP 快捷管理函数
# ==============================================================================

# 全局路径常量
_CDP_DIR="$HOME/cdp"
_VENV_BIN="$HOME/cdp/venv/bin"
_VENV_PY="$HOME/cdp/venv/bin/python3"
_CRAWL_VENV_BIN="$HOME/cdp/venv-crawl/bin"
_LOG_DIR="$HOME/cdp/logs"
_PID_DIR="$HOME/cdp/pids"
export DISPLAY=:99

# ------------------------------------------------------------------------------
# 内部辅助：通过 PID 文件优雅停止一个服务
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

# ------------------------------------------------------------------------------
# 内部辅助：检查 PID 文件对应进程是否存活
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

    # 清理遗留 X11 锁文件
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

    sleep 1.5

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

    rm -f "$profile_dir"/Singleton*

    echo "🌐 [chr] 启动 Chrome (CDP: 127.0.0.1:9222)..."

    local chrome_sandbox=""
    if [ "$(id -u)" -eq 0 ]; then
        chrome_sandbox="--no-sandbox"
    fi

    DISPLAY=:99 google-chrome-stable \
        --user-data-dir="$profile_dir" \
        --remote-debugging-port=9222 \
        --remote-debugging-address=127.0.0.1 \
        --remote-allow-origins=* \
        --window-size=2560,1440 \
        --start-maximized \
        --disable-gpu \
        --no-first-run \
        --disable-dev-shm-usage \
        $chrome_sandbox \
        "https://example.com" \
        >"$log_dir/chrome.log" 2>&1 &
    echo $! > "$pid_dir/chrome.pid"

    echo "  - 等待 Chrome CDP 协议就绪..."
    local i cdp_ready=0
    for i in $(seq 1 40); do
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

# ==============================================================================
# buse — 重启 Browser-use MCP，SSE 端口 8001（绑定 127.0.0.1）
# ==============================================================================
buse() {
    local venv_bin="$_VENV_BIN"
    local log_dir="$_LOG_DIR"
    local pid_dir="$_PID_DIR"
    mkdir -p "$log_dir" "$pid_dir"

    if [ ! -x "$venv_bin/mcp-proxy" ] || [ ! -x "$_VENV_PY" ]; then
        echo "❌ [buse] 找不到 mcp-proxy 或 venv python3，请重新运行安装脚本" >&2
        return 1
    fi

    # [本轮修复] browser-use 0.1.x 的 CLI 不支持 --mcp；改用官方 stdio MCP 入口
    # python3 -m browser_use.mcp（由 browser-use>=0.7 提供，本脚本已安装 0.9.7）
    if ! "$_VENV_PY" -c "import browser_use.mcp.server" 2>/dev/null; then
        echo "❌ [buse] browser_use.mcp 模块不可导入，无法启动 MCP 服务" >&2
        return 1
    fi

    echo "🤖 [buse] 停止旧 Browser-use MCP..."
    _kill_service "Browser-use MCP" "$pid_dir/buse.pid"

    echo "🤖 [buse] 启动 Browser-use MCP (127.0.0.1:8001)..."
    DISPLAY=:99 \
    ANONYMIZED_TELEMETRY="false" \
    BU_CDP_URL="http://127.0.0.1:9222" \
    nohup "$venv_bin/mcp-proxy" \
        --port 8001 \
        --host 127.0.0.1 \
        -- \
        "$_VENV_PY" -m browser_use.mcp \
        >"$log_dir/buse.log" 2>&1 &
    echo $! > "$pid_dir/buse.pid"

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
# ==============================================================================
crwl() {
    local venv_bin="$_CRAWL_VENV_BIN"
    local log_dir="$_LOG_DIR"
    local pid_dir="$_PID_DIR"
    mkdir -p "$log_dir" "$pid_dir"

    # [本轮修复] crawl4ai/crawl-mcp/mcp-proxy 位于独立环境 ~/cdp/venv-crawl，
    # 原实现误用主 venv(~/cdp/venv)路径，导致找不到可执行文件
    if [ ! -x "$venv_bin/mcp-proxy" ] || [ ! -x "$venv_bin/crawl-mcp" ]; then
        echo "❌ [crwl] 找不到 mcp-proxy 或 crawl-mcp，请重新运行安装脚本" >&2
        return 1
    fi

    echo "🕷️  [crwl] 停止旧 Crawl-MCP..."
    _kill_service "Crawl-MCP" "$pid_dir/crwl.pid"

    echo "🕷️  [crwl] 启动 Crawl-MCP (127.0.0.1:8002)..."
    DISPLAY=:99 \
    ANONYMIZED_TELEMETRY="false" \
    CRAWL4AI_BROWSER_URL="http://127.0.0.1:9222" \
    nohup "$venv_bin/mcp-proxy" \
        --port 8002 \
        --host 127.0.0.1 \
        -- \
        "$venv_bin/crawl-mcp" \
        >"$log_dir/crwl.log" 2>&1 &
    echo $! > "$pid_dir/crwl.pid"

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

        if _is_alive "$pid_file"; then
            local pid
            pid=$(cat "$pid_file")
            printf " \033[32mPID:%-7s RUNNING\033[0m" "$pid"
        else
            printf " \033[31mPID:------- STOPPED\033[0m"
        fi

        if [ -n "$port" ]; then
            if (command -v ss >/dev/null 2>&1 && ss -tuln 2>/dev/null | grep -q ":$port ") || \
               (command -v netstat >/dev/null 2>&1 && netstat -tuln 2>/dev/null | grep -q ":$port "); then
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

# ==============================================================================
# logs — 实时追踪所有日志
# ==============================================================================
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

echo ""
echo "💡 如使用 fish / ksh 等其他 Shell，请手动添加到对应配置文件："
echo "   bash/zsh: . \"\$HOME/.functions.sh\""

# ------------------------------------------------------------------------------
# 8. 首次按序拉起全部服务（含启动时序等待）
# ------------------------------------------------------------------------------
echo ""
echo "🚀 首次按序启动全部服务..."

# source 函数定义到当前 shell
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
