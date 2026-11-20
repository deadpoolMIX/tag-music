import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({super.key});

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> {
  static const _window = MethodChannel('tag_music/window');
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    _window.setMethodCallHandler((call) async {
      if (call.method == 'maximizedChanged' && call.arguments is bool) {
        _updateMaximized(call.arguments as bool);
      }
    });
    unawaited(_readWindowState());
  }

  Future<void> _readWindowState() async {
    try {
      _updateMaximized(
        await _window.invokeMethod<bool>('isMaximized') ?? false,
      );
    } on MissingPluginException {
      // The Flutter view can be hosted without the Windows runner.
    }
  }

  void _updateMaximized(bool maximized) {
    if (mounted && maximized != _maximized) {
      setState(() => _maximized = maximized);
    }
  }

  void _command(String name) => unawaited(_window.invokeMethod<void>(name));

  @override
  void dispose() {
    _window.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => _command('drag'),
                onDoubleTap: () => _command('toggleMaximize'),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 13),
                  child: Row(
                    spacing: 8,
                    children: [
                      Icon(
                        Icons.library_music_rounded,
                        size: 18,
                        color: colors.primary,
                      ),
                      Expanded(
                        child: Text(
                          'Tag Music',
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _windowButton('最小化', Icons.remove_rounded, 'minimize'),
            _windowButton(
              _maximized ? '还原窗口' : '最大化',
              _maximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              'toggleMaximize',
            ),
            _windowButton(
              '关闭',
              Icons.close_rounded,
              'close',
              closeColor: colors.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _windowButton(
    String label,
    IconData icon,
    String command, {
    Color? closeColor,
  }) => IconButton(
    tooltip: label,
    onPressed: () => _command(command),
    style: IconButton.styleFrom(
      minimumSize: const Size(38, 32),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      overlayColor: closeColor,
    ),
    icon: Icon(icon, size: 17),
  );
}
