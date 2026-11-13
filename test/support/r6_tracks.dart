import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';

LibraryTrack r6Track(
  String id, {
  String? title,
  String? artist,
  String? album,
  int? modified = 1,
  bool available = true,
  String? name,
}) => LibraryTrack(
  Song(
    id: id,
    identity: id,
    location: '/synthetic/$id',
    name: name ?? '$id.mp3',
    title: title ?? '歌曲$id',
    artist: artist,
    album: album,
    modified: modified,
  ),
  available ? '/synthetic/$id' : null,
);
