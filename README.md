# SaiSuite · 赛赛工具箱

Android 工具箱，Flutter + Dart + Material 3。v1.3.1 共 **60 项工具**：36 个基础工具、9 个电化学扩展，加上 14 个创作、设备与电解液工具，以及中英数字空格清理。

- PDF：合并、拆分、提取、整理、旋转、图片互转、水印、密码处理、文本提取、文档信息，共 12 项。
- 日常计算 6 项、文本开发 9 项、基础科研计算 6 项、日期时间 4 项。
- 科研栏目合并基础科研与电化学：面积、归一化、理论容量、N/P、浆料、电解液、溶剂配比、参比换算、iR 校正。
- 新增点按科学计算器、配色、图片取色、番茄钟、画板、图片/视频处理、指南针、水平仪、传感器和可校准标尺。
- 提供多盐/添加剂配方、实际称量反算、装电池备料、测试参数和电导率换算。
- 密码默认 14 位；新增只清理中文与英文/数字间空格的工具；图片单张处理与多张拼图分别进入，配色助手提供 12 组五色预设及随机灵感。
- 取色器提供定位圆环和像素放大镜，画板可全屏，PDF 水印按内容、样式、页面分区。
- 新科研工具不自动保存实验数据，支持主动导出与未导出退出提示。统一搜索、分类、入口收藏与三种主题继续保留。
- v1.3 重做计算器、单位转换、随机选择、二维码、番茄钟、视频和指南针；画板铺满可用区域，作品比例自适应。

- v1.3.1 删除循环数据分析、锂金属测试分析、电流积分与容量、梯度配方，科研栏目聚焦配液与装电池的快速计算。

每次正式交付同时保留 **Universal 通用包和三种独立架构包**，当前四种版本都在 `dist/`：

| 版本 | 文件 | 大小 |
|---|---|---:|
| Universal（三种架构） | SaiSuite-1.3.1-universal.apk | 67.95 MiB |
| ARM64 | SaiSuite-1.3.1-arm64-v8a.apk | 32.80 MiB |
| ARM32 | SaiSuite-1.3.1-armeabi-v7a.apk | 30.39 MiB |
| x86_64 | SaiSuite-1.3.1-x86_64.apk | 34.21 MiB |

按设备支持的 CPU 架构选一个安装，四种版本功能相同；不确定架构时使用 Universal。校验值在 `dist/SHA256SUMS.txt`。签名密钥与构建产物不提交到 Git。Android 包名：`io.github.wxia529.saisuite`。

## 文档

- [v1.3.1 范围调整](docs/V1_3_1_GUIDE.md)：移除的工具、升级处理与当前科研功能。
- [v1.3 使用说明](docs/V1_3_GUIDE.md)：八个常用工具新版界面、时间轴、适配画布与指南针。
- [v1.2 使用说明](docs/V1_2_GUIDE.md)：图片独立工作台、五色配色、放大取色、全屏画板与水印分区。
- [使用说明](docs/USER_GUIDE.md)：原工具操作与安装。
- [v1.1 使用说明](docs/V1_1_GUIDE.md)：新增功能、科研数据口径与限制。
- [开发指南](docs/DEVELOPMENT_GUIDE.md)：范围、里程碑、完成定义。
- [下一阶段范围](docs/NEXT_VERSION_SCOPE.md)：点按计算器、配色、计时、画板、媒体与设备工具，以及不保存实验记录的电解液计算。
- [构建说明](docs/BUILD.md)：工具链、签名、构建与测试命令。
- [验收记录](docs/ACCEPTANCE.md)：逐项功能矩阵、设备和验证证据。
- [依赖与许可](docs/DEPENDENCIES.md)：PDF 原生服务与数据来源。
- [电化学后续规划](docs/ELECTROCHEMISTRY_ROADMAP.md)：其余 40 项候选保留后续排期。

## 开发

```powershell
flutter pub get
flutter analyze
flutter test
flutter test integration_test/pdf_test.dart -d emulator-5554
flutter test integration_test/tools_test.dart -d emulator-5554
flutter build apk --release
```

release 构建需要已备份的本地签名材料，见构建说明。运行设备集成测试后，正式构建应保留默认的依赖准备步骤，避免复用测试插件注册缓存。

## 代码

`lib/features/catalog.dart` 注册 60 个工具；`lib/core/engine.dart` 和 `electrolyte.dart` 实现可测试的计算；各工作台负责即时输入和导出。Android 原生服务处理 PDF、媒体、传感器与计时通知。SharedPreferences 仅用于既有应用设置、入口收藏/最近使用、普通计算器历史，以及番茄钟状态和标尺校准。新科研输入/计算结果不写入实验数据库。

当前交付为 Android 版。PDF 不提供 OCR、正文编辑、转 Word 或签名验证；复杂书签、表单、批注关系不保证在页面重组后完整保留。
