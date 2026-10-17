#!/usr/bin/env bash
# ==============================================================================
# vccc_bf1.sh — Chrome + VNC + 双 MCP 自动化生产环境 一键安装脚本
#
# 两种安装方式（推荐 source 方式）：
#   root 下 `. vccc.sh`（或 `source vccc.sh`）— 装完当前终端立即可用
#       chr/buse/st 等快捷命令（脚本内部会 source ~/.functions.sh）
#   `sudo bash vccc.sh` — 子进程无法把函数传回当前终端，装完需手动执行
#       一次 `. ~/.functions.sh`；新开的终端自动加载
#
# 基于 vccc_gemini.sh 的修复版本（原文件不改动，修复内容另存为本文件）：
#   1. 【Bug 修复】crawl-mcp==0.3.3 在 PyPI 上不存在（最高仅 0.2.0），
#      pip 直接 404 —— 改为锁定真实存在的 crawl-mcp==0.2.0
#   2. 【Bug 修复】crawl-mcp 要求 Python>=3.12，Ubuntu 22.04 系统 Python 仅 3.10，
#      导致依赖解析失败 —— 改用 uv 安装托管 Python 3.12 并重建 venv
#   3. 【Bug 修复】browser-use==0.1.45 根本没有 MCP 功能，`browser-use --mcp`
#      必然失败 —— 改为 0.13.10（提供 stdio MCP 服务）
#   3b.【Bug 修复】0.13.10 的 MCP 服务并不读取 BU_CDP_URL 环境变量（经源码核验：
#      该变量只存在于 CLI 3.0 帮助文案与云 daemon 传递路径；MCP 的 env 覆盖仅支持
#      HEADLESS / ALLOWED_DOMAINS / PROXY_*）。接管既有 Chrome 的唯一入口是
#      config.json 默认 browser_profile 条目里的 cdp_url 字段（BrowserProfile.cdp_url，
#      cdp_url 为空时 session.py 会置 is_local=True 自行拉起 Chrome）——
#      buse() 已改为写入 BROWSER_USE_CONFIG_DIR 指向的 config.json
#   4. 【Bug 修复】mcp-proxy 0.9.0 与 browser-use 钉死的 mcp==2.1.1 不兼容，
#      启动即崩溃 —— 改用 fastmcp==4.0.10 把 stdio MCP 代理成 SSE
#   5. 保留原脚本全部兼容性修复（POSIX sh/dash、curl 23 EPIPE、幂等注入等）
#   6. 【性能修复】crawl4ai 的浏览器渲染回退因 Playwright Chromium 缺失而必崩
#      （BrowserType.launch: Executable doesn't exist at ~/.cache/ms-playwright/...），
#      导致 crawl_batch 不可用、crawl_single 只能走快速抽取 —— 新增第 4b 步
#      `playwright install --with-deps chromium`，并在第 5 步校验可执行文件真实存在
#   7. 【性能优化】新增 crawl-helper 本地批量抓取 MCP 服务（第 4c 步写入
#      ~/cdp/crawl_helper.py，第 6 步随 crwl() 一并代理到 8002 端口）：
#      提供 crawl_urls_to_file(urls, out_path, concurrent) 工具，抓取循环全部在
#      远端本机并发完成、合并 markdown 落盘并随响应返回 —— 外部 Agent 一次调用
#      即可完成整批抓取，不再让几十个 HTML 大 payload 穿隧道
#      （约定：browser-use 侧不配 LLM key，正文提取只用 get_html(selector=...)）
# ==============================================================================

# 兼容 POSIX sh（dash 不支持 pipefail，仅在 bash/zsh/ksh 下启用）
set -eu
case "${BASH_VERSION:-}${ZSH_VERSION:-}${KSH_VERSION:-}" in
  "") : ;;
  *) set -o pipefail 2>/dev/null || true ;;
esac

