import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import 'catalog.dart';

class Workbench extends StatefulWidget {
  const Workbench({
    super.key,
    required this.tool,
    required this.state,
    required this.children,
    this.dirty = false,
    this.onExport,
    this.blocked = false,
  });
  final ToolSpec tool;
  final AppState state;
  final List<Widget> children;
  final bool dirty;
  final Future<void> Function()? onExport;
  final bool blocked;
  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench> {
  bool allowExit = false;
  Future<void> exit() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('内容尚未导出'),
        content: const Text('当前内容不会自动保存，请选择继续编辑、导出或放弃。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('继续编辑'),
          ),
          if (widget.onExport != null)
            TextButton(
              onPressed: () => Navigator.pop(c, 'export'),
              child: const Text('导出'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'discard'),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (choice == 'export') {
      await widget.onExport?.call();
      return;
    }
    if (choice == 'discard' && mounted) {
      setState(() => allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.blocked && (!widget.dirty || allowExit),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) {
        if (widget.blocked) {
          message(context, '处理中，请先取消或等待完成');
        } else {
          exit();
        }
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.tool.name),
        actions: [
          ListenableBuilder(
            listenable: widget.state,
            builder: (c, _) => IconButton(
              tooltip: '收藏',
              onPressed: () => widget.state.star(widget.tool.id),
              icon: Icon(
                widget.state.favorites.contains(widget.tool.id)
                    ? Icons.star
                    : Icons.star_border,
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: widget.children,
          ),
        ),
      ),
    ),
  );
}

void message(BuildContext context, String text) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

Future<void> copyResult(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) message(context, '已复制');
}
