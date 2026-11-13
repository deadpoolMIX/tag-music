import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../playback/documents.dart';

class TrackCover extends StatefulWidget {
  const TrackCover({
    required this.documents,
    required this.track,
    this.size = 48,
    super.key,
  });
  final DocumentAccess documents;
  final ProbeTrack track;
  final double size;
  @override
  State<TrackCover> createState() => _TrackCoverState();
}

class _TrackCoverState extends State<TrackCover> {
  late final Future<Uint8List?> _cover = widget.documents.cover(widget.track);
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _cover,
    builder: (context, snapshot) => SizedBox(
      height: widget.size,
      width: widget.size,
      child: snapshot.data == null
          ? const Icon(Icons.album_outlined, size: 32)
          : Image.memory(
              snapshot.data!,
              cacheWidth: (widget.size * 2).round(),
              cacheHeight: (widget.size * 2).round(),
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) =>
                  const Icon(Icons.album_outlined, size: 32),
            ),
    ),
  );
}
