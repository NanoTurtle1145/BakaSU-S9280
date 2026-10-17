#!/usr/bin/env bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 读取上一次崩溃的 /proc/last_kmsg（需要 root 会话）
# 用法: ./scripts/04-lastkmsg.sh [序列号]
set -uo pipefail
ADB="${ADB:-adb}"
SERIAL="${SERIAL:-R5CX14VMD7X}"
BASE=/data/local/tmp/bakasu
TS=$(date +%Y%m%d-%H%M%S)
OUT="$ROOT_DIR/logs/last_kmsg-$TS.log"
echo "== $(date '+%F %T') 拉 /proc/last_kmsg（序列号 $SERIAL）=="
if ! "$ADB" -s "$SERIAL" shell "$BASE/roothelper -c 'id'" 2>/dev/null | grep -q "uid=0"; then
  echo "❌ 没有 root 会话。先跑 ./scripts/01-exploit.sh。"
  exit 1
fi
"$ADB" -s "$SERIAL" shell "$BASE/roothelper -c 'cat /proc/last_kmsg'" > "$OUT" 2>/dev/null
echo "已保存: $OUT ($(wc -c < "$OUT") bytes)"
echo "--- 关键行 ---"
grep -anE "KernelSU|kernelsu|RAMDUMP|panic|BUG|Oops|Call trace|Unable to handle|tp_marker|patch syscall|hook_manager|Internal error|SError" "$OUT" | tail -60
