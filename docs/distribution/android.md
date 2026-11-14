# Android 安装与自测入口

本页只给可执行入口；真机/模拟器手测仍由人执行。产物目录中的 `<versionName>` 与
`<versionCode>` 由根 `VERSION` 与 gradle 配置派生，本文不写版本字面值。

## 1. 出包

环境：JDK 21、Android SDK 36，在仓库根执行。

```bash
bash scripts/package-android.sh
```

产物目录（仓外）：

```text
${TMPDIR:-/tmp}/purepace-dist/android/<versionName>-<versionCode>/
├── purepace-<versionName>-<versionCode>-debug.apk
├── manifest.json
└── checksums.txt
```

stdout 末尾的 `APK=` 与 `SHA256=` 行可直接对照；`PUREPACE_DIST_ROOT` 可覆盖分发根，
解析结果落在仓库内会被拒绝。`manifest.json` 记录 applicationId、version、versionCode、
commit、sha256、minSdk、targetSdk 与 buildTime。

## 2. 校验

```bash
DIST="${TMPDIR:-/tmp}/purepace-dist/android/<versionName>-<versionCode>"
cd "$DIST"
shasum -a 256 -c checksums.txt
# Linux 回退
sha256sum -c checksums.txt
```

`checksums.txt` 中的 sha256 必须与 `APK=` 对应文件实测一致。

## 3. 安装

```bash
DIST="${TMPDIR:-/tmp}/purepace-dist/android/<versionName>-<versionCode>"
adb install -r "$DIST/purepace-<versionName>-<versionCode>-debug.apk"
```

## 4. 同意门手测顺序

1. 首启拦截：干净安装后首次启动，根视图是独立同意屏；正文含「敏感个人信息」
   「只存在本机」「可以拒绝」「可随时撤回」四条；此时点「开始记录」不进入记录态，
   并出现来自资源的原因文案。
2. 同意：点主按钮「同意」后进入主界面，开跑入口可点击；杀进程重启后仍为已同意。
3. 关于页：从主界面进入「关于」，政策全文由随包资源渲染（不联网），正文与
   `docs/privacy/privacy-policy-zh-Hans.md` 一致；完整隐私政策见
   https://munk.sh/privacy（含 PurePace 专项小节）。
4. 撤回：在关于页点「撤回同意」并确认，回到未同意态，开跑入口再次不可用并出现原因；
   杀进程重启后仍为未同意。

状态口径只有两种：未同意（`unattended`）与已同意（`granted`）；「不同意」不会写入
已同意。本页不声明已发布、已分发或可下载。
