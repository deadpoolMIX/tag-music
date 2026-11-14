import 'package:flutter/material.dart';

import 'library_controller.dart';

Future<void> showSongInformation(
  BuildContext context,
  LibraryTrack track,
) => showDialog<void>(
  context: context,
  builder: (context) {
    final song = track.song;
    String known(Object? value) =>
        value == null || value.toString().trim().isEmpty
        ? '未知'
        : value.toString();
    final fields = <String, String>{
      '歌名': known(song.title),
      '歌手': known(song.artist),
      '专辑': known(song.album),
      '时长': song.durationMs == null
          ? '未知'
          : '${song.durationMs! ~/ 60000}:${((song.durationMs! ~/ 1000) % 60).toString().padLeft(2, '0')}',
      '文件名': song.name,
      '格式': song.name.contains('.')
          ? song.name.split('.').last.toUpperCase()
          : '未知',
      '大小': song.size == null ? '未知' : '${song.size} 字节',
      '修改时间': song.modified == null
          ? '未知'
          : DateTime.fromMillisecondsSinceEpoch(song.modified!)
                .toLocal()
                .toString(),
      '可用状态': track.available ? '可用' : '文件失联或目录不可访问',
    };
    return AlertDialog(
      title: const Text('歌曲信息 · 只读'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in fields.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('${field.key}：${field.value}'),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  },
);