# ------------------------------------------------------------------------------
# 0a. 检测本脚本是被 source/. 加载还是被执行
#     - source 方式（root 下 `. vccc.sh`）：第 8 步的 `. ~/.functions.sh` 会把
#       chr/buse/st 等快捷函数直接留在当前终端，装完立即可用
#     - 执行方式（`bash vccc.sh`）：子进程无法把函数传回父 shell，装完需在
#       当前终端手动执行一次 `. ~/.functions.sh`（新终端自动加载）
# ------------------------------------------------------------------------------
_CCC_SOURCED=0
if [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
    _CCC_SOURCED=1
fi

# source 方式下非 root 禁止继续：脚本中途失败时的 exit 会直接关掉用户终端
if [ "$_CCC_SOURCED" -eq 1 ] && [ "$(id -u)" -ne 0 ]; then
    echo "❌ 以 source 方式安装必须是 root（否则脚本出错时的 exit 会关闭你的终端）" >&2
    echo "   请改用: sudo bash $0" >&2
    return 1
fi

# ------------------------------------------------------------------------------
# 0. 前置检查：必须以 root 运行（apt-get / dpkg 需要）
# ------------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 此脚本需要 root 权限运行，请使用: sudo bash $0" >&2
    exit 1
fi

echo "=================================================="
echo "🚀 开始安装 Chrome + VNC + 双 MCP 自动化生产环境"
echo "=================================================="

# ------------------------------------------------------------------------------
# 1. 基础系统依赖（使用系统包管理器，不污染系统 pip）
# ------------------------------------------------------------------------------
echo "📦 [1/6] 安装系统依赖..."
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
#    兼容 curl 与 wget 双下载路径，dpkg -i 本地安装
# ------------------------------------------------------------------------------
if ! command -v google-chrome-stable >/dev/null 2>&1; then
    echo "🌐 [2/6] 下载并安装 Google Chrome..."
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
    echo "✅ [2/6] Google Chrome 已安装，跳过"
fi

# 安装完成后校验
if ! command -v google-chrome-stable >/dev/null 2>&1; then
    echo "❌ Google Chrome 安装失败，请检查网络或系统架构" >&2
    exit 1
fi
echo "   Chrome 版本: $(google-chrome-stable --version)"

# ------------------------------------------------------------------------------
# 3. 准备运行目录与 Python 虚拟环境
#    修复：crawl-mcp 0.2.0 要求 Python>=3.12，而 Ubuntu 22.04 系统 Python 为
#    3.10，直接用系统 python3 建 venv 会在依赖解析阶段失败。
#    改用 uv 安装托管的 Python 3.12；venv 已存在但版本过低时自动重建。
# ------------------------------------------------------------------------------
echo "🐍 [3/6] 初始化 Python 3.12 虚拟环境..."

# 实际运行用户的 HOME（root 运行时通常是 /root，sudo 时需要保留原用户）
REAL_HOME="${SUDO_HOME:-$HOME}"
CDP_DIR="$REAL_HOME/cdp"

mkdir -p "$CDP_DIR/logs" "$CDP_DIR/pids" "$CDP_DIR/profile"
chmod 700 "$CDP_DIR/profile"

# 安装 uv（若缺失），用于获取 Python 3.12 与加速 pip 安装
if ! command -v uv >/dev/null 2>&1; then
    echo "   未检测到 uv，正在安装..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi
if ! command -v uv >/dev/null 2>&1; then
    echo "❌ uv 安装失败，无法继续" >&2
    exit 1
fi

uv python install 3.12

VENV_DIR="$CDP_DIR/venv"
VENV_PY="$VENV_DIR/bin/python"

# venv 必须使用 Python>=3.12；已存在但版本过低时自动重建
if [ -x "$VENV_PY" ] && \
   "$VENV_PY" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] >= (3, 12) else 1)'; then
    echo "   虚拟环境已存在且 Python 版本满足要求，跳过创建"
else
    rm -rf "$VENV_DIR"
    uv venv --python 3.12 "$VENV_DIR"
    echo "   虚拟环境已创建 (Python 3.12): $VENV_DIR"
fi

# 统一通过 uv 操作 venv 内的 pip（带全局缓存，比 venv 内 pip 更快）
run_pip() {
    uv pip install --python "$VENV_PY" "$@"
}
VENV_BIN="$VENV_DIR/bin"

