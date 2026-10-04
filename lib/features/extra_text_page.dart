import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lpinyin/lpinyin.dart';

import '../core/app_state.dart';
import '../core/extra_text.dart';
import '../core/files.dart';
import 'catalog.dart';
import 'workbench.dart';
import 'extra_widgets.dart';

class ExtraTextPage extends StatefulWidget {
  const ExtraTextPage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<ExtraTextPage> createState() => _ExtraTextPageState();
}

class _ExtraTextPageState extends State<ExtraTextPage> {
  final input = TextEditingController(),
      customFrom = TextEditingController(text: '10'),
      customTo = TextEditingController(text: '16');
  String mode = '', output = '', error = '';
  int from = 10, to = 16;
  final selected = <int>{}, overrides = <int, String>{};
  String get id => widget.tool.id;
  @override
  void initState() {
    super.initState();
    mode = switch (id) {
      'X02' => '中文数字',
      'X03' => '上标',
      'X04' => '编码',
      'X07' => '声调符号',
      _ => '',
    };
    input.text = switch (id) {
      'X01' => '255',
      'X02' => '10001.25',
      'X03' => 'H2O + x2',
      'X04' => 'HELLO WORLD',
      'X05' => 'SaiSuite',
      'X06' => '电解液 Electrolyte 123',
      _ => '重庆银行',
    };
    convert();
  }

  @override
  void dispose() {
    input.dispose();
    customFrom.dispose();
    customTo.dispose();
    super.dispose();
  }

  void convert() {
    try {
      final text = input.text;
      if (text.length > 20000) throw const FormatException('文本最多 20000 个字符');
      output = switch (id) {
        'X01' => convertBase(text, from, to),
        'X02' => chineseNumber(text, money: mode == '金额大写'),
        'X03' => raisedDigits(text, sub: mode == '下标'),
        'X04' => morse(text, decode: mode == '解码'),
        'X05' => miniEnglish(text),
        'X06' =>
          splitWords(text)
              .asMap()
              .entries
              .where((e) => selected.contains(e.key))
              .map((e) => e.value)
              .join(),
        'X07' => pinyinText(text, mode, overrides),
        _ => '',
      };
      error = '';
    } catch (e) {
      output = '';
      error = e is FormatException ? e.message.toString() : '$e';
    }
  }

