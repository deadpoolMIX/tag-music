import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../playback/documents.dart';

class TrackCover extends StatefulWidget {
  const TrackCover({
    required this.documents,
    required ProbeTrack track,
    this.size = 48,
    super.key,
  }) : _track = track,
       _albumTracks = const [];

  const TrackCover.album({
    required this.documents,
    required List<ProbeTrack> tracks,
    this.size = 48,
    super.key,
  }) : _track = null,
       _albumTracks = tracks;

  final DocumentAccess documents;
  final ProbeTrack? _track;
  final List<ProbeTrack> _albumTracks;
  final double size;

  Iterable<ProbeTrack> get _candidates =>
      _track == null ? _albumTracks : [_track];

  List<(String, int?, int?)> get _coverKeys => _candidates
      .map((track) => (track.location, track.size, track.modified))
      .toList();

  @override
  State<TrackCover> createState() => _TrackCoverState();
}

class _TrackCoverState extends State<TrackCover> {
  int _revision = 0;
  late Future<Uint8List?> _cover = _load();

  Future<Uint8List?> _load() async {
    final revision = ++_revision;
    final documents = widget.documents;
    final targetSize = widget.size <= 64 ? 96 : (widget.size * 2).round();
    for (final track in widget._candidates) {
      if (!mounted || revision != _revision) return null;
      final cover = await documents.cachedCover(track, targetSize: targetSize);
      if (cover != null) return cover;
    }
    return null;
  }

  @override
  void didUpdateWidget(TrackCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documents != widget.documents ||
        oldWidget.size != widget.size ||
        !listEquals(oldWidget._coverKeys, widget._coverKeys)) {
      _cover = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    key: ValueKey(_cover),
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
