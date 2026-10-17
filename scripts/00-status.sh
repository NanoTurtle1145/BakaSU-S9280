#!/usr/bin/env bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 快速体检：设备在线？开机多久？屏幕状态？BakaSU 载荷三件套还在不在？
# 用法: ./scripts/00-status.sh [序列号]
set -uo pipefail
ADB="${ADB:-adb}"
SERIAL="${1:-${SERIAL:-R5CX14VMD7X}}"
echo "== $(date '+%F %T') =="
"$ADB" devices -l
echo "--- 设备状态 ---"
"$ADB" -s "$SERIAL" shell '
  echo "uptime: $(cut -d" " -f1 /proc/uptime) 秒"
  echo "boot_completed: $(getprop sys.boot_completed)"
  echo "屏幕: $(dumpsys power 2>/dev/null | grep -m1 mWakefulness=)"
  echo -n "kernelsu 模块: "; (cat /proc/modules 2>/dev/null | grep -q kernelsu && echo "已加载") || echo "未加载（干净）"
  echo "--- /data/local/tmp/bakasu ---"; ls -l /data/local/tmp/bakasu/ 2>/dev/null || echo "缺少！需要重新推送"
' 2>&1
