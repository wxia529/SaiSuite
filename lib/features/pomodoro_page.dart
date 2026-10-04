import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import 'catalog.dart';
import 'workbench.dart';

class PomodoroPage extends StatefulWidget {
  const PomodoroPage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('saisuite/device');
  final focus = TextEditingController(text: '25'),
      short = TextEditingController(text: '5'),
      long = TextEditingController(text: '15'),
      rounds = TextEditingController(text: '4');
  Timer? ticker;
  int? deadline;
  int remaining = 25 * 60, round = 1;
  String phase = '专注';
  bool running = false, ready = false, updating = false;
  String notice = '后台提醒可能受系统省电、通知设置或强行停止影响；请勿用于关键实验定时。';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restore();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> restore() async {
    final prefs = widget.state.prefs;
    await prefs.reload();
    for (final pair in [
      ('focus', focus),
      ('short', short),
      ('long', long),
      ('rounds', rounds),
    ]) {
      pair.$2.text = prefs.getString('pom_${pair.$1}') ?? pair.$2.text;
    }
    phase = prefs.getString('pom_phase') ?? '专注';
    round = prefs.getInt('pom_round') ?? 1;
    deadline = prefs.getInt('pom_deadline');
    running = deadline != null;
    remaining = prefs.getInt('pom_remaining') ?? 25 * 60;
    if (mounted) {
      setState(() => ready = true);
      tick();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) tick();
  }

