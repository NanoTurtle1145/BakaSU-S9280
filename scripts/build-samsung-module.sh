#!/usr/bin/env bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 从 /home/nt/项目/bakasu (分支 samsung-port) 构建三星 DZH3 版 BakaSU 内核模块与 ksud
# 依赖: docker + ghcr.io/ylarod/ddk-min:android14-6.1-20260313 镜像、NDK r29、cargo-ndk
set -euo pipefail
REPO="${REPO:-$(cd "$ROOT_DIR/.." && pwd)/bakasu}"
OUT="${OUT:-$ROOT_DIR}"
KMI=android14-6.1
REL="6.1.145-android14-11-3254743-abS9280ZCS6DZH3"
MODULE_CRC=0xea759d7f
IMAGE=ghcr.io/ylarod/ddk-min:android14-6.1-20260313
STRIP="${STRIP:-$(command -v llvm-strip || echo llvm-strip)}"
NDK="${ANDROID_NDK_HOME:-$HOME/Android/Sdk/ndk/29.0.14206865}"

echo "== [1/4] DDK 容器内构建 kernelsu.ko =="
cat >/tmp/ddk_samsung_build.sh <<'EOF'
set -e
REL="$REL"
echo "$REL" > /opt/ddk/kdir/android14-6.1/include/config/kernel.release
sed -i "s|^#define UTS_RELEASE .*|#define UTS_RELEASE \"$REL\"|" /opt/ddk/kdir/android14-6.1/include/generated/utsrelease.h
rm -rf /build/kernel/out/android14-6.1
mkdir -p /build/kernel/out/android14-6.1
cd /build/kernel
make -C /opt/ddk/kdir/android14-6.1 M=/build/kernel/out/android14-6.1 src=/build/kernel modules \
  KCFLAGS="-DKSU_FORCE_UAPI_VERSION=4" -j"$(nproc)" 2>&1 | tail -5
EOF
docker run --rm -i --platform linux/amd64 -v "$REPO":/build -w /build/kernel \
  -e REL="$REL" \
  -e CONFIG_KSU=m -e CONFIG_KSU_TRACEPOINT_HOOK=y -e CONFIG_KSU_MULTI_MANAGER_SUPPORT=y \
  -e CONFIG_KSU_SAMSUNG_KDP=y -e CONFIG_KSU_SAMSUNG_RKP=y -e CONFIG_KSU_SAMSUNG_DEFEX=y \
  -e CONFIG_KSU_SAMSUNG_NO_PATCH_TEXT=y -e KSU_VERSION_OVERRIDE=35171 \
  "$IMAGE" bash -s < /tmp/ddk_samsung_build.sh

echo "== [2/4] strip + 注入 module_layout CRC =="
cp "$REPO/kernel/out/$KMI/kernelsu.ko" /tmp/ksu-samsung.ko
"$STRIP" -d /tmp/ksu-samsung.ko
python3 - "$MODULE_CRC" "$OUT/release/android14-6.1_kernelsu-e3q-S9280ZCS6DZH3-samsung-35171.ko" <<'PY'
import struct, sys
crc=int(sys.argv[1],16); dst=sys.argv[2]
d=bytearray(open('/tmp/ksu-samsung.ko','rb').read())
so=struct.unpack_from('<Q',d,0x28)[0]; es=struct.unpack_from('<H',d,0x3a)[0]
n=struct.unpack_from('<H',d,0x3c)[0]; si=struct.unpack_from('<H',d,0x3e)[0]
sh=[]
for i in range(n):
    h=so+i*es; v=struct.unpack_from('<IIQQQQIIQQ',d,h); sh.append({'hdr':h,'name':v[0],'off':v[4],'size':v[5]})
st=d[sh[si]['off']:sh[si]['off']+sh[si]['size']]
nm=lambda x: st[x:st.find(b'\0',x)].decode(errors='replace') if x<len(st) else ''
vers=[s for s in sh if nm(s['name'])=='__versions'][0]
ent=struct.pack('<Q',crc)+b'module_layout'.ljust(56,b'\0')
o=len(d); d+=ent
struct.pack_into('<Q',d,vers['hdr']+0x18,o); struct.pack_into('<Q',d,vers['hdr']+0x20,len(ent))
open(dst,'wb').write(bytes(d)); print('module:',dst,len(d),'bytes')
PY

echo "== [3/4] 嵌入 ksud 并重建 =="
cp "$OUT/release/android14-6.1_kernelsu-e3q-S9280ZCS6DZH3-samsung-35171.ko" \
   "$REPO/userspace/ksud/bin/aarch64/${KMI}_kernelsu.ko"
export PATH="$HOME/.cargo/bin:$PATH" ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}" \
       ANDROID_NDK_HOME="$NDK" RUSTC_BOOTSTRAP=1
(cd "$REPO/userspace/ksud" && cargo ndk -t arm64-v8a -P 26 build --release)
cp "$REPO/userspace/ksud/target/aarch64-linux-android/release/ksud" \
   "$OUT/release/ksud-e3q-S9280ZCS6DZH3-samsung-35171"

echo "== [4/4] 完成 =="
ls -l "$OUT/release/" | sed -n '1,6p'
