import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../playback/cover_cache.dart';
import '../playback/documents.dart';

class TrackCover extends StatefulWidget {
  const TrackCover({
    required this.documents,
    required ProbeTrack track,
    this.size = 48,
    this.currentArtwork = false,
    super.key,
  }) : _track = track,
       _albumTracks = const [];

  const TrackCover.album({
    required this.documents,
    required List<ProbeTrack> tracks,
    this.size = 48,
    super.key,
  }) : _track = null,
       _albumTracks = tracks,
       currentArtwork = false;

  final DocumentAccess documents;
  final ProbeTrack? _track;
  final List<ProbeTrack> _albumTracks;
  final double size;
  final bool currentArtwork;

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
  Uint8List? _image;
  _CoverScrollRegionState? _scrollRegion;

  CoverPriority _priority(int revision, {bool large = false}) {
    if (!mounted || revision != _revision) return CoverPriority.stale;
    if (widget.currentArtwork) {
      return large ? CoverPriority.artwork : CoverPriority.current;
    }
    if (_scrollRegion?.deferred == true) return CoverPriority.deferred;
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      final RenderObject? viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport is RenderBox && viewport.hasSize) {
        final origin = box.localToGlobal(Offset.zero, ancestor: viewport);
        if (!(origin & box.size).overlaps(Offset.zero & viewport.size)) {
          return CoverPriority.nearby;
        }
      }
    }
    return CoverPriority.visible;
  }

  Future<void> _load() async {
    final revision = ++_revision;
    final documents = widget.documents;
    final targetSize = widget.size <= 64
        ? CoverCache.thumbnailSize
        : (widget.size * 2).round().clamp(CoverCache.thumbnailSize, 1024);
    final quickPreview =
        widget.currentArtwork && targetSize > CoverCache.thumbnailSize;
    for (final track in widget._candidates) {
      if (!mounted || revision != _revision) return;
      final cover = await documents.cachedCover(
        track,
        targetSize: quickPreview ? CoverCache.thumbnailSize : targetSize,
        priority: () => _priority(revision),
      );
      if (!mounted || revision != _revision) return;
      if (cover == null) continue;
      setState(() => _image = cover);
      if (quickPreview) {
        final large = await documents.cachedCover(
          track,
          targetSize: targetSize,
          priority: () => _priority(revision, large: true),
        );
        if (!mounted || revision != _revision || large == null) return;
        setState(() => _image = large);
      }
      return;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollRegion = context
        .dependOnInheritedWidgetOfExactType<_CoverScrollScope>()
        ?.region;
    if (_revision == 0) unawaited(_load());
  }

  @override
  void didUpdateWidget(TrackCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documents != widget.documents ||
        oldWidget.size != widget.size ||
        oldWidget.currentArtwork != widget.currentArtwork ||
        !listEquals(oldWidget._coverKeys, widget._coverKeys)) {
      _image = null;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _revision++;
    widget.documents.coverCache.resume();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.size,
    width: widget.size,
    child: _image == null
        ? const Icon(Icons.album_outlined, size: 32)
        : Image.memory(
            _image!,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stack) =>
                const Icon(Icons.album_outlined, size: 32),
          ),
  );
}

class CoverScrollRegion extends StatefulWidget {
  const CoverScrollRegion({
    required this.cache,
    required this.child,
    super.key,
  });

  final CoverCache cache;
  final Widget child;

  @override
  State<CoverScrollRegion> createState() => _CoverScrollRegionState();
}

class _CoverScrollRegionState extends State<CoverScrollRegion> {
  final _clock = Stopwatch()..start();
  int _lastUpdate = 0;
  Timer? _settleTimer;
  bool get deferred => _settleTimer?.isActive == true;

  bool _onScroll(ScrollNotification notice) {
    if (notice.depth != 0 || notice.metrics.axis != Axis.vertical) return false;
    if (notice is ScrollStartNotification) {
      _lastUpdate = _clock.elapsedMicroseconds;
    } else if (notice is ScrollUpdateNotification) {
      final now = _clock.elapsedMicroseconds;
      final elapsed = (now - _lastUpdate).clamp(8000, 70000) / 1000000;
      final distance = notice.scrollDelta?.abs() ?? 0.0;
      final viewport = notice.metrics.viewportDimension;
      _lastUpdate = now;
      if (deferred ||
          distance > viewport * .22 ||
          (distance > viewport * .035 && distance / elapsed > viewport * 1.4)) {
        _settleTimer?.cancel();
        _settleTimer = Timer(const Duration(milliseconds: 75), _settled);
      }
    } else if (notice is ScrollEndNotification && deferred) {
      _settled();
    }
    return false;
  }

  void _settled() {
    _settleTimer?.cancel();
    _settleTimer = null;
    widget.cache.resume();
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    widget.cache.resume();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: _CoverScrollScope(region: this, child: widget.child),
      );
}

class _CoverScrollScope extends InheritedWidget {
  const _CoverScrollScope({required this.region, required super.child});
  final _CoverScrollRegionState region;

  @override
  bool updateShouldNotify(_CoverScrollScope oldWidget) =>
      oldWidget.region != region;
}
