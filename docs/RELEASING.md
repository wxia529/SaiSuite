# 发布流程

仓库为 `wxia529/SaiSuite`，默认分支 `main`。工作流配置在 `.github/workflows/release.yml`，发布检查实现为 `tools/release.py`。版本与构建号以源码为准，正式更新说明集中在 `docs/releases/`。

## 准备版本与文档

只有用户明确要求升级时修改版本。同步 `pubspec.yaml` 的 `X.Y.Z+BUILD` 与 `lib/core/updates.dart` 的 `appVersion`，基础构建号严格增加并保持在 1—999；保持包名、原签名与 ABI 偏移规则。

在 `docs/releases/vX.Y.Z.md` 写该版实际改动、兼容条件和升级注意事项，更新 [发布索引](releases/README.md)。不写未实现的候选功能，不把本地构建描述成 GitHub 已发布，不在更新说明中堆叠工具数量或开发过程。

提交标题和正文都不含版本号或构建号，版本仍记录于源码、发布说明和 tag。例如：

```text
fix: refine image interactions and unify app branding
docs: consolidate guides and release documentation
```

这是后续提交约定，不重写已有历史提交。

## 本地检查与构建

```powershell
flutter analyze
flutter test
python -m unittest discover -s tools/tests -v
python tools/release.py version
```

根据本版改动补充 Android API 36、Windows、最低系统及实体硬件检查，核对实际设备。具体构建命令见 [构建说明](BUILD.md)。GitHub 不运行应用测试，发布前必须在本地完成必要验证；CI 仍保留版本、签名、架构与附件校验。

开发包放入独立的 `dist/development/` 目录，不覆盖此前交付文件。正式分发同时包含 Universal、ARM32、ARM64、x86_64 APK、Windows 安装版与 ZIP 便携版；重新构建后重算校验值，不能沿用旧版本哈希或仅重命名安装包。

## Actions 与 tag

| 触发方式 | 行为 |
|---|---|
| 普通源码 push／Pull Request | 不启动构建、测试或发布 |
| 手动运行 **Android and Windows packages**，选择 main | 构建并校验两平台包，上传 Actions artifacts，不公开 Release |
| 推送匹配源码的 `vX.Y.Z+BUILD` tag | 两平台构建成功后上传完整附件到草稿，校验后公开 Release |

发布前将经过检查的改动提交，再推送源码和对应 tag。以下为当前版本示例，执行 tag 推送就是正式发布操作：

```powershell
git push origin main
git tag -a 'v1.4.2+11' -m 'Publish verified application packages'
git push origin 'v1.4.2+11'
```

tag 必须指向实际构建提交，必须与源码版本／构建号一致，且对应的发布说明存在。工作流使用该说明作为 GitHub Release 正文；正式公开后再更新发布索引状态，记录 tag、实际发布日期及 Release 链接。

发布附件包含四个 APK、四份单包校验和 `SHA256SUMS.txt`，以及 Windows 安装 EXE／ZIP 和各自校验文件。脚本核对版本、包名、SDK、ABI、原证书、大小、SHA-256 和草稿附件完整性后公开；任何平台失败或附件缺失时保留草稿，不公开半成品。重新运行失败 job 可继续同一草稿；已经公开的版本不覆盖，修复使用新版本与构建号。

## 签名与 CI 配置

本地密钥和配置在 `.private/saisuite-release.jks` 与 `android/key.properties`，不提交、不输出密码。迁移环境时备份这两者并核对路径；不能重新生成密钥来覆盖已有应用。

仓库 Actions Secrets 配置如下；由密钥和属性文件提供，不能放入文档或提交内容：

| Secret | 内容 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | 原 keystore 的 Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 原密钥别名 |
| `ANDROID_KEY_PASSWORD` | 原密钥密码 |

CI 恢复临时密钥并在使用后删除，构建前后强制核对证书 SHA-256：

```text
86d06951211ad5412b4dd90079a379b46bbc223933b9891599835ff2dd99b250
```

第三方 Actions 固定到提交 SHA，Android 通过显式 setup 安装 SDK，Flutter 与 Java 版本固定。构建任务只读取权限，发布 job 才取得 `contents: write`；由 GitHub 提供 `GITHUB_TOKEN`，应用不包含 Token。不同构建环境可产生不同 APK 哈希，签名一致不要求文件字节完全相同。

## 应用更新行为

应用读取固定仓库的 GitHub 最新正式 Release，忽略草稿和预发布，按主／次／补丁和构建号比较版本。Android 优先匹配当前已安装包的架构，缺少附件时只提供发布页；不将分架构包回退为低 versionCode 的 Universal。Windows 优先安装 EXE，缺少时回退 ZIP。

下载按钮对合法附件 URL 加 `https://gh-proxy.org/` 前缀，原标签编码和文件名保留；Dart、Windows 与 Android 打开入口均检查固定源和固定代理。元数据查询及发布页仍直接使用 GitHub，缓存保存原附件 URL，浏览器处理下载，系统／安装器处理升级。详细使用行为见 [使用指南](USER_GUIDE.md)。
