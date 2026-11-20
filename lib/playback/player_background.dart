import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cover_cache.dart';
import 'playback_controller.dart';

Duration playerLayoutFadeDuration(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 200);

class PlayerBackground extends StatefulWidget {
  const PlayerBackground({
    required this.playback,
    required this.immersive,
    required this.lyricsVisible,
    required this.builder,
    this.surfaceColor,
    this.shareBackdrop = false,
    super.key,
  });

  final PlaybackController? playback;
  final bool immersive, lyricsVisible;
  final Color? surfaceColor;
  final bool shareBackdrop;
  final Widget Function(
    BuildContext context,
    Color? controlColor,
    Color lyricsColor,
  )
  builder;

  static Widget sharedBackdropOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_PlayerBackdropScope>()!
      .backdrop;

  @override
  State<PlayerBackground> createState() => _PlayerBackgroundState();
}

class _PlayerBackgroundState extends State<PlayerBackground> {
  (String, int?, int?)? _coverKey;
  Future<((String, int?, int?), _BlurredCover?)?>? _cover;

  (String, int?, int?)? get _currentKey {
    final track = widget.playback?.current;
    return track == null ? null : (track.location, track.size, track.modified);
  }

  void _updateCover() {
    final key = _currentKey;
    if (key != _coverKey) {
      _coverKey = key;
      _cover = null;
    }
    if ((widget.immersive || widget.shareBackdrop) && key != null) {
      _cover ??= _loadCover(key);
    }
  }

  Future<((String, int?, int?), _BlurredCover?)?> _loadCover(
    (String, int?, int?) key,
  ) async {
    final playback = widget.playback!;
    final track = playback.current!;
    final bytes = await playback.documents.cachedCover(
      track,
      priority: () => mounted && _currentKey == key
          ? CoverPriority.current
          : CoverPriority.stale,
    );
    if (!mounted || _currentKey != key) return null;
    final blurred = await _BlurredCover.load(bytes);
    return mounted && _currentKey == key ? (key, blurred) : null;
  }