  @override
  void dispose() {
    ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [focus, short, long, rounds]) {
      c.dispose();
    }
    super.dispose();
  }

  int count(TextEditingController c, {int max = 180}) {
    final n = int.tryParse(c.text);
    if (n == null || n < 1 || n > max) throw FormatException('请输入 1—$max 的整数');
    return n;
  }

  Future<void> persist() async {
    final prefs = widget.state.prefs;
    for (final pair in [
      ('focus', focus),
      ('short', short),
      ('long', long),
      ('rounds', rounds),
    ]) {
      await prefs.setString('pom_${pair.$1}', pair.$2.text);
    }
    await prefs.setString('pom_phase', phase);
    await prefs.setInt('pom_round', round);
    await prefs.setInt('pom_remaining', remaining);
    if (deadline == null) {
      await prefs.remove('pom_deadline');
    } else {
      await prefs.setInt('pom_deadline', deadline!);
    }
  }

  void tick() {
    if (!ready || !running || !mounted || deadline == null) return;
    final seconds = ((deadline! - DateTime.now().millisecondsSinceEpoch) / 1000)
        .ceil()
        .clamp(0, 10800);
    setState(() => remaining = seconds);
    if (seconds == 0) {
      running = false;
      deadline = null;
      persist();
      message(context, '$phase结束，点击下一阶段继续');
    }
  }

  Future<void> action(String kind) async {
    if (updating) return;
    setState(() => updating = true);
    try {
      final f = count(focus),
          s = count(short),
          l = count(long),
          total = count(rounds, max: 20);
      if (kind == '开始') {
        if (remaining <= 0) {
          remaining =
              (phase == '专注'
                  ? f
                  : phase == '短休息'
                  ? s
                  : l) *
              60;
        }
        // Initial configuration changes apply before the first start.
        if (!widget.state.prefs.containsKey('pom_phase')) remaining = f * 60;
        deadline = DateTime.now().millisecondsSinceEpoch + remaining * 1000;
        final allowed = await channel.invokeMethod<bool>('timerSchedule', {
          'deadline': deadline,
          'label': phase,
        });
        running = true;
        if (allowed != true) notice = '通知权限未开启，到时只会在 App 内显示；后台提醒不可用。';
      } else {
        tick();
        await channel.invokeMethod('timerCancel');
        running = false;
        deadline = null;
        if (kind == '重置') {
          phase = '专注';
          round = 1;
          remaining = f * 60;
        }
        if (kind == '下一阶段') {
          if (phase == '专注') {
            phase = round >= total ? '长休息' : '短休息';
            remaining = (phase == '长休息' ? l : s) * 60;
          } else {
            round = phase == '长休息' ? 1 : round + 1;
            phase = '专注';
            remaining = f * 60;
          }
        }
      }
      await persist();
    } catch (e) {
      if (mounted) {
        message(context, '操作失败：${e is FormatException ? e.message : e}');
      }
    } finally {
      if (mounted) setState(() => updating = false);
    }
  }

  Widget config(String label, TextEditingController c) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      enabled: !running && !updating,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
    ),
  );
  Future<void> selectPhase(String next) async {
    if (running || updating) return;
    setState(() => updating = true);
    try {
      final minutes = count(
        next == '专注'
            ? focus
            : next == '短休息'
            ? short
            : long,
      );
      setState(() {
        phase = next;
        remaining = minutes * 60;
      });
      await persist();
    } catch (e) {
      if (mounted) message(context, '$e');
    } finally {
      if (mounted) setState(() => updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration =
        int.tryParse(
          (phase == '专注'
                  ? focus
                  : phase == '短休息'
                  ? short
                  : long)
              .text,
        ) ??
        25;
    final progress = (remaining / (math.max(1, duration) * 60)).clamp(0.0, 1.0);
    final accent = phase == '专注' ? const Color(0xffd36b58) : scheme.primary;
    return Workbench(
      tool: widget.tool,
      state: widget.state,
      children: [
        if (!ready) const LinearProgressIndicator(),
        Text(
          'POMODORO',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(letterSpacing: 3),
        ),
        const SizedBox(height: 8),
        Text('留一点时间，专注当下。', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 22),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: '专注', label: Text('专注')),
            ButtonSegment(value: '短休息', label: Text('短休息')),
            ButtonSegment(value: '长休息', label: Text('长休息')),
          ],
          selected: {phase},
          onSelectionChanged: running || updating || !ready
              ? null
              : (v) => selectPhase(v.first),
        ),
        const SizedBox(height: 28),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: AspectRatio(
              aspectRatio: 1,
              child: CustomPaint(
                painter: TimerRingPainter(
                  progress,
                  accent,
                  scheme.surfaceContainerHighest,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      phase == '专注'
                          ? Icons.spa_outlined
                          : Icons.coffee_outlined,
                      color: accent,
                      size: 30,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${(remaining ~/ 60).toString().padLeft(2, '0')}:${(remaining % 60).toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.displayMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$phase · 第 $round 轮',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: accent),
          onPressed: !ready || updating
              ? null
              : () => action(running ? '暂停' : '开始'),
          icon: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded),
          label: Text(running ? '暂停' : '开始 / 继续'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: !ready || updating ? null : () => action('下一阶段'),
                child: const Text('跳过 / 下一阶段'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: !ready || updating ? null : () => action('重置'),
                child: const Text('重置'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          margin: EdgeInsets.zero,
          child: ExpansionTile(
            title: const Text('时长与轮次'),
            subtitle: Text(
              '${focus.text} / ${short.text} / ${long.text} 分钟 · ${rounds.text} 轮',
            ),
            childrenPadding: const EdgeInsets.all(18),
            children: [
              Row(
                children: [
                  Expanded(child: config('专注 / 分钟', focus)),
                  const SizedBox(width: 12),
                  Expanded(child: config('短休息 / 分钟', short)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: config('长休息 / 分钟', long)),
                  const SizedBox(width: 12),
                  Expanded(child: config('专注轮数', rounds)),
                ],
              ),
              const Text('修改后点按重置应用设置。'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(notice, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        const Text('每段结束后，手动开始下一段。', textAlign: TextAlign.center),
      ],
    );
  }
}

class TimerRingPainter extends CustomPainter {
  TimerRingPainter(this.progress, this.color, this.track);
  final double progress;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(12);
    canvas.drawOval(rect, Paint()..color = color.withValues(alpha: .06));
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(TimerRingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