# ------------------------------------------------------------------------------
# 4. 在虚拟环境内安装所有 Python 依赖（版本全部锁定）
#
#    版本说明（全部经 PyPI 实际核验）：
#      setuptools<82     — setuptools>=82 与 crawl4ai 0.8.9 的 setup.py 不兼容
#      lxml~=5.3         — >=5.3,<6；crawl4ai 0.8.9 的最低兼容版本
#      click==8.3.3      — browser-use 与 crawl-mcp 均依赖 click，锁定公共兼容版本
#      browser-use==0.13.10 — 提供 `browser-use --mcp`（stdio MCP 服务）。注意：
#                          MCP 路径不读 BU_CDP_URL，接管既有 Chrome 需通过
#                          config.json 写入 cdp_url（见第 6 步 buse() 实现）。
#                          原固定值 0.1.45 没有 MCP 功能，必然失败。
#      crawl4ai==0.8.9   — 已验证版本
#      crawl-mcp==0.2.0  — PyPI 上真实存在的最高版本；原固定值 0.3.3 不存在
#                          （pip 直接报 "No matching distribution found"）。
#                          要求 Python>=3.12，见第 3 步。
#      fastmcp==4.0.10   — 用 `fastmcp run <mcp.json> --transport sse` 把 stdio
#                          的 MCP 服务代理成 SSE。原方案 mcp-proxy（0.9.0/0.12.0）
#                          与 browser-use 钉死的 mcp==2.1.1 不兼容，启动即崩溃。
# ------------------------------------------------------------------------------
echo "📦 [4/6] 安装 Python MCP 套件（虚拟环境隔离）..."

run_pip --upgrade pip setuptools wheel

# 先固定基础约束，防止后续包升级覆盖
run_pip \
    "setuptools<82" \
    "lxml~=5.3" \
    "click==8.3.3"

# 安装核心包（crawl-mcp 锁定为 PyPI 真实存在的最高版本 0.2.0）
run_pip \
    "browser-use[cli]==0.13.10" \
    "crawl4ai==0.8.9" \
    "crawl-mcp==0.2.0" \
    "fastmcp==4.0.10"

# click 最后强制固定，防止上面任何包将其升级
run_pip --force-reinstall "click==8.3.3"

# ------------------------------------------------------------------------------
# 4b. 安装 Playwright Chromium（修复 crawl4ai 浏览器渲染回退）
#     crawl4ai 的快速抽取（fast-extract）失败时会回退到 Playwright 渲染，
#     但 Playwright 自带的 Chromium 需要单独下载，缺失时报：
#       BrowserType.launch: Executable doesn't exist at
#       /root/.cache/ms-playwright/chromium-*/chrome-linux*/chrome
#     导致 crawl_batch 整体崩溃、crawl_single 只能依赖快速抽取。
#     --with-deps 会用 apt 补齐系统库；失败时降级为纯浏览器下载
#     （Chrome 官方包已把绝大多数依赖装齐）。
# ------------------------------------------------------------------------------
echo "🎭 [4b/6] 安装 Playwright Chromium（crawl4ai 渲染回退依赖）..."
if ! "$VENV_PY" -m playwright install --with-deps chromium; then
    echo "   --with-deps 安装失败，降级为仅下载浏览器..."
    "$VENV_PY" -m playwright install chromium
fi

# ------------------------------------------------------------------------------
# 4c. 写入 crawl-helper 本地批量抓取 MCP 服务
#     目的：把「几十个 URL 逐个抓取」的循环从外部 Agent 侧搬到远端本机，
#     外部只需一次 MCP 调用（crawl_urls_to_file），大 HTML 不再穿隧道。
#     随 crwl() 与 crawl-mcp 一起被 fastmcp 代理到 127.0.0.1:8002/sse。
# ------------------------------------------------------------------------------
echo "🧰 [4c/6] 写入 crawl-helper 批量抓取服务 ($CDP_DIR/crawl_helper.py)..."
cat > "$CDP_DIR/crawl_helper.py" << 'CRAWL_HELPER_EOF'
#!/usr/bin/env python3
# ==============================================================================
# crawl_helper.py — 远端本机批量抓取 MCP 服务（补充 crawl-mcp，由 vcbc.sh 写入）
#
# 工具:
#   crawl_urls_to_file(urls, out_path, concurrent=5, header_title, return_content)
#     在远端本机并发抓取全部 URL 正文（crawl4ai，含浏览器渲染回退），
#     合并为一个 markdown 文件写入 out_path，并返回 JSON 摘要；
#     return_content=True 时摘要附带全文（一次调用拿到最终产物）。
# ==============================================================================
import asyncio
import json
import os
from typing import List

