#!/usr/bin/env bash
#
# vm.sh — 管理 Tart macOS 虚拟机 + 黄金镜像工作流
# 详见同目录 README.md
#
#   ./vm.sh create 3        建空白 mac-1..mac-3(mac-1 下载, 其余从 mac-1 克隆)
#   ./vm.sh golden 07 [vm]  把某 VM(默认 mac-1)做成黄金镜像 golden-07(先关机)
#   ./vm.sh new 2 07        从 golden-07 克隆出 mac-2(已登录, 秒开即用)
#   ./vm.sh del 2           删除 mac-2
#   ./vm.sh list            列出所有 VM/镜像 + 路径 + 大小
#   ./vm.sh run 1           开窗口运行 mac-1
#
set -euo pipefail

PREFIX="mac-"
GOLD="golden-"
DISK_SIZE="${VM_DISK_SIZE:-60}"
VMS_DIR="$HOME/.tart/vms"
HERE="$(cd "$(dirname "$0")" && pwd)"

die()  { echo "✗ $*" >&2; exit 1; }
have() { tart list --quiet 2>/dev/null | grep -qx "$1"; }
running() { tart list 2>/dev/null | awk -v n="$1" '$2==n {print $NF}' | grep -qx running; }

stop_if_running() {
  local name="$1"
  if running "$name"; then
    echo "▶ $name 在运行,优雅关机..."
    tart stop "$name" 2>/dev/null || true
    for _ in $(seq 1 20); do running "$name" || break; sleep 2; done
  fi
}

command -v tart >/dev/null || die "没装 tart。先运行: brew install cirruslabs/cli/tart"

# --- create N : 建空白机 ---------------------------------------------------
cmd_create() {
  local n="${1:-}"
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || die "用法: ./vm.sh create <数量>"
  local base="${PREFIX}1"
  if ! have "$base"; then
    echo "▶ $base 不存在,从 Apple 官方 IPSW 下载安装(约 16GB)..."
    tart create --from-ipsw latest "$base" --disk-size "$DISK_SIZE"
  fi
  (( n >= 2 )) && stop_if_running "$base"
  local i name
  for (( i=2; i<=n; i++ )); do
    name="${PREFIX}${i}"
    if have "$name"; then echo "• $name 已存在,跳过"
    else echo "▶ 克隆 $base → $name ..."; tart clone "$base" "$name"; fi
  done
  echo; cmd_list
}

# --- golden TAG [vm] : 做黄金镜像 -----------------------------------------
cmd_golden() {
  local tag="${1:-}" src="${2:-${PREFIX}1}"
  [[ -n "$tag" ]] || die "用法: ./vm.sh golden <tag> [源VM, 默认mac-1]   例: ./vm.sh golden 07"
  have "$src" || die "源 VM $src 不存在。"
  local g="${GOLD}${tag}"
  if have "$g"; then
    read -r -p "$g 已存在,覆盖? [y/N] " a; [[ "${a:-}" == [yY] ]] || die "已取消。"
    stop_if_running "$g"; tart delete "$g"
  fi
  stop_if_running "$src"
  echo "▶ 从 $src 制作黄金镜像 $g ..."
  tart clone "$src" "$g"
  echo "✓ 黄金镜像 $g 已建。以后 ./vm.sh new <编号> $tag 即可秒出已登录的机器。"
}

# --- new N TAG : 从黄金镜像克隆 -------------------------------------------
cmd_new() {
  local n="${1:-}" tag="${2:-}"
  [[ "$n" =~ ^[1-9][0-9]*$ && -n "$tag" ]] || die "用法: ./vm.sh new <编号> <tag>   例: ./vm.sh new 2 07"
  local g="${GOLD}${tag}" name="${PREFIX}${n}"
  have "$g" || die "黄金镜像 $g 不存在。先 ./vm.sh golden $tag 制作(需手动登一次 Apple ID)。"
  if have "$name"; then
    read -r -p "$name 已存在,覆盖? [y/N] " a; [[ "${a:-}" == [yY] ]] || die "已取消。"
    stop_if_running "$name"; tart delete "$name"
  fi
  echo "▶ 从 $g 克隆 → $name (已登录, 秒开即用)..."
  tart clone "$g" "$name"
  echo "✓ $name 就绪。开窗口: ./vm.sh run $n"
}

# --- del N -----------------------------------------------------------------
cmd_del() {
  local n="${1:-}"
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || die "用法: ./vm.sh del <编号>"
  local name="${PREFIX}${n}"
  have "$name" || die "$name 不存在。"
  read -r -p "确定删除 $name ? 不可恢复 [y/N] " a; [[ "${a:-}" == [yY] ]] || die "已取消。"
  stop_if_running "$name"; tart delete "$name"; echo "✓ 已删除 $name"
}

# --- list ------------------------------------------------------------------
cmd_list() {
  echo "VM 与黄金镜像:"; tart list
  echo; echo "存储路径: $VMS_DIR"
  local d
  for d in "$VMS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    printf "  %-22s %s  (%s)\n" "$(basename "$d")" "$d" "$(du -sh "$d" 2>/dev/null | cut -f1)"
  done
}

# --- run N -----------------------------------------------------------------
cmd_run() {
  local n="${1:-}"
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || die "用法: ./vm.sh run <编号>"
  local name="${PREFIX}${n}"
  have "$name" || die "$name 不存在。"
  echo "▶ 运行 $name (关窗口或 VM 内关机即停止)..."
  tart run "$name"
}

case "${1:-}" in
  create) shift; cmd_create "$@";;
  golden) shift; cmd_golden "$@";;
  new)    shift; cmd_new "$@";;
  del|delete|rm) shift; cmd_del "$@";;
  list|ls) cmd_list;;
  run) shift; cmd_run "$@";;
  *) cat <<EOF
vm.sh — Tart macOS 虚拟机管理 + 黄金镜像工作流

  ./vm.sh create <数量>     建空白机 mac-1..mac-N
  ./vm.sh golden <tag> [vm] 把 VM(默认 mac-1)做成黄金镜像 golden-<tag>(先手动登 Apple ID)
  ./vm.sh new <编号> <tag>  从 golden-<tag> 克隆 mac-<编号>(已登录, 秒开)
  ./vm.sh del <编号>        删除 mac-<编号>
  ./vm.sh list              列出全部 + 路径 + 大小
  ./vm.sh run <编号>        开窗口运行 mac-<编号>

详细说明见 README.md
EOF
  ;;
esac
