#!/usr/bin/env bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 读取上一次 panic 的 pstore/ramoops（需要 root 会话；不重启就一直在）
# 用法: ./scripts/03-pstore.sh [序列号]
set -uo pipefail
ADB="${ADB:-adb}"
SERIAL="${SERIAL:-R5CX14VMD7X}"
BASE=/data/local/tmp/bakasu
LOG="$ROOT_DIR/logs/pstore-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "== $(date '+%F %T') pstore / ramoops 读取（序列号 $SERIAL）=="

if ! "$ADB" -s "$SERIAL" shell "$BASE/roothelper -c 'id'" 2>/dev/null | grep -q "uid=0"; then
  echo "❌ 没有 root 会话（uid 不是 0）。先跑 ./scripts/01-exploit.sh。"
  exit 1
fi

echo "[1/2] 列出 pstore ..."
"$ADB" -s "$SERIAL" shell "$BASE/roothelper -c 'ls -l /sys/fs/pstore/ 2>&1'"

echo "[2/2] 导出内容（也会存一份到设备 /data/local/tmp/pstore-dump.txt）..."
"$ADB" -s "$SERIAL" shell "$BASE/roothelper -c 'for f in /sys/fs/pstore/*; do echo \"===== \$f\"; cat \"\$f\"; done > /data/local/tmp/pstore-dump.txt 2>&1; wc -c /data/local/tmp/pstore-dump.txt'"
"$ADB" -s "$SERIAL" pull /data/local/tmp/pstore-dump.txt $ROOT_DIR/logs/pstore-dump-latest.txt 2>&1 | tail -1

echo "--- 关键行（panic/BUG/Oops/kernelsu/module）---"
grep -inE "panic|BUG|Oops|Call trace|kernelsu|module|KDP|RKP|defex" $ROOT_DIR/logs/pstore-dump-latest.txt 2>/dev/null | tail -40
echo "完整内容: $ROOT_DIR/logs/pstore-dump-latest.txt"
