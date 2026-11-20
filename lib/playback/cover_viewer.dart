import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/desktop_navigation.dart';
import '../library/track_cover.dart';
import 'documents.dart';

const coverViewerRouteName = '/player/cover';

Object playerCoverHeroTag(ProbeTrack track) =>
    ('player-cover', track.location, track.size, track.modified);

Future<void> showCoverViewer(
  BuildContext context, {
  required DocumentAccess documents,
  required ProbeTrack track,
  required double previewSize,
}) async {
  if (ModalRoute.of(context)?.isCurrent != true) return;
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  await pushAppPage(
    context,
    () => PageRouteBuilder<void>(
      settings: const RouteSettings(name: coverViewerRouteName),
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 240),
      reverseTransitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 190),
      pageBuilder: (_, _, _) => _CoverViewer(
        documents: documents,
        track: track,
        previewSize: previewSize,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _CoverViewer extends StatefulWidget {
  const _CoverViewer({
    required this.documents,
    required this.track,
    required this.previewSize,
  });

  final DocumentAccess documents;
  final ProbeTrack track;
  final double previewSize;

  @override
  State<_CoverViewer> createState() => _CoverViewerState();
}

class _CoverViewerState extends State<_CoverViewer> {
  late final _original = widget.documents.cover(widget.track);
  bool _saving = false;

  Future<void> _save(Uint8List bytes) async {
    if (_saving) return;
    setState(() => _saving = true);
    String message;
    try {
      final path = await widget.documents.saveCover(bytes, widget.track.name);
      message = '已保存原图\n$path';
    } catch (error) {
      message = '保存封面失败。$error';
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _preview(AsyncSnapshot<Uint8List?> snapshot) {
    final bytes = snapshot.data;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const _CoverMessage('无法预览这张封面'),
      );
    }
    if (snapshot.connectionState == ConnectionState.done) {
      return _CoverMessage(snapshot.hasError ? '无法读取封面' : '这首歌没有可用封面');
    }
    return TrackCover(
      documents: widget.documents,
      track: widget.track,
      size: widget.previewSize,
      currentArtwork: true,
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.maybePop(context),
    },
    child: Focus(
      autofocus: true,
      child: FutureBuilder<Uint8List?>(
        future: _original,
        builder: (context, snapshot) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => InteractiveViewer(
                      maxScale: 5,
                      child: Center(
                        child: Hero(
                          tag: playerCoverHeroTag(widget.track),
                          flightShuttleBuilder: (_, _, direction, from, to) =>
                              ((direction == HeroFlightDirection.push
                                              ? from
                                              : to)
                                          .widget
                                      as Hero)
                                  .child,
                          child: SizedBox.square(
                            dimension: math.min(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            ),
                            child: _preview(snapshot),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const PositionedDirectional(
                    top: 8,
                    start: 8,
                    child: BackButton(color: Colors.white),
                  ),
                  PositionedDirectional(
                    bottom: 16,
                    end: 16,
                    child: FilledButton.icon(
                      onPressed: snapshot.data == null || _saving
                          ? null
                          : () => _save(snapshot.data!),
                      icon: const Icon(Icons.download),
                      label: Text(_saving ? '保存中…' : '保存'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CoverMessage extends StatelessWidget {
  const _CoverMessage(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(label, style: const TextStyle(color: Colors.white)),
  );
}