from fastmcp import FastMCP
from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig, CacheMode

mcp = FastMCP("crawl-helper")


def _md_of(result) -> str:
    """兼容 crawl4ai 各版本的 markdown 取值。"""
    md = getattr(result, "markdown", None)
    for attr in ("fit_markdown", "raw_markdown"):
        val = getattr(md, attr, None)
        if val:
            md = val
            break
    if isinstance(md, list):
        md = "\n".join(str(x) for x in md)
    return (md or "").strip() if isinstance(md, str) else ""


def _title_of(result) -> str:
    meta = getattr(result, "metadata", None) or {}
    if isinstance(meta, dict):
        return str(meta.get("title") or meta.get("og:title") or "")
    return ""


@mcp.tool()
async def crawl_urls_to_file(
    urls: List[str],
    out_path: str,
    concurrent: int = 5,
    header_title: str = "抓取结果",
    return_content: bool = True,
) -> str:
    """批量抓取 URL 列表的网页正文，合并为 markdown 文件（远端本机完成）。

    Args:
        urls: 待抓取的 URL 列表（保持顺序编号）。
        out_path: 合并后 markdown 的输出路径（如 /content/results.md）。
        concurrent: 并发数（1-10，默认 5）。
        header_title: 输出文件的大标题。
        return_content: True 时响应 JSON 附带合并后的全文。

    Returns:
        JSON 字符串: {ok, out_path, total, success, failed[], bytes, content?}
    """
    if not urls:
        return json.dumps({"ok": False, "error": "urls 为空"}, ensure_ascii=False)

    sem = asyncio.Semaphore(max(1, min(int(concurrent or 5), 10)))
    records: list = [None] * len(urls)

    browser_cfg = BrowserConfig(headless=True, verbose=False)
    run_cfg = CrawlerRunConfig(
        cache_mode=CacheMode.BYPASS,
        page_timeout=60000,
        wait_until="domcontentloaded",
        verbose=False,
    )

    async with AsyncWebCrawler(config=browser_cfg) as crawler:

        async def work(i: int, url: str) -> None:
            async with sem:
                rec = {"url": url, "ok": False, "title": "", "markdown": "", "error": ""}
                try:
                    r = await crawler.arun(url=url, config=run_cfg)
                    if r is None:
                        rec["error"] = "无结果返回"
                    elif not r.success:
                        rec["error"] = str(getattr(r, "error_message", "") or "抓取失败")[:300]
                    else:
                        md = _md_of(r)
                        rec["title"] = _title_of(r)
                        if len(md) > 50:
                            rec["ok"] = True
                            rec["markdown"] = md
                        else:
                            rec["error"] = f"正文过短（{len(md)} 字符），疑似验证页/空壳页"
                except Exception as e:  # noqa: BLE001
                    rec["error"] = f"{type(e).__name__}: {e}"[:300]
                records[i] = rec

        await asyncio.gather(*(work(i, u) for i, u in enumerate(urls)))

    ok_n = sum(1 for r in records if r and r["ok"])
    lines = [
        f"# {header_title}",
        "",
        f"- URL 总数: {len(urls)}",
        f"- 抓取成功: {ok_n}",
        f"- 抓取失败: {len(urls) - ok_n}",
        "",
        "---",
        "",
    ]
    for i, r in enumerate(records, 1):
        r = r or {"url": urls[i - 1], "ok": False, "title": "", "markdown": "", "error": "未完成"}
        head = r["title"] or r["url"]
        lines.append(f"## [{i}] {head}")
        lines.append("")
        lines.append(f"- URL: {r['url']}")
        lines.append(f"- 状态: {'成功' if r['ok'] else '失败 — ' + (r['error'] or '未知原因')}")
        lines.append("")
        lines.append(r["markdown"] if r["ok"] else "（正文抓取失败）")
        lines.append("")
        lines.append("---")
        lines.append("")
    content = "\n".join(lines)

    out_path = os.path.abspath(out_path)
    os.makedirs(os.path.dirname(out_path) or "/", exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(content)

    resp = {
        "ok": True,
        "out_path": out_path,
        "total": len(urls),
        "success": ok_n,
        "failed": [{"url": r["url"], "error": r["error"]} for r in records if r and not r["ok"]],
        "bytes": len(content.encode("utf-8")),
    }
    if return_content:
        resp["content"] = content
    return json.dumps(resp, ensure_ascii=False)


if __name__ == "__main__":
    mcp.run()
CRAWL_HELPER_EOF
chmod +x "$CDP_DIR/crawl_helper.py"

# ------------------------------------------------------------------------------
# 5. 安装完整性校验（使用 POSIX 循环，兼容 dash/ash）
#    新增：对 browser-use / fastmcp 做 CLI 冒烟测试，确保入口真实可用
# ------------------------------------------------------------------------------
echo "🔍 [5/6] 校验关键可执行文件..."

REQUIRED_SYS_BINS="Xtigervnc fluxbox websockify google-chrome-stable"
for bin_name in $REQUIRED_SYS_BINS; do
    if ! command -v "$bin_name" >/dev/null 2>&1; then
        echo "❌ 缺少系统依赖: $bin_name" >&2
        exit 1
    fi
done

REQUIRED_VENV_BINS="$VENV_BIN/fastmcp $VENV_BIN/browser-use $VENV_BIN/crawl-mcp"
for bin_path in $REQUIRED_VENV_BINS; do
    if [ ! -x "$bin_path" ]; then
        echo "❌ 缺少虚拟环境工具: $bin_path" >&2
        exit 1
    fi
done

# CLI 冒烟测试：能正常打印帮助信息，说明入口点与依赖导入链完好
if ! "$VENV_BIN/browser-use" --help >/dev/null 2>&1; then
    echo "❌ browser-use CLI 冒烟测试失败" >&2
    exit 1
fi
if ! "$VENV_BIN/fastmcp" version >/dev/null 2>&1; then
    echo "❌ fastmcp CLI 冒烟测试失败" >&2
    exit 1
fi

# Playwright Chromium 校验：确认渲染回退所需的可执行文件真实存在
if ! "$VENV_PY" -c '
import os
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    exe = p.chromium.executable_path
    assert exe and os.path.exists(exe), f"缺失: {exe}"
    print("   Playwright Chromium:", exe)
'; then
    echo "❌ Playwright Chromium 校验失败（crawl4ai 渲染回退将不可用）" >&2
    exit 1
fi

# crawl-helper 冒烟测试：模块能被完整导入（FastMCP 实例化 + crawl4ai 依赖链完好）
if ! "$VENV_PY" -c "
import importlib.util
spec = importlib.util.spec_from_file_location('crawl_helper', '$CDP_DIR/crawl_helper.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert hasattr(mod, 'mcp'), 'crawl_helper 缺少 mcp 实例'
"; then
    echo "❌ crawl-helper 冒烟测试失败: $CDP_DIR/crawl_helper.py" >&2
    exit 1
fi

echo "   所有可执行文件校验通过 ✅"

# ==============================================================================
# 6. 生成快捷管理函数文件 ~/.functions.sh
#
#    设计原则：
#      - 所有服务均通过 PID 文件管理，不使用 pkill -f 模糊匹配
#      - MCP 代理（fastmcp）绑定 127.0.0.1，由 Tailscale 负责外部转发
#      - 服务启动后进行健康探测，确认就绪后才返回
#      - DISPLAY 统一设为 :99
#      - 完全兼容 sh/bash/zsh 环境解析
#
#    变更（相对 vccc_gemini.sh）：
#      buse / crwl 改用 `fastmcp run <mcp.json> --transport sse` 将 stdio 的
#      browser-use --mcp / crawl-mcp 代理为 SSE（mcp-proxy 方案不兼容，启动即崩），
#      并增加 SSE 端点健康探测。
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

    # --no-sandbox 仅在 root 用户下必须，普通用户不需要且会降低安全性
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
        # 预先读取完整响应，杜绝管道早期截断导致的 curl 23 错误
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
#
#   实现说明：
#     `fastmcp run <mcp.json> --transport sse` 把 stdio 的 browser-use --mcp
#     代理为 SSE。fastmcp 绑定 127.0.0.1 而非 0.0.0.0，
#     外部 AI Agent 通过 Tailscale 隧道访问，不直接暴露公网。
# ==============================================================================
buse() {
    local venv_bin="$_VENV_BIN"
    local cdp_dir="$_CDP_DIR"
    local log_dir="$_LOG_DIR"
    local pid_dir="$_PID_DIR"
    mkdir -p "$log_dir" "$pid_dir"

    if [ ! -x "$venv_bin/fastmcp" ] || [ ! -x "$venv_bin/browser-use" ]; then
        echo "❌ [buse] 找不到 fastmcp 或 browser-use，请重新运行 vccc_bf1.sh" >&2
        return 1
    fi

    # 【关键修复】browser-use 0.13.10 的 MCP 服务不读取 BU_CDP_URL 环境变量；
    # 其 BrowserProfile 仅由 config.json 的默认 browser_profile 条目构建
    # （源码链：server.py:_init_browser_session → get_default_profile →
    #   config.py:_load_config，env 覆盖不含 CDP 地址）。
    # 接管 chr() 启动的 Chrome 必须把 cdp_url 写进 config.json，
    # 并用 BROWSER_USE_CONFIG_DIR 把配置目录指到本脚本可控的位置。
    local bu_config_dir="$cdp_dir/browseruse-config"
    mkdir -p "$bu_config_dir"
    cat > "$bu_config_dir/config.json" << BU_CONFIG_JSON_EOF
{
  "browser_profile": {
    "cdp-9222": {
      "id": "cdp-9222",
      "default": true,
      "cdp_url": "http://127.0.0.1:9222"
    }
  },
  "llm": {},
  "agent": {}
}
BU_CONFIG_JSON_EOF

    # 接管前置条件：9222 上的 Chrome 必须已就绪，否则 browser-use 建会话时报
    # "Root CDP client not initialized"（cdp_url 模式下连接失败不会回退为自启）
    if ! curl -s --max-time 2 http://127.0.0.1:9222/json/version 2>/dev/null | grep -q '"Browser"'; then
        echo "⚠️  [buse] 未检测到 Chrome CDP (127.0.0.1:9222)，请先执行 chr" >&2
    fi

    # 生成 browser-use 的 stdio MCPConfig
    cat > "$cdp_dir/buse-mcp.json" << BUSE_MCP_JSON_EOF
{
  "mcpServers": {
    "browser-use": {
      "command": "$venv_bin/browser-use",
      "args": ["--mcp"],
      "env": {
        "DISPLAY": ":99",
        "BROWSER_USE_CONFIG_DIR": "$bu_config_dir"
      }
    }
  }
}
BUSE_MCP_JSON_EOF

    echo "🤖 [buse] 停止旧 Browser-use MCP..."
    _kill_service "Browser-use MCP" "$pid_dir/buse.pid"

    echo "🤖 [buse] 启动 Browser-use MCP (127.0.0.1:8001)..."
    nohup "$venv_bin/fastmcp" run "$cdp_dir/buse-mcp.json" \
        --transport sse \
        --host 127.0.0.1 \
        --port 8001 \
        --no-banner \
        >"$log_dir/buse.log" 2>&1 &
    echo $! > "$pid_dir/buse.pid"

    # 健康探测：等待 SSE 端点真实响应
    # （SSE 会保持长连接，故只检查 HTTP 状态码，忽略 curl 的 --max-time 超时退出码）
    local i buse_ready=0 buse_code
    for i in $(seq 1 30); do
        buse_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 1 \
            http://127.0.0.1:8001/sse 2>/dev/null || true)
        if [ "$buse_code" = "200" ]; then
            buse_ready=1
            break
        fi
        sleep 0.5
    done

    if [ "$buse_ready" -eq 1 ]; then
        echo "✅ [buse] Browser-use MCP 已启动 (SSE: 127.0.0.1:8001/sse)"
    else
        echo "❌ [buse] 启动失败，请查看: $log_dir/buse.log" >&2
        return 1
    fi
}

# ==============================================================================
# crwl — 重启 Crawl-MCP 抓取服务，SSE 端口 8002（绑定 127.0.0.1）
#
#   实现说明：
#     同 buse，用 fastmcp 把 stdio 的 crawl-mcp 代理为 SSE。
#     注：crawl-mcp 0.2.0 会启动自身的无头浏览器（Playwright Chromium，
#     已由第 4b 步安装），不使用外部 CDP 地址。
#     同时把 crawl-helper（~/cdp/crawl_helper.py）作为第二个 stdio server
#     合并代理到同一端口，对外新增 crawl_urls_to_file 批量抓取工具。
# ==============================================================================
crwl() {
    local venv_bin="$_VENV_BIN"
    local cdp_dir="$_CDP_DIR"
    local log_dir="$_LOG_DIR"
    local pid_dir="$_PID_DIR"
    mkdir -p "$log_dir" "$pid_dir"

    if [ ! -x "$venv_bin/fastmcp" ] || [ ! -x "$venv_bin/crawl-mcp" ]; then
        echo "❌ [crwl] 找不到 fastmcp 或 crawl-mcp，请重新运行 vccc_bf1.sh" >&2
        return 1
    fi

    if [ ! -f "$cdp_dir/crawl_helper.py" ]; then
        echo "❌ [crwl] 找不到 $cdp_dir/crawl_helper.py，请重新运行 vccc_bf1.sh" >&2
        return 1
    fi

    # 生成 crawl-mcp + crawl-helper 的 stdio MCPConfig（fastmcp 合并代理）
    cat > "$cdp_dir/crwl-mcp.json" << CRWL_MCP_JSON_EOF
{
  "mcpServers": {
    "crawl-mcp": {
      "command": "$venv_bin/crawl-mcp",
      "env": {
        "DISPLAY": ":99"
      }
    },
    "crawl-helper": {
      "command": "$venv_bin/python",
      "args": ["$cdp_dir/crawl_helper.py"],
      "env": {
        "DISPLAY": ":99"
      }
    }
  }
}
CRWL_MCP_JSON_EOF

    echo "🕷️  [crwl] 停止旧 Crawl-MCP..."
    _kill_service "Crawl-MCP" "$pid_dir/crwl.pid"

    echo "🕷️  [crwl] 启动 Crawl-MCP (127.0.0.1:8002)..."
    nohup "$venv_bin/fastmcp" run "$cdp_dir/crwl-mcp.json" \
        --transport sse \
        --host 127.0.0.1 \
        --port 8002 \
        --no-banner \
        >"$log_dir/crwl.log" 2>&1 &
    echo $! > "$pid_dir/crwl.pid"

    # 健康探测：等待 SSE 端点真实响应（只检查 HTTP 状态码）
    local i crwl_ready=0 crwl_code
    for i in $(seq 1 30); do
        crwl_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 1 \
            http://127.0.0.1:8002/sse 2>/dev/null || true)
        if [ "$crwl_code" = "200" ]; then
            crwl_ready=1
            break
        fi
        sleep 0.5
    done

    if [ "$crwl_ready" -eq 1 ]; then
        echo "✅ [crwl] Crawl-MCP 已启动 (SSE: 127.0.0.1:8002/sse)"
    else
        echo "❌ [crwl] 启动失败，请查看: $log_dir/crwl.log" >&2
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

st                   # 5. 输出最终健康状态

# source 方式安装时，把脚本内部用的严格选项从当前交互 shell 上摘掉，
# 避免 set -e/-u 影响用户后续手敲命令
if [ "$_CCC_SOURCED" -eq 1 ]; then
    set +eu
    set +o pipefail 2>/dev/null || true
fi

echo ""
echo "=================================================="
echo "🎉 安装完成！全部服务已启动"
echo ""
if [ "$_CCC_SOURCED" -eq 1 ]; then
    echo "   ✅ 本次以 source 方式安装，当前终端已可直接使用快捷命令"
else
    echo "   ⚡ 想在当前终端立刻使用快捷命令，请执行一次:"
    echo "      . \"\$HOME/.functions.sh\""
    echo "      （新开的终端会自动加载，无需任何命令）"
fi
echo ""
echo "   快捷命令一览:"
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
echo ""
echo "   批量抓取（推荐外部 Agent 使用，一次调用完成整批）:"
echo "   crawl_urls_to_file(urls, out_path, concurrent=5)  ← 8002 端口 crawl-helper 提供"
echo "   正文提取约定: browser-use 只用 get_html(selector=...)，不依赖 extract_content"
echo "=================================================="
