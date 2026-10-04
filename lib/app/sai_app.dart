import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../features/catalog.dart';
import '../features/tool_page.dart';
import '../features/pdf_page.dart';
import '../features/palette_page.dart';
import '../features/image_picker_page.dart';
import '../features/pomodoro_page.dart';
import '../features/drawing_page.dart';
import '../features/sensor_page.dart';
import '../features/ruler_page.dart';
import '../features/media_page.dart';
import '../features/analysis_page.dart';
import '../features/image_tools_hub.dart';

class SaiApp extends StatelessWidget {
  const SaiApp({super.key, required this.state});
  final AppState state;
  ThemeData theme(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xff147d73),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xfff7f8f4)
          : const Color(0xff111c1b),
      appBarTheme: const AppBarTheme(centerTitle: false),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => MaterialApp(
      title: '赛赛工具箱',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: state.theme,
      home: HomeShell(state: state),
    ),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});
  final AppState state;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  String query = '', category = '全部';
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void open(ToolSpec tool) {
    widget.state.visit(tool.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => switch (tool.id) {
          'A01' => PalettePage(tool: tool, state: widget.state),
          'A02' => ImagePickerPage(tool: tool, state: widget.state),
          'A03' => PomodoroPage(tool: tool, state: widget.state),
          'A04' => DrawingPage(tool: tool, state: widget.state),
          'A05' ||
          'A06' ||
          'A07' => SensorPage(tool: tool, state: widget.state),
          'A08' => RulerPage(tool: tool, state: widget.state),
          'A09' => ImageToolsHub(tool: tool, state: widget.state),
          'A10' => MediaPage(tool: tool, state: widget.state),
          'N06' || 'N07' => AnalysisPage(tool: tool, state: widget.state),
          _ =>
            tool.pdf
                ? PdfPage(tool: tool, state: widget.state)
                : ToolPage(tool: tool, state: widget.state),
        },
      ),
    );
  }

  List<ToolSpec> byIds(List<String> ids) => ids
      .map((id) => tools.where((t) => t.id == id).firstOrNull)
      .whereType<ToolSpec>()
      .toList();
  Widget toolTile(ToolSpec tool) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          tool.icon,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(tool.name),
      subtitle: Text(
        tool.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: '收藏 ${tool.name}',
        onPressed: () => widget.state.star(tool.id),
        icon: Icon(
          widget.state.favorites.contains(tool.id)
              ? Icons.star
              : Icons.star_border,
        ),
      ),
      onTap: () => open(tool),
    ),
  );
  Widget section(String title, List<ToolSpec> entries) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      ...entries.map(toolTile),
    ],
  );
  Widget home() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: Theme.of(context).colorScheme.primaryContainer,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SAISUITE  /  EVERYDAY & LAB',
              style: TextStyle(fontSize: 11, letterSpacing: 2),
            ),
            const SizedBox(height: 12),
            Text(
              '小事，随手解决。',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => setState(() {
                tab = 1;
                category = '全部';
              }),
              icon: const Icon(Icons.grid_view),
              label: Text('浏览 ${tools.length} 个工具'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      TextField(
        readOnly: true,
        onTap: () => setState(() => tab = 1),
        decoration: const InputDecoration(
          hintText: '搜索工具、单位或关键词',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(18),
          leading: const Icon(Icons.picture_as_pdf_outlined, size: 36),
          title: const Text('PDF 工作台'),
          subtitle: const Text('合并 · 拆分 · 整理 · 转换 · 加密'),
          trailing: const Icon(Icons.arrow_forward),
          onTap: () => setState(() {
            tab = 1;
            category = 'PDF';
          }),
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: categories
            .skip(2)
            .map(
              (c) => ActionChip(
                label: Text(c),
                onPressed: () => setState(() {
                  tab = 1;
                  category = c;
                }),
              ),
            )
            .toList(),
      ),
      if (widget.state.favorites.isNotEmpty)
        section('固定在手边', byIds(widget.state.favorites).take(4).toList()),
      if (widget.state.recent.isNotEmpty)
        section('最近使用', byIds(widget.state.recent).take(5).toList()),
      section(
        '实验室常用',
        tools
            .where((t) => ['S01', 'S04', 'EC04', 'EC05', 'EC21'].contains(t.id))
            .toList(),
      ),
    ],
  );
  Widget catalog() {
    final filtered = tools
        .where(
          (t) =>
              (category == '全部' || t.category == category) && t.matches(query),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: TextField(
            controller: search,
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
              hintText: '搜索名称、关键词或编号',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        search.clear();
                        setState(() => query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: categories
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c),
                      selected: category == c,
                      onSelected: (_) => setState(() => category = c),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('没有匹配的工具，试试其他关键词'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('${filtered.length} 个工具'),
                    ),
                    ...filtered.map(toolTile),
                  ],
                ),
        ),
      ],
    );
  }

  Widget favorites() {
    final entries = byIds(widget.state.favorites);
    if (entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_outline, size: 56),
            SizedBox(height: 16),
            Text('收藏常用工具，建立你的工作台'),
          ],
        ),
      );
    }
    return ReorderableListView(
      padding: const EdgeInsets.all(16),
      onReorderItem: widget.state.reorder,
      children: entries
          .map((t) => SizedBox(key: ValueKey(t.id), child: toolTile(t)))
          .toList(),
    );
  }

  Widget settings() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('让工具适合你', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 20),
      RadioGroup<ThemeMode>(
        groupValue: widget.state.theme,
        onChanged: (v) {
          if (v != null) widget.state.setTheme(v);
        },
        child: Column(
          children: ThemeMode.values
              .map(
                (mode) => RadioListTile<ThemeMode>(
                  title: Text(switch (mode) {
                    ThemeMode.system => '跟随系统',
                    ThemeMode.light => '浅色主题',
                    ThemeMode.dark => '深色主题',
                  }),
                  value: mode,
                ),
              )
              .toList(),
        ),
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.history),
        title: const Text('清除最近使用与计算历史'),
        onTap: () async {
          final yes = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('清除使用记录？'),
              content: const Text('收藏会保留。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('清除'),
                ),
              ],
            ),
          );
          if (yes == true) await widget.state.clearHistory();
        },
      ),
      ListTile(
        leading: const Icon(Icons.description_outlined),
        title: const Text('开源许可'),
        onTap: () => showLicensePage(
          context: context,
          applicationName: 'SaiSuite · 赛赛工具箱',
          applicationVersion: '1.3.0',
        ),
      ),
      AboutListTile(
        applicationName: 'SaiSuite · 赛赛工具箱',
        applicationVersion: '1.3.0',
        aboutBoxChildren: [
          Text(
            '${tools.length} 个工具：PDF、日常计算、创作、设备、科研与日期。\nPDF、媒体和设备原生能力在 Android 版提供。',
          ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          '计算结果取决于输入、单位和模型条件。科研工具会保留计算口径；PDF 操作生成新文件。',
          style: TextStyle(fontSize: 12),
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(['赛赛工具箱', '全部工具', '我的收藏', '设置'][tab])),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: switch (tab) {
            0 => home(),
            1 => catalog(),
            2 => favorites(),
            _ => settings(),
          },
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: '工具',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: '收藏',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    ),
  );
}
