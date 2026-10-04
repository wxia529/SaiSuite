# 图片编辑升级

本次按用户选择接入 `pro_image_editor 14.6.1`，应用版本保持 `1.4.0+9`。这是一项尚未发布的功能更新，不创建新版本标签，也不覆盖已交付的正式 APK。

## 使用方式

进入「图片工具 → 图片编辑」，选择一张图片后进入全屏画布。底部工具分别为裁剪、调整、滤镜、标注、文字和模糊；标注工具包含箭头、直线、矩形、圆圈、局部模糊、马赛克和橡皮。文字可用于标注或水印，图层可以移动和缩放。

顶部提供返回、撤销、重做、导出设置和另存为。按住画布右上方的「按住看原图」可以对照本次载入的图片。尺寸与格式、快速文字水印、多张拼图仍为独立入口。

## 文件和清晰度

- 输入支持 JPEG、PNG、WebP；单张文件上限 30 MB，像素数上限 4000 万。EXIF 方向在进入编辑器前统一校正。
- 图片经过保护性解码，编辑副本的长边不超过 4096 px；大图可能按采样级别缩小，编辑器不会承诺保留超大原图的全部像素。
- 导出支持 JPEG 和 PNG，可选最长边 1024、2048、4096 px，保持比例且不放大小图。JPEG 质量为 50—100，默认 90；PNG 保留透明度，JPEG 将透明区域填为白色。
- 图片输入只读。编辑和撤销历史仅在当前页面的内存中存在，历史最多保留 30 步；无作品库、草稿自动保存或实验记录管理。
- 点击另存为后通过 Android 系统保存界面写入新文件，只有实际写入成功才提示成功。取消保存或保存失败继续保留当前编辑，退出时提示继续编辑、导出或放弃。
- 准备图片和导出的临时文件不会充当用户记录，操作结束后清理；失败遗留的工具缓存由既有启动清理机制处理。

## 实现

`ImageEditorPage` 负责图片选择和准备，`ImageEditingSession` 接入全屏编辑。编辑器生成 PNG 工作副本，Android 原生服务完成最终缩放、JPEG 白底合成和编码，沿用已有的系统另存为接口。

编辑器新增的依赖以 Dart/Flutter 实现为主，没有引入 AI 模型或新的大型原生图像库。实际体积增量以本机正式模式构建结果为准。

中文工具栏和应用主色统一适配。编辑器及根导航注册两套 Material 组件所需的中文本地化资源，保证进入裁剪、文字等子页面时也能正常显示；应用原有页面继续使用既有主题。编辑器及其内置库的许可声明打包在 `assets/licenses/pro-image-editor-NOTICES.txt`，可以在应用开源许可页查看。

## 验证

2026-10-04 在 `SaiSuite_API_36` 上检查，实际设备 ID 为 `emulator-5558`，读取 SDK 确认为 36。

- `flutter analyze` 无问题，117 项单元/界面测试通过，包括图片工具入口、独立拼图和尺寸工具的回归检查。
- 2 项真实设备集成测试通过：透明 PNG、JPEG 白底、缩放尺寸、输入文件不变、缓存清理、中文编辑、撤销重做、导出设置、取消保存仍提示退出，以及成功保存后退出。
- 经 Android 系统保存界面导出的 PNG 拉回电脑后独立解析，尺寸为 320 × 160，透明角落仍为 RGBA `(0, 0, 0, 0)`，中文文字标注保留。
- 实际安装正式模式的 x86_64 测试包，通过系统图片选择器进入编辑器，选择 1:1 裁剪并保存；拉回的 JPEG 为 RGB、160 × 160。应用 crash 日志为空。
- 四种最终测试包全部通过签名、版本号和 ABI 检查，沿用原签名证书，minSdk 24、targetSdk 36；原有 Flutter 引擎及其他原生库与先前正式包逐项一致。

默认使用 Android 16 / API 36；模拟器结果不替代旧设备上的大图内存和实体硬件验证。检查记录为 `.buildlog/image-editor-{analyze,tests,integration}.log`，独立解析的文件为 `image-editor-verified.png` 和 `image-editor-crop.jpg`。

## 开发测试包

以下为正式模式构建的开发测试包，版本仍为 `1.4.0+9`，未创建标签或发布 Release。包单独位于 `dist/development/image-editor/`，未覆盖先前正式交付文件。

| 类型 | 文件 | 大小（MiB） | 相比原本机正式包增加（MiB） | versionCode |
|---|---|---:|---:|---:|
| Universal | [通用测试包](../dist/development/image-editor/SaiSuite-1.4.0-image-editor-universal.apk) | 77.76 | 9.02 | 9 |
| ARM64 | [arm64-v8a 测试包](../dist/development/image-editor/SaiSuite-1.4.0-image-editor-arm64-v8a.apk) | 35.89 | 2.85 | 2009 |
| ARM32 | [armeabi-v7a 测试包](../dist/development/image-editor/SaiSuite-1.4.0-image-editor-armeabi-v7a.apk) | 33.95 | 3.27 | 1009 |
| x86_64 | [模拟器测试包](../dist/development/image-editor/SaiSuite-1.4.0-image-editor-x86_64.apk) | 37.43 | 2.97 | 4009 |

体积增量主要来自编译后的 Dart 编辑器代码。`SHA256SUMS.txt`、每包的 `.apk.sha256` 和 `inspection.json` 位于同一测试目录，记录最终包的校验值、尺寸、版本和证书。

设备集成检查可以在 Windows PowerShell 中运行 `tools/test_image_editor.ps1`，默认检查 `emulator-5558` 的 SDK 确为 36，再执行集成测试。脚本只操作测试自己生成的图片：根据系统保存界面的实际节点，第一次取消、第二次保存；可通过参数指定 Flutter、ADB 和设备路径。记录位于 `.buildlog/image-editor-integration.log` 和 `image-editor-save-stage-*.xml`。直接执行该集成测试文件时，需要手动完成这两次系统保存操作。
