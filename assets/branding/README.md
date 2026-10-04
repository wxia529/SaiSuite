# 赛赛工具箱图标

Android 与 Windows 统一使用原 Android 图标的配色和形状：青绿色背景（`#147D73`）、浅色圆角方块（`#F3F7E8`）、浅绿色闪电（`#BEE2AF`）。方块位于左上、左下、右下，闪电位于右上。

`tools/generate_app_icons.py` 是统一几何来源，使用 Python 与 Pillow 运行：

```powershell
python tools/generate_app_icons.py
```

生成本目录的 SVG／PNG、Windows 九尺寸 ICO、Android 五种密度的传统图标，以及 API 26 自适应图标和 API 33 单色主题图标。旧命令 `tools/generate_windows_icon.py` 保留为兼容入口。

Android 自适应前景只有方块和闪电，背景独立铺满，由系统决定圆形或圆角方形轮廓；Windows 与 Android 7 使用完整圆角方形图标。Android 清单的普通／圆形图标均指向 `@mipmap/ic_launcher`。

修改图标后需重新构建程序和安装包；`tools/verify_windows_icon.py` 可核对 Windows 程序／安装器实际内嵌图标。

Android 图标层与主题图标规则见 [Android 官方自适应图标文档](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)。
