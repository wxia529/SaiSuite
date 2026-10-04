# 依赖、许可与数据

实际版本以 `pubspec.lock`、`android/app/build.gradle.kts`、`windows/backend/requirements.txt` 和构建脚本为准。开源许可页由 Flutter 许可注册及 `assets/licenses/` 提供；分发的桌面组件同时带许可证和来源说明。

## Flutter 与字体

| 依赖 | 用途 |
|---|---|
| shared_preferences | 应用偏好、收藏、最近使用、普通计算器历史等既有状态 |
| file_picker、path_provider、share_plus | 系统文件选择／保存、缓存和分享 |
| crypto、qr_flutter、timezone、characters、archive | 摘要、二维码、时区、Unicode 用户字符和 ZIP |
| pro_image_editor 14.6.1、material_ui | 全屏图片编辑及所需 UI／本地化 |
| video_player 2.14.1、video_player_win 3.3.0 | Android 与 Windows 内嵌视频播放 |
| image 4.10.1、lpinyin 2.0.3 | 图片创作与 GIF，中文拼音 |
| integration_test、flutter_test、flutter_lints | 开发测试与静态检查，不作为用户功能 |

彩色 emoji 使用未修改的 Noto Emoji Windows-compatible 字体，按 SIL OFL 1.1 分发；精确来源、提交和 SHA-256 见 [字体说明](../assets/fonts/README.md)。许可在 `assets/licenses/noto-emoji-LICENSE.txt`，已注册到应用许可页。图标使用项目自有矢量几何，见 [品牌资源](../assets/branding/README.md)。

## Android

- PDF 使用 PdfBox-Android 2.0.27.0（Apache 2.0），后台线程处理，许可与 NOTICE 随包提供。页面重组保留页面对象和内容流，中文文字水印以透明图像叠加；不提供正文编辑、扫描 OCR、签名验证或可选 JPEG2000 解码。
- 视频导出使用 AndroidX Media3 Transformer／Effect 1.11.1（Apache 2.0）及设备编解码器，不捆绑 FFmpeg。
- 图片使用 BitmapFactory、ExifInterface 与 Canvas；设备工具使用 SensorManager；番茄钟使用 AlarmManager 与通知。
- 中英文图片 OCR 使用随包 ML Kit 中文识别依赖 16.0.1，模型按 Google 条款提供。相机通过系统应用和 FileProvider 返回单个输出，不请求 CAMERA 或广泛文件权限。
- 更新检查使用标准 Dart HttpClient，INTERNET 权限用于 HTTPS；提醒使用 POST_NOTIFICATIONS 运行时权限，文件通过系统选择器授权。应用不嵌入 GitHub Token，不上传工具输入或实验数据，不申请自动安装包权限。

## Windows

PDF／图片／视频通过独立的嵌入式 Python 3.13.7 组件处理，包含 pypdf、pypdfium2／PDFium、ReportLab、Pillow、PyCryptodome 和 LGPL shared FFmpeg。精确版本由 `windows/backend/requirements.txt` 和 `tools/prepare_windows.py` 固定，下载来源、存档哈希与版本写入包内 `runtime-manifest.json`。

许可证包含 Python PSF、pypdf BSD-3-Clause、PDFium 及其第三方许可、ReportLab BSD、Pillow HPND、PyCryptodome 许可和 FFmpeg LGPL／所引用许可。FFmpeg 使用可替换的共享库和 Windows H.264 编码器，不引入 x264；完整来源与对应源码地址随 `THIRD-PARTY-NOTICES.txt` 分发。OCR 使用 Windows.Media.Ocr，中文语言资源由系统提供，视频播放依赖 Windows Media Foundation。

安装器使用 Inno Setup 6.5.3，来源和下载哈希固定于 `tools/build_windows_installer.py`，中文语言文件保留其作者说明。微软 Visual C++ CRT 按 Visual Studio 可再分发许可收集。桌面组件只随 Windows 包提供，不进入 Android APK。

## 科研数据

原子量采用 CIAAW 2024 约化标准表，无标准原子量的元素采用 PubChem 参考质量数，应用区分两种口径。生成脚本为 `tools/update_atomic_weights.py`；常量和公式见 [科研口径](SCIENCE.md)。时区数据随锁定的 timezone 包更新，不把显示小数位当作实验精度。

后续更新依赖需同时核对许可证、平台支持、模型／字体体积和实际构建结果；不能只修改文档中的版本。用户操作、限制与平台差异统一在 [使用指南](USER_GUIDE.md) 维护。
