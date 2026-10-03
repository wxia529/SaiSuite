import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/engine.dart';
import '../core/files.dart';
import 'catalog.dart';

const pdfChannel = MethodChannel('saisuite/pdf');

class PdfInput {
  PdfInput(this.path, this.name, this.password, this.info);
  final String path, name, password;
  final Map<String, dynamic> info;
  int get count => (info['count'] as num).toInt();
}

List<int> parsePages(String text, int count) {
  if (text.trim().isEmpty || text.trim() == '全部') {
    return List.generate(count, (i) => i);
  }
  final selected = <int>{};
  for (final item in text.replaceAll('，', ',').split(',')) {
    final part = item.trim(),
        m = RegExp(r'^(\d+)(?:\s*-\s*(\d+))?$').firstMatch(part);
    if (m == null) throw const FormatException('页码格式如 1,3-5；留空表示全部');
    final a = int.parse(m[1]!), b = int.parse(m[2] ?? m[1]!);
    if (a < 1 || b < a || b > count) {
      throw FormatException('页码应在 1—$count 内，范围按升序填写');
    }
    for (var i = a; i <= b; i++) {
      selected.add(i - 1);
    }
  }
  if (selected.isEmpty) throw const FormatException('至少选择一页');
  return selected.toList();
}

class PdfPage extends StatefulWidget {
  const PdfPage({
    super.key,
    required this.tool,
    required this.state,
    this.initialInput,
  });
  final ToolSpec tool;
  final AppState state;
  final PdfInput? initialInput;
  @override
  State<PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<PdfPage> {
  final inputs = <PdfInput>[], images = <String>[], outputs = <String>[];
  final pageRange = TextEditingController(),
      splitSize = TextEditingController(text: '1'),
      watermark = TextEditingController(text: '赛赛工具箱'),
      newPassword = TextEditingController(),
      margin = TextEditingController(text: '20');
  final undo = <List<int>>[];
  final previews = <String, Future<String>>{};
  final temporary = <String>{};
  List<int> order = [];
  String? error, textResult, watermarkImage;
  bool busy = false, landscape = false, cancelRequested = false;
  String status = '',
      paper = 'A4',
      splitMode = '按单页',
      imageFormat = 'PNG',
      position = 'center';
  int rotation = 90;
  double dpi = 144, opacity = .25, markSize = 24;
  bool get imageMode => widget.tool.id == 'P06';
  PdfInput? get current => inputs.firstOrNull;
  @override
  void initState() {
    super.initState();
    if (widget.initialInput != null) {
      inputs.add(widget.initialInput!);
      order = List.generate(current!.count, (i) => i);
    }
  }

  @override
  void dispose() {
    pdfChannel
        .invokeMethod<void>('cleanup', {'paths': temporary.toList()})
        .catchError((_) {});
    for (final c in [pageRange, splitSize, watermark, newPassword, margin]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<T?> native<T>(String method, Map<String, dynamic> args) =>
      pdfChannel.invokeMethod<T>(method, args);
  Future<void> guarded(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
      cancelRequested = false;
    });
    try {
      await action();
      checkCancellation();
    } catch (e) {
      if (mounted) {
        if (cancelRequested) {
          outputs.clear();
          textResult = null;
        }
        setState(
          () => error = e is PlatformException
              ? e.message
              : e is FormatException
              ? e.message.toString()
              : '处理失败：$e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          status = '';
        });
      }
    }
  }

  void checkCancellation() {
    if (cancelRequested) throw const FormatException('操作已取消，可重新开始');
  }

  Future<void> cancel() async {
    cancelRequested = true;
    await native<void>('cancel', {});
  }