  Widget _gradient(ColorScheme scheme) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          scheme.secondaryContainer,
          scheme.surface,
          scheme.primaryContainer,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    _updateCover();
    final scheme = Theme.of(context).colorScheme;
    final immersive = widget.immersive;
    final lyrics = immersive && widget.lyricsVisible;
    final surfaceIsDark = scheme.brightness == Brightness.dark;
    final surface =
        widget.surfaceColor ??
        (surfaceIsDark ? const Color(0xFF161616) : Colors.white);
    return FutureBuilder(
      future: _cover,
      builder: (context, snapshot) {
        final coverReady =
            snapshot.connectionState == ConnectionState.done &&
            snapshot.data?.$1 == _coverKey;
        final cover = coverReady ? snapshot.data?.$2 : null;
        final lyricsDarkInk = cover == null ? !surfaceIsDark : cover.bright;
        final lyricsInk = lyricsDarkInk
            ? const Color(0xFF181A1E)
            : Colors.white;
        if (widget.shareBackdrop) {
          final fade = playerLayoutFadeDuration(context);
          final backdrop = Stack(
            fit: StackFit.expand,
            children: [
              _gradient(scheme),
              AnimatedSwitcher(
                duration: fade,
                // The default switcher loosens constraints for its layers.
                layoutBuilder: (current, outgoing) => Stack(
                  fit: StackFit.expand,
                  children: [...outgoing, ?current],
                ),
                child: cover == null
                    ? const SizedBox.expand()
                    : Image.memory(
                        cover.bytes,
                        key: ValueKey(_coverKey),
                        fit: BoxFit.fill,
                        excludeFromSemantics: true,
                      ),
              ),
              AnimatedContainer(
                duration: fade,
                color: (lyricsDarkInk ? Colors.white : Colors.black).withValues(
                  alpha: .55,
                ),
              ),
            ],
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: surface),
              AnimatedOpacity(
                opacity: immersive ? 1 : 0,
                duration: fade,
                child: IgnorePointer(child: backdrop),
              ),
              _PlayerBackdropScope(
                backdrop: backdrop,
                appearance: (scheme, cover, fade),
                child: widget.builder(context, null, lyricsInk),
              ),
            ],
          );
        }
        final lightSystemIcons = lyrics
            ? !lyricsDarkInk
            : !immersive || cover == null
            ? surfaceIsDark
            : !cover.topBright;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: lightSystemIcons
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: surface),
              AnimatedOpacity(
                duration: playerLayoutFadeDuration(context),
                opacity: immersive && (coverReady || _coverKey == null) ? 1 : 0,
                child: RepaintBoundary(
                  child: cover != null
                      ? Image.memory(
                          cover.bytes,
                          key: ValueKey(_coverKey),
                          fit: BoxFit.fill,
                          excludeFromSemantics: true,
                        )
                      : coverReady || _coverKey == null
                      ? _gradient(scheme)
                      : const SizedBox.expand(),
                ),
              ),
              AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context) || !immersive
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                color: lyrics
                    ? (lyricsDarkInk ? Colors.white : Colors.black).withValues(
                        alpha: .55,
                      )
                    : Colors.transparent,
              ),
              widget.builder(
                context,
                immersive
                    ? (cover?.bottomBright ?? !surfaceIsDark)
                          ? const Color(0xFF181A1E)
                          : Colors.white
                    : null,
                immersive ? lyricsInk : scheme.onSurface,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayerBackdropScope extends InheritedWidget {
  const _PlayerBackdropScope({
    required this.backdrop,
    required this.appearance,
    required super.child,
  });

  final Widget backdrop;
  final (ColorScheme, _BlurredCover?, Duration) appearance;

  @override
  bool updateShouldNotify(_PlayerBackdropScope oldWidget) =>
      oldWidget.appearance != appearance;
}

class _BlurredCover {
  const _BlurredCover(
    this.bytes,
    this.bright,
    this.topBright,
    this.bottomBright,
  );

  final Uint8List bytes;
  final bool bright, topBright, bottomBright;

  static const _size = 48;

  // Blur the small texture once per cover. Painting or moving the page only
  // scales the resulting bitmap.
  static Future<_BlurredCover?> load(Uint8List? bytes) async {
    if (bytes == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final image = (await codec.getNextFrame()).image;
        try {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            Rect.fromLTWH(0, 0, _size.toDouble(), _size.toDouble()),
            Paint()
              ..filterQuality = FilterQuality.low
              ..imageFilter = ui.ImageFilter.blur(
                sigmaX: 5,
                sigmaY: 5,
                tileMode: TileMode.clamp,
              ),
          );
          final picture = recorder.endRecording();
          try {
            final blurred = await picture.toImage(_size, _size);
            try {
              final pixels = await blurred.toByteData(
                format: ui.ImageByteFormat.rawStraightRgba,
              );
              final png = await blurred.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (pixels == null || png == null) return null;
              return _BlurredCover(
                png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
                _isBright(pixels, 0, _size),
                _isBright(pixels, 0, 6),
                _isBright(pixels, 36, _size - 2),
              );
            } finally {
              blurred.dispose();
            }
          } finally {
            picture.dispose();
          }
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  static bool _isBright(ByteData pixels, int startRow, int endRow) {
    var luma = 0.0;
    var weight = 0.0;
    for (var y = startRow; y < endRow; y += 3) {
      for (var x = 2; x < _size - 2; x += 3) {
        final offset = (y * _size + x) * 4;
        final alpha = pixels.getUint8(offset + 3) / 255;
        luma +=
            alpha *
            Color.fromARGB(
              255,
              pixels.getUint8(offset),
              pixels.getUint8(offset + 1),
              pixels.getUint8(offset + 2),
            ).computeLuminance();
        weight += alpha;
      }
    }
    return weight > 0 && luma / weight >= .26;
  }
}
