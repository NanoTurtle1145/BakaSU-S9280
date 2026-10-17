#!/usr/bin/env bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 第二阶段：在拿到临时 root 的同一会话里加载 BakaSU 内核
#
# 用法:
#   ./scripts/02-late-load.sh                     # 正常 late-load（会跑后续 stage 脚本）
#   STOP_AFTER_LOAD=1 ./scripts/02-late-load.sh   # 只加载 LKM，不跑 stage 脚本（先验证兼容性）
#   ./scripts/02-late-load.sh --dry-run
#
# 前置: 01-exploit.sh 成功（root 会话还在），且手机没有重启过
# 日志: logs/lateload-*.log + logs/logcat-*.log + logs/kmsg-*.log
set -uo pipefail
ADB="${ADB:-adb}"
SERIAL="${SERIAL:-R5CX14VMD7X}"
STOP_AFTER_LOAD="${STOP_AFTER_LOAD:-0}"
ALLOW_LOADED="${ALLOW_LOADED:-0}"  # =1 时允许内核里已有 kernelsu（继续跑 stage 脚本用）
DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -*) echo "未知参数: $a"; exit 2 ;;
    *) SERIAL="$a" ;;
  esac
done
BASE=/data/local/tmp/bakasu
TS=$(date +%Y%m%d-%H%M%S)
LOG="$ROOT_DIR/logs/lateload-$TS.log"
CATLOG="$ROOT_DIR/logs/logcat-$TS.log"
KMSG="$ROOT_DIR/logs/kmsg-$TS.log"
ENVS="KSU_NO_DAEMON=1"
[[ "$STOP_AFTER_LOAD" == "1" ]] && ENVS="$ENVS KSU_STOP_AFTER_LOAD=1"

if [[ "$DRY" == "1" ]]; then
  echo "[dry-run] adb -s $SERIAL shell '$ENVS $BASE/roothelper --late-load'"
  echo "[dry-run] 同时抓 logcat(KernelSU) 与 /dev/kmsg"
  exit 0
fi

exec > >(tee -a "$LOG") 2>&1
echo "日志: $LOG (logcat: $CATLOG, kmsg: $KMSG)"
echo "== $(date '+%F %T') BakaSU late-load（序列号 $SERIAL，STOP_AFTER_LOAD=$STOP_AFTER_LOAD）=="

"$ADB" -s "$SERIAL" get-state >/dev/null 2>&1 || { echo "设备不在线"; exit 1; }

echo "[1/4] 确认 exploit 的 root 会话还在..."
if ! "$ADB" -s "$SERIAL" shell "$BASE/roothelper -c 'id'" 2>/dev/null | grep -q "uid=0"; then
  echo "❌ 连不上 root 会话（uid 不是 0）。手机可能重启过 —— 先跑 01-exploit.sh。"
  exit 1
fi
echo "  root 会话正常"

if [[ "$ALLOW_LOADED" != "1" ]] && "$ADB" -s "$SERIAL" shell 'cat /proc/modules 2>/dev/null | grep -qi kernelsu'; then
  echo "⚠ 内核里已有 kernelsu 模块。"
  echo "  若这是刚才 STOP_AFTER_LOAD=1 加载的，可用 ALLOW_LOADED=1 ./scripts/02-late-load.sh 继续跑 stage；"
  echo "  否则先重启手机再按 01 → 02 重来。"
  exit 2
fi

echo "[2/4] 关掉 panic_on_oops（oops 不再直接重启，尽量抓完整调用栈）..."
"$ADB" -s "$SERIAL" shell "$BASE/roothelper -c 'echo 0 > /proc/sys/kernel/panic_on_oops 2>/dev/null; cat /proc/sys/kernel/panic_on_oops'" 2>&1 | tail -1

echo "[2/4] 启动内核日志捕获（logcat + /dev/kmsg）..."
"$ADB" -s "$SERIAL" logcat -v threadtime -s KernelSU:* >"$CATLOG" 2>&1 &
LOGPID=$!
"$ADB" -s "$SERIAL" shell "$BASE/roothelper -c 'cat /dev/kmsg'" >"$KMSG" 2>&1 &
KMSGPID=$!
sleep 1

# 三星 staging：模块加载会改变进程安全上下文，先把 ksud 放到固定暂存路径
"$ADB" -s "$SERIAL" shell "$BASE/roothelper -c 'cp $BASE/ksud /data/local/tmp/.ksud-stage && chmod 755 /data/local/tmp/.ksud-stage'" >/dev/null 2>&1 || true

echo "[3/4] 执行 late-load ..."
"$ADB" -s "$SERIAL" shell "$ENVS $BASE/roothelper --late-load"
rc=$?
echo "late-load 退出码=$rc  $(date '+%T')"

sleep 2
kill "$LOGPID" "$KMSGPID" 2>/dev/null
wait "$LOGPID" "$KMSGPID" 2>/dev/null

if ! "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
  echo "⚠ 设备已断开（很可能 kernel panic 后重启）。"
  echo "  抓到的最后内核日志: tail -n 80 \"$KMSG\""
  echo "  设备重启完后，重新跑 01-exploit.sh。"
  exit 3
fi

echo "[4/4] 验证"
echo "--- ksud debug info ---"
"$ADB" -s "$SERIAL" shell "$BASE/ksud debug info" 2>&1
echo "--- 内核模块 ---"
"$ADB" -s "$SERIAL" shell 'ls -d /sys/module/kernelsu 2>/dev/null; cat /proc/modules 2>/dev/null | grep -i kernelsu' 2>&1

if [[ $rc -eq 0 ]]; then
  echo "✅ late-load 返回 0。看 debug info 里 version 是否 35xxx、lkm/late_load 是否 true。"
else
  echo "❌ late-load 失败 rc=$rc —— 看 logcat: grep -iE 'KernelSU|kernelsu|Error' \"$CATLOG\""
  echo "   以及 kmsg: tail -n 120 \"$KMSG\""
fi