  void update(void Function() action) => setState(() {
    action();
    convert();
  });
  @override
  Widget build(BuildContext context) => Workbench(
    tool: widget.tool,
    state: widget.state,
    children: [
      StudioBanner(
        'TEXT LAB',
        widget.tool.name,
        widget.tool.description,
        color: const Color(0xff596ac8),
        icon: widget.tool.icon,
      ),
      StudioPanel(
        title: '输入',
        children: [
          TextField(
            controller: input,
            minLines: 3,
            maxLines: 7,
            maxLength: 20000,
            decoration: const InputDecoration(labelText: '待处理内容'),
            onChanged: (_) => update(() {
              selected.clear();
              overrides.clear();
            }),
          ),
          if (id == 'X01') ...[
            const SizedBox(height: 12),
            Text('输入进制 $from'),
            studioChoices(
              ['2', '8', '10', '16', '36'],
              '$from',
              (s) => update(() => from = int.parse(s)),
            ),
            const SizedBox(height: 12),
            Text('输出进制 $to'),
            studioChoices(
              ['2', '8', '10', '16', '36'],
              '$to',
              (s) => update(() => to = int.parse(s)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: customFrom,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '自定义输入 2—36'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: customTo,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '自定义输出 2—36'),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => update(() {
                from = int.tryParse(customFrom.text) ?? 0;
                to = int.tryParse(customTo.text) ?? 0;
              }),
              child: const Text('应用自定义进制'),
            ),
            TextButton.icon(
              onPressed: () => update(() {
                if (error.isEmpty) input.text = output;
                final old = from;
                from = to;
                to = old;
              }),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('交换进制'),
            ),
          ],
          if (id == 'X02')
            studioChoices(
              ['中文数字', '金额大写'],
              mode,
              (v) => update(() => mode = v),
            ),
          if (id == 'X03')
            studioChoices(['上标', '下标'], mode, (v) => update(() => mode = v)),
          if (id == 'X04')
            studioChoices(['编码', '解码'], mode, (v) => update(() => mode = v)),
          if (id == 'X07')
            studioChoices(
              ['声调符号', '声调数字', '无声调', '首字母'],
              mode,
              (v) => update(() {
                mode = v;
                overrides.clear();
              }),
            ),
        ],
      ),
      if (id == 'X06')
        StudioPanel(
          title: '点选需要的字符或英文词',
          children: [
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: splitWords(input.text)
                  .asMap()
                  .entries
                  .map(
                    (e) => FilterChip(
                      label: Text(e.value),
                      selected: selected.contains(e.key),
                      onSelected: (yes) => update(() {
                        yes ? selected.add(e.key) : selected.remove(e.key);
                      }),
                    ),
                  )
                  .toList(),
            ),
            Wrap(
              children: [
                TextButton(
                  onPressed: () => update(
                    () => selected.addAll(
                      List.generate(splitWords(input.text).length, (i) => i),
                    ),
                  ),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () => update(selected.clear),
                  child: const Text('清空选择'),
                ),
              ],
            ),
          ],
        ),
      if (id == 'X07')
        StudioPanel(
          title: '多音字校正 · 点选读音',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: input.text.characters
                  .toList()
                  .asMap()
                  .entries
                  .take(150)
                  .where(
                    (e) =>
                        PinyinHelper.convertToPinyinArray(
                          e.value,
                          PinyinFormat.WITH_TONE_MARK,
                        ).length >
                        1,
                  )
                  .map(
                    (e) => PopupMenuButton<String>(
                      tooltip: '选择 ${e.value} 的读音',
                      onSelected: (s) => update(() => overrides[e.key] = s),
                      itemBuilder: (_) =>
                          PinyinHelper.convertToPinyinArray(
                                e.value,
                                mode == '声调数字'
                                    ? PinyinFormat.WITH_TONE_NUMBER
                                    : mode == '无声调' || mode == '首字母'
                                    ? PinyinFormat.WITHOUT_TONE
                                    : PinyinFormat.WITH_TONE_MARK,
                              )
                              .map(
                                (s) => PopupMenuItem(value: s, child: Text(s)),
                              )
                              .toList(),
                      child: Chip(
                        label: Text('${e.value} ${overrides[e.key] ?? '选择读音'}'),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const Text('词组优先匹配；选择后按逐字读音输出。不认识的字符保留，转换结果请核对。'),
          ],
        ),
      StudioPanel(
        title: '转换结果',
        children: [
          if (error.isNotEmpty)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else
            SelectableText(
              output.isEmpty ? '在上方输入或选择内容' : output,
              style: const TextStyle(fontSize: 22, height: 1.6),
            ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            children: [
              FilledButton.icon(
                onPressed: output.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: output));
                        if (context.mounted) message(context, '已复制');
                      },
                icon: const Icon(Icons.copy),
                label: const Text('复制结果'),
              ),
              OutlinedButton.icon(
                onPressed: output.isEmpty
                    ? null
                    : () async {
                        final path = await Files.saveText(
                          output,
                          '${widget.tool.name}.txt',
                        );
                        if (context.mounted && path != null) {
                          message(context, '已导出');
                        }
                      },
                icon: const Icon(Icons.save_alt),
                label: const Text('导出 TXT'),
              ),
            ],
          ),
        ],
      ),
      if (id == 'X04') const Text('字符间用空格，单词间用 /。支持英文、数字及常用标点。'),
      if (id == 'X03' || id == 'X05')
        const Text('结果使用 Unicode 字符，显示效果取决于接收应用的字体。'),
    ],
  );
}
