# 项目测试约定

用户于 2026-10-04 指定：以后默认在 Android 13（API 33）上进行开发、设备集成测试和安装包检查。

- 优先使用已建立的 `SaiSuite_API_33` 测试模拟器。运行前检查实际设备 ID 与 `ro.build.version.sdk`，不要仅凭端口判断系统版本。
- 当前端口为 `emulator-5556`，可通过 `flutter devices` 或 `adb devices` 核对；端口变化时按实际 ID 执行。
- 最低支持版本、其他 Android 版本和实体硬件的兼容验证按改动需要补充；Android 13 测试不能替代这些验证。
- 测试平台偏好不改变应用的 minSdk、targetSdk 或 compileSdk 设置。
