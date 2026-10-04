# Windows 桌面版

当前版本为 `1.4.1+10`。提供 Windows x64 安装版与 ZIP 便携版；无需安装 Python、Java 或 FFmpeg。安装版运行 `SaiSuite-1.4.1-windows-x64-setup.exe`，便携版解压整个文件夹后双击 `saisuite.exe`，不要只复制 EXE。支持 Windows 10/11 的常规 64 位桌面环境；本轮实测 Windows 10 22H2，Windows 11 尚未单独验证。

安装程序采用中文向导，按当前用户安装，不要求管理员权限；默认目录为 `%LOCALAPPDATA%\Programs\SaiSuite`，可选择其他目录、开始菜单位置和桌面快捷方式。Windows“应用和功能”以及开始菜单均提供卸载入口。稳定的 AppId 保证后续安装沿用已有目录；更新时先关闭应用，安装程序不会强制终止编辑窗口。卸载只删除安装管理的文件，不清除用户偏好、导出结果或用户加入目录的其他文件。

## 功能范围

桌面版提供现有目录中的 79 个工具；未恢复此前删除的 CSV 分析功能，也没有新增实验记录、配方历史或自动保存。

| 工具 | Windows 行为 |
|---|---|
| 日常计算、单位转换、文本、密码、二维码、日期 | 共用 Android 的计算引擎和界面；文件选择和导出使用 Windows 对话框 |
| 科研与电化学、电解液配方 | 独立字段输入、实时计算、复制和主动导出；不保存实验记录 |
| PDF | 合并、拆分、提取、排序、旋转、预览、多选、PDF 转图片、水印、AES-256 加解密、文字提取和信息查看 |
| 图片转 PDF | A4、Letter，以及“按图片尺寸”；多页可各有尺寸，1 px = 1 pt，保留像素、透明度和 EXIF 方向；限单张 1600 万像素、每批 6400 万像素 |
| 图片 | 完整编辑器、尺寸与格式转换、文字水印、模板拼图与长图；EXIF 方向归一，PNG 透明、JPEG 填白 |
| 图片创作与识别 | 渐变、九格、GIF、文字卡片、表情、幻影坦克、JPEG EXIF、图片 OCR、阈值计数；Windows OCR 需要系统中文语言资源，计数支持人工增删 |
| 文字与日常扩展 | 进制、中文数字、上下标、摩斯、迷你英文、选词、拼音；全屏时钟／弹幕、分段秒表、记分与反应力 |
| 视频音轨 | 提取并转为 M4A AAC；没有音轨时明确报错 |
| 配色与取色 | 照片主色、锁色随机、排序、HEX 编辑、色卡导出、环形取色与放大镜 |
| 画板 | 缩放平移、笔触、真实擦除、形状、箭头、可移动文字、透明 PNG、全屏 |
| 视频 | 内嵌播放、时间轴、截帧、剪辑、静音和分辨率/码率调整；MP4 H.264/AAC |
| 番茄钟 | 应用运行、窗口最小化时可弹窗并响铃；关闭程序、电脑休眠时不能保证提醒 |
| 标尺 | 需要用实体尺校准；Windows 缩放 DPI 不能当成屏幕物理尺寸 |
| 指南针、水平仪、传感器 | 三项从 Windows 目录及收藏显示中隐藏；Android 保留 |
| 更新检查 | 默认打开，可关闭；优先匹配 `SaiSuite-版本-windows-x64-setup.exe`，旧发布没有安装程序时回退到 ZIP，不会推荐 Android APK |

PDF 操作生成新文件；扫描 PDF 仍不提供 OCR 或改写原有正文。视频播放依赖 Windows Media Foundation 自带解码器；N/KN 系统需具有媒体功能，特殊视频编码可能无法内嵌播放，但 FFmpeg 可处理的输入仍可剪辑、截帧。

桌面导航使用侧栏，窄窗口改用底部导航。编辑器与画板支持鼠标操作；关闭工具页面时沿用未导出提醒，点击窗口关闭按钮且工具仍打开时也会确认。

## 构建与组成

需要 Flutter 3.47.6、Dart 3.13.5、Visual Studio 的“使用 C++ 的桌面开发”工作负载、Windows SDK、构建用 Python 和 pip。运行便携包不需要这些开发环境。

```powershell
./tools/build_windows.ps1 -Flutter E:/apps/flutter/bin/flutter.bat -Python python
```

脚本准备专属处理组件、解析 Flutter 依赖、构建 Release、复制微软允许分发的 Visual C++ CRT，生成 ZIP、安装 EXE 和各自的 SHA-256。未开启开发者模式时，脚本使用工程内临时插件目录的目录联接，不改系统设置，也不改 Pub 缓存。

