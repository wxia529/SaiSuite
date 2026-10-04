# 构建与调试

版本以 `pubspec.yaml` 为准，发布前检查与标签流程见 [发布流程](RELEASING.md)。

## 环境

| 组件 | 项目配置 |
|---|---|
| Flutter／Dart | 3.47.6 stable／3.13.5；依赖由 `pubspec.lock` 锁定 |
| Android SDK | 平台 36、Build Tools 36.0.0、NDK 28.2.13676358、CMake 3.22.1 |
| Android 构建 | Gradle 9.3.1、AGP 9.1.0、Kotlin 2.4.0，JVM 17 字节码 |
| Java | CI 使用 Temurin 17；本机 Flutter 配置的 JBR 与终端 JDK 可不同，用 `flutter doctor -v` 核对 |
| Android 支持 | minSdk 24；compileSdk／targetSdk 36 |
| Windows | Visual Studio“使用 C++ 的桌面开发”工作负载与 Windows SDK，构建用 Python／pip；目标 Windows 10／11 x64 |

本机 Flutter 位于 `E:/apps/flutter`，Android SDK 位于 `E:/Android/Sdk`；路径是示例，不是项目要求。首次解析依赖和准备构建组件需要网络。终端未配置 PATH 时使用对应完整路径执行命令。

## 日常检查与 Android 调试

```powershell
flutter doctor -v
flutter pub get
flutter analyze
flutter test
python -m unittest discover -s tools/tests -v
adb devices
adb -s <设备ID> shell getprop ro.build.version.sdk
flutter run -d <设备ID>
```

默认选择 `SaiSuite_API_36`，确认实际 SDK 输出 36，不能仅依据模拟器端口判断版本。设备测试示例：

```powershell
flutter test integration_test/pdf_test.dart -d <设备ID>
flutter test integration_test/tools_test.dart -d <设备ID>
flutter test integration_test/updates_test.dart -d <设备ID>
flutter test integration_test/creative_test.dart -d <设备ID>
flutter test integration_test/image_interaction_test.dart -d <设备ID>
```

图片编辑、工作台视频和原尺寸 PDF 验证可使用 `tools/test_image_editor.ps1`、`tools/test_tool_upgrades.ps1`、`tools/test_pdf_original_size.ps1`，先阅读脚本参数和样例准备要求。测试素材不进入发行包。调试包名为 `io.github.wxia529.saisuite.dev`，与正式版分开；使用专用测试设备，测试清理可能卸载调试包。

## Android 签名与交付

本地正式密钥为 `.private/saisuite-release.jks`，配置为 `android/key.properties`，都由 Git 忽略。安全备份两者，后续覆盖升级沿用原密钥；密码不写入仓库或日志。CI 的 Secret 设置见发布流程，`prepare-signing` 专供 CI 使用，不覆盖本地配置。

下面生成带 Universal 标识的通用包与分架构包，并在独立开发目录校验版本、证书、SDK、ABI、OCR 资源和哈希：

```powershell
flutter build apk --release
python tools/package_creative_android.py --universal --output dist/development/current/android
flutter build apk --release --split-per-abi
python tools/package_creative_android.py --split --output dist/development/current/android
```

先保存 Universal，再构建分架构包，避免生成目录重写通用产物。`current/` 是示例输出目录；需要保留不同批次时换成新的目录。正式构建保留默认 pub 步骤，不能在设备测试后直接加 `--no-pub`，否则可能复用测试插件注册。

Flutter 原始输出在 `build/app/outputs/flutter-apk/`；收集后文件名为 `SaiSuite-X.Y.Z-universal.apk`、`-armeabi-v7a.apk`、`-arm64-v8a.apk`、`-x86_64.apk`，带同名 `.sha256`、`SHA256SUMS.txt` 和 `inspection.json`。

Flutter 的分架构 versionCode 采用基础构建号加 ABI 偏移：Universal 加 0、ARM32 加 1000、ARM64 加 2000、x86_64 加 4000。保持原架构升级；通用包较低的 versionCode 不能直接覆盖已安装的分架构包。

## Windows 构建、运行与交付

```powershell
./tools/build_windows.ps1 -Flutter flutter -Python python -OutputDirectory dist/development/current/windows
flutter test integration_test/windows_test.dart -d windows
flutter test integration_test/creative_test.dart -d windows
flutter test integration_test/image_interaction_test.dart -d windows
```

构建脚本准备 Windows 专属处理组件，构建 Release，收集完整运行目录与可分发的 Visual C++ CRT，生成 ZIP、中文安装 EXE 和 SHA-256。安装器使用固定版本与哈希的 Inno Setup 编译器，不安装到系统；桌面运行时不需要用户自行安装 Python、Java 或 FFmpeg。

构建组件位于 `.buildlog/windows-runtime/`，随桌面包置于 `backend/`，没有加入 Android 公共 assets。未开启 Windows 开发者模式时，脚本在工程内使用目录联接处理插件，不更改系统设置或 Pub 缓存。

可按改动执行以下独立检查：

```powershell
.buildlog/windows-runtime/python.exe -X utf8 tools/test_windows_backend.py
python tools/verify_windows_icon.py <程序EXE> <安装EXE>
python tools/verify_windows_installer.py
```

安装验证脚本使用专用测试目录，执行真实安装／卸载；先检查参数，避免与用户安装目录混用。完整文件校验见包内 `FILES-SHA256.json`。Windows 程序没有 Authenticode 签名，Android 密钥不用于 Windows。

## 图标与常见问题

`python tools/generate_app_icons.py` 统一生成 Android 和 Windows 图标；几何和配色说明见 [品牌资源](../assets/branding/README.md)。改图标后重新构建程序和安装器，再核对实际嵌入资源。

- 跨盘 Kotlin 增量缓存问题：项目已关闭增量编译并使用 in-process，配置在 `android/gradle.properties`。
- SDK 工具找不到：核对 Android SDK 路径、命令行工具与 Flutter 实际使用的 Java；CI 通过 `.github/actions/setup/action.yml` 显式安装 SDK，不依赖预装 PATH。
- 正式构建出现测试插件引用：保留构建的默认依赖准备，勿复用 `--no-pub` 的生成注册文件。
- Windows OCR 缺少中文资源或 N／KN 系统缺少媒体能力：按使用指南补齐系统资源；这与开发 SDK 无关。

不要并行运行 Flutter 平台测试与构建。最低系统、实体硬件和不同 Windows 环境的补充验证按改动安排，不把一次模拟器通过当作全部兼容性结论。
