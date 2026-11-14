import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'playback_controller.dart';

String sleepTimeLabel(Duration value) {
  // Round up so a positive remainder never looks like an expired timer.
  final totalSeconds = math.max(
    0,
    (value.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/
        Duration.microsecondsPerSecond,
  );
  final hours = totalSeconds ~/ 3600;
  final minutes = totalSeconds ~/ 60 % 60;
  final seconds = totalSeconds % 60;
  return '${hours > 0 ? '$hours小时' : ''}$minutes分${seconds.toString().padLeft(2, '0')}秒';
}

String sleepTimerProgressLabel(PlaybackController playback) =>
    playback.sleep.waitingForEnd
    ? '本曲结束后停止'
    : '${playback.sleepCounting ? '计时中' : '计时已暂停'} · 还可播放 ${sleepTimeLabel(playback.sleep.remaining)}';

/// Uses the controller's playback clock; this view never starts another timer.
class SleepTimerStatus extends StatelessWidget {
  const SleepTimerStatus({required this.playback, this.onManage, super.key});
  final PlaybackController playback;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: const ValueKey('sleep-timer-status'),
    onPressed: onManage ?? () => showSleepTimer(context, playback),
    icon: const Icon(Icons.bedtime_outlined, size: 18),
    label: Text(sleepTimerProgressLabel(playback), textAlign: TextAlign.center),
  );
}

Future<void> showSleepTimer(
  BuildContext context,
  PlaybackController playback,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _SleepTimerPanel(playback: playback),
);

class _SleepTimerPanel extends StatefulWidget {
  const _SleepTimerPanel({required this.playback});
  final PlaybackController playback;
  @override
  State<_SleepTimerPanel> createState() => _SleepTimerPanelState();
}

class _SleepTimerPanelState extends State<_SleepTimerPanel> {
  bool _submitting = false, _choosing = false;
  String? _error;
  bool get _busy => _submitting || _choosing;

