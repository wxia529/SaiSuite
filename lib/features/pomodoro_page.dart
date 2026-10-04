import 'dart:async';

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
  @override
  Widget build(BuildContext context) => Workbench(
    tool: widget.tool,
    state: widget.state,
    children: [
      if (!ready) const LinearProgressIndicator(),
      Text(
        '$phase · 第 $round 轮',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '${(remaining ~/ 60).toString().padLeft(2, '0')}:${(remaining % 60).toString().padLeft(2, '0')}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displayLarge,
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: !ready || updating
                ? null
                : () => action(running ? '暂停' : '开始'),
            child: Text(running ? '暂停' : '开始 / 继续'),
          ),
          OutlinedButton(
            onPressed: !ready || updating ? null : () => action('下一阶段'),
            child: const Text('跳过 / 下一阶段'),
          ),
          TextButton(
            onPressed: !ready || updating ? null : () => action('重置'),
            child: const Text('重置'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      config('专注时长（分钟，1—180）', focus),
      config('短休息（分钟，1—180）', short),
      config('长休息（分钟，1—180）', long),
      config('长休息前的专注轮数（1—20）', rounds),
      Text(notice),
      const SizedBox(height: 8),
      const Text('每段结束后由你确认开始下一段。只保存当前计时状态和设置，不建立专注历史。'),
    ],
  );
}
