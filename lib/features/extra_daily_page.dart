import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../core/app_state.dart';
import '../core/files.dart';
import 'catalog.dart';
import 'workbench.dart';
import 'extra_widgets.dart';

String stopwatchLabel(Duration time, {bool precise = true}) {
  final ms = time.inMilliseconds;
  return '${(ms ~/ 3600000).toString().padLeft(2, '0')}:${(ms ~/ 60000 % 60).toString().padLeft(2, '0')}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}${precise ? '.${(ms ~/ 10 % 100).toString().padLeft(2, '0')}' : ''}';
}

class ExtraDailyPage extends StatefulWidget {
  const ExtraDailyPage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<ExtraDailyPage> createState() => _ExtraDailyPageState();
}

class _ExtraDailyPageState extends State<ExtraDailyPage>
    with WidgetsBindingObserver {
  final text = TextEditingController(text: '今天也要闪闪发光'),
      teamA = TextEditingController(text: '青队'),
      teamB = TextEditingController(text: '橙队');
  final stopwatch = Stopwatch(), reactionWatch = Stopwatch();
  final laps = <Duration>[], samples = <int>[];
  final scoreHistory = <(int, int)>[];
  Timer? refresh, wait;
  int a = 0, b = 0;
  String reaction = 'ready', clockMode = '数字时钟', font = '圆润';
  double fontSize = 72, speed = 120;
  bool landscape = true;
  Color foreground = Colors.white, background = const Color(0xff122d2b);
  String get id => widget.tool.id;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted && (id == 'U01' || stopwatch.isRunning)) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        (reaction == 'waiting' || reaction == 'go')) {
      wait?.cancel();
      reactionWatch.stop();
      setState(() => reaction = 'interrupted');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    refresh?.cancel();
    wait?.cancel();
    text.dispose();
    teamA.dispose();
    teamB.dispose();
    super.dispose();
  }

  void react() {
    if (reaction == 'waiting') {
      wait?.cancel();
      setState(() => reaction = 'early');
      return;
    }
    if (reaction == 'go') {
      reactionWatch.stop();
      samples.add(reactionWatch.elapsedMilliseconds);
      if (samples.length > 20) samples.removeAt(0);
      setState(() => reaction = 'result');
      return;
    }
    setState(() => reaction = 'waiting');
    wait = Timer(
      Duration(milliseconds: 1500 + math.Random.secure().nextInt(3000)),
      () {
        if (mounted) {
          reactionWatch
            ..reset()
            ..start();
          setState(() => reaction = 'go');
        }
      },
    );
  }

  String clockText() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}${clockMode == '显示秒' ? ':${now.second.toString().padLeft(2, '0')}' : ''}';
  }

  Future<void> fullScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DisplayStage(
          text: text.text,
          clock: id == 'U01',
          seconds: clockMode == '显示秒',
          fontSize: fontSize,
          speed: speed,
          foreground: foreground,
          background: background,
          font: font,
          landscape: landscape,
        ),
      ),
    );
  }

  Widget colorPick(String label, Color value, void Function(Color) change) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                [
                      Colors.white,
                      const Color(0xff122d2b),
                      const Color(0xff8bf0c6),
                      const Color(0xffffce82),
                      const Color(0xff7388ff),
                      const Color(0xffed7896),
                    ]
                    .map(
                      (c) => InkWell(
                        onTap: () => setState(() => change(c)),
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c == value
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey,
                              width: c == value ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ],
      );
  @override
  Widget build(BuildContext context) => Workbench(
    tool: widget.tool,
    state: widget.state,
    children: [
      StudioBanner(
        'DAILY STUDIO',
        widget.tool.name,
        widget.tool.description,
        icon: widget.tool.icon,
      ),
      if (id == 'U01' || id == 'U02') ...[
        const SizedBox(height: 18),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(22),
          ),
          padding: const EdgeInsets.all(20),
          child: Center(
            child: FittedBox(
              child: Text(
                id == 'U01' ? clockText() : text.text,
                style: TextStyle(
                  fontSize: fontSize,
                  color: foreground,
                  fontWeight: font == '粗体' ? FontWeight.w900 : FontWeight.w400,
                  fontFamily: font == '等宽' ? 'monospace' : null,
                ),
              ),
            ),
          ),
        ),
        StudioPanel(
          title: '显示设置',
          children: [
            if (id == 'U02')
              TextField(
                controller: text,
                maxLength: 200,
                decoration: const InputDecoration(labelText: '弹幕内容'),
                onChanged: (_) => setState(() {}),
              ),
            if (id == 'U01')
              studioChoices(
                ['数字时钟', '显示秒'],
                clockMode,
                (v) => setState(() => clockMode = v),
              ),
            studioChoices(
              ['圆润', '粗体', '等宽'],
              font,
              (v) => setState(() => font = v),
            ),
            studioSlider(
              '字号',
              fontSize,
              32,
              240,
              (v) => setState(() => fontSize = v),
            ),
            if (id == 'U02')
              studioSlider(
                '滚动速度',
                speed,
                0,
                350,
                (v) => setState(() => speed = v),
                display: speed == 0 ? '静止' : '${speed.round()} px/s',
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('横屏展示'),
              value: landscape,
              onChanged: (v) => setState(() => landscape = v),
            ),
            colorPick('文字颜色', foreground, (v) => foreground = v),
            const SizedBox(height: 16),
            colorPick('背景颜色', background, (v) => background = v),
          ],
        ),
        FilledButton.icon(
          onPressed: id == 'U02' && text.text.trim().isEmpty
              ? null
              : fullScreen,
          icon: const Icon(Icons.fullscreen),
          label: const Text('进入全屏'),
        ),
      ],
      if (id == 'U03') ...[
        StudioPanel(
          title: '秒表',
          children: [
            SizedBox(
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: CircularProgressIndicator(
                      value: stopwatch.elapsedMilliseconds % 60000 / 60000,
                      strokeWidth: 8,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                    ),
                  ),
                  FittedBox(
                    child: Text(
                      stopwatchLabel(stopwatch.elapsed),
                      style: const TextStyle(
                        fontSize: 30,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => setState(() {
                    stopwatch.isRunning ? stopwatch.stop() : stopwatch.start();
                  }),
                  icon: Icon(
                    stopwatch.isRunning ? Icons.pause : Icons.play_arrow,
                  ),
                  label: Text(stopwatch.isRunning ? '暂停' : '开始'),
                ),
                OutlinedButton(
                  onPressed: stopwatch.isRunning && laps.length < 200
                      ? () => setState(() => laps.add(stopwatch.elapsed))
                      : null,
                  child: const Text('分段'),
                ),
                TextButton(
                  onPressed: stopwatch.isRunning
                      ? null
                      : () => setState(() {
                          stopwatch.reset();
                          laps.clear();
                        }),
                  child: const Text('重置'),
                ),
              ],
            ),
          ],
        ),
        if (laps.isNotEmpty)
          StudioPanel(
            title: '分段 · ${laps.length}',
            children: [
              ...laps.asMap().entries.toList().reversed.map(
                (e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text('#${e.key + 1}'),
                  title: Text(stopwatchLabel(e.value)),
                  trailing: Text(
                    '+${stopwatchLabel(e.value - (e.key == 0 ? Duration.zero : laps[e.key - 1]))}',
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: () async {
                  await Files.saveText(
                    laps
                        .asMap()
                        .entries
                        .map((e) => '${e.key + 1}\t${stopwatchLabel(e.value)}')
                        .join('\n'),
                    '秒表分段.txt',
                  );
                },
                child: const Text('导出分段'),
              ),
            ],
          ),
        const Text('按实际经过时间计时；退出本工具后结束本次计时，不自动保存。'),
      ],
      if (id == 'U04') ...[
        StudioPanel(
          title: '双方比分',
          children: [
            Row(
              children: [
                Expanded(
                  child: teamPanel(
                    teamA,
                    a,
                    const Color(0xff147d73),
                    (delta) => score(delta, 0),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(':', style: TextStyle(fontSize: 32)),
                ),
                Expanded(
                  child: teamPanel(
                    teamB,
                    b,
                    const Color(0xffbc6a36),
                    (delta) => score(0, delta),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: scoreHistory.isEmpty
                      ? null
                      : () => setState(() {
                          final old = scoreHistory.removeLast();
                          a = old.$1;
                          b = old.$2;
                        }),
                  child: const Text('撤销'),
                ),
                TextButton(
                  onPressed: () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('重置比分？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('重置'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true && mounted) {
                      setState(() {
                        scoreHistory.add((a, b));
                        a = b = 0;
                      });
                    }
                  },
                  child: const Text('重置'),
                ),
                OutlinedButton(
                  onPressed: () => Files.saveText(
                    '${teamA.text} $a : $b ${teamB.text}',
                    '比分.txt',
                  ),
                  child: const Text('导出比分'),
                ),
              ],
            ),
          ],
        ),
        const Text('仅保留当前页面的比分，退出后不自动保存。'),
      ],
      if (id == 'U05') ...[
        const SizedBox(height: 18),
        GestureDetector(
          onTapDown: (_) => react(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            height: 300,
            decoration: BoxDecoration(
              color: reaction == 'go'
                  ? const Color(0xff147d73)
                  : reaction == 'waiting'
                  ? const Color(0xffae6b3e)
                  : const Color(0xff394575),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    reaction == 'go' ? Icons.touch_app : Icons.bolt,
                    size: 48,
                    color: Colors.white70,
                  ),
                  const SizedBox(height: 20),
                  Text(switch (reaction) {
                    'waiting' => '等到变绿再点',
                    'go' => '现在点！',
                    'early' => '点早了，再试一次',
                    'interrupted' => '本轮中断，点按重试',
                    'result' => '${samples.last} ms',
                    _ => '点按开始',
                  }, style: const TextStyle(fontSize: 27, color: Colors.white)),
                  const SizedBox(height: 12),
                  const Text(
                    '屏幕与触摸延迟会影响结果',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (samples.isNotEmpty)
          StudioPanel(
            title: '本次成绩',
            children: [
              Text(
                '最快 ${samples.reduce(math.min)} ms  ·  平均 ${(samples.reduce((a, b) => a + b) / samples.length).round()} ms',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: samples
                    .map((s) => Chip(label: Text('$s ms')))
                    .toList(),
              ),
              TextButton(
                onPressed: () => setState(() {
                  samples.clear();
                  reaction = 'ready';
                }),
                child: const Text('清空成绩'),
              ),
            ],
          ),
      ],
    ],
  );
  void score(int da, int db) {
    if (a + da < 0 || b + db < 0 || a + da > 999 || b + db > 999) return;
    setState(() {
      scoreHistory.add((a, b));
      if (scoreHistory.length > 100) scoreHistory.removeAt(0);
      a += da;
      b += db;
    });
  }

  Widget teamPanel(
    TextEditingController name,
    int value,
    Color color,
    void Function(int) change,
  ) => Column(
    children: [
      TextField(
        controller: name,
        textAlign: TextAlign.center,
        maxLength: 20,
        decoration: const InputDecoration(counterText: '', labelText: '队伍'),
      ),
      const SizedBox(height: 14),
      FittedBox(
        child: Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 76,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          IconButton(
            onPressed: () => change(-1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          IconButton.filled(
            onPressed: () => change(1),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    ],
  );
}

class DisplayStage extends StatefulWidget {
  const DisplayStage({
    super.key,
    required this.text,
    required this.clock,
    required this.seconds,
    required this.fontSize,
    required this.speed,
    required this.foreground,
    required this.background,
    required this.font,
    required this.landscape,
  });
  final String text, font;
  final bool clock, seconds, landscape;
  final double fontSize, speed;
  final Color foreground, background;
  @override
  State<DisplayStage> createState() => _DisplayStageState();
}

class _DisplayStageState extends State<DisplayStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController ticker;
  final elapsed = Stopwatch()..start();
  @override
  void initState() {
    super.initState();
    ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    screen(true);
  }

  Future<void> screen(bool full) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        await const MethodChannel('saisuite/windows')
            .invokeMethod('fullScreen', full);
      } catch (_) {}
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
      await SystemChrome.setPreferredOrientations(
        full
            ? (widget.landscape
                  ? [
                      DeviceOrientation.landscapeLeft,
                      DeviceOrientation.landscapeRight,
                    ]
                  : [DeviceOrientation.portraitUp])
            : [],
      );
    }
  }

  @override
  void dispose() {
    ticker.dispose();
    elapsed.stop();
    screen(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: widget.background,
    body: Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: ticker,
            builder: (_, _) {
              final now = DateTime.now();
              final value = widget.clock
                  ? '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}${widget.seconds ? ':${now.second.toString().padLeft(2, '0')}' : ''}'
                  : widget.text;
              return CustomPaint(
                painter: _DisplayPainter(
                  value,
                  widget.foreground,
                  widget.fontSize,
                  widget.font,
                  widget.clock ? 0 : widget.speed,
                  elapsed.elapsedMilliseconds / 1000,
                  widget.clock,
                ),
              );
            },
          ),
        ),
        Positioned(
          right: 16,
          top: 16,
          child: SafeArea(
            child: IconButton.filledTonal(
              tooltip: '退出全屏',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.fullscreen_exit),
            ),
          ),
        ),
      ],
    ),
  );
}

class _DisplayPainter extends CustomPainter {
  _DisplayPainter(
    this.text,
    this.color,
    this.fontSize,
    this.font,
    this.speed,
    this.seconds,
    this.fit,
  );
  final String text, font;
  final Color color;
  final double fontSize, speed, seconds;
  final bool fit;
  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: font == '粗体' ? FontWeight.w900 : FontWeight.w400,
          fontFamily: font == '等宽' ? 'monospace' : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (speed == 0) {
      final scale = fit
          ? math.min(
              (size.width - 40) / painter.width,
              (size.height - 40) / painter.height,
            )
          : math.min(1.0, (size.width - 40) / painter.width);
      canvas.save();
      canvas.translate(
        (size.width - painter.width * scale) / 2,
        (size.height - painter.height * scale) / 2,
      );
      canvas.scale(scale);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    } else {
      painter.paint(
        canvas,
        Offset(
          size.width - (seconds * speed) % (size.width + painter.width),
          (size.height - painter.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DisplayPainter old) => true;
}
