import 'dart:io';

import 'package:flutter/material.dart';

typedef PdfPreviewLoader = Future<String> Function(int page, int dpi);

class PdfFullPreview extends StatefulWidget {
  const PdfFullPreview({
    super.key,
    required this.pages,
    required this.load,
    this.initial = 0,
  });
  final List<int> pages;
  final PdfPreviewLoader load;
  final int initial;
  @override
  State<PdfFullPreview> createState() => _PdfFullPreviewState();
}

class _PdfFullPreviewState extends State<PdfFullPreview> {
  late final controller = PageController(initialPage: widget.initial);
  late int index = widget.initial;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '第 ${widget.pages[index] + 1} 页 · ${index + 1}/${widget.pages.length}',
      ),
    ),
    body: Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: controller,
            itemCount: widget.pages.length,
            onPageChanged: (v) => setState(() => index = v),
            itemBuilder: (c, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: Center(
                child: PdfThumbnail(
                  page: widget.pages[i],
                  load: widget.load,
                  dpi: 120,
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '上一页',
                onPressed: index == 0
                    ? null
                    : () => controller.previousPage(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              const Text('双指缩放 · 左右翻页'),
              IconButton(
                tooltip: '下一页',
                onPressed: index == widget.pages.length - 1
                    ? null
                    : () => controller.nextPage(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class PdfThumbnail extends StatefulWidget {
  const PdfThumbnail({
    super.key,
    required this.page,
    required this.load,
    this.dpi = 40,
  });
  final int page, dpi;
  final PdfPreviewLoader load;
  @override
  State<PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends State<PdfThumbnail> {
  late Future<String> future = widget.load(widget.page, widget.dpi);
  @override
  void didUpdateWidget(PdfThumbnail old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page || old.dpi != widget.dpi) {
      future = widget.load(widget.page, widget.dpi);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: future,
    builder: (c, s) => s.hasData
        ? Image.file(File(s.data!), fit: BoxFit.contain)
        : s.hasError
        ? const Center(child: Text('页面预览失败'))
        : const Center(child: CircularProgressIndicator()),
  );
}

class PdfPageGrid extends StatefulWidget {
  const PdfPageGrid({
    super.key,
    required this.pages,
    required this.load,
    required this.initialSelection,
  });
  final List<int> pages;
  final PdfPreviewLoader load;
  final Set<int> initialSelection;
  @override
  State<PdfPageGrid> createState() => _PdfPageGridState();
}

class _PdfPageGridState extends State<PdfPageGrid> {
  late final selected = Set<int>.of(widget.initialSelection);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('已选 ${selected.length}/${widget.pages.length} 页'),
    ),
    body: Column(
      children: [
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              onPressed: () => setState(() {
                selected.addAll(List.generate(widget.pages.length, (i) => i));
              }),
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: () => setState(selected.clear),
              child: const Text('清空'),
            ),
            TextButton(
              onPressed: () => setState(() {
                final inverse = List.generate(
                  widget.pages.length,
                  (i) => i,
                ).where((i) => !selected.contains(i)).toList();
                selected
                  ..clear()
                  ..addAll(inverse);
              }),
              child: const Text('反选'),
            ),
          ],
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              childAspectRatio: .65,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: widget.pages.length,
            itemBuilder: (c, i) => Card(
              color: selected.contains(i)
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() {
                  if (!selected.add(i)) selected.remove(i);
                }),
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: PdfThumbnail(
                          page: widget.pages[i],
                          load: widget.load,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: selected.contains(i),
                          onChanged: (_) => setState(() {
                            if (!selected.add(i)) selected.remove(i);
                          }),
                        ),
                        Expanded(child: Text('第 ${widget.pages[i] + 1} 页')),
                        IconButton(
                          tooltip: '全屏预览',
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => PdfFullPreview(
                                pages: widget.pages,
                                load: widget.load,
                                initial: i,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.fullscreen, size: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected.toList()..sort()),
              child: const Text('应用所选页面'),
            ),
          ),
        ),
      ],
    ),
  );
}
