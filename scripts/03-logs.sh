#!/usr/bin/env bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 看最新的日志（默认跟随；-n 只打印最后 100 行不跟随）
set -uo pipefail
D=$ROOT_DIR/logs
f=$(ls -t "$D"/*.log 2>/dev/null | head -1) || true
[[ -z "${f:-}" ]] && { echo "还没有日志（先跑 01-exploit.sh）"; exit 0; }
echo "== $f =="
if [[ "${1:-}" == "-n" ]]; then tail -n 100 "$f"; else tail -n 40 -f "$f"; fi
