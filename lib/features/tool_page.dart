import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_state.dart';
import '../core/engine.dart';
import '../core/files.dart';
import '../core/background.dart';
import 'catalog.dart';

class ToolPage extends StatefulWidget {
  const ToolPage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<ToolPage> createState() => _ToolPageState();
}

class _ToolPageState extends State<ToolPage> {
  late Map<String, String> values;
  final controllers = <String, TextEditingController>{};
  final qrKey = GlobalKey();
  String? result, error;
  bool busy = false;
  String? hashFile;
  @override
  void initState() {
    super.initState();
    values = widget.tool.defaults;
    for (final field in widget.tool.fields) {
      controllers[field.name] = TextEditingController(text: field.value);
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> guarded(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? '${e.message}${e.offset == null ? '' : '\n字符位置：${e.offset! + 1}'}'
              : '操作失败：${e.toString()}',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void sync() {
    for (final f in widget.tool.fields) {
      if (f.kind != FieldKind.choice && f.kind != FieldKind.toggle) {
        values[f.name] = controllers[f.name]!.text;
      }
    }
  }

  Future<void> calculate() => guarded(() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => result = null);
    sync();
    if (widget.tool.id == 'T07' && hashFile != null) {
      final algorithm = values['算法'];
      final digest =
          await (algorithm == 'MD5'
                  ? md5
                  : algorithm == 'SHA-1'
                  ? sha1
                  : sha256)
              .bind(File(hashFile!).openRead())
              .first;
      final expected = values['预期校验值']!.trim();
      if (mounted) {
        setState(
          () => result =
              '$digest\n文件：${hashFile!.split(Platform.pathSeparator).last}${expected.isEmpty ? '' : '\n${expected.toLowerCase() == digest.toString() ? '校验一致' : '校验不一致'}'}',
        );
      }
      return;
    }
    final output = values.values.any((v) => v.length > 4096)
        ? await compute(evaluateInBackground, {
            'id': widget.tool.id,
            'values': Map<String, String>.of(values),
          })
        : runTool(widget.tool.id, values);
    if (widget.tool.id == 'C06') {
      final validation = QrValidator.validate(data: output);
      if (!validation.isValid) {
        throw const FormatException('内容超过二维码容量，请缩短后重新生成');
      }
      // qr defers capacity validation until the image matrix is constructed.
      try {
        QrImage(validation.qrCode!);
      } on InputTooLongException {
        throw const FormatException('内容超过二维码容量，请缩短后重新生成');
      }
    }
    if (mounted) setState(() => result = output);
    if (widget.tool.id == 'C01') {
      await widget.state.rememberCalculation(values['表达式']!, output);
    }
  });
  Future<void> pickInput() => guarded(() async {
    final picked = await FilePicker.pickFile();
    if (picked == null) return;
    final path = await Files.localCopy(
      picked,
      maxBytes: widget.tool.id == 'T07' ? 104857600 : 2097152,
    );
    if (widget.tool.id == 'T07') {
      setState(() => hashFile = path);
      return;
    }
    final file = File(path);
    if (await file.length() > 2 * 1024 * 1024) {
      throw const FormatException('文本导入上限 2 MB，请缩小数据');
    }
    final text = await file.readAsString();
    final field = widget.tool.fields
        .firstWhere((f) => f.kind == FieldKind.multiline)
        .name;
    controllers[field]!.text = text;
    setState(() => values[field] = text);
  });
  Future<Uint8List> qrBytes() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List();
    } finally {
      image.dispose();
    }
  }

  String exportRecord() {
    sync();
    if (widget.tool.id == 'C05' || widget.tool.id == 'C06') return result ?? '';
    return jsonEncode({
      'app': 'SaiSuite',
      'version': '1.0.0',
      'tool': widget.tool.id,
      'name': widget.tool.name,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'inputs': values,
      'result': result,
      'conditions': widget.tool.hint,
    });
  }

  void reset({bool examples = false}) {
    for (final f in widget.tool.fields) {
      values[f.name] = examples
          ? f.value
          : (f.kind == FieldKind.toggle
                ? 'false'
                : f.kind == FieldKind.choice
                ? f.value
                : '');
      controllers[f.name]!.text = values[f.name]!;
    }
    setState(() {
      result = null;
      error = null;
      hashFile = null;
    });
  }

  Widget field(ToolField f) {
    if (f.kind == FieldKind.toggle) {
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(f.name),
        value: values[f.name] == 'true',
        onChanged: busy ? null : (v) => setState(() => values[f.name] = '$v'),
      );
    }
    if (f.kind == FieldKind.choice) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DropdownButtonFormField<String>(
          key: ValueKey('${f.name}:${values[f.name]}'),
          initialValue: values[f.name],
          isExpanded: true,
          decoration: InputDecoration(labelText: f.name),
          items: f.options
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: busy ? null : (v) => setState(() => values[f.name] = v!),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controllers[f.name],
        enabled: !busy,
        obscureText: f.kind == FieldKind.password,
        minLines: f.kind == FieldKind.multiline ? 4 : 1,
        maxLines: f.kind == FieldKind.multiline ? 8 : 1,
        keyboardType: f.kind == FieldKind.number
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : f.kind == FieldKind.multiline
            ? TextInputType.multiline
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: f.name,
          alignLabelWithHint: true,
        ),
        onChanged: (_) {
          if (hashFile != null) setState(() => hashFile = null);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.tool.name),
      actions: [
        ListenableBuilder(
          listenable: widget.state,
          builder: (context, _) => IconButton(
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
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.tool.description,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (widget.tool.hint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  widget.tool.hint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ...widget.tool.fields.map(field),
            if (widget.tool.fields.any((f) => f.kind == FieldKind.multiline) ||
                widget.tool.id == 'T07')
              OutlinedButton.icon(
                onPressed: busy ? null : pickInput,
                icon: const Icon(Icons.file_open_outlined),
                label: Text(hashFile == null ? '导入文件' : '已选择文件 · 点击更换'),
              ),
            if (hashFile != null)
              TextButton(
                onPressed: () => setState(() => hashFile = null),
                child: const Text('改用文本计算'),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : calculate,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(busy ? '处理中…' : '计算 / 处理'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '清空',
                  onPressed: busy ? null : () => reset(),
                  icon: const Icon(Icons.clear_all),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : () => reset(examples: true),
                child: const Text('填入示例'),
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (result != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '结果',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      if (widget.tool.id == 'C06')
                        Center(
                          child: RepaintBoundary(
                            key: qrKey,
                            child: ColoredBox(
                              color: Colors.white,
                              child: QrImageView(
                                data: result!,
                                size: 240,
                                backgroundColor: Colors.white,
                                errorStateBuilder: (c, e) =>
                                    const Text('内容过长，无法生成二维码'),
                              ),
                            ),
                          ),
                        ),
                      if (widget.tool.id == 'T08')
                        Container(
                          height: 60,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Color(
                              int.parse(result!.substring(1, 7), radix: 16) |
                                  0xff000000,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      SelectableText(
                        result!,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => guarded(() async {
                              await Clipboard.setData(
                                ClipboardData(text: result!),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已复制')),
                                );
                              }
                            }),
                            icon: const Icon(Icons.copy),
                            label: const Text('复制'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => guarded(() async {
                              final path = widget.tool.id == 'C06'
                                  ? await Files.saveBytes(
                                      await qrBytes(),
                                      'saisuite-qr.png',
                                    )
                                  : await Files.saveText(
                                      exportRecord(),
                                      '${widget.tool.id}-result.${widget.tool.id == 'C05' ? 'txt' : 'json'}',
                                    );
                              if (path != null && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已保存')),
                                );
                              }
                            }),
                            icon: const Icon(Icons.save_alt),
                            label: Text(
                              widget.tool.id == 'C06' ? '保存二维码' : '保存记录',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => guarded(() async {
                              if (widget.tool.id == 'C06') {
                                final bytes = await qrBytes();
                                if (!context.mounted) return;
                                await Files.shareBytes(
                                  context,
                                  bytes,
                                  'saisuite-qr.png',
                                );
                              } else {
                                await Files.shareText(context, result!);
                              }
                            }),
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('分享'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (widget.tool.id == 'C01' &&
                widget.state.calculatorHistory.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('计算历史'),
              ...widget.state.calculatorHistory.take(10).map((e) {
                final value = jsonDecode(e) as Map;
                return ListTile(
                  title: Text(value['expression'] as String),
                  subtitle: Text(value['result'] as String),
                  onTap: () =>
                      controllers['表达式']!.text = value['expression'] as String,
                );
              }),
            ],
          ],
        ),
      ),
    ),
  );
}
