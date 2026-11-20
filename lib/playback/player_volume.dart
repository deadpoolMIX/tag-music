import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show MatrixUtils;

import 'playback_controller.dart';

class PlayerVolume extends StatefulWidget {
  const PlayerVolume({required this.playback, super.key});

  final PlaybackController playback;

  @override
  State<PlayerVolume> createState() => _PlayerVolumeState();
}

class _PlayerVolumeState extends State<PlayerVolume> {
  final _overlay = OverlayPortalController();
  Timer? _hideTimer;

  void _show() {
    _hideTimer?.cancel();
    if (!_overlay.isShowing) _overlay.show();
  }

  void _scheduleHide(PointerExitEvent _) {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 180), _overlay.hide);
  }

  void _scroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      unawaited(
        widget.playback.adjustVolume(event.scrollDelta.dy < 0 ? 5 : -5),
      );
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final volume = widget.playback.player.state.volume.clamp(0.0, 100.0);
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlay,
      overlayChildBuilder: (context, info) {
        final anchor = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );
        const width = 60.0;
        final height = anchor.top.clamp(0.0, 152.0);
        if (height < 56) return const SizedBox.shrink();
        return Positioned(
          left: (anchor.center.dx - width / 2).clamp(
            0.0,
            (info.overlaySize.width - width).clamp(0.0, double.infinity),
          ),
          bottom: info.overlaySize.height - anchor.top,
          width: width,
          height: height,
          child: MouseRegion(
            onEnter: (_) => _show(),
            onExit: _scheduleHide,
            child: Listener(
              onPointerSignal: _scroll,
              child: Material(
                elevation: 5,
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  children: [
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Semantics(
                          label: '播放音量',
                          child: Slider(
                            value: volume,
                            max: 100,
                            semanticFormatterCallback: (value) =>
                                '${value.round()}%',
                            onChanged: widget.playback.setVolume,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('${volume.round()}%'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => _show(),
        onExit: _scheduleHide,
        child: Listener(
          onPointerSignal: _scroll,
          child: IconButton(
            key: const ValueKey('player-volume'),
            onPressed: _show,
            icon: Icon(
              volume == 0
                  ? Icons.volume_off_outlined
                  : Icons.volume_up_outlined,
              semanticLabel: '音量 ${volume.round()}%',
            ),
          ),
        ),
      ),
    );
  }
}
