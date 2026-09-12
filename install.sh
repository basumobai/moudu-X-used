#!/usr/bin/env bash
set -Eeuo pipefail

REPO_RAW="https://raw.githubusercontent.com/basumobai/moudu-X-used/main"
PACKAGE_URL="${REPO_RAW}/proxy.zip"
PACKAGE_SHA256="90f5ff0511e705af10926ac9a3607b1a008eae0613025b42f0af66d3e450034c"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { printf "%b\n" "${GREEN}[+]${NC} $*"; }
warn() { printf "%b\n" "${YELLOW}[!]${NC} $*"; }
die()  { printf "%b\n" "${RED}[-]${NC} $*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 root 运行此安装命令"
[[ "$(uname -s)" == "Linux" ]] || die "当前一键入口仅支持 Linux"
case "$(uname -m)" in
  x86_64|amd64) ;;
  *) die "当前安装包仅支持 x86_64/amd64，检测到: $(uname -m)" ;;
esac

install_dependencies() {
  local missing=()
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || missing+=(downloader)
  command -v unzip >/dev/null 2>&1 || missing+=(unzip)
  command -v sha256sum >/dev/null 2>&1 || missing+=(sha256sum)
  ((${#missing[@]} == 0)) && return 0

  info "第 1/4 步：安装必要工具"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl unzip coreutils
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y ca-certificates curl unzip coreutils
  elif command -v yum >/dev/null 2>&1; then
    yum install -y ca-certificates curl unzip coreutils
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache ca-certificates curl unzip coreutils bash
  else
    die "无法识别包管理器，请先安装 curl、unzip 和 sha256sum"
  fi
}

download() {
  local url="$1" output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 15 "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget --tries=3 --timeout=15 -O "$output" "$url"
  else
    die "没有可用的下载工具"
  fi
}

install_dependencies
work_dir="$(mktemp -d /tmp/mnode-install.XXXXXX)"
trap 'rm -rf -- "$work_dir"' EXIT
package="$work_dir/proxy.zip"

info "第 2/4 步：下载 proxy-node 安装包"
download "$PACKAGE_URL" "$package"

info "第 3/4 步：校验并解压安装包"
actual_sha256="$(sha256sum "$package" | awk '{print $1}')"
[[ "$actual_sha256" == "$PACKAGE_SHA256" ]] || die "安装包校验失败，已停止安装"
unzip -q "$package" -d "$work_dir/package"

entry="$(find "$work_dir/package" -type f -name onekey.sh -print -quit)"
[[ -n "$entry" ]] || die "安装包内未找到 onekey.sh"
entry_dir="$(dirname "$entry")"
[[ -f "$entry_dir/proxy-node" ]] || die "onekey.sh 同目录下未找到 proxy-node"
chmod +x "$entry" "$entry_dir/proxy-node"

info "第 4/4 步：安装服务并注册 mnode"
if [[ -r /dev/tty ]]; then
  bash "$entry" "$@" </dev/tty
else
  bash "$entry" "$@"
fi

if command -v mnode >/dev/null 2>&1; then
  info "安装完成，以后输入 mnode 即可进入管理菜单"
  if [[ -r /dev/tty ]]; then
    exec mnode </dev/tty
  else
    warn "当前没有交互终端，请稍后执行 mnode"
  fi
else
  die "安装程序已结束，但未找到 mnode 命令"
fi
