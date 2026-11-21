import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'lan_sync_merge.dart';

const lanSyncPort = 49218;
const _frameLimit = 64 * 1024 * 1024;
const _timeout = Duration(minutes: 3);
final _cipher = AesGcm.with128bits();

Uint8List _randomBytes(int size) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(size, (_) => random.nextInt(256)));
}

bool isPrivateAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  return bytes.length == 4 &&
      (bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 169 && bytes[1] == 254));
}

class LanEndpoint {
  LanEndpoint(this.address, this.key);

  factory LanEndpoint.decode(String code) {
    final normalized = code.replaceAll(RegExp(r'\s+'), '');
    final bytes = base64Url.decode(base64Url.normalize(normalized));
    if (bytes.length != 21 || bytes.first != 1) {
      throw const FormatException('连接码无效，请使用电脑上显示的连接码。');
    }
    final address = InternetAddress.fromRawAddress(
      Uint8List.sublistView(bytes, 1, 5),
    );
    if (!isPrivateAddress(address)) {
      throw const FormatException('连接码必须指向局域网地址。');
    }
    return LanEndpoint(address, Uint8List.sublistView(bytes, 5));
  }

  static String newKey() => base64Url.encode(_randomBytes(16));

  final InternetAddress address;
  final Uint8List key;
  String get peer => stableSyncId('computer', base64Url.encode(key));
  String get code =>
      base64Url.encode([1, ...address.rawAddress, ...key]).replaceAll('=', '');

  Future<SyncRow> exchange(SyncRow request) async {
    final socket = await Socket.connect(
      address,
      lanSyncPort,
      timeout: const Duration(seconds: 8),
    );
    final link = _LanLink(socket, key);
    try {
      final challenge = await link
          .read(32)
          .timeout(const Duration(seconds: 10));
      if (challenge.length != 32) {
        throw const FormatException('对端不是 Tag Music 同步服务。');
      }
      await link.sendJson({'hello': 1}, challenge, direction: 2);
      await link.sendJson(request, challenge, direction: 0);
      return await link.readJson(challenge, direction: 1).timeout(_timeout);
    } finally {
      link.close();
    }
  }
}

class LanSyncReceiver {
  LanSyncReceiver(this._server, this.endpoints, this.transfer) {
    _subscription = _server.listen(_receive);
  }

  static Future<LanSyncReceiver> open(
    Uint8List key,
    Future<SyncRow> Function(SyncRow) transfer,
  ) async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final addresses = <String, LanEndpoint>{
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (isPrivateAddress(address))
            address.address: LanEndpoint(address, key),
    };
    if (addresses.isEmpty) throw const FormatException('电脑没有可用的局域网 IPv4 地址。');
    final server = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      lanSyncPort,
    );
    return LanSyncReceiver(server, addresses.values.toList(), transfer);
  }

  final ServerSocket _server;
  final List<LanEndpoint> endpoints;
  final Future<SyncRow> Function(SyncRow) transfer;
  late final StreamSubscription<Socket> _subscription;
  final _connections = <_LanLink>{};
  bool _transferring = false;

  Future<void> _receive(Socket socket) async {
    if (!isPrivateAddress(socket.remoteAddress) ||
        _connections.length >= 4 ||
        _transferring) {
      socket.destroy();
      return;
    }
    final link = _LanLink(socket, endpoints.first.key);
    _connections.add(link);
    final challenge = _randomBytes(32);
    var ownsTransfer = false;
    try {
      await link.send(challenge);
      final hello = await link
          .readJson(challenge, direction: 2, limit: 128)
          .timeout(const Duration(seconds: 8));
      if (hello['hello'] != 1) return;
      final request = await link
          .readJson(challenge, direction: 0)
          .timeout(const Duration(seconds: 30));
      if (_transferring) {
        await link.sendJson(
          {'error': '电脑正在处理另一台设备，请稍后重试。'},
          challenge,
          direction: 1,
        );
        return;
      }
      ownsTransfer = _transferring = true;
      final reply = await transfer(request);
      await link.sendJson(reply, challenge, direction: 1);
      await socket.close().timeout(const Duration(seconds: 8));
    } catch (_) {
      // Invalid or disconnected clients are not entitled to a response.
    } finally {
      if (ownsTransfer) _transferring = false;
      _connections.remove(link);
      link.close();
    }
  }

  void close() {
    for (final link in _connections) {
      link.close();
    }
    unawaited(_subscription.cancel());
    unawaited(_server.close());
  }
}

class _LanLink {
  _LanLink(this.socket, List<int> bytes)
    : _chunks = StreamIterator(socket),
      key = SecretKey(bytes);

  final Socket socket;
  final StreamIterator<Uint8List> _chunks;
  final SecretKey key;
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;

  Future<Uint8List> _exact(int size) async {
    final result = Uint8List(size);
    var written = 0;
    while (written < size) {
      if (_offset == _buffer.length) {
        if (!await _chunks.moveNext()) {
          throw const SocketException('连接已关闭');
        }
        _buffer = _chunks.current;
        _offset = 0;
      }
      final count = min(size - written, _buffer.length - _offset);
      result.setRange(written, written + count, _buffer, _offset);
      _offset += count;
      written += count;
    }
    return result;
  }

  Future<Uint8List> read(int limit) async {
    final header = await _exact(4);
    final size = ByteData.sublistView(header).getUint32(0);
    if (size <= 0 || size > limit) throw const FormatException('同步数据大小无效。');
    return _exact(size);
  }

  Future<void> send(Uint8List data) async {
    if (data.length > _frameLimit) {
      throw const FormatException('同步数据超过 64 MiB。');
    }
    final header = ByteData(4)..setUint32(0, data.length);
    socket.add(header.buffer.asUint8List());
    socket.add(data);
    await socket.flush().timeout(const Duration(seconds: 30));
  }

  Future<void> sendJson(
    SyncRow data,
    List<int> challenge, {
    required int direction,
  }) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: key,
      aad: [direction, ...challenge],
    );
    await send(box.concatenation());
  }

  Future<SyncRow> readJson(
    List<int> challenge, {
    required int direction,
    int limit = _frameLimit,
  }) async {
    final data = await read(limit);
    final box = SecretBox.fromConcatenation(
      data,
      nonceLength: _cipher.nonceLength,
      macLength: 16,
      copy: false,
    );
    final clear = await _cipher.decrypt(
      box,
      secretKey: key,
      aad: [direction, ...challenge],
    );
    return jsonDecode(utf8.decode(clear)) as SyncRow;
  }

  void close() {
    socket.destroy();
    unawaited(_chunks.cancel());
  }
}
