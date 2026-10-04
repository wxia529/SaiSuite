import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' as editor_ui;
import 'package:pro_image_editor/pro_image_editor.dart';

import '../core/app_state.dart';
import '../core/platform_channel.dart';
import '../core/files.dart';
import '../core/localizations.dart';
import 'catalog.dart';
import 'image_editor_strings.dart';
import 'workbench.dart';

const imageEditorChannel = SaiChannel('saisuite/media');

class ImageEditorPage extends StatefulWidget {
  const ImageEditorPage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;

  @override
  State<ImageEditorPage> createState() => _ImageEditorPageState();
}

class _ImageEditorPageState extends State<ImageEditorPage> {
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? prepared;
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      if (picked == null || !mounted) return;
      final source = await Files.localCopy(picked, maxBytes: 30 * 1024 * 1024);
      final result = await imageEditorChannel.invokeMapMethod<String, dynamic>(
        'imagePrepareEditor',
        {'path': source},
      );
      prepared = result?['path'] as String?;
      if (prepared == null) throw const FormatException('没有生成可编辑的图片');
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ImageEditingSession(
            sourcePath: prepared!,
            sourceName: picked.name,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (prepared != null) {
        await _cleanOutputs([prepared]);
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Workbench(
    tool: widget.tool,
    state: widget.state,
    blocked: _busy,
    children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.surfaceContainerLow,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.photo_filter_outlined, size: 36),
            const SizedBox(height: 20),
            Text('把画面调整到位', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            const Text('拖动裁剪，细调色彩，用文字和箭头说明细节。'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_busy ? '正在准备图片' : '选择图片开始编辑'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final title in ['手势裁剪', '调色与滤镜', '文字与箭头', '模糊与马赛克', '撤销与重做'])
            Chip(label: Text(title)),
        ],
      ),
      const SizedBox(height: 20),
      const Text(
        '支持 JPEG、PNG 和 WebP，单张最多 30 MB、4000 万像素。超大图片会缩小至长边不超过 4096 px 后编辑。导出可选 JPEG 或 PNG；原文件保持不变。',
      ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.only(top: 20),
          child: LinearProgressIndicator(),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}

String _errorText(Object error) => error is PlatformException
    ? error.message ?? error.code
    : error is FormatException
    ? error.message
    : '图片处理失败，请重试：$error';

Future<void> _cleanOutputs(List<String> paths) async {
  try {
    await imageEditorChannel.invokeMethod('mediaCleanup', {'paths': paths});
  } on PlatformException {
    // Startup cache cleanup also removes stale working files.
  }
}

/// Edits only the prepared working copy; history stays in memory for this session.
class ImageEditingSession extends StatefulWidget {
  const ImageEditingSession({
    super.key,
    required this.sourcePath,
    required this.sourceName,
  });
  final String sourcePath;
  final String sourceName;

  @override
  State<ImageEditingSession> createState() => _ImageEditingSessionState();
}

class _ImageEditingSessionState extends State<ImageEditingSession> {
  final _editorKey = GlobalKey<ProImageEditorState>();
  bool _busy = false, _ready = false, _compare = false, _promptOpen = false;
  String _format = 'JPEG';
  int _maxEdge = 4096;
  double _quality = 90;
  Object? _savedState;

  Object? _currentState(ProImageEditorState editor) =>
      editor.stateHistory.isEmpty
      ? null
      : editor.stateHistory[editor.stateManager.historyPointer];

  Future<bool> _confirmClose(ProImageEditorState editor) async {
    if (_busy || _promptOpen) return false;
    if (_savedState != null && identical(_savedState, _currentState(editor))) {
      return true;
    }
    _promptOpen = true;
    try {
      final choice = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('图片尚未导出'),
          content: const Text('当前编辑不会自动保存，请选择继续编辑、导出或放弃。'),
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
      if (choice == 'export') await _export();
      return choice == 'discard';
    } finally {
      _promptOpen = false;
    }
  }

  Future<void> _settings() async {
    var format = _format, edge = _maxEdge;
    var quality = _quality;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, refresh) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('导出设置', style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: format,
                  decoration: const InputDecoration(labelText: '文件格式'),
                  items: [
                    for (final f in ['JPEG', 'PNG'])
                      DropdownMenuItem(value: f, child: Text(f)),
                  ],
                  onChanged: (v) => refresh(() => format = v!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: edge,
                  decoration: const InputDecoration(labelText: '最长边（不放大小图）'),
                  items: [
                    for (final n in [1024, 2048, 4096])
                      DropdownMenuItem(value: n, child: Text('$n px')),
                  ],
                  onChanged: (v) => refresh(() => edge = v!),
                ),
                const SizedBox(height: 16),
                if (format == 'JPEG') ...[
                  Text('JPEG 质量 ${quality.round()}'),
                  Slider(
                    value: quality,
                    min: 50,
                    max: 100,
                    divisions: 50,
                    label: '${quality.round()}',
                    onChanged: (v) => refresh(() => quality = v),
                  ),
                  const Text('JPEG 不保留透明度，透明区域会填充为白色。'),
                ] else
                  const Text('PNG 保留透明度，文件通常较大。'),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('应用设置'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (accepted == true && mounted) {
      setState(() {
        _format = format;
        _maxEdge = edge;
        _quality = quality;
      });
    }
  }

  Future<void> _export() async {
    final editor = _editorKey.currentState;
    if (_busy || !_ready || editor == null) return;
    setState(() {
      _busy = true;
      _compare = false;
    });
    File? working;
    String? generated;
    try {
      editor.layerInteractionManager.clearSelectedLayers();
      await WidgetsBinding.instance.endOfFrame;
      final bytes = await editor.captureEditorImage();
      if (bytes.isEmpty) throw const FormatException('图片生成失败，请重试');
      final revision = _currentState(editor);
      final temp = await Files.temporaryDirectory();
      working = File(
        '${temp.path}/saisuite_editor_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await working.writeAsBytes(bytes, flush: true);
      final output = await imageEditorChannel.invokeMapMethod<String, dynamic>(
        'imageEditorExport',
        {
          'path': working.path,
          'format': _format,
          'maxEdge': _exportEdge(editor),
          'quality': _quality.round(),
        },
      );
      generated = output?['path'] as String?;
      if (generated == null) throw const FormatException('没有生成导出文件');
      final extension = _format == 'PNG' ? 'png' : 'jpg';
      final name = widget.sourceName
          .replaceFirst(RegExp(r'\.[^.]+$'), '')
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final uri = await imageEditorChannel.invokeMethod<String>('saveOutput', {
        'path': generated,
        'name': '${name.isEmpty ? 'image' : name}-edited.$extension',
        'mime': _format == 'PNG' ? 'image/png' : 'image/jpeg',
      });
      if (uri != null && mounted) {
        _savedState = revision;
        message(
          context,
          '已另存为新文件 · ${output!['width']} × ${output['height']} px',
        );
      }
    } catch (e) {
      if (mounted) message(context, _errorText(e));
    } finally {
      try {
        if (working != null && await working.exists()) await working.delete();
        if (generated != null) await _cleanOutputs([generated]);
      } on FileSystemException {
        // A cache cleanup failure must not lock the editor or undo a save.
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  int _exportEdge(ProImageEditorState editor) {
    var size = editor.sizesManager.originalImageSize!;
    final transform = editor.stateManager.transformConfigs;
    if (transform.isNotEmpty) size = transform.getCropSize(size);
    final edge = (size.width > size.height ? size.width : size.height)
        .floor()
        .clamp(1, 4096);
    return edge < _maxEdge ? edge : _maxEdge;
  }

  ProImageEditorConfigs _configs() => ProImageEditorConfigs(
    theme: editor_ui.ThemeData(
      colorScheme: editor_ui.ColorScheme.fromSeed(
        seedColor: const Color(0xff47bfa8),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    i18n: imageEditorChinese,
    stateHistory: const StateHistoryConfigs(stateHistoryLimit: 30),
    imageGeneration: const ImageGenerationConfigs(
      outputFormat: OutputFormat.png,
      cropToDrawingBounds: false,
      maxOutputSize: Size(4096, 4096),
      enableUseOriginalBytes: false,
      enableBackgroundGeneration: false,
      processorConfigs: ProcessorConfigs(processorMode: ProcessorMode.minimum),
    ),
    mainEditor: MainEditorConfigs(
      tools: const [
        SubEditorMode.cropRotate,
        SubEditorMode.tune,
        SubEditorMode.filter,
        SubEditorMode.paint,
        SubEditorMode.text,
        SubEditorMode.blur,
      ],
      style: const MainEditorStyle(
        background: Color(0xff101a18),
        appBarBackground: Color(0xff172622),
        bottomBarBackground: Color(0xff172622),
      ),
      widgets: MainEditorWidgets(
        closeWarningDialog: _confirmClose,
        appBar: (editor, stream) => ReactiveAppbar(
          stream: stream,
          builder: (_) => AppBar(
            backgroundColor: const Color(0xff172622),
            foregroundColor: Colors.white,
            title: const Text('图片编辑', style: TextStyle(fontSize: 16)),
            leading: IconButton(
              tooltip: '返回',
              onPressed: _busy ? null : editor.closeEditor,
              icon: const Icon(Icons.arrow_back),
            ),
            actions: [
              IconButton(
                tooltip: '撤销',
                disabledColor: Colors.white38,
                onPressed: !_busy && editor.canUndo ? editor.undoAction : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: '重做',
                disabledColor: Colors.white38,
                onPressed: !_busy && editor.canRedo ? editor.redoAction : null,
                icon: const Icon(Icons.redo),
              ),
              IconButton(
                tooltip: '导出设置',
                onPressed: _busy ? null : _settings,
                icon: const Icon(Icons.tune),
              ),
              IconButton(
                key: const ValueKey('image-editor-export'),
                tooltip: '另存为',
                disabledColor: Colors.white38,
                onPressed: !_busy && _ready ? _export : null,
                icon: const Icon(Icons.file_download_outlined),
              ),
            ],
          ),
        ),
      ),
    ),
    paintEditor: const PaintEditorConfigs(
      tools: [
        PaintMode.moveAndZoom,
        PaintMode.freeStyle,
        PaintMode.arrow,
        PaintMode.line,
        PaintMode.rect,
        PaintMode.circle,
        PaintMode.pixelate,
        PaintMode.blur,
        PaintMode.eraser,
      ],
    ),
    cropRotateEditor: const CropRotateEditorConfigs(
      aspectRatios: [
        AspectRatioItem(text: '自由', value: -1),
        AspectRatioItem(text: '原图', value: 0),
        AspectRatioItem(text: '1:1', value: 1),
        AspectRatioItem(text: '4:3', value: 4 / 3),
        AspectRatioItem(text: '3:4', value: 3 / 4),
        AspectRatioItem(text: '16:9', value: 16 / 9),
        AspectRatioItem(text: '9:16', value: 9 / 16),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Localizations.override(
    context: context,
    locale: const Locale('zh', 'CN'),
    delegates: saiLocalizationsDelegates,
    child: Scaffold(
      backgroundColor: const Color(0xff101a18),
      body: PopScope(
        canPop: !_busy,
        child: Stack(
          children: [
            AbsorbPointer(
              absorbing: _busy,
              child: ProImageEditor.file(
                File(widget.sourcePath),
                key: _editorKey,
                configs: _configs(),
                callbacks: ProImageEditorCallbacks(
                  onCloseEditor: (_) {
                    if (!_busy && mounted) Navigator.pop(context);
                  },
                  mainEditorCallbacks: MainEditorCallbacks(
                    onImageDecoded: () {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _ready = true);
                      });
                    },
                  ),
                ),
              ),
            ),
            if (_compare)
              Positioned.fill(
                top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                bottom: 92 + MediaQuery.paddingOf(context).bottom,
                child: IgnorePointer(
                  child: ColoredBox(
                    color: const Color(0xff101a18),
                    child: Image.file(
                      File(widget.sourcePath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
              right: 12,
              child: GestureDetector(
                onTapDown: _busy
                    ? null
                    : (_) => setState(() => _compare = true),
                onTapUp: (_) => setState(() => _compare = false),
                onTapCancel: () => setState(() => _compare = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xdd172622),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                    ),
                    child: Text('按住看原图'),
                  ),
                ),
              ),
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text('正在导出 $_format'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
