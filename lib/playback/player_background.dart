import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'playback_controller.dart';

class PlayerBackground extends StatefulWidget {
  const PlayerBackground({
    required this.playback,
    required this.immersive,
    required this.lyricsVisible,
    required this.builder,
    super.key,
  });

  final PlaybackController playback;
  final bool immersive, lyricsVisible;
  final Widget Function(
    BuildContext context,
    Color? controlColor,
    Color lyricsColor,
  )
  builder;

  @override
  State<PlayerBackground> createState() => _PlayerBackgroundState();
}

class _PlayerBackgroundState extends State<PlayerBackground> {
  (String, int?, int?)? _coverKey;
  Future<_BlurredCover?>? _cover;

  void _updateCover() {
    final track = widget.playback.current;
    final key = track == null
        ? null
        : (track.location, track.size, track.modified);
    if (key == _coverKey) return;
    _coverKey = key;
    _cover = track == null
        ? null
        : widget.playback.documents.cachedCover(track).then(_BlurredCover.load);
  }

  @override
  Widget build(BuildContext context) {
    _updateCover();
    final scheme = Theme.of(context).colorScheme;
    final immersive = widget.immersive;
    final lyrics = immersive && widget.lyricsVisible;
    final surfaceIsDark = scheme.brightness == Brightness.dark;
    return FutureBuilder<_BlurredCover?>(
      future: _cover,
      builder: (context, snapshot) {
        final cover = snapshot.connectionState == ConnectionState.done
            ? snapshot.data
            : null;
        final lyricsDarkInk = cover == null ? !surfaceIsDark : cover.bright;
        final lyricsInk = lyricsDarkInk
            ? const Color(0xFF181A1E)
            : Colors.white;
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
              RepaintBoundary(
                child: DecoratedBox(
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
                  child: cover == null
                      ? const SizedBox.expand()
                      : ExcludeSemantics(
                          child: Image.memory(
                            cover.bytes,
                            fit: BoxFit.fill,
                            opacity: immersive
                                ? null
                                : const AlwaysStoppedAnimation(.25),
                          ),
                        ),
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
                    : immersive
                    ? Colors.transparent
                    : scheme.surface.withValues(alpha: .55),
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
