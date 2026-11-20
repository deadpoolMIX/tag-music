import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/compact_dialog.dart';

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
) => showDialog<void>(
  context: context,
  builder: (_) => _SleepDialDialog(playback: playback),
);

class _SleepDialDialog extends StatefulWidget {
  const _SleepDialDialog({required this.playback});
  final PlaybackController playback;

  @override
  State<_SleepDialDialog> createState() => _SleepDialDialogState();
}

class _SleepDialDialogState extends State<_SleepDialDialog> {
  final _dialFocus = FocusNode(debugLabel: 'sleep-time-dial');
  int _hours = 0, _minutes = 15;
  bool _hourDial = false, _showFocus = false, _submitting = false;
  String? _error;
  int? _dialPointer;

  int get _count => _hourDial ? 13 : 60;
  int get _value => _hourDial ? _hours : _minutes;
  String get _unit => _hourDial ? '小时' : '分钟';
  Duration get _duration => Duration(hours: _hours, minutes: _minutes);

  Future<void> _apply(Duration? duration) async {
    if (_submitting) return;
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

  void _set(int value) {
    final next = value.clamp(0, _count - 1);
    if (_submitting || next == _value) return;
    setState(() {
      if (_hourDial) {
        _hours = next;
      } else {
        _minutes = next;
      }
    });
  }

  void _point(Offset point, double side) {
    final delta = point - Offset(side / 2, side / 2);
    if (delta.distanceSquared < 9) return;
    final angle =
        (math.atan2(delta.dy, delta.dx) + math.pi / 2) % (2 * math.pi);
    _set((angle * _count / (2 * math.pi)).round() % _count);
  }

  Widget _dial(BuildContext context, double side) => Semantics(
    label: '${_unit}圆盘',
    value: '$_value $_unit',
    increasedValue: _value < _count - 1 ? '${_value + 1} $_unit' : null,
    decreasedValue: _value > 0 ? '${_value - 1} $_unit' : null,
    onIncrease: _value < _count - 1 ? () => _set(_value + 1) : null,
    onDecrease: _value > 0 ? () => _set(_value - 1) : null,
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _set(_value + 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _set(_value + 1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _set(_value - 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _set(_value - 1),
        const SingleActivator(LogicalKeyboardKey.home): () => _set(0),
        const SingleActivator(LogicalKeyboardKey.end): () => _set(_count - 1),
      },
      child: FocusableActionDetector(
        focusNode: _dialFocus,
        onShowFocusHighlight: (value) => setState(() => _showFocus = value),
        child: ClipOval(
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              EagerGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                    () => EagerGestureRecognizer(
                      supportedDevices: const {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.stylus,
                        PointerDeviceKind.invertedStylus,
                      },
                      allowedButtonsFilter: (buttons) =>
                          buttons == kPrimaryButton,
                    ),
                    (_) {},
                  ),
            },
            child: Listener(
              onPointerDown: (event) {
                if (_submitting ||
                    _dialPointer != null ||
                    event.buttons != kPrimaryButton) {
                  return;
                }
                _dialPointer = event.pointer;
                _dialFocus.requestFocus();
                _point(event.localPosition, side);
              },
              onPointerMove: (event) {
                if (event.pointer == _dialPointer) {
                  _point(event.localPosition, side);
                }
              },
              onPointerUp: _releaseDial,
              onPointerCancel: _releaseDial,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: _showFocus
                      ? Border.all(color: Theme.of(context).colorScheme.primary)
                      : null,
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
      ),
    ),
  );

  void _releaseDial(PointerEvent event) {
    if (event.pointer == _dialPointer) _dialPointer = null;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.playback,
    builder: (context, _) {
      final playback = widget.playback;
      return CompactAlertDialog(
        title: const Text('睡眠定时'),
        scrollable: true,
        content: SizedBox(
          width: 264,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                children: [
                  for (final minutes in [15, 30, 45, 60])
                    Tooltip(
                      message: '$minutes 分钟',
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          minimumSize: const Size.square(44),
                          padding: const EdgeInsets.all(6),
                        ),
                        onPressed: _submitting
                            ? null
                            : () => _apply(Duration(minutes: minutes)),
                        child: Text('$minutes'),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      _hours == 0 ? '$_minutes 分钟' : '$_hours 小时 $_minutes 分钟',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: IconButton.filledTonal(
                      tooltip: _hourDial ? '切换到分钟' : '切换到小时',
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _hourDial = !_hourDial),
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(36),
                        padding: EdgeInsets.zero,
                      ),
                      icon: Text(_hourDial ? 'H' : 'S'),
                    ),
                  ),
                ],
              ),
              LayoutBuilder(
                builder: (context, constraints) =>
                    _dial(context, math.min(216, constraints.maxWidth) * .92),
              ),
              if (playback.sleep.active)
                Text(sleepTimerProgressLabel(playback)),
              if (_submitting) const LinearProgressIndicator(),
              if (_error case final error?)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (playback.sleep.active)
            TextButton(
              onPressed: _submitting ? null : () => _apply(null),
              child: const Text('取消定时'),
            )
          else
            TextButton(
              onPressed: _submitting ? null : () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          FilledButton(
            onPressed: _submitting || _duration == Duration.zero
                ? null
                : () => _apply(_duration),
            child: const Text('开始计时'),
          ),
        ],
      );
    },
  );

  @override
  void dispose() {
    _dialFocus.dispose();
    super.dispose();
  }
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
    final center = size.center(Offset.zero), radius = size.shortestSide / 2;
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

    final selectedPoint = point(selected, .47);
    canvas.drawLine(
      center,
      selectedPoint,
      Paint()
        ..color = scheme.primary
        ..strokeWidth = 2,
    );
    canvas.drawCircle(selectedPoint, 15, Paint()..color = scheme.primary);
    canvas.drawCircle(center, 3, Paint()..color = scheme.primary);
    void drawLabel(int value, Offset position, Color color) {
      final label = TextPainter(
        text: TextSpan(
          text: '$value',
          style: TextStyle(fontSize: 14, color: color),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(math.min(textScaler.scale(14) / 14, 1.3)),
      )..layout();
      label.paint(canvas, position - Offset(label.width / 2, label.height / 2));
      label.dispose();
    }

    for (var i = 0; i < count; i += count == 60 ? 5 : 1) {
      drawLabel(i, point(i, .78), scheme.onSurface);
    }
    drawLabel(selected, selectedPoint, scheme.onPrimary);
  }

  @override
  bool shouldRepaint(_SleepDialPainter old) =>
      old.count != count ||
      old.selected != selected ||
      old.scheme != scheme ||
      old.textScaler != textScaler;
}
