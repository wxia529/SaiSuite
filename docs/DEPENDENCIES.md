# 依赖与实现选择

记录日期：2026-10-04。实际版本锁定在 `pubspec.lock`；Android 原生依赖在 `android/app/build.gradle.kts`。

## PDF

采用 [PdfBox-Android 2.0.27.0](https://github.com/TomRoush/PdfBox-Android)，在 Android 的后台线程内处理文件。此库为 Apache PDFBox 的 Android 移植，项目采用 Apache 2.0 许可证。应用中的开源许可页面包含 LICENSE 与 NOTICE，并在 `assets/licenses/` 保留相应文件。

用同一原生服务完成读取、渲染、页面导入与排序、图片导入、文字提取、水印和密码处理。合并、拆分、提取、排序、旋转使用页面对象与内容流，不把原始页面整体转为位图。文字水印通过系统字体生成透明图像后叠加，支持中文，原页文字层保持独立。

采用 Flutter MethodChannel 隔离平台实现，因此当前 PDF 工作台只提供 Android 版。库选择的功能依据和示例见项目官方 [使用说明](https://github.com/TomRoush/PdfBox-Android) 与 [渲染 API](https://github.com/TomRoush/PdfBox-Android/blob/master/library/src/main/java/com/tom_roush/pdfbox/rendering/PDFRenderer.java)。具体能力仍以本项目的 Android 集成测试为准。

支持普通密码保护 PDF；写入 AES-256 打开密码。没有证书解密、OCR、JPEG2000 的可选解码器或专有文档格式转换。修改可能破坏原签名；跨文档书签、复杂表单、批注关系不保证完整保留。

## Flutter 依赖

| 依赖 | 用途 |
|---|---|
| shared_preferences | 主题、收藏、最近使用与计算器历史 |
| file_picker | 系统文件选择和保存，支持 Android content URI |
| path_provider | 应用临时目录 |
| share_plus | 系统分享 |
| crypto | 文本和文件摘要 |
| qr_flutter | 二维码渲染 |
| timezone | IANA 时区及夏令时 |
| characters | 用户可见 Unicode 字符统计 |
| archive | 多份导出结果打包 ZIP |
| integration_test | Android 原生与 Flutter 关键流程验收 |

计算器使用独立表达式解析器，化学式使用独立解析器。未引入后端、账号、商业 PDF SDK 或外部 AI 服务。Material 图标、布局和应用图标均使用代码与原生矢量资源。

原子量优先使用 [CIAAW 2024 约化标准原子量表](https://ciaaw.org/abridged-atomic-weights.htm)，84 项有标准值与对应不确定度；其余 34 项使用 [PubChem 周期表接口](https://pubchem.ncbi.nlm.nih.gov/rest/pug/periodictable/JSON) 的参考质量数。2026-10-04 下载生成 118 项离线 Dart 常量，生成脚本为 `tools/update_atomic_weights.py`。参考质量数与标准原子量在结果中区分，不计算不确定度传播。时区数据随锁定的 timezone 包版本更新。公式与常量见 [科研口径](SCIENCE.md)。

## 当前机器的构建设置

- 项目在 E:，Pub 缓存在 C:。Kotlin 增量缓存无法处理跨磁盘相对路径，因此项目关闭 Kotlin 增量编译，并采用 in-process 编译策略。
- 使用 Android SDK 平台 36、NDK 28.2.13676358；首次构建还会下载依赖自身需要的平台版本。
- 新版 Android CLI 的旧 `sdkmanager` 包装器不能可靠处理 Gradle 自动安装 NDK 的调用。本机已用官方 `android sdk install` 命令安装对应包。
- 工程同时生成 Android 与 Windows。Windows 专属 PDF/图片/视频组件由 CMake 安装到桌面包中，不加入 Android assets；构建脚本不要求修改系统开发者模式。详见 [Windows 说明](WINDOWS.md)。
- release 使用单独本地签名，不使用默认 debug 密钥。私钥和密码文件不进入 Git。

## v1.1 原生媒体与设备

视频采用 [AndroidX Media3 Transformer 1.11.1](https://developer.android.com/media/media3/transformer)，Android 原生 Gradle 依赖，使用设备编解码器而不捆绑 FFmpeg。Apache 2.0 许可证保存在 assets/licenses/media3-LICENSE.txt 并注册到开源许可页。图片使用 BitmapFactory、ExifInterface 与 Canvas；设备工具使用 SensorManager、屏幕参数和手动标尺校准。番茄钟使用 AlarmManager 与本地通知，新增 POST_NOTIFICATIONS 运行时权限；不请求相机、定位或广泛媒体读取权限。

Android 集成测试下载 AndroidX Media3 的 sample.mp4 测试素材，下载代码只在 integration_test/tools_test.dart 中，不进入正式 APK。该测试需联网，正式应用处理本地文件。


## GitHub 更新检查（v1.4.0）

2026-10-04 创作扩展增加 image 4.10.1（MIT）与 lpinyin 2.0.3（BSD-2-Clause）；Android 增加随包 ML Kit 中文 OCR 16.0.1；Windows 使用系统 Windows.Media.Ocr 中文语言资源。系统相机输出通过 FileProvider 接收，不新增 CAMERA 权限。功能、模型依赖和限制见 [创作扩展](CREATIVE_TOOLS.md)。

使用 Dart 标准库 HttpClient 请求公开仓库 wxia529/SaiSuite 的 GitHub Releases API，不新增第三方包，不嵌入访问令牌。正式应用新增 INTERNET 权限，仅提交更新请求所需的 HTTP 信息，不发送工具输入或实验数据。下载由浏览器处理，不申请安装包权限或后台下载 APK。详见 [更新与发布说明](UPDATES.md)。