  Future<void> _apply(Duration? duration) async {
    if (_busy) return;
    final playback = widget.playback;
    final generation = playback.sleep.generation;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (duration == null) {
        await playback.cancelSleepTimer();
      } else {
        await playback.setSleepTimer(duration);
      }
      if (!mounted) return;
      // The controller serial lane reports errors without throwing. An unchanged
      // generation also covers a request ignored by a disposed controller.
      if (playback.sleep.generation == generation) {
        setState(() => _error = playback.error ?? '定时尚未更新，请稍后重试。');
      } else if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '定时操作失败：$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _custom() async {
    if (_busy) return;
    setState(() => _choosing = true);
    Duration? duration;
    try {
      duration = await showDialog<Duration>(
        context: context,
        builder: (_) => const _SleepDialDialog(),
      );
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
    if (!mounted || duration == null) return;
    await _apply(duration);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: ListenableBuilder(
          listenable: widget.playback,
          builder: (context, _) {
            final sleep = widget.playback.sleep;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('睡眠定时', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(
                  sleep.waitingForEnd
                      ? '已到时间，将在当前歌曲结束后停止。切换歌曲会停止播放；取消定时后可继续切换。'
                      : sleep.active
                      ? sleepTimerProgressLabel(widget.playback)
                      : '按实际播放时间计时，暂停或缓冲时不计。到时间后播完当前歌曲再停止。',
                ),
                if (sleep.active && !sleep.waitingForEnd) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.playback.sleepCounting
                        ? '正在按实际播放时间累计。选择新时长会重新开始计时；暂停和缓冲时不计时。'
                        : '当前未累计，恢复实际播放后继续。选择新时长会重新开始计时；暂停和缓冲时不计时。',
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final minutes in [15, 30, 45, 60])
                      FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _apply(Duration(minutes: minutes)),
                        child: Text('$minutes 分钟'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : _custom,
                  child: const Text('自定义时间'),
                ),
                if (sleep.active)
                  TextButton(
                    onPressed: _busy ? null : () => _apply(null),
                    child: const Text('取消定时'),
                  ),
                if (_submitting)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: const Text('正在更新定时…', textAlign: TextAlign.center),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _SleepDialDialog extends StatefulWidget {
  const _SleepDialDialog();
  @override
  State<_SleepDialDialog> createState() => _SleepDialDialogState();
}

class _SleepDialDialogState extends State<_SleepDialDialog> {
  final _dialFocus = FocusNode(debugLabel: 'sleep-time-dial');
  int _hours = 0, _minutes = 15;
  bool _hourDial = false, _showFocus = false;
  int get _count => _hourDial ? 13 : 60;
  int get _value => _hourDial ? _hours : _minutes;
  String get _unit => _hourDial ? '小时' : '分钟';

  @override
  void dispose() {
    _dialFocus.dispose();
    super.dispose();
  }

  void _set(int value) => setState(() {
    if (_hourDial) {
      _hours = value.clamp(0, 12);
    } else {
      _minutes = value.clamp(0, 59);
    }
  });
  void _point(Offset point, double side) {
    final delta = point - Offset(side / 2, side / 2);
    if (delta.distance < side * .12) return;
    final angle =
        (math.atan2(delta.dy, delta.dx) + math.pi / 2) % (2 * math.pi);
    _set((angle * _count / (2 * math.pi)).round() % _count);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义睡眠时间'),
    content: SizedBox(
      width: 300,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_hours 小时 $_minutes 分钟',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('选择小时'),
                  selected: _hourDial,
                  onSelected: (_) => setState(() => _hourDial = true),
                ),
                ChoiceChip(
                  label: const Text('选择分钟'),
                  selected: !_hourDial,
                  onSelected: (_) => setState(() => _hourDial = false),
                ),
              ],
            ),
            Text(_hourDial ? '小时 · 0～12' : '分钟 · 0～59'),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final side = math.min(280.0, constraints.maxWidth);
                return Semantics(
                  label: _hourDial ? '小时圆盘' : '分钟圆盘',
                  value: '$_value $_unit',
                  increasedValue: _value < _count - 1
                      ? '${_value + 1} $_unit'
                      : null,
                  decreasedValue: _value > 0 ? '${_value - 1} $_unit' : null,
                  onIncrease: _value < _count - 1
                      ? () => _set(_value + 1)
                      : null,
                  onDecrease: _value > 0 ? () => _set(_value - 1) : null,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                          _set(_value + 1),
                      const SingleActivator(
                        LogicalKeyboardKey.arrowRight,
                      ): () =>
                          _set(_value + 1),
                      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                          _set(_value - 1),
                      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                          _set(_value - 1),
                      const SingleActivator(LogicalKeyboardKey.home): () =>
                          _set(0),
                      const SingleActivator(LogicalKeyboardKey.end): () =>
                          _set(_count - 1),
                    },
                    child: FocusableActionDetector(
                      autofocus: true,
                      focusNode: _dialFocus,
                      onShowFocusHighlight: (value) =>
                          setState(() => _showFocus = value),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (event) {
                          _dialFocus.requestFocus();
                          _point(event.localPosition, side);
                        },
                        onPanStart: (event) {
                          _dialFocus.requestFocus();
                          _point(event.localPosition, side);
                        },
                        onPanUpdate: (event) =>
                            _point(event.localPosition, side),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              width: 2,
                              color: _showFocus
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                            ),
                          ),
                          child: CustomPaint(
                            size: Size.square(side),
                            painter: _SleepDialPainter(
                              count: _count,
                              selected: _value,
                              scheme: Theme.of(context).colorScheme,
                              textScaler: MediaQuery.textScalerOf(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.outlined(
                  tooltip: '减少1$_unit',
                  onPressed: _value == 0 ? null : () => _set(_value - 1),
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: Text('$_value $_unit', textAlign: TextAlign.center),
                ),
                IconButton.outlined(
                  tooltip: '增加1$_unit',
                  onPressed: _value == _count - 1
                      ? null
                      : () => _set(_value + 1),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('切换小时与分钟会保留选择，最长12小时59分钟。', textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('返回'),
      ),
      FilledButton(
        onPressed: _hours == 0 && _minutes == 0
            ? null
            : () => Navigator.pop(
                context,
                Duration(hours: _hours, minutes: _minutes),
              ),
        child: const Text('开始计时'),
      ),
    ],
  );
}

class _SleepDialPainter extends CustomPainter {
  _SleepDialPainter({
    required this.count,
    required this.selected,
    required this.scheme,
    required this.textScaler,
  });
  final int count, selected;
  final ColorScheme scheme;
  final TextScaler textScaler;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.shortestSide * .46;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = scheme.surfaceContainerHighest,
    );
    Offset point(int value, double fraction) {
      final angle = value * 2 * math.pi / count - math.pi / 2;
      return center +
          Offset(math.cos(angle), math.sin(angle)) * (radius * fraction);
    }

    final selectedPoint = point(selected, .78);
    canvas.drawLine(
      center,
      selectedPoint,
      Paint()
        ..color = scheme.primary
        ..strokeWidth = 2,
    );
    canvas.drawCircle(selectedPoint, 19, Paint()..color = scheme.primary);
    canvas.drawCircle(center, 4, Paint()..color = scheme.primary);
    for (var i = 0; i < count; i++) {
      final labelled = count == 13 || i % 5 == 0 || i == selected;
      if (!labelled) {
        canvas.drawCircle(
          point(i, .78),
          1,
          Paint()..color = scheme.onSurfaceVariant,
        );
        continue;
      }
      final label = TextPainter(
        text: TextSpan(
          text: '$i',
          style: TextStyle(
            fontSize: 14,
            color: i == selected ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(math.min(textScaler.scale(14) / 14, 1.3)),
      )..layout();
      label.paint(
        canvas,
        point(i, .78) - Offset(label.width / 2, label.height / 2),
      );
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(_SleepDialPainter old) =>
      old.count != count ||
      old.selected != selected ||
      old.scheme != scheme ||
      old.textScaler != textScaler;
}
