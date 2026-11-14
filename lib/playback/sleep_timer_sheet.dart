import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'playback_controller.dart';

String sleepTimeLabel(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes % 60;
  final seconds = value.inSeconds % 60;
  return '${hours > 0 ? '$hours小时' : ''}$minutes分${seconds.toString().padLeft(2, '0')}秒';
}

/// Uses the controller's playback clock; this view never starts another timer.
class SleepTimerStatus extends StatelessWidget {
  const SleepTimerStatus({required this.playback, super.key});
  final PlaybackController playback;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: const ValueKey('sleep-timer-status'),
    onPressed: () => showSleepTimer(context, playback),
    icon: const Icon(Icons.bedtime_outlined, size: 18),
    label: Text(
      playback.sleep.waitingForEnd
          ? '本曲结束后停止'
          : '还可播放 ${sleepTimeLabel(playback.sleep.remaining)}',
      textAlign: TextAlign.center,
    ),
  );
}

Future<void> showSleepTimer(
  BuildContext context,
  PlaybackController playback,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: ListenableBuilder(
          listenable: playback,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('睡眠定时', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(
                playback.sleep.waitingForEnd
                    ? '已到时间，将在当前歌曲结束后停止。切换歌曲会停止播放；取消定时后可继续切换。'
                    : playback.sleep.active
                    ? '剩余实际播放时间：${sleepTimeLabel(playback.sleep.remaining)}'
                    : '按实际播放时间计时，暂停或缓冲时不计。到时间后播完当前歌曲再停止。',
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in [15, 30, 45, 60])
                    FilledButton.tonal(
                      onPressed: () {
                        unawaited(
                          playback.setSleepTimer(Duration(minutes: minutes)),
                        );
                        Navigator.pop(context);
                      },
                      child: Text('$minutes 分钟'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final duration = await showDialog<Duration>(
                    context: context,
                    builder: (_) => const _SleepDialDialog(),
                  );
                  if (duration == null) return;
                  await playback.setSleepTimer(duration);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('自定义时间'),
              ),
              if (playback.sleep.active)
                TextButton(
                  onPressed: () {
                    unawaited(playback.cancelSleepTimer());
                    Navigator.pop(context);
                  },
                  child: const Text('取消定时'),
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);

class _SleepDialDialog extends StatefulWidget {
  const _SleepDialDialog();
  @override
  State<_SleepDialDialog> createState() => _SleepDialDialogState();
}

class _SleepDialDialogState extends State<_SleepDialDialog> {
  int _hours = 0, _minutes = 15;
  bool _hourDial = false;
  int get _count => _hourDial ? 13 : 60;
  int get _value => _hourDial ? _hours : _minutes;
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$_hours 小时 $_minutes 分钟',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _hourDial = !_hourDial),
                  child: Text(_hourDial ? '选择分钟' : '选择小时'),
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
                  value: '$_value',
                  increasedValue: '${(_value + 1).clamp(0, _count - 1)}',
                  decreasedValue: '${(_value - 1).clamp(0, _count - 1)}',
                  onIncrease: () => _set(_value + 1),
                  onDecrease: () => _set(_value - 1),
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
                    },
                    child: Focus(
                      autofocus: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (event) => _point(event.localPosition, side),
                        onPanStart: (event) =>
                            _point(event.localPosition, side),
                        onPanUpdate: (event) =>
                            _point(event.localPosition, side),
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
                );
              },
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
