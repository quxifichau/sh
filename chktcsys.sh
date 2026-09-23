#!/usr/bin/env bash  
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
  echo "  dpkg -i tailcat_*_${GOARCH}.deb"  
elif command -v rpm >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then  
  echo "检测到 rpm/dnf/yum，下载对应 .rpm 并安装:"  
  echo "  rpm -i tailcat_*_${GOARCH}.rpm"  
else  
  echo "无匹配包管理器/工具链，回退到静态二进制 tar.gz:"  
  echo "  下载 tailcat_{version}_linux_${GOARCH}.tar.gz 并解压"  
fi
