# GitHub 更新检查与发布

当前版本：1.4.0+9。公开仓库：[wxia529/SaiSuite](https://github.com/wxia529/SaiSuite)。更新检查不计入工具目录，仍为 60 个工具。

## 使用行为

- 自动检查默认开启，在启动或返回应用时，距离最近请求达到 24 小时才再次请求 GitHub。失败也记为一次尝试，避免频繁联网；手动“检查更新”可立即重试。
- 设置可关闭自动检查，关闭状态保存到下次启动。关闭后仍可手动检查。
- 检查在后台进行，不阻塞工具使用。失败只在更新区域显示原因；GitHub 无正式 Release 时显示“GitHub 暂无正式发布版本”。
- 有新版本时首页显示入口，设置可以查看更新说明。下载通过浏览器打开匹配 APK，随后由用户在系统安装界面确认；应用不会自动下载或自动安装。
- 仅接受固定公开仓库的正式 Release 与 HTTPS 下载地址，不嵌入 GitHub Token，不上传工具输入或实验数据。新增 INTERNET 权限，未新增后台下载或安装包权限。
- 最近发布信息缓存到应用设置，以便再次打开仍可查看此前发现的版本；该缓存不保存实验数据。

## 版本与安装包约定

接口：`https://api.github.com/repos/wxia529/SaiSuite/releases/latest`。使用 GitHub 的最新正式发布，不纳入草稿或预发布版本。

Release 标签支持 `v1.4.0` 或包含构建号的 `v1.4.0+9`。比较主、次、修订版本的整数，避免把 1.10.0 当作小于 1.9.0；同版本的再次发布必须在标签加入更大的构建号。推荐使用包含构建号的标签，发布说明也应注明应用版本及构建号。

每次发布提升 pubspec 的构建号，所有 APK 的 versionCode 必须高于上一版同架构的包。当前基础构建号为 9，Universal 为 9，ARM32 为 1009，ARM64 为 2009，x86_64 为 4009。本项目使用 Flutter 的 ABI 偏移，基础构建号应保持小于 1000；接近此上限前需调整分发与更新识别方案。

附件使用固定文件命名规则：

| 分发类型 | v1.4.0 附件名 |
|---|---|
| Universal | SaiSuite-1.4.0-universal.apk |
| ARM64 | SaiSuite-1.4.0-arm64-v8a.apk |
| ARM32 | SaiSuite-1.4.0-armeabi-v7a.apk |
| x86_64 | SaiSuite-1.4.0-x86_64.apk |

后续附件只替换版本号，架构后缀保持一致。应用按当前已安装包的分发类型匹配附件；独立架构包不回退下载 Universal，避免其较低版本码无法覆盖。缺少对应附件时仅提供发布页，不显示 APK 下载按钮。所有正式版本保持包名与原签名一致。

## 发布步骤

1. 修改 pubspec 版本、构建号和应用显示版本，完成默认 API 36 的测试。
2. 同时生成 Universal 与三个分架构包，校验版本、签名、架构和 SHA-256。四包与汇总 `SHA256SUMS.txt` 都在 dist。
3. 在 GitHub 仓库的 Releases 创建草稿，标签采用如 `v1.4.0+9`；标签应指向本次交付源码提交。填写版本说明，上传四个 APK、对应 .sha256 文件和 SHA256SUMS.txt。
4. 确认附件完整、草稿/预发布状态符合要求后公开发布，并设为最新正式发布。建议先上传到草稿再公开，避免用户检查到尚未上传 APK 的版本。
5. 在同版本 App 中手动检查应显示当前已是最新版本；后续版本需在装有上一版的设备中确认提示、下载链接和覆盖安装。

首次公开 Release 是更新服务开始提供版本信息的前提。创建更新功能本身不会自动发布 GitHub Release；公开发布前应完成本次交付审阅。

## 实现与验证

`lib/core/updates.dart` 处理网络、版本、附件匹配、24 小时节流与缓存；设置/更新说明 UI 在 `lib/features/update_settings.dart`，Android MethodChannel 提供真实版本及浏览器打开。

`test/updates_test.dart` 覆盖版本比较、正式发布过滤、下载地址、附件缺失、HTTP 错误、超限/损坏响应、开关保存、节流、缓存恢复、退出时异步返回及窄屏布局。`integration_test/updates_test.dart` 在 Android 上验证原生桥、真实设置保存、更新页面与真实 GitHub API。测试的新版本说明使用合成 Release，避免为测试发布虚假的公开版本。

官方接口说明：[GitHub Releases REST API](https://docs.github.com/en/rest/releases/releases)。
