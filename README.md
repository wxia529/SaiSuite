# SaiSuite · 赛赛工具箱

Android 与 Windows 工具箱，Flutter + Dart + Material 3。当前开发版 **1.4.1+10**，Android 共 **82 项工具**，Windows 共 **79 项工具**；本轮新增 22 个创作、文字与日常工作台。

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
- v1.4 新增 GitHub 自动更新检查，设置可关闭，保留手动检查与同架构 APK 下载入口。

每次交付同时保留 **Universal 通用包和三种独立架构包**，当前 1.4.1 开发包位于 `dist/development/1.4.1/android/`：

| 版本 | 文件 | 大小 |
|---|---|---:|
| Universal（三种架构） | SaiSuite-1.4.1-universal.apk | 115.20 MiB |
| ARM32 | SaiSuite-1.4.1-armeabi-v7a.apk | 45.86 MiB |
| ARM64 | SaiSuite-1.4.1-arm64-v8a.apk | 51.32 MiB |
| x86_64 | SaiSuite-1.4.1-x86_64.apk | 53.39 MiB |

按设备支持的 CPU 架构选一个安装，四种版本功能相同；不确定架构时使用 Universal。同架构可覆盖升级；校验值在同目录 `SHA256SUMS.txt`。旧包保留。签名密钥与构建产物不提交到 Git。Android 包名：`io.github.wxia529.saisuite`。

## 文档

- [GitHub Actions 与首次推送](docs/GITHUB_ACTIONS.md)：原密钥签名、四包构建、标签发布与 Secrets 配置；测试在本地进行。
- [更新检查与 GitHub 发布](docs/UPDATES.md)：自动检查规则、版本号和四包发布步骤。
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

默认设备测试使用 Android 16（API 36）的 `SaiSuite_API_36` 模拟器，执行前核对实际设备 ID。其他系统版本按兼容需求补充验证，详见 [构建说明](docs/BUILD.md)。

```powershell
flutter pub get
flutter analyze
flutter test
flutter test integration_test/pdf_test.dart -d emulator-5558
flutter test integration_test/tools_test.dart -d emulator-5558
flutter test integration_test/updates_test.dart -d emulator-5558
flutter build apk --release
```

release 构建需要已备份的本地签名材料，见构建说明。运行设备集成测试后，正式构建应保留默认的依赖准备步骤，避免复用测试插件注册缓存。

## 代码

`lib/features/catalog.dart` 注册 82 个工具；`lib/core/engine.dart` 和 `electrolyte.dart` 实现可测试的计算；各工作台负责即时输入和导出。Android 原生服务处理 PDF、媒体、传感器与计时通知。SharedPreferences 仅用于既有应用设置、入口收藏/最近使用、普通计算器历史，以及番茄钟状态和标尺校准。新科研输入/计算结果不写入实验数据库。

当前交付为 Android 版。PDF 不提供 OCR、正文编辑、转 Word 或签名验证；复杂书签、表单、批注关系不保证在页面重组后完整保留。


## Windows 桌面版

新增的 22 个创作、文字与日常工作台见 [扩展功能说明](docs/CREATIVE_TOOLS.md)，包括 GIF、九格、渐变、文字卡片、OCR、拍照计数、音频提取与拼音。开发包单独放在 `dist/development/1.4.1/`，版本为 1.4.1+10。

新增 Windows 10/11 x64 安装版与便携版，版本为 1.4.1+10。安装版运行 -setup.exe，中文向导支持选择目录、快捷方式和卸载；便携版解压完整 ZIP 后运行 saisuite.exe。79 项工具包含 PDF、图片、视频和电解液计算；手机传感器工具仅在 Android 提供。本轮开发包位于 `dist/development/1.4.1/`，上一轮包保留在 `dist/development/windows/`；构建与平台说明见 [Windows 文档](docs/WINDOWS.md)。下一次 tag 构建会同时产出 Android 和两种 Windows 包。
