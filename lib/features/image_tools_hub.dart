import 'package:flutter/material.dart';

import '../core/app_state.dart';
import 'catalog.dart';
import 'media_page.dart';
import 'workbench.dart';

class ImageToolsHub extends StatelessWidget {
  const ImageToolsHub({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;

  void open(BuildContext context, ImageAction action, String title) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MediaPage(
          tool: ToolSpec(
            tool.id,
            title,
            tool.category,
            tool.description,
            tool.icon,
          ),
          state: state,
          imageAction: action,
        ),
      ),
    );
  }

  Widget entry(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    ImageAction action,
    Color tint,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => open(context, action, title),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: tint, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.arrow_forward_rounded, size: 22),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Workbench(
    tool: tool,
    state: state,
    children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.surfaceContainerLow,
            ],
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome_outlined, size: 32),
            const SizedBox(height: 18),
            Text('让图片，恰到好处。', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('先选择要做的事，再进入专属工作台。处理完成后预览并另存新文件。'),
          ],
        ),
      ),
      const SizedBox(height: 28),
      Text('单张图片', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      const Text('一次专注处理一张，原图保持不变。'),
      const SizedBox(height: 16),
      entry(
        context,
        '裁剪与旋转',
        '裁剪范围、旋转方向、水平翻转',
        Icons.crop_rotate,
        ImageAction.transform,
        const Color(0xff147d73),
      ),
      entry(
        context,
        '尺寸与格式',
        '调整宽度、JPEG 压缩、PNG 转换',
        Icons.aspect_ratio,
        ImageAction.resize,
        const Color(0xff596ac8),
      ),
      entry(
        context,
        '文字水印',
        '为图片添加文字，再预览导出',
        Icons.branding_watermark_outlined,
        ImageAction.watermark,
        const Color(0xffa36b38),
      ),
      const SizedBox(height: 18),
      Text('多张图片', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      const Text('把 2—9 张图片组合到一张画面里。'),
      const SizedBox(height: 16),
      entry(
        context,
        '图片拼图',
        '网格、横向、竖向排列，独立拼图设置',
        Icons.grid_view_rounded,
        ImageAction.collage,
        const Color(0xff9b5a7e),
      ),
    ],
  );
}
