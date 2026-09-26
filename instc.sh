#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# 1. 架构检测与映射
# ==========================================
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
    # armhf 是 Debian 包格式名称，uname -m 实际输出为 armv7l
    GOARCH="arm"
    PKG_ARCH="armv7"
    ;;
  *)
    echo "[-] 不受支持的 CPU 架构: $ARCH" >&2
    exit 1
    ;;
esac

echo "[+] 检测到系统架构: $ARCH (包资产标识: $PKG_ARCH)"

# ==========================================
# 2. 检查权限 (非 root 自动尝试加 sudo)
# ==========================================
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "[!] 警告: 当前为普通用户且未检测到 sudo，系统级安装可能会失败"
  fi
fi

# 需要提权操作前的权限检查函数
require_root() {
  if [ "$(id -u)" -ne 0 ] && [ -z "$SUDO" ]; then
    echo "[-] 需要 root 或 sudo 权限才能继续安装，请切换至 root 用户或安装 sudo。" >&2
    exit 1
  fi
}

# ==========================================
# 3. 辅助函数：网络下载
# ==========================================
download_file() {
  local url="$1"
  local dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --progress-bar "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "$dest" "$url"
  else
    echo "[-] 缺少 curl 或 wget，无法下载安装包" >&2
    exit 1
  fi
}

