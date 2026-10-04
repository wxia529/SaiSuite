import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../core/platform_channel.dart';
import 'package:video_player/video_player.dart';

class VideoStudioPreview extends StatefulWidget {
  const VideoStudioPreview({
    super.key,
    required this.path,
    required this.start,
    required this.end,
    required this.frame,
    required this.frameMode,
    required this.onFrame,
    this.disabled = false,
  });
  final String path;
  final double start, end, frame;
  final bool frameMode, disabled;
  final ValueChanged<double> onFrame;
  @override
  State<VideoStudioPreview> createState() => _VideoStudioPreviewState();
}

class _VideoStudioPreviewState extends State<VideoStudioPreview>
    with WidgetsBindingObserver {
  static const native = SaiChannel('saisuite/media');
  late final controller = VideoPlayerController.file(File(widget.path));
  final thumbnails = <String>[];
  bool looping = true, seeking = false, disposed = false;
  bool restartingLoop = false;
  double? pendingSeek;
  Timer? seekTimer;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(tick);
    initialize();
  }

  Future<void> initialize() async {
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {});
      final duration = controller.value.duration.inMilliseconds / 1000;
      for (var i = 0; i < 6; i++) {
        if (disposed) break;
        final result = await native.invokeMapMethod<String, dynamic>(
          'videoThumbnail',
          {'path': widget.path, 'seconds': duration * i / 6},
        );
        if (result != null) {
          final path = result['path'] as String;
          if (disposed) {
            await native.invokeMethod<void>('mediaCleanup', {
              'paths': [path],
            });
            break;
          }
          setState(() => thumbnails.add(path));
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '预览失败：$e');
    }
  }

  void tick() {
    if (!mounted || !controller.value.isInitialized) return;
    if (controller.value.hasError) {
      if (error == null) {
        setState(() => error = controller.value.errorDescription);
      }
      return;
    }
    if (looping &&
        !widget.disabled &&
        !widget.frameMode &&
        (controller.value.isPlaying || controller.value.isCompleted) &&
        !restartingLoop &&
        !seeking &&
        widget.end > widget.start &&
        controller.value.position.inMilliseconds / 1000 >= widget.end) {
      restartLoop();
    }
  }

  Future<void> restartLoop() async {
    restartingLoop = true;
    try {
      await controller.seekTo(
        Duration(milliseconds: (widget.start * 1000).round()),
      );
      if (!disposed && looping && !widget.disabled && !widget.frameMode) {
        await controller.play();
      }
    } catch (e) {
      if (mounted) setState(() => error = '循环播放失败：$e');
    } finally {
      restartingLoop = false;
    }
  }

  void seek(double seconds, {bool immediate = false}) {
    pendingSeek = seconds;
    seekTimer?.cancel();
    if (immediate) {
      flushSeek();
    } else {
      seekTimer = Timer(const Duration(milliseconds: 80), flushSeek);
    }
  }

  Future<void> flushSeek() async {
    if (disposed ||
        seeking ||
        pendingSeek == null ||
        !controller.value.isInitialized) {
      return;
    }
    final seconds = pendingSeek!;
    pendingSeek = null;
    seeking = true;
    try {
      await controller.seekTo(Duration(milliseconds: (seconds * 1000).round()));
    } catch (e) {
      if (mounted) setState(() => error = '定位失败：$e');
    } finally {
      seeking = false;
      if (!disposed && pendingSeek != null) flushSeek();
    }
  }

  @override
  void didUpdateWidget(VideoStudioPreview old) {
    super.didUpdateWidget(old);
    if (widget.disabled || widget.frameMode) controller.pause();
    if (widget.frameMode &&
        (old.frame != widget.frame || old.frameMode != widget.frameMode)) {
      seek(widget.frame);
    } else if (old.start != widget.start) {
      seek(widget.start);
    } else if (old.end != widget.end) {
      seek(widget.end);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) controller.pause();
  }

  @override
  void dispose() {
    disposed = true;
    seekTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(tick);
    controller.dispose();
    native.invokeMethod<void>('mediaCleanup', {'paths': thumbnails});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (controller.value.isInitialized) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: ColoredBox(
              color: Colors.black,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (c, v, _) => Row(
            children: [
              IconButton(
                tooltip: v.isPlaying ? '暂停' : '播放',
                onPressed: widget.disabled
                    ? null
                    : () async {
                        if (v.isPlaying) {
                          await controller.pause();
                        } else {
                          if (looping &&
                              !widget.frameMode &&
                              (v.position.inMilliseconds / 1000 <
                                      widget.start ||
                                  v.position.inMilliseconds / 1000 >=
                                      widget.end)) {
                            seek(widget.start, immediate: true);
                          }
                          await controller.play();
                        }
                      },
                icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              Expanded(
                child: Slider(
                  value: v.position.inMilliseconds.toDouble().clamp(
                    0,
                    v.duration.inMilliseconds.toDouble(),
                  ),
                  max: v.duration.inMilliseconds.toDouble().clamp(
                    1,
                    double.infinity,
                  ),
                  onChanged: widget.disabled
                      ? null
                      : (ms) {
                          controller.pause();
                          seek(ms / 1000);
                          if (widget.frameMode) widget.onFrame(ms / 1000);
                        },
                ),
              ),
              Text(
                '${(v.position.inMilliseconds / 1000).toStringAsFixed(2)} s',
              ),
            ],
          ),
        ),
        if (thumbnails.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 55,
              child: Row(
                children: [
                  for (var i = 0; i < thumbnails.length; i++)
                    Expanded(
                      child: InkWell(
                        onTap: widget.disabled
                            ? null
                            : () {
                                final t =
                                    controller.value.duration.inMilliseconds /
                                    1000 *
                                    i /
                                    6;
                                controller.pause();
                                seek(t, immediate: true);
                                if (widget.frameMode) widget.onFrame(t);
                              },
                        child: Image.file(
                          File(thumbnails[i]),
                          fit: BoxFit.cover,
                          height: 55,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (!widget.frameMode)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('循环播放选中片段'),
            value: looping,
            onChanged: widget.disabled
                ? null
                : (v) => setState(() => looping = v),
          ),
        if (widget.frameMode) const Text('播放器用于定位；生成截帧后显示实际导出的画面。'),
      ] else if (error == null)
        const Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
    ],
  );
}
