# GitHub Actions 与首次推送

仓库：`wxia529/SaiSuite`；默认分支：`main`。当前发布版本为 `1.4.0+9`。

## 已配置的流程

| 触发方式 | 行为 |
|---|---|
| 推送 main、Pull Request，或手动运行 Android checks | 静态分析、Flutter 单元/界面测试、发布脚本测试，以及 API 36 原生 PDF、媒体/设备、更新检查测试 |
| 手动运行 Signed Android packages（选择 main） | 先完成上述测试，再生成四种正式签名 APK 和校验文件；上传 Actions artifact，不创建公开 Release |
| 推送 `vX.Y.Z+构建号` 标签 | 测试、四包构建和校验全部通过后，创建 Release 草稿、上传全部九个附件，再公开并设为最新正式版本 |

固定使用 Flutter 3.47.6、Temurin JDK 17、Android 平台 36、Build Tools 36.0.0、NDK 28.2.13676358、CMake 3.22.1；Gradle/AGP/Kotlin 继续使用仓库配置。JDK 17 满足当前 AGP 要求，字节码仍为 JVM 17。本机使用 JBR 25 不影响签名一致性；不同构建环境生成的 APK 校验值可能不同。

通过固定提交的 `android-actions/setup-android` 显式安装命令行工具 16.0（12266719）和上述 SDK 包，配置 SDK 环境变量、PATH 与许可证；不依赖运行器预装工具是否可直接调用。Flutter 构建前会检查 `sdkmanager` 路径和版本。测试和正式包构建共用此配置。

第三方 Actions 固定到提交 SHA。常规测试不读取签名 Secrets；只有正式包构建读取四项签名 Secrets，发布 job 才获得仓库写权限。PR 不构建正式签名包。CI 临时密钥使用后删除，不纳入构建产物或日志。

API 36 模拟器启动后核对实际设备 ID 和 SDK。媒体测试需要下载官方测试视频，更新检查测试会访问 GitHub API，因此网络异常可能导致设备测试失败，失败时检查 Actions 的日志附件。源码推送不会直接发布 App 更新。

## 首次配置签名 Secrets

在仓库 **Settings → Secrets and variables → Actions → New repository secret** 添加：

| Secret 名称 | 本机来源 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `.private/saisuite-release.jks` 的 Base64 编码 |
| `ANDROID_KEYSTORE_PASSWORD` | `android/key.properties` 的 `storePassword` 值 |
| `ANDROID_KEY_ALIAS` | `android/key.properties` 的 `keyAlias` 值 |
| `ANDROID_KEY_PASSWORD` | `android/key.properties` 的 `keyPassword` 值 |

填写实际密码和别名；如果属性文件使用了反斜线转义，不要把转义符当作密码的一部分。必须使用当前保管的密钥，不要重新生成。工作流会在构建前与构建后核对原证书 SHA-256：

```text
86d06951211ad5412b4dd90079a379b46bbc223933b9891599835ff2dd99b250
```

以下 PowerShell 命令仅将密钥的 Base64 复制到剪贴板，不在终端打印内容；将其粘贴到对应 Secret，然后清空剪贴板。其他三项从本地配置读取并分别填入，不要把密码放进聊天或提交到 Git。

```powershell
Set-Clipboard -Value ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path '.private/saisuite-release.jks'))))
# 在 GitHub 保存 ANDROID_KEYSTORE_BASE64 后清空
Set-Clipboard -Value ''
```

仓库 Actions 设置需允许所固定的 Actions 执行。发布流程使用 GitHub 自动提供的 `GITHUB_TOKEN`，不需要在 App 中加入 Token，也不需要为工作流保存个人访问令牌。默认读取权限在发布 job 中声明提升为 `contents: write`；若组织策略禁止写权限，需要管理员调整策略。

## 推送与首次发布

先将源码推送至 main：

```powershell
git push -u origin main
```

检查 **Android checks** 成功，再手动运行 **Signed Android packages**，下载 artifact，确认四个 APK 可用。手动构建成功后，准备公开发布时创建并推送版本标签：

```powershell
git tag -a 'v1.4.0+9' -m 'SaiSuite v1.4.0'
git push origin 'v1.4.0+9'
```

标签必须与 pubspec 版本和构建号完全一致，应用显示版本必须一致，且 `docs/releases/v1.4.0.md` 必须存在。基础构建号限制在 1–999，以保持现有 ABI 版本码约定。后续发布必须增加基础构建号，且不能降低应用版本。

每次发布包含 `SaiSuite-版本-universal.apk`、`arm64-v8a.apk`、`armeabi-v7a.apk`、`x86_64.apk`，四份同名 `.apk.sha256` 和 `SHA256SUMS.txt`，共九个附件。校验包名、minSdk 24、targetSdk 36、各包版本码、原签名和实际原生架构后才上传。

上传失败时保留草稿，不会公开半成品；重新运行失败的发布 job 可继续上传同一草稿。已经公开的 Release 不允许由脚本覆盖，修复需提升版本/构建号并创建新标签。新的正式 Release 发布后，App 才能检查到它。

GitHub Secrets、首次云端执行与公开发布是独立步骤；本地校验工作流成功并不代表 GitHub 构建已经成功。首次云端运行也用于验证 Ubuntu 运行器的 SDK 下载、资源和网络条件。

## 本地校验发布材料

Python 3.11 或更新版本，仅使用标准库：

```powershell
python -m unittest discover -s tools/tests -v
python tools/release.py version
$env:ANDROID_HOME = 'E:\Android\Sdk'
python tools/release.py verify
```

`verify` 检查当前版本的四包并重算校验文件；不修改 APK。`prepare-signing` 专供 CI 使用，拒绝覆盖已有本地签名配置。`clean-signing` 只清理 CI 临时配置，不删除现有正式密钥。

相关官方资料：[GitHub 工作流语法](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)、[Android Gradle Plugin 9.1 工具链要求](https://developer.android.com/build/releases/agp-9-1-0-release-notes)、[Android SDK 安装 Action](https://github.com/android-actions/setup-android)、[API 模拟器运行 Action](https://github.com/ReactiveCircus/android-emulator-runner)。

2026-10-04 本地验证：actionlint 1.7.12 工作流检查通过、Bash 语法检查通过、11 项发布脚本测试通过；现有 v1.4.0 四包经新脚本验证原签名、版本码、SDK、权限、架构和校验值。真实密钥的 CI 恢复及 Java 属性读取往返也已验证。上述检查不能代替云端执行。

首次云端执行在 SDK 环境初始化失败，日志为 `sdkmanager: command not found`（退出码 127）。已将隐含的预装工具依赖改为上述显式安装步骤；修复后的云端执行结果仍需在推送新提交后验证。