# ==========================================
# 4. 获取版本号 (优先重定向解析，避免API限流)
# ==========================================
get_latest_version() {
  if [ -n "${TAILCAT_VERSION:-}" ]; then
    echo "${TAILCAT_VERSION#v}"
    return
  fi

  local version=""
  # 通过跟踪 release/latest 302 重定向获取最新 tag，不依赖 API 配额与 jq
  if command -v curl >/dev/null 2>&1; then
    version=$(curl -fsSLI -o /dev/null -w "%{url_effective}" https://github.com/tailscale/tailcat/releases/latest 2>/dev/null | awk -F'/' '{print $NF}')
  elif command -v wget >/dev/null 2>&1; then
    # 使用大小写不敏感匹配 Location 头，兼容不同 wget 版本的输出格式
    version=$(wget -S --spider --max-redirect=0 https://github.com/tailscale/tailcat/releases/latest 2>&1 | awk -F'/tag/' 'tolower($0) ~ /location:/{print $2}' | tr -d ' \r\n')
  fi

  # 若重定向失败，尝试 API 获取
  if [ -z "$version" ] || [ "$version" = "latest" ]; then
    if command -v curl >/dev/null 2>&1; then
      version=$(curl -fsSL https://api.github.com/repos/tailscale/tailcat/releases/latest 2>/dev/null | grep -m1 '"tag_name":' | cut -d '"' -f 4 || true)
    fi
  fi

  # 验证版本号格式是否合法（注意：本函数输出经命令替换捕获，
  # 警告信息必须显式重定向到 stderr，否则用户将看不到）
  if ! printf '%s' "$version" | grep -qE '^v?[0-9]+\.[0-9]+(\.[0-9]+)?([-+][0-9A-Za-z.-]+)?$'; then
    printf '[!] 版本号格式异常: %s, 使用兜底版本 v0.7.0\n' "'${version:-空}'" >&2
    version="v0.7.0"
  fi

  echo "${version#v}"
}

# 创建临时工作目录并确保清理（兼容 Bash 3.x，不使用 ${var,,} 等 4.x 扩展）
TMP_DIR=$(mktemp -d) || { echo "[-] 无法创建临时目录" >&2; exit 1; }
cleanup() { [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

# ==========================================
# 5. 执行环境检测与安装 (原生包管理器优先)
# ==========================================

# 路径 A: Debian / Ubuntu 系列 (.deb)
if command -v dpkg >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
  require_root
  VERSION=$(get_latest_version)
  DEB_FILE="tailcat_${VERSION}_linux_${PKG_ARCH}.deb"
  DEB_URL="https://github.com/tailscale/tailcat/releases/download/v${VERSION}/${DEB_FILE}"

  echo "[+] 检测到 Debian/Ubuntu 环境，准备安装 Tailcat (v${VERSION})..."
  download_file "$DEB_URL" "$TMP_DIR/$DEB_FILE"

  echo "[+] 正在安装 .deb 并解决依赖..."
  if ! $SUDO dpkg -i "$TMP_DIR/$DEB_FILE"; then
    echo "[!] 检测到缺失依赖，尝试自动修复..."
    # || true 为有意忽略 update 可能的失败（如离线环境），确保继续尝试修复依赖
    $SUDO apt-get update -qq || true
    $SUDO apt-get install -f -y
  fi

# 路径 B: RHEL / CentOS / Fedora 系列 (.rpm)
elif command -v rpm >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
  require_root
  VERSION=$(get_latest_version)
  RPM_FILE="tailcat_${VERSION}_linux_${PKG_ARCH}.rpm"
  RPM_URL="https://github.com/tailscale/tailcat/releases/download/v${VERSION}/${RPM_FILE}"

  echo "[+] 检测到 RPM 系统环境，准备安装 Tailcat (v${VERSION})..."
  download_file "$RPM_URL" "$TMP_DIR/$RPM_FILE"

  echo "[+] 正在安装 .rpm 包..."
  if command -v dnf >/dev/null 2>&1; then
    $SUDO dnf install -y "$TMP_DIR/$RPM_FILE"
  elif command -v yum >/dev/null 2>&1; then
    $SUDO yum localinstall -y "$TMP_DIR/$RPM_FILE"
  else
    $SUDO rpm -Uvh "$TMP_DIR/$RPM_FILE"
  fi

# 路径 C: Nix 独立环境 (系统无原生 deb/rpm 时采用)
elif command -v nix >/dev/null 2>&1; then
  echo "[+] 系统无常见包管理器，检测到 Nix 环境，正在安装..."
  if ! nix profile install nixpkgs#tailcat 2>/dev/null; then
    echo "[-] Nix 安装失败，nixpkgs 中可能不存在 tailcat 包，请考虑手动安装或指定 TAILCAT_VERSION 环境变量后重试。" >&2
    exit 1
  fi

# 路径 D: 通用静态二进制包安装 (.tar.gz 回退机制)
else
  echo "[+] 未匹配到系统包管理器，使用通用预编译二进制包 (.tar.gz) 安装..."
  VERSION=$(get_latest_version)
  TAR_FILE="tailcat_${VERSION}_linux_${PKG_ARCH}.tar.gz"
  TAR_URL="https://github.com/tailscale/tailcat/releases/download/v${VERSION}/${TAR_FILE}"

  download_file "$TAR_URL" "$TMP_DIR/$TAR_FILE"

  EXTRACT_DIR="$TMP_DIR/extracted"
  mkdir -p "$EXTRACT_DIR"
  tar -xzf "$TMP_DIR/$TAR_FILE" -C "$EXTRACT_DIR"

  # 动态定位二进制文件（避免打包时多层目录嵌套问题）
  BIN_PATH=$(find "$EXTRACT_DIR" -type f -name "tailcat" | head -n 1)

  if [ -z "$BIN_PATH" ] || [ ! -f "$BIN_PATH" ]; then
    echo "[-] 解压后未能在压缩包内找到可执行文件 tailcat" >&2
    exit 1
  fi
  chmod +x "$BIN_PATH"

  TARGET_DIR="/usr/local/bin"
  if [ -w "$TARGET_DIR" ]; then
    install -m 755 "$BIN_PATH" "$TARGET_DIR/tailcat"
    echo "[+] 已成功安装至 $TARGET_DIR/tailcat"
  elif [ -n "$SUDO" ]; then
    $SUDO install -m 755 "$BIN_PATH" "$TARGET_DIR/tailcat"
    echo "[+] 已成功通过 sudo 安装至 $TARGET_DIR/tailcat"
  else
    TARGET_DIR="$HOME/.local/bin"
    mkdir -p "$TARGET_DIR"
    install -m 755 "$BIN_PATH" "$TARGET_DIR/tailcat"
    echo "[!] 无系统目录写入权限，已安装至 $TARGET_DIR/tailcat"
    if [[ ":$PATH:" != *":$TARGET_DIR:"* ]]; then
      echo "[!] 提示: 请将 $TARGET_DIR 加入你的 PATH 环境变量中:"
      echo "    export PATH=\"\$PATH:$TARGET_DIR\""
    fi
  fi
fi

# ==========================================
# 6. 验证安装结果
# ==========================================
echo "------------------------------------------"
if command -v tailcat >/dev/null 2>&1; then
  echo "[✓] Tailcat 安装完成！"
  echo "可执行文件路径: $(command -v tailcat)"
  tailcat --version 2>/dev/null || tailcat version 2>/dev/null || echo "Tailcat 已可用"
else
  echo "[!] 安装已完成，但在当前终端 PATH 中未找到 tailcat 命令。"
  echo "    若安装在 /usr/local/bin 或 ~/.local/bin，请尝试重新打开终端或执行 hash -r。"
fi
echo "------------------------------------------"
