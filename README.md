# BakaSU-S9280

三星 SM-S9280（S24 Ultra 国行 / DZH3 固件，内核
`6.1.145-android14-11-3254743-abS9280ZCS6DZH3`）上运行 **BakaSU 内核**的
late-load 工具链与三星适配补丁。

**状态**：真机验证通过。BakaSU 管理器显示「工作中 / LKM / 越狱模式」，
超级用户、模块安装均可用（每次开机需重新执行，不写 boot，不会触发 Knox/变砖）。

## 原理速览

1. 用 CVE-2026-43499 exploit 拿临时 root；
2. 用 `ksud late-load` 把一个**按 DZH3 精确构建 + 三星适配**的 BakaSU 内核模块
   加载进内核（不刷 boot）；
3. 加载前把 ksud staging 到 `/data/adb/ksud`，加载后进程进入 `u:r:ksu:s0`
   再完成 assets/管理器安装，绕过 DEFEX 的 Safeplace kill。

三星适配补丁（见 `patches/`）包含：

- KDP 保护的 cred 处理（`prepare_ro_creds` / `kdp_assign_pgd` /
  `kdp_usecount_dec_and_test`）；
- DEFEX 凭据同步 + `task_defex_enforce` kprobe；
- RKP 目标禁用 live text patch，改用 `__arm64_sys_setresuid` kretprobe +
  sucompat 地址级 kprobe 回退；
- ksud 用户态 staging（加载模块前落盘，加载后 `finish_install`）；
- UAPI 4 上报（兼容 BakaSU v4.2.0-rc3 管理器）。

## 目录

```
scripts/
  00-status.sh              设备/模块/文件状态检查
  01-exploit.sh             运行 CVE-2026-43499 获取临时 root
  02-late-load.sh           late-load 加载 BakaSU 内核 + 完整安装
  03-logs.sh                查看最新日志
  03-pstore.sh              读取 pstore/ramoops（崩溃取证）
  04-lastkmsg.sh            读取 /proc/last_kmsg（崩溃取证）
  build-samsung-module.sh   从 BakaSU 源码构建 DZH3 模块 + ksud（DDK 容器）
docs/
  BAKASU_SAMSUNG_PORT_NOTES.md   完整移植记录、验证结果、已知限制
patches/
  *.patch                   对 BakaSU 源码的三星适配提交
```

## 手动使用（不进 RootMyS24 App）

前置：adb 可用、设备已连；payload / roothelper / ksud 已推到
`/data/local/tmp/bakasu/`（可从 RootMyS24 App 的 assets 或 release 产物获取）。

```bash
./scripts/01-exploit.sh     # 拿临时 root（屏幕保持熄灭，1~3 分钟）
./scripts/02-late-load.sh   # 加载 BakaSU 内核 + 安装（约 10 秒）
```

然后打开 **BakaSU 管理器**（`com.resukisu.resukisu` v4.2.0-rc3）即可看到
「工作中 / LKM」并授权 root、装模块。

> ⚠️ 不要点管理器里的「安装/刷入」页面（会写 boot 分区，有变砖风险）。
> 装模块请用「模块」页的安装入口。

## 从源码构建模块

需要：docker + `ghcr.io/ylarod/ddk-min:android14-6.1-20260313` 镜像、
Android NDK r29、cargo-ndk，以及同目录下的 BakaSU 源码仓库（默认 `../bakasu`，
已打 `patches/` 里的补丁并切到 `samsung-port` 分支）。

```bash
./scripts/build-samsung-module.sh
```

产物输出到 `release/`：

- `android14-6.1_kernelsu-e3q-S9280ZCS6DZH3-samsung-35171.ko`
- `ksud-e3q-S9280ZCS6DZH3-samsung-35171`

## RootMyS24 App 集成

RootMyS24（`~/AndroidStudioProjects/RootMyS9280`）的设置里打开
「BakaSU 内核（实验）」后，运行 root 流程会自动：

- 使用 `cve-2026-43499-root-bakasu` 守护进程 + `ksud-bakasu-dzh3`（内嵌模块）；
- 在加载模块前自动安装 `bakasu-manager.apk`；
- 按 `com.resukisu.resukisu` 检测管理器状态。

## 已知限制

- 每次开机需要重新跑（late-load 不持久；这是与 RootMyS9280 一致的 per-boot 模型）；
- `selinux_hide` feature 不可用（依赖 live text patch，RKP 禁止），日志会有一条
  `Failed to set feature selinux_hide`，不影响 root；
- 内核 full_version 字符串显示 `v4.1.0-unknown-dirty@BakaSU`（git tag 问题，纯显示）。

## 许可

脚本与补丁：MIT。BakaSU 源码遵循其上游（GPL）许可。
