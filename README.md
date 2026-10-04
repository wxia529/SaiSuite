# SaiSuite · 赛赛工具箱

离线 Android 工具箱，Flutter + Dart + Material 3。v1.0.0 包含已确认的 **36 个基础工具 + 10 个电化学扩展，共 46 项**。

- PDF：合并、拆分、提取、整理、旋转、图片互转、水印、密码处理、文本提取、文档信息，共 12 项。
- 日常计算 6 项、文本开发 8 项、科研计算 6 项、日期时间 4 项。
- 电化学：面积、归一化、理论容量、N/P、浆料、电解液、溶剂配比、参比换算、iR 校正、电流积分。
- 统一搜索、分类、收藏排序、最近使用、计算器历史、三种主题；结果可复制、保存和分享。

每次正式交付同时保留 **Universal 通用包和三种独立架构包**，当前四种版本都在 `dist/`：

| 版本 | 文件 | 大小 |
|---|---|---:|
| Universal（三种架构） | SaiSuite-1.0.0-universal.apk | 63.78 MiB |
| ARM64 | SaiSuite-1.0.0-arm64-v8a.apk | 29.79 MiB |
| ARM32 | SaiSuite-1.0.0-armeabi-v7a.apk | 27.35 MiB |
| x86_64 | SaiSuite-1.0.0-x86_64.apk | 31.20 MiB |

按设备支持的 CPU 架构选一个安装，四种版本功能相同；不确定架构时使用 Universal。校验值在 `dist/SHA256SUMS.txt`。签名密钥与构建产物不提交到 Git。Android 包名：`io.github.wxia529.saisuite`。

## 文档

- [使用说明](docs/USER_GUIDE.md)：操作流程、数据口径与限制。
- [开发指南](docs/DEVELOPMENT_GUIDE.md)：范围、里程碑、完成定义。
- [下一阶段范围](docs/NEXT_VERSION_SCOPE.md)：点按计算器、配色、计时、画板、媒体与设备工具，以及不保存实验记录的电解液计算。
- [构建说明](docs/BUILD.md)：工具链、签名、构建与测试命令。
- [验收记录](docs/ACCEPTANCE.md)：逐项功能矩阵、设备和验证证据。
- [依赖与许可](docs/DEPENDENCIES.md)：PDF 原生服务、离线数据来源。
- [电化学后续规划](docs/ELECTROCHEMISTRY_ROADMAP.md)：其余 40 项候选保留后续排期。

## 开发

```powershell
flutter pub get
flutter analyze
flutter test
flutter test integration_test/pdf_test.dart -d emulator-5554
flutter build apk --release
```

release 构建需要已备份的本地签名材料，见构建说明。运行设备集成测试后，正式构建应保留默认的依赖准备步骤，避免复用测试插件注册缓存。

## 代码

`lib/features/catalog.dart` 注册 46 个工具；`lib/core/engine.dart` 实现独立可测试的计算逻辑；`lib/features/pdf_page.dart` 提供 PDF 工作台；Android 的 `PdfService.kt` 在后台线程处理 PDF。主题、收藏和历史使用 SharedPreferences，文件使用系统选择器与保存界面。

当前交付为 Android 版。PDF 不提供 OCR、正文编辑、转 Word 或签名验证；复杂书签、表单、批注关系不保证在页面重组后完整保留。