安装程序使用 [Inno Setup 6.5.3](https://github.com/jrsoftware/issrc/releases/tag/is-6_5_3)，编译器下载的 SHA-256 固定为 `9345ee029faa0b7aed0818c3d5b227699ef9a496cce79e20c19eb9d6ef2e2c2d`，以便携模式放在 `.buildlog/inno-compiler/`。不向系统安装编译器。配置位于 `windows/installer/SaiSuite.iss`；中文翻译来自同一官方标签的 `Files/Languages/Unofficial/ChineseSimplified.isl`，保留作者信息并补齐 6.5.3 的提示。运行中保护使用 [AppMutex](https://jrsoftware.org/ishelp/topic_setup_appmutex.htm)，安装和卸载均检查应用持有的 `SaiSuite.Desktop`。

处理组件位于便携包的 `backend/`：Python 3.13.7 嵌入式解释器、pypdf、PDFium/pypdfium2、ReportLab、Pillow、PyCryptodome、LGPL shared FFmpeg 8.1。依赖固定版本，下载来源及存档哈希写入 `runtime-manifest.json`；许可与对应 FFmpeg 源码地址随包附带。H.264 使用 Windows 编码器，不引入 x264。桌面组件由 Windows CMake 安装到 EXE 旁边，未加入 Flutter 公共 assets，不会进入 Android APK。

默认产物放在 `dist/development/windows/`，本轮升级包单独放在 `dist/development/1.4.1/windows/`，不覆盖原 Android 正式包。整个文件夹为可运行目录，ZIP 与 `-setup.exe` 均为交付文件；每个程序文件另有 `FILES-SHA256.json`，两种包各有 `.sha256`。程序与安装包没有 Windows Authenticode 证书签名，Windows 可能显示未知发布者提示；Android 密钥仍只用于 Android。

GitHub Actions 仍由 tag 触发。Windows 构建任务与四个 Android 包一起成功后再发布 Release；GitHub 不运行应用测试。下一次正式发布将包含 Windows ZIP、安装 EXE 及两份校验文件，共十三项附件。本轮没有推送、创建标签或发布。

## 验证

- 本轮 Dart 静态分析与 138 项单元/界面测试通过，包括 Windows 更新不误选 APK。
- 随包解释器实际运行五组后端验证：PDF 页序与旋转、透明图片原尺寸与 EXIF、AES-256 密码和中文水印、图片导出、视频截帧与剪辑。
- Windows 真机桌面集成三项通过：原尺寸 PDF/加解密/清理不删除输入、完整图片编辑器初始化；真实剪辑与内嵌播放器；桌面导航、初版 57 项目录（历史验收）、传感器隐藏和 Windows 更新类型。
- Android 16/API 36 两项 PDF/拼图/视频集成回归通过；桌面版不能替代 Android 或实体传感器验证。
- 安装版真实安装、重复安装、快捷方式、本轮 924 个文件、已安装 EXE 启动、运行中安装/卸载拦截与完整卸载通过；卸载保留实际偏好文件、用户加入目录的文件及目录外导出结果。17 项发布脚本测试通过，完整包体积与哈希见 [验收记录](ACCEPTANCE.md)。

Windows 临时输出只在工具箱专属 `TEMP/SaiSuite-cache` 内清理，不会扫描清除共享 TEMP 中的用户输入；集成测试包含两天前的同名前缀输入保护检查。

```powershell
python tools/prepare_windows.py
.buildlog/windows-runtime/python.exe -X utf8 tools/test_windows_backend.py
flutter test integration_test/windows_test.dart -d windows
python tools/build_windows_installer.py
python tools/verify_windows_installer.py
```

视频测试使用 `.buildlog/windows-fixture.mp4`：可用随组件的 FFmpeg `testsrc2` 生成 3 秒 320×240 H.264 片段。测试文件不进入交付包。

安装验证使用 `.buildlog/` 中唯一的中文/空格目录，拒绝覆盖已有安装或桌面快捷方式；检查全部安装文件、快捷方式、注册表卸载入口、重复安装、应用启动、随包后端和运行中的安装/卸载拦截。最后卸载测试安装，并核对用户偏好与保留文件。测试日志和 JSON 报告留在 `.buildlog/`，测试用导出文件不会打入交付包。

本轮 22 项扩展及三项 Windows 创作集成验收见 [扩展功能说明](CREATIVE_TOOLS.md)。安装 EXE 和 ZIP 的实际文件哈希、安装／卸载、运行保护和五组后端验证全部通过；新包体积及哈希见 [验收记录](ACCEPTANCE.md) 最后一节。
