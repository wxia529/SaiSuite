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
import '../core/electrolyte.dart';
import 'workbench.dart' show message;
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
  bool exported = false, allowExit = false;
  Map<String, String>? resultInputs;
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
        : widget.tool.id.startsWith('N')
        ? runLabTool(widget.tool.id, values)
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
    if (mounted) {
      setState(() {
        result = output;
        exported = false;
        resultInputs = Map.of(values);
      });
    }
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
      'version': '1.2.0',
      'tool': widget.tool.id,
      'name': widget.tool.name,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'inputs': resultInputs ?? values,
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

  Iterable<ToolField> get visibleFields => widget.tool.fields.where((f) {
    if (widget.tool.id == 'N01') {
      if (f.name == '模式') return true;
      final reverse = values['模式'] == '实际称量反算';
      final actual = f.name.startsWith('实际') || f.name == '实测最终体积 mL';
      return reverse ? actual : !actual;
    }
    if (widget.tool.id == 'N05') {
      if (f.name == '电导池常数 cm⁻¹') return values['口径'] == '电导池常数';
      if (f.name == '样品厚度 mm' || f.name == '有效面积 cm²') {
        return values['口径'] == '厚度与面积';
      }
    }
    return true;
  });

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

  Widget resultCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('结果', style: Theme.of(context).textTheme.titleMedium),
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
                    errorStateBuilder: (c, e) => const Text('内容过长，无法生成二维码'),
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
                  int.parse(result!.substring(1, 7), radix: 16) | 0xff000000,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          SelectableText(result!, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => guarded(() async {
                  await Clipboard.setData(ClipboardData(text: result!));
                  if (mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('已复制')));
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
                  if (path != null && mounted) {
                    setState(() => exported = true);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('已保存')));
                  }
                }),
                icon: const Icon(Icons.save_alt),
                label: Text(
                  widget.tool.id == 'C06'
                      ? '保存二维码'
                      : widget.tool.id.startsWith('N')
                      ? '导出结果'
                      : '保存记录',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => guarded(() async {
                  if (widget.tool.id == 'C06') {
                    final bytes = await qrBytes();
                    if (!mounted) return;
                    await Files.shareBytes(context, bytes, 'saisuite-qr.png');
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
  );

  void keyPress(String key) {
    if (key == '=') {
      calculate();
      return;
    }
    final c = controllers['表达式']!;
    final text = c.text;
    final selection = c.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    if (key == 'AC') {
      c.clear();
    } else if (key == '⌫') {
      final from = start == end ? (start - 1).clamp(0, text.length) : start;
      c.value = TextEditingValue(
        text: text.replaceRange(from, end, ''),
        selection: TextSelection.collapsed(offset: from),
      );
    } else {
      final insert = switch (key) {
        '×' => '*',
        '÷' => '/',
        'π' => 'pi',
        'sin' || 'cos' || 'tan' || 'sqrt' || 'ln' || 'log' || 'abs' => '$key(',
        _ => key,
      };
      c.value = TextEditingValue(
        text: text.replaceRange(start, end, insert),
        selection: TextSelection.collapsed(offset: start + insert.length),
      );
    }
    setState(() {
      result = null;
      error = null;
    });
  }

  Widget calculatorKeys() => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: LayoutBuilder(
      builder: (context, box) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children:
            [
                  'AC',
                  '⌫',
                  '(',
                  ')',
                  '7',
                  '8',
                  '9',
                  '÷',
                  '4',
                  '5',
                  '6',
                  '×',
                  '1',
                  '2',
                  '3',
                  '-',
                  '0',
                  '.',
                  '=',
                  '+',
                  'sin',
                  'cos',
                  'tan',
                  '^',
                  'sqrt',
                  'ln',
                  'log',
                  'π',
                  'abs',
                  'e',
                  '%',
                  ',',
                ]
                .map(
                  (key) => SizedBox(
                    width: (box.maxWidth - 18) / 4,
                    height: 52,
                    child: FilledButton.tonal(
                      onPressed: busy ? null : () => keyPress(key),
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                      ),
                      child: Text(key),
                    ),
                  ),
                )
                .toList(),
      ),
    ),
  );

  Future<void> exportLab() async {
    if (result == null) return;
    await guarded(() async {
      final path = await Files.saveText(
        exportRecord(),
        '${widget.tool.id}-result.json',
      );
      if (path != null && mounted) {
        setState(() => exported = true);
        message(context, '已导出到所选文件');
      }
    });
  }

  Future<void> confirmExit() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('结果尚未导出'),
        content: const Text('计算结果不会自动保存。请导出需要保留的结果，或选择放弃。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('继续编辑'),
          ),
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
      await exportLab();
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
    canPop:
        !widget.tool.id.startsWith('N') ||
        allowExit ||
        (result == null || exported) && !busy,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) {
        if (busy) {
          message(context, '处理中，请等待完成');
        } else {
          confirmExit();
        }
      }
    },
    child: Scaffold(
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
              ...visibleFields.map(field),
              if (widget.tool.id == 'C01')
                SizedBox(
                  height: 120,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: SelectableText(
                                result ?? '结果',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '复制结果',
                            onPressed: result == null
                                ? null
                                : () => Clipboard.setData(
                                    ClipboardData(text: result!),
                                  ),
                            icon: const Icon(Icons.copy),
                          ),
                          IconButton(
                            tooltip: '导出结果',
                            onPressed: result == null ? null : exportLab,
                            icon: const Icon(Icons.save_alt),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (widget.tool.id == 'C01') calculatorKeys(),
              if (widget.tool.fields.any(
                    (f) => f.kind == FieldKind.multiline,
                  ) ||
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
              if (result != null && widget.tool.id != 'C01') resultCard(),
              if (widget.tool.id == 'C01' &&
                  widget.state.calculatorHistory.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('计算历史'),
                ...widget.state.calculatorHistory.take(10).map((e) {
                  final value = jsonDecode(e) as Map;
                  return ListTile(
                    title: Text(value['expression'] as String),
                    subtitle: Text(value['result'] as String),
                    onTap: () => controllers['表达式']!.text =
                        value['expression'] as String,
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