  Future<String?> passwordDialog({bool retry = false}) async {
    final c = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(retry ? '密码错误，请重试' : '输入 PDF 打开密码'),
        content: TextField(controller: c, obscureText: true, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('打开'),
          ),
        ],
      ),
    );
    // Delay disposal until the dialog route has finished its transition.
    Future<void>.delayed(const Duration(seconds: 1), c.dispose);
    return value;
  }

  Future<PdfInput?> inspect(String path, String name) async {
    var password = '';
    while (true) {
      try {
        final raw = await native<Map>('inspect', {
          'path': path,
          'password': password,
        });
        return PdfInput(path, name, password, Map<String, dynamic>.from(raw!));
      } on PlatformException catch (e) {
        if (e.code != 'PASSWORD') rethrow;
        if (!mounted) return null;
        final value = await passwordDialog(retry: password.isNotEmpty);
        if (value == null) return null;
        password = value;
      }
    }
  }

  Future<void> pick() => guarded(() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: imageMode ? ['png', 'jpg', 'jpeg'] : ['pdf'],
    );
    if (result.isEmpty) return;
    checkCancellation();
    if (imageMode) {
      if (images.length + result.length > 100) {
        throw const FormatException('最多 100 张图片');
      }
      for (final file in result) {
        checkCancellation();
        images.add(await Files.localCopy(file));
      }
      setState(() {});
      return;
    }
    final newInputs = <PdfInput>[];
    for (final file in result) {
      checkCancellation();
      setState(() => status = '读取 ${file.name}');
      final path = await Files.localCopy(file);
      final doc = await inspect(path, file.name);
      if (doc != null) newInputs.add(doc);
    }
    if (newInputs.isEmpty) return;
    if (widget.tool.id == 'P01') {
      if (inputs.length + newInputs.length > 30) {
        throw const FormatException('合并最多支持 30 份 PDF');
      }
      inputs.addAll(newInputs);
    } else {
      inputs
        ..clear()
        ..addAll(newInputs.take(1));
    }
    order = List.generate(current!.count, (i) => i);
    undo.clear();
    pageRange.clear();
    setState(() {
      outputs.clear();
      textResult = null;
    });
  });
  Future<String> preview(int page) {
    final doc = current!;
    final key = '${doc.path}:$page';
    return previews.putIfAbsent(key, () async {
      final path = (await native<String>('render', {
        'path': doc.path,
        'password': doc.password,
        'page': page,
        'dpi': 50,
      }))!;
      temporary.add(path);
      return path;
    });
  }

  void rememberOrder() {
    undo.add(List.of(order));
    if (undo.length > 30) undo.removeAt(0);
  }

  Future<void> process() => guarded(() async {
    FocusManager.instance.primaryFocus?.unfocus();
    outputs.clear();
    textResult = null;
    if (imageMode) {
      if (images.isEmpty) throw const FormatException('先选择图片');
      final m = double.tryParse(margin.text);
      if (m == null || !m.isFinite || m < 0) {
        throw const FormatException('请输入有效边距');
      }
      setState(() => status = '生成 PDF');
      final path = await native<String>('images', {
        'images': images,
        'paper': paper,
        'landscape': landscape,
        'margin': m,
      });
      outputs.add(path!);
      temporary.add(path);
      return;
    }
    final doc = current;
    if (doc == null) throw const FormatException('先选择 PDF');
    final selected = parsePages(pageRange.text, doc.count),
        base = <String, dynamic>{
          'path': doc.path,
          'password': doc.password,
          'pages': selected,
        };
    setState(() => status = '处理中，请稍候');
    Future<void> add(String method, Map<String, dynamic> args) async {
      checkCancellation();
      final path = (await native<String>(method, args))!;
      temporary.add(path);
      checkCancellation();
      outputs.add(path);
    }

    switch (widget.tool.id) {
      case 'P01':
        await add('merge', {
          'sources': inputs
              .map((e) => {'path': e.path, 'password': e.password})
              .toList(),
        });
      case 'P02':
        final size = splitMode == '按单页'
            ? 1
            : splitMode == '按范围'
            ? selected.length
            : int.tryParse(splitSize.text);
        if (size == null || size < 1 || size > 500) {
          throw const FormatException('每份页数应在 1—500');
        }
        for (var i = 0; i < selected.length; i += size) {
          setState(() => status = '拆分 ${i + 1}/${selected.length}');
          await add('transform', {
            ...base,
            'pages': selected.sublist(i, (i + size).clamp(0, selected.length)),
          });
        }
      case 'P03':
        await add('transform', base);
      case 'P04':
        await add('transform', {...base, 'pages': order});
      case 'P05':
        await add('transform', {
          ...base,
          'pages': List.generate(doc.count, (i) => i),
          'rotation': rotation,
          'rotationPages': selected,
        });
      case 'P07':
        for (final page in selected) {
          setState(() => status = '导出第 ${page + 1} 页');
          await add('render', {
            ...base,
            'page': page,
            'dpi': dpi,
            'format': imageFormat,
          });
        }
      case 'P08':
        await add('watermark', {
          ...base,
          'text': watermark.text,
          'image': watermarkImage,
          'opacity': opacity,
          'size': markSize,
          'position': position,
        });
      case 'P09':
        if (newPassword.text.isEmpty) throw const FormatException('请输入新密码');
        await add('encrypt', {...base, 'newPassword': newPassword.text});
        newPassword.clear();
      case 'P10':
        await add('decrypt', base);
      case 'P11':
        textResult = (await native<String>('text', base))!;
        if (textResult!
            .replaceAll(RegExp(r'--- 第 \d+ 页 ---'), '')
            .trim()
            .isEmpty) {
          textResult = '未提取到文字层。扫描件或文字转曲的 PDF 需要 OCR；当前版本不提供 OCR。';
        }
      case 'P12':
        textResult = infoText(doc);
    }
    setState(() {});
  });
  String infoText(PdfInput doc) {
    final p = doc.info['pages'] as List;
    return '文件：${doc.name}\n页数：${doc.count}\n大小：${fmt((doc.info['bytes'] as num) / 1024)} KiB\n加密：${doc.info['encrypted']}\n标题：${doc.info['title']}\n作者：${doc.info['author']}\n主题：${doc.info['subject']}\n生成软件：${doc.info['producer']}\n表单：${doc.info['forms']}\n签名：${doc.info['signed']}\n\n${p.indexed.map((e) {
      final d = e.$2 as Map;
      return '第 ${e.$1 + 1} 页：${fmt(d['width'] as num)} × ${fmt(d['height'] as num)} pt；旋转 ${d['rotation']}°';
    }).join('\n')}';
  }

  Future<(Uint8List, String)> exportData() async {
    if (outputs.isEmpty) throw const FormatException('请先处理文件');
    if (outputs.length == 1) {
      final path = outputs.single;
      return (
        await File(path).readAsBytes(),
        '${widget.tool.id}-result.${path.split('.').last}',
      );
    }
    final archive = Archive();
    var bytes = 0;
    for (final (i, path) in outputs.indexed) {
      final content = await File(path).readAsBytes();
      bytes += content.length;
      if (bytes > 200 * 1024 * 1024) {
        throw const FormatException('打包超过 200 MB，请减少选中页面');
      }
      archive.addFile(
        ArchiveFile(
          '${widget.tool.id}-${(i + 1).toString().padLeft(3, '0')}.${path.split('.').last}',
          content.length,
          content,
        ),
      );
    }
    return (
      Uint8List.fromList(ZipEncoder().encode(archive)),
      '${widget.tool.id}-results.zip',
    );
  }

  Widget dropdown(
    String title,
    List<String> values,
    String value,
    void Function(String) update,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$title:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: title),
      items: values
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: busy ? null : (v) => setState(() => update(v!)),
    ),
  );
  Widget orderList() => SizedBox(
    height: 400,
    child: ReorderableListView.builder(
      itemCount: order.length,
      onReorderItem: (old, next) {
        if (busy) return;
        rememberOrder();
        setState(() => order.insert(next, order.removeAt(old)));
      },
      itemBuilder: (context, index) {
        final page = order[index];
        return Card(
          key: ValueKey('$index:$page'),
          child: ListTile(
            leading: SizedBox(
              width: 48,
              height: 65,
              child: FutureBuilder<String>(
                future: preview(page),
                builder: (c, s) => s.hasData
                    ? Image.file(File(s.data!), fit: BoxFit.contain)
                    : const Icon(Icons.description_outlined),
              ),
            ),
            title: Text('第 ${page + 1} 页'),
            subtitle: Text('输出顺序 ${index + 1}'),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: '复制页面',
                  onPressed: busy
                      ? null
                      : () {
                          if (order.length >= 500) return;
                          rememberOrder();
                          setState(() => order.insert(index + 1, page));
                        },
                  icon: const Icon(Icons.copy, size: 18),
                ),
                IconButton(
                  tooltip: '删除页面',
                  onPressed: busy || order.length == 1
                      ? null
                      : () {
                          rememberOrder();
                          setState(() => order.removeAt(index));
                        },
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
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
      body: !Platform.isAndroid
          ? const Center(child: Text('PDF 工作台在 Android 版提供。'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      widget.tool.description,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '本地处理，导出新文件。最多 500 页 / 单文件 100 MB；合并最多 30 份。修改后原签名可能失效；跨文档书签、表单和批注关系不保证完整保留。',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: busy ? null : pick,
                      icon: Icon(
                        imageMode
                            ? Icons.add_photo_alternate_outlined
                            : Icons.file_open_outlined,
                      ),
                      label: Text(
                        imageMode
                            ? '选择 / 添加图片'
                            : widget.tool.id == 'P01'
                            ? '选择 / 添加 PDF'
                            : '选择 PDF',
                      ),
                    ),
                    if (images.isNotEmpty)
                      SizedBox(
                        height: 240,
                        child: ReorderableListView.builder(
                          itemCount: images.length,
                          onReorderItem: (a, b) {
                            setState(
                              () => images.insert(b, images.removeAt(a)),
                            );
                          },
                          itemBuilder: (c, i) => ListTile(
                            key: ValueKey('$i:${images[i]}'),
                            leading: Image.file(
                              File(images[i]),
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                            title: Text('图片 ${i + 1}'),
                            trailing: IconButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(() => images.removeAt(i)),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        ),
                      ),
                    if (inputs.isNotEmpty && widget.tool.id == 'P01')
                      SizedBox(
                        height: 240,
                        child: ReorderableListView.builder(
                          itemCount: inputs.length,
                          onReorderItem: (a, b) {
                            setState(
                              () => inputs.insert(b, inputs.removeAt(a)),
                            );
                          },
                          itemBuilder: (c, i) => ListTile(
                            key: ValueKey('$i:${inputs[i].path}'),
                            leading: const Icon(Icons.picture_as_pdf),
                            title: Text(inputs[i].name),
                            subtitle: Text('${inputs[i].count} 页'),
                            trailing: IconButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(() => inputs.removeAt(i)),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        ),
                      ),
                    if (current != null && widget.tool.id != 'P01') ...[
                      Card(
                        child: ListTile(
                          title: Text(current!.name),
                          subtitle: Text(
                            '${current!.count} 页 · ${fmt((current!.info['bytes'] as num) / 1024)} KiB',
                          ),
                        ),
                      ),
                      if (widget.tool.id != 'P04')
                        SizedBox(
                          height: 200,
                          child: FutureBuilder<String>(
                            future: preview(0),
                            builder: (c, s) => s.hasData
                                ? Image.file(File(s.data!), fit: BoxFit.contain)
                                : s.hasError
                                ? const Center(child: Text('预览失败，仍可尝试文件处理'))
                                : const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                          ),
                        ),
                      if (widget.tool.id == 'P04') ...[
                        Row(
                          children: [
                            const Expanded(child: Text('拖动页面调整顺序')),
                            TextButton.icon(
                              onPressed: undo.isEmpty || busy
                                  ? null
                                  : () => setState(
                                      () => order = undo.removeLast(),
                                    ),
                              icon: const Icon(Icons.undo),
                              label: const Text('撤销'),
                            ),
                          ],
                        ),
                        orderList(),
                      ],
                      if ([
                        'P02',
                        'P03',
                        'P05',
                        'P07',
                        'P08',
                        'P11',
                      ].contains(widget.tool.id))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: TextField(
                            controller: pageRange,
                            enabled: !busy,
                            decoration: const InputDecoration(
                              labelText: '页面范围',
                              hintText: '1,3-5；留空为全部',
                            ),
                          ),
                        ),
                    ],
                    if (widget.tool.id == 'P02') ...[
                      dropdown(
                        '拆分方式',
                        ['按单页', '按范围', '每份固定页数'],
                        splitMode,
                        (v) => splitMode = v,
                      ),
                      if (splitMode == '每份固定页数')
                        TextField(
                          controller: splitSize,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '每份页数'),
                        ),
                    ],
                    if (widget.tool.id == 'P05')
                      dropdown(
                        '顺时针旋转',
                        ['90', '180', '270'],
                        '$rotation',
                        (v) => rotation = int.parse(v),
                      ),
                    if (imageMode) ...[
                      dropdown('纸张', ['A4', 'Letter'], paper, (v) => paper = v),
                      SwitchListTile(
                        title: const Text('横向纸张'),
                        value: landscape,
                        onChanged: busy
                            ? null
                            : (v) => setState(() => landscape = v),
                      ),
                      TextField(
                        controller: margin,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: '边距 mm'),
                      ),
                    ],
                    if (widget.tool.id == 'P07') ...[
                      dropdown(
                        '图片格式',
                        ['PNG', 'JPEG'],
                        imageFormat,
                        (v) => imageFormat = v,
                      ),
                      Text('清晰度：${dpi.round()} dpi（长边上限 4096 px）'),
                      Slider(
                        value: dpi,
                        min: 72,
                        max: 300,
                        divisions: 19,
                        onChanged: busy ? null : (v) => setState(() => dpi = v),
                      ),
                    ],
                    if (widget.tool.id == 'P08') ...[
                      TextField(
                        controller: watermark,
                        decoration: const InputDecoration(
                          labelText: '文字水印（最多 128 字符）',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => guarded(() async {
                                final file = await FilePicker.pickFile(
                                  type: FileType.image,
                                );
                                if (file != null) {
                                  final path = await Files.localCopy(file);
                                  if (mounted) {
                                    setState(() => watermarkImage = path);
                                  }
                                }
                              }),
                        icon: const Icon(Icons.image_outlined),
                        label: Text(
                          watermarkImage == null ? '或选择图片水印' : '已选图片水印',
                        ),
                      ),
                      if (watermarkImage != null)
                        TextButton(
                          onPressed: () =>
                              setState(() => watermarkImage = null),
                          child: const Text('改用文字'),
                        ),
                      dropdown(
                        '位置',
                        ['center', 'top', 'bottom'],
                        position,
                        (v) => position = v,
                      ),
                      Text('透明度 ${(opacity * 100).round()}%'),
                      Slider(
                        value: opacity,
                        min: .05,
                        max: 1,
                        onChanged: busy
                            ? null
                            : (v) => setState(() => opacity = v),
                      ),
                      Text('大小 ${markSize.round()} pt'),
                      Slider(
                        value: markSize,
                        min: 8,
                        max: 96,
                        onChanged: busy
                            ? null
                            : (v) => setState(() => markSize = v),
                      ),
                    ],
                    if (widget.tool.id == 'P09')
                      TextField(
                        controller: newPassword,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '新打开密码（不保存）',
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: busy ? null : process,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        busy
                            ? status.isEmpty
                                  ? '处理中…'
                                  : status
                            : '处理 / 查看',
                      ),
                    ),
                    if (busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      TextButton(
                        onPressed: cancel,
                        child: const Text('取消当前操作'),
                      ),
                    ],
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (outputs.isNotEmpty || textResult != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                textResult != null
                                    ? '结果'
                                    : '已生成 ${outputs.length} 份文件',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (textResult != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: SelectableText(textResult!),
                                ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: busy
                                        ? null
                                        : () => guarded(() async {
                                            if (textResult != null) {
                                              await Files.saveText(
                                                textResult!,
                                                '${widget.tool.id}-result.txt',
                                              );
                                            } else {
                                              final (bytes, name) =
                                                  await exportData();
                                              await Files.saveBytes(
                                                bytes,
                                                name,
                                              );
                                            }
                                          }),
                                    icon: const Icon(Icons.save_alt),
                                    label: Text(
                                      outputs.length > 1 ? '保存 ZIP' : '另存为',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: busy
                                        ? null
                                        : () => guarded(() async {
                                            if (textResult != null) {
                                              await Files.shareText(
                                                context,
                                                textResult!,
                                              );
                                            } else {
                                              final (bytes, name) =
                                                  await exportData();
                                              if (mounted) {
                                                await Files.shareBytes(
                                                  context,
                                                  bytes,
                                                  name,
                                                );
                                              }
                                            }
                                          }),
                                    icon: const Icon(Icons.share_outlined),
                                    label: const Text('分享'),
                                  ),
                                  if (textResult != null)
                                    OutlinedButton.icon(
                                      onPressed: () => Clipboard.setData(
                                        ClipboardData(text: textResult!),
                                      ),
                                      icon: const Icon(Icons.copy),
                                      label: const Text('复制'),
                                    ),
                                  if (outputs.length == 1 &&
                                      outputs.first.endsWith('.pdf'))
                                    OutlinedButton.icon(
                                      onPressed: busy
                                          ? null
                                          : () => guarded(() async {
                                              final d = await inspect(
                                                outputs.single,
                                                '上次处理结果',
                                              );
                                              if (d != null) {
                                                setState(() {
                                                  inputs
                                                    ..clear()
                                                    ..add(d);
                                                  order = List.generate(
                                                    d.count,
                                                    (i) => i,
                                                  );
                                                  undo.clear();
                                                  pageRange.clear();
                                                  outputs.clear();
                                                });
                                              }
                                            }),
                                      icon: const Icon(Icons.arrow_forward),
                                      label: const Text('继续处理此文件'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (current != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Wrap(
                          spacing: 8,
                          children: tools
                              .where(
                                (t) =>
                                    t.pdf &&
                                    t.id != widget.tool.id &&
                                    t.id != 'P06',
                              )
                              .map(
                                (t) => ActionChip(
                                  label: Text(t.name),
                                  onPressed: busy
                                      ? null
                                      : () {
                                          widget.state.visit(t.id);
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute<void>(
                                              builder: (_) => PdfPage(
                                                tool: t,
                                                state: widget.state,
                                                initialInput: current,
                                              ),
                                            ),
                                          );
                                        },
                                ),
                              )
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    ),
  );
}
