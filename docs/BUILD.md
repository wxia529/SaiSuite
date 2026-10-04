# 构建与签名

记录日期：2026-10-04，版本 `1.3.1+8`，包名 `io.github.wxia529.saisuite`。

## 已验证工具链

| 项目 | 本机配置 |
|---|---|
| Flutter / Dart | 3.47.6 stable / 3.13.5，`E:\apps\flutter` |
| Flutter 构建 Java | Android Studio JBR 25.0.3 |
| 用户终端 Java | JDK 25.0.4.1；与 Flutter 实际构建 Java 区分 |
| Android SDK | `E:\Android\Sdk`，平台 36，Build Tools 36.0.0 |
| NDK / CMake | 28.2.13676358 / 3.22.1 |
| Gradle / AGP | 9.3.1 / 9.1.0 |
| Kotlin | 2.4.0；JVM 17 字节码 |
| 验收设备 | Medium Phone 模拟器，Android 17 / API 37，x86_64，WHPX |

依赖锁定于 `pubspec.lock`。首次构建需要网络下载 SDK、Maven 和 Pub 依赖；应用运行不需要联网。最终 APK 验证 minSdk 24（Android 7.0）、targetSdk 36，三种 ABI。正式 manifest 没有 INTERNET 或广泛文件访问权限，文件通过系统授权 URI 读取和保存。

## 签名保管

当前正式密钥在 `.private/saisuite-release.jks`，配置在 `android/key.properties`，均被 Git 忽略。请将这两个文件一并安全备份，后续升级必须沿用同一密钥；丢失密钥会影响覆盖安装。密码不要放进文档、命令记录、仓库或聊天。

新机器恢复备份后，检查配置中的路径：

```properties
storeFile=../.private/saisuite-release.jks
storePassword=<本地密码>
keyPassword=<本地密码>
keyAlias=saisuite
```

如果构建自己的独立发行版而非升级当前 APK，可用 JDK `keytool -genkeypair` 新建密钥，再配置上述文件。构建脚本拒绝没有签名配置的 release，不会自动回退到 debug 密钥。

## 命令

在工程根目录运行，Flutter 已在 PATH 时可直接调用：

```powershell
flutter pub get
flutter analyze
flutter test
flutter test integration_test/pdf_test.dart -d emulator-5554
flutter test integration_test/tools_test.dart -d emulator-5554
flutter build apk --release
```

最后一步不要在刚运行过设备集成测试后直接加 `--no-pub`：测试入口曾导致生成的插件注册文件包含 integration_test，而 release 不编译该测试插件。正常依赖准备会重新生成正确注册文件。

APK 输出 `build/app/outputs/flutter-apk/app-release.apk`，交付副本 `dist/SaiSuite-1.3.1-universal.apk`。默认 APK 包含 arm64-v8a、armeabi-v7a 与 x86_64。需要独立架构包可另外执行 `flutter build apk --release --split-per-abi`。

交付要求：Universal 与独立架构包同时提供。每次更新先构建并复制保存 Universal，再构建并保存三种独立包，不用独立包替代通用包；四种包来自同一份源码、同一版本号和同一签名密钥，并更新全部校验值。

### 已交付的独立架构包

2026-10-04 已执行：

```powershell
flutter build apk --release --split-per-abi
```

| ABI | dist 文件 | 大小 | versionCode |
|---|---|---:|---:|
| arm64-v8a | SaiSuite-1.3.1-arm64-v8a.apk | 34,389,634 字节 / 32.80 MiB | 2008 |
| armeabi-v7a | SaiSuite-1.3.1-armeabi-v7a.apk | 31,863,886 字节 / 30.39 MiB | 1008 |
| x86_64 | SaiSuite-1.3.1-x86_64.apk | 35,873,406 字节 / 34.21 MiB | 4008 |

Flutter 输出文件名是 `app-<ABI>-release.apk`，交付时复制到上表名称。三包与通用包采用同一签名证书，versionName 均为 1.3.1，compileSdk/targetSdk 为 36，minSdk 为 24。每包只包含对应 ABI；公共代码、资源与对应原生库经 SHA-256 比对，与通用包完全相同。

Flutter 的独立包默认加入 ABI 对应的 versionCode 偏移，因此数值不同于通用包的 8。同架构后续独立包继续增加基础 build number；若改为通用包覆盖已经安装的独立包，通用包 versionCode 必须高于已安装包。当前模拟器安装的是 x86_64 包，versionCode 4008，后续直接安装 versionCode 8 的通用包会被视为降级。

本轮删除四个科研工具，未引入新的媒体架构库或 FFmpeg。四包大小见 README 和验收记录。

每个 APK 有同名 `.sha256` 文件，另汇总到 `dist/SHA256SUMS.txt`；架构、签名与安装检查见验收记录。

```powershell
adb install -r dist/SaiSuite-1.3.1-universal.apk
adb shell am start -n io.github.wxia529.saisuite/.MainActivity
Get-FileHash dist/SaiSuite-1.3.1-universal.apk -Algorithm SHA256
```

debug 使用独立包名 `io.github.wxia529.saisuite.dev`，名称为「赛赛工具箱（测试）」，正式签名仍沿用原密钥。设备集成测试运行器可能在清理阶段卸载包，应使用专用测试模拟器；不要在装有用户正式数据的设备上运行集成测试。v1.1.0 的正式包安装在集成测试之后执行；v1.3.1 从已安装的 v1.3.0 x86_64 包覆盖升级验收。

## 本机问题与处理

- C: Pub 缓存与 E: 项目之间的 Kotlin 增量相对路径失败：`android/gradle.properties` 关闭增量编译，并使用 in-process 编译。
- 新 Android 命令行工具的旧 `sdkmanager.bat` 对 Gradle 自动安装 NDK 的分号参数解析失败。已使用官方新入口安装：

```powershell
E:\Android\Sdk\cmdline-tools\latest\bin\android.exe --no-metrics --sdk=E:\Android\Sdk sdk install ndk/28.2.13676358
E:\Android\Sdk\cmdline-tools\latest\bin\android.exe --no-metrics --sdk=E:\Android\Sdk sdk install platforms/android-36
```

源码只包含 Android 工程。Windows 桌面版和系统开发者模式不是本次构建要求。构建过程的 JDK native-access 警告不影响当前验收，但更换 Java、Flutter 或 Gradle 版本后应重新验证。

当前已在本机执行 `flutter clean` 后完成依赖解析和 release 构建；未在第二台完全干净机器上复现。可复现步骤与版本已记录，不将第二台机器验证视为已经执行。
