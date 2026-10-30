// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $SongsTable extends Songs with TableInfo<$SongsTable, Song> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SongsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityMeta = const VerificationMeta(
    'identity',
  );
  @override
  late final GeneratedColumn<String> identity = GeneratedColumn<String>(
    'identity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modifiedMeta = const VerificationMeta(
    'modified',
  );
  @override
  late final GeneratedColumn<int> modified = GeneratedColumn<int>(
    'modified',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataErrorMeta = const VerificationMeta(
    'metadataError',
  );
  @override
  late final GeneratedColumn<String> metadataError = GeneratedColumn<String>(
    'metadata_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    identity,
    location,
    name,
    size,
    modified,
    title,
    artist,
    album,
    durationMs,
    metadataError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'songs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Song> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('identity')) {
      context.handle(
        _identityMeta,
        identity.isAcceptableOrUnknown(data['identity']!, _identityMeta),
      );
    } else if (isInserting) {
      context.missing(_identityMeta);
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    } else if (isInserting) {
      context.missing(_locationMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    if (data.containsKey('modified')) {
      context.handle(
        _modifiedMeta,
        modified.isAcceptableOrUnknown(data['modified']!, _modifiedMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('metadata_error')) {
      context.handle(
        _metadataErrorMeta,
        metadataError.isAcceptableOrUnknown(
          data['metadata_error']!,
          _metadataErrorMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Song map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Song(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      identity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity'],
      )!,
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      ),
      modified: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}modified'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      ),
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      metadataError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_error'],
      ),
    );
  }

  @override
  $SongsTable createAlias(String alias) {
    return $SongsTable(attachedDatabase, alias);
  }
}

class Song extends DataClass implements Insertable<Song> {
  final String id;
  final String identity;
  final String location;
  final String name;
  final int? size;
  final int? modified;
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;
  final String? metadataError;
  const Song({
    required this.id,
    required this.identity,
    required this.location,
    required this.name,
    this.size,
    this.modified,
    this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.metadataError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['identity'] = Variable<String>(identity);
    map['location'] = Variable<String>(location);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || size != null) {
      map['size'] = Variable<int>(size);
    }
    if (!nullToAbsent || modified != null) {
      map['modified'] = Variable<int>(modified);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || artist != null) {
      map['artist'] = Variable<String>(artist);
    }
    if (!nullToAbsent || album != null) {
      map['album'] = Variable<String>(album);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || metadataError != null) {
      map['metadata_error'] = Variable<String>(metadataError);
    }
    return map;
  }

  SongsCompanion toCompanion(bool nullToAbsent) {
    return SongsCompanion(
      id: Value(id),
      identity: Value(identity),
      location: Value(location),
      name: Value(name),
      size: size == null && nullToAbsent ? const Value.absent() : Value(size),
      modified: modified == null && nullToAbsent
          ? const Value.absent()
          : Value(modified),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      artist: artist == null && nullToAbsent
          ? const Value.absent()
          : Value(artist),
      album: album == null && nullToAbsent
          ? const Value.absent()
          : Value(album),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      metadataError: metadataError == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataError),
    );
  }

  factory Song.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Song(
      id: serializer.fromJson<String>(json['id']),
      identity: serializer.fromJson<String>(json['identity']),
      location: serializer.fromJson<String>(json['location']),
      name: serializer.fromJson<String>(json['name']),
      size: serializer.fromJson<int?>(json['size']),
      modified: serializer.fromJson<int?>(json['modified']),
      title: serializer.fromJson<String?>(json['title']),
      artist: serializer.fromJson<String?>(json['artist']),
      album: serializer.fromJson<String?>(json['album']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      metadataError: serializer.fromJson<String?>(json['metadataError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'identity': serializer.toJson<String>(identity),
      'location': serializer.toJson<String>(location),
      'name': serializer.toJson<String>(name),
      'size': serializer.toJson<int?>(size),
      'modified': serializer.toJson<int?>(modified),
      'title': serializer.toJson<String?>(title),
      'artist': serializer.toJson<String?>(artist),
      'album': serializer.toJson<String?>(album),
      'durationMs': serializer.toJson<int?>(durationMs),
      'metadataError': serializer.toJson<String?>(metadataError),
    };
  }

  Song copyWith({
    String? id,
    String? identity,
    String? location,
    String? name,
    Value<int?> size = const Value.absent(),
    Value<int?> modified = const Value.absent(),
    Value<String?> title = const Value.absent(),
    Value<String?> artist = const Value.absent(),
    Value<String?> album = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<String?> metadataError = const Value.absent(),
  }) => Song(
    id: id ?? this.id,
    identity: identity ?? this.identity,
    location: location ?? this.location,
    name: name ?? this.name,
    size: size.present ? size.value : this.size,
    modified: modified.present ? modified.value : this.modified,
    title: title.present ? title.value : this.title,
    artist: artist.present ? artist.value : this.artist,
    album: album.present ? album.value : this.album,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    metadataError: metadataError.present
        ? metadataError.value
        : this.metadataError,
  );
  Song copyWithCompanion(SongsCompanion data) {
    return Song(
      id: data.id.present ? data.id.value : this.id,
      identity: data.identity.present ? data.identity.value : this.identity,
      location: data.location.present ? data.location.value : this.location,
      name: data.name.present ? data.name.value : this.name,
      size: data.size.present ? data.size.value : this.size,
      modified: data.modified.present ? data.modified.value : this.modified,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      metadataError: data.metadataError.present
          ? data.metadataError.value
          : this.metadataError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Song(')
          ..write('id: $id, ')
          ..write('identity: $identity, ')
          ..write('location: $location, ')
          ..write('name: $name, ')
          ..write('size: $size, ')
          ..write('modified: $modified, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('durationMs: $durationMs, ')
          ..write('metadataError: $metadataError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    identity,
    location,
    name,
    size,
    modified,
    title,
    artist,
    album,
    durationMs,
    metadataError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Song &&
          other.id == this.id &&
          other.identity == this.identity &&
          other.location == this.location &&
          other.name == this.name &&
          other.size == this.size &&
          other.modified == this.modified &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.durationMs == this.durationMs &&
          other.metadataError == this.metadataError);
}

class SongsCompanion extends UpdateCompanion<Song> {
  final Value<String> id;
  final Value<String> identity;
  final Value<String> location;
  final Value<String> name;
  final Value<int?> size;
  final Value<int?> modified;
  final Value<String?> title;
  final Value<String?> artist;
  final Value<String?> album;
  final Value<int?> durationMs;
  final Value<String?> metadataError;
  final Value<int> rowid;
  const SongsCompanion({
    this.id = const Value.absent(),
    this.identity = const Value.absent(),
    this.location = const Value.absent(),
    this.name = const Value.absent(),
    this.size = const Value.absent(),
    this.modified = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.metadataError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SongsCompanion.insert({
    required String id,
    required String identity,
    required String location,
    required String name,
    this.size = const Value.absent(),
    this.modified = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.metadataError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       identity = Value(identity),
       location = Value(location),
       name = Value(name);
  static Insertable<Song> custom({
    Expression<String>? id,
    Expression<String>? identity,
    Expression<String>? location,
    Expression<String>? name,
    Expression<int>? size,
    Expression<int>? modified,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<int>? durationMs,
    Expression<String>? metadataError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (identity != null) 'identity': identity,
      if (location != null) 'location': location,
      if (name != null) 'name': name,
      if (size != null) 'size': size,
      if (modified != null) 'modified': modified,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (durationMs != null) 'duration_ms': durationMs,
      if (metadataError != null) 'metadata_error': metadataError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SongsCompanion copyWith({
    Value<String>? id,
    Value<String>? identity,
    Value<String>? location,
    Value<String>? name,
    Value<int?>? size,
    Value<int?>? modified,
    Value<String?>? title,
    Value<String?>? artist,
    Value<String?>? album,
    Value<int?>? durationMs,
    Value<String?>? metadataError,
    Value<int>? rowid,
  }) {
    return SongsCompanion(
      id: id ?? this.id,
      identity: identity ?? this.identity,
      location: location ?? this.location,
      name: name ?? this.name,
      size: size ?? this.size,
      modified: modified ?? this.modified,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      metadataError: metadataError ?? this.metadataError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (identity.present) {
      map['identity'] = Variable<String>(identity.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (modified.present) {
      map['modified'] = Variable<int>(modified.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (metadataError.present) {
      map['metadata_error'] = Variable<String>(metadataError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SongsCompanion(')
          ..write('id: $id, ')
          ..write('identity: $identity, ')
          ..write('location: $location, ')
          ..write('name: $name, ')
          ..write('size: $size, ')
          ..write('modified: $modified, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('durationMs: $durationMs, ')
          ..write('metadataError: $metadataError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LibraryRootsTable extends LibraryRoots
    with TableInfo<$LibraryRootsTable, LibraryRoot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryRootsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accessibleMeta = const VerificationMeta(
    'accessible',
  );
  @override
  late final GeneratedColumn<bool> accessible = GeneratedColumn<bool>(
    'accessible',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("accessible" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('尚未扫描'),
  );
  static const VerificationMeta _scannedAtMeta = const VerificationMeta(
    'scannedAt',
  );
  @override
  late final GeneratedColumn<int> scannedAt = GeneratedColumn<int>(
    'scanned_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    location,
    accessible,
    status,
    scannedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_roots';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryRoot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    } else if (isInserting) {
      context.missing(_locationMeta);
    }
    if (data.containsKey('accessible')) {
      context.handle(
        _accessibleMeta,
        accessible.isAcceptableOrUnknown(data['accessible']!, _accessibleMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('scanned_at')) {
      context.handle(
        _scannedAtMeta,
        scannedAt.isAcceptableOrUnknown(data['scanned_at']!, _scannedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {location};
  @override
  LibraryRoot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryRoot(
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      )!,
      accessible: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}accessible'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      scannedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scanned_at'],
      ),
    );
  }

  @override
  $LibraryRootsTable createAlias(String alias) {
    return $LibraryRootsTable(attachedDatabase, alias);
  }
}

class LibraryRoot extends DataClass implements Insertable<LibraryRoot> {
  final String location;
  final bool accessible;
  final String status;
  final int? scannedAt;
  const LibraryRoot({
    required this.location,
    required this.accessible,
    required this.status,
    this.scannedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['location'] = Variable<String>(location);
    map['accessible'] = Variable<bool>(accessible);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || scannedAt != null) {
      map['scanned_at'] = Variable<int>(scannedAt);
    }
    return map;
  }

  LibraryRootsCompanion toCompanion(bool nullToAbsent) {
    return LibraryRootsCompanion(
      location: Value(location),
      accessible: Value(accessible),
      status: Value(status),
      scannedAt: scannedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(scannedAt),
    );
  }

  factory LibraryRoot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryRoot(
      location: serializer.fromJson<String>(json['location']),
      accessible: serializer.fromJson<bool>(json['accessible']),
      status: serializer.fromJson<String>(json['status']),
      scannedAt: serializer.fromJson<int?>(json['scannedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'location': serializer.toJson<String>(location),
      'accessible': serializer.toJson<bool>(accessible),
      'status': serializer.toJson<String>(status),
      'scannedAt': serializer.toJson<int?>(scannedAt),
    };
  }

  LibraryRoot copyWith({
    String? location,
    bool? accessible,
    String? status,
    Value<int?> scannedAt = const Value.absent(),
  }) => LibraryRoot(
    location: location ?? this.location,
    accessible: accessible ?? this.accessible,
    status: status ?? this.status,
    scannedAt: scannedAt.present ? scannedAt.value : this.scannedAt,
  );
  LibraryRoot copyWithCompanion(LibraryRootsCompanion data) {
    return LibraryRoot(
      location: data.location.present ? data.location.value : this.location,
      accessible: data.accessible.present
          ? data.accessible.value
          : this.accessible,
      status: data.status.present ? data.status.value : this.status,
      scannedAt: data.scannedAt.present ? data.scannedAt.value : this.scannedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryRoot(')
          ..write('location: $location, ')
          ..write('accessible: $accessible, ')
          ..write('status: $status, ')
          ..write('scannedAt: $scannedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(location, accessible, status, scannedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryRoot &&
          other.location == this.location &&
          other.accessible == this.accessible &&
          other.status == this.status &&
          other.scannedAt == this.scannedAt);
}

class LibraryRootsCompanion extends UpdateCompanion<LibraryRoot> {
  final Value<String> location;
  final Value<bool> accessible;
  final Value<String> status;
  final Value<int?> scannedAt;
  final Value<int> rowid;
  const LibraryRootsCompanion({
    this.location = const Value.absent(),
    this.accessible = const Value.absent(),
    this.status = const Value.absent(),
    this.scannedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryRootsCompanion.insert({
    required String location,
    this.accessible = const Value.absent(),
    this.status = const Value.absent(),
    this.scannedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : location = Value(location);
  static Insertable<LibraryRoot> custom({
    Expression<String>? location,
    Expression<bool>? accessible,
    Expression<String>? status,
    Expression<int>? scannedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (location != null) 'location': location,
      if (accessible != null) 'accessible': accessible,
      if (status != null) 'status': status,
      if (scannedAt != null) 'scanned_at': scannedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryRootsCompanion copyWith({
    Value<String>? location,
    Value<bool>? accessible,
    Value<String>? status,
    Value<int?>? scannedAt,
    Value<int>? rowid,
  }) {
    return LibraryRootsCompanion(
      location: location ?? this.location,
      accessible: accessible ?? this.accessible,
      status: status ?? this.status,
      scannedAt: scannedAt ?? this.scannedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (accessible.present) {
      map['accessible'] = Variable<bool>(accessible.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (scannedAt.present) {
      map['scanned_at'] = Variable<int>(scannedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryRootsCompanion(')
          ..write('location: $location, ')
          ..write('accessible: $accessible, ')
          ..write('status: $status, ')
          ..write('scannedAt: $scannedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SongLocationsTable extends SongLocations
    with TableInfo<$SongLocationsTable, SongLocation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SongLocationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES songs (id)',
    ),
  );
  static const VerificationMeta _rootMeta = const VerificationMeta('root');
  @override
  late final GeneratedColumn<String> root = GeneratedColumn<String>(
    'root',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES library_roots (location)',
    ),
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _availableMeta = const VerificationMeta(
    'available',
  );
  @override
  late final GeneratedColumn<bool> available = GeneratedColumn<bool>(
    'available',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("available" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    songId,
    root,
    location,
    relativePath,
    available,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'song_locations';
  @override
  VerificationContext validateIntegrity(
    Insertable<SongLocation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('root')) {
      context.handle(
        _rootMeta,
        root.isAcceptableOrUnknown(data['root']!, _rootMeta),
      );
    } else if (isInserting) {
      context.missing(_rootMeta);
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    } else if (isInserting) {
      context.missing(_locationMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('available')) {
      context.handle(
        _availableMeta,
        available.isAcceptableOrUnknown(data['available']!, _availableMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {songId, root};
  @override
  SongLocation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SongLocation(
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      root: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}root'],
      )!,
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      available: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}available'],
      )!,
    );
  }

  @override
  $SongLocationsTable createAlias(String alias) {
    return $SongLocationsTable(attachedDatabase, alias);
  }
}

class SongLocation extends DataClass implements Insertable<SongLocation> {
  final String songId;
  final String root;
  final String location;
  final String relativePath;
  final bool available;
  const SongLocation({
    required this.songId,
    required this.root,
    required this.location,
    required this.relativePath,
    required this.available,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['song_id'] = Variable<String>(songId);
    map['root'] = Variable<String>(root);
    map['location'] = Variable<String>(location);
    map['relative_path'] = Variable<String>(relativePath);
    map['available'] = Variable<bool>(available);
    return map;
  }

  SongLocationsCompanion toCompanion(bool nullToAbsent) {
    return SongLocationsCompanion(
      songId: Value(songId),
      root: Value(root),
      location: Value(location),
      relativePath: Value(relativePath),
      available: Value(available),
    );
  }

  factory SongLocation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SongLocation(
      songId: serializer.fromJson<String>(json['songId']),
      root: serializer.fromJson<String>(json['root']),
      location: serializer.fromJson<String>(json['location']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      available: serializer.fromJson<bool>(json['available']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'songId': serializer.toJson<String>(songId),
      'root': serializer.toJson<String>(root),
      'location': serializer.toJson<String>(location),
      'relativePath': serializer.toJson<String>(relativePath),
      'available': serializer.toJson<bool>(available),
    };
  }

  SongLocation copyWith({
    String? songId,
    String? root,
    String? location,
    String? relativePath,
    bool? available,
  }) => SongLocation(
    songId: songId ?? this.songId,
    root: root ?? this.root,
    location: location ?? this.location,
    relativePath: relativePath ?? this.relativePath,
    available: available ?? this.available,
  );
  SongLocation copyWithCompanion(SongLocationsCompanion data) {
    return SongLocation(
      songId: data.songId.present ? data.songId.value : this.songId,
      root: data.root.present ? data.root.value : this.root,
      location: data.location.present ? data.location.value : this.location,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      available: data.available.present ? data.available.value : this.available,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SongLocation(')
          ..write('songId: $songId, ')
          ..write('root: $root, ')
          ..write('location: $location, ')
          ..write('relativePath: $relativePath, ')
          ..write('available: $available')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(songId, root, location, relativePath, available);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SongLocation &&
          other.songId == this.songId &&
          other.root == this.root &&
          other.location == this.location &&
          other.relativePath == this.relativePath &&
          other.available == this.available);
}

class SongLocationsCompanion extends UpdateCompanion<SongLocation> {
  final Value<String> songId;
  final Value<String> root;
  final Value<String> location;
  final Value<String> relativePath;
  final Value<bool> available;
  final Value<int> rowid;
  const SongLocationsCompanion({
    this.songId = const Value.absent(),
    this.root = const Value.absent(),
    this.location = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.available = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SongLocationsCompanion.insert({
    required String songId,
    required String root,
    required String location,
    required String relativePath,
    this.available = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : songId = Value(songId),
       root = Value(root),
       location = Value(location),
       relativePath = Value(relativePath);
  static Insertable<SongLocation> custom({
    Expression<String>? songId,
    Expression<String>? root,
    Expression<String>? location,
    Expression<String>? relativePath,
    Expression<bool>? available,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (songId != null) 'song_id': songId,
      if (root != null) 'root': root,
      if (location != null) 'location': location,
      if (relativePath != null) 'relative_path': relativePath,
      if (available != null) 'available': available,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SongLocationsCompanion copyWith({
    Value<String>? songId,
    Value<String>? root,
    Value<String>? location,
    Value<String>? relativePath,
    Value<bool>? available,
    Value<int>? rowid,
  }) {
    return SongLocationsCompanion(
      songId: songId ?? this.songId,
      root: root ?? this.root,
      location: location ?? this.location,
      relativePath: relativePath ?? this.relativePath,
      available: available ?? this.available,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (root.present) {
      map['root'] = Variable<String>(root.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (available.present) {
      map['available'] = Variable<bool>(available.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SongLocationsCompanion(')
          ..write('songId: $songId, ')
          ..write('root: $root, ')
          ..write('location: $location, ')
          ..write('relativePath: $relativePath, ')
          ..write('available: $available, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LibraryDatabase extends GeneratedDatabase {
  _$LibraryDatabase(QueryExecutor e) : super(e);
  $LibraryDatabaseManager get managers => $LibraryDatabaseManager(this);
  late final $SongsTable songs = $SongsTable(this);
  late final $LibraryRootsTable libraryRoots = $LibraryRootsTable(this);
  late final $SongLocationsTable songLocations = $SongLocationsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    songs,
    libraryRoots,
    songLocations,
  ];
}

typedef $$SongsTableCreateCompanionBuilder = SongsCompanion Function({
  required String id,
  required String identity,
  required String location,
  required String name,
  Value<int?> size,
  Value<int?> modified,
  Value<String?> title,
  Value<String?> artist,
  Value<String?> album,
  Value<int?> durationMs,
  Value<String?> metadataError,
  Value<int> rowid,
});
typedef $$SongsTableUpdateCompanionBuilder = SongsCompanion Function({
  Value<String> id,
  Value<String> identity,
  Value<String> location,
  Value<String> name,
  Value<int?> size,
  Value<int?> modified,
  Value<String?> title,
  Value<String?> artist,
  Value<String?> album,
  Value<int?> durationMs,
  Value<String?> metadataError,
  Value<int> rowid,
});

final class $$SongsTableReferences
    extends BaseReferences<_$LibraryDatabase, $SongsTable, Song> {
  $$SongsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SongLocationsTable, List<SongLocation>>
  _songLocationsRefsTable(_$LibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.songLocations,
        aliasName: 'songs__id__song_locations__song_id',
      );

  $$SongLocationsTableProcessedTableManager get songLocationsRefs {
    final manager = $$SongLocationsTableTableManager(
      $_db,
      $_db.songLocations,
    ).filter((f) => f.songId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_songLocationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SongsTableFilterComposer
    extends Composer<_$LibraryDatabase, $SongsTable> {
  $$SongsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identity => $composableBuilder(
    column: $table.identity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get modified => $composableBuilder(
    column: $table.modified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataError => $composableBuilder(
    column: $table.metadataError,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> songLocationsRefs(
    Expression<bool> Function($$SongLocationsTableFilterComposer f) f,
  ) {
    final $$SongLocationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.songLocations,
      getReferencedColumn: (t) => t.songId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongLocationsTableFilterComposer(
            $db: $db,
            $table: $db.songLocations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SongsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $SongsTable> {
  $$SongsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identity => $composableBuilder(
    column: $table.identity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get modified => $composableBuilder(
    column: $table.modified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataError => $composableBuilder(
    column: $table.metadataError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SongsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $SongsTable> {
  $$SongsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get identity =>
      $composableBuilder(column: $table.identity, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<int> get modified =>
      $composableBuilder(column: $table.modified, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadataError => $composableBuilder(
    column: $table.metadataError,
    builder: (column) => column,
  );

  Expression<T> songLocationsRefs<T extends Object>(
    Expression<T> Function($$SongLocationsTableAnnotationComposer a) f,
  ) {
    final $$SongLocationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.songLocations,
      getReferencedColumn: (t) => t.songId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongLocationsTableAnnotationComposer(
            $db: $db,
            $table: $db.songLocations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SongsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $SongsTable,
          Song,
          $$SongsTableFilterComposer,
          $$SongsTableOrderingComposer,
          $$SongsTableAnnotationComposer,
          $$SongsTableCreateCompanionBuilder,
          $$SongsTableUpdateCompanionBuilder,
          (Song, $$SongsTableReferences),
          Song,
          PrefetchHooks Function({bool songLocationsRefs})
        > {
  $$SongsTableTableManager(_$LibraryDatabase db, $SongsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SongsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SongsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SongsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> identity = const Value.absent(),
                Value<String> location = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> size = const Value.absent(),
                Value<int?> modified = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> metadataError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SongsCompanion(
                id: id,
                identity: identity,
                location: location,
                name: name,
                size: size,
                modified: modified,
                title: title,
                artist: artist,
                album: album,
                durationMs: durationMs,
                metadataError: metadataError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String identity,
                required String location,
                required String name,
                Value<int?> size = const Value.absent(),
                Value<int?> modified = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> metadataError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SongsCompanion.insert(
                id: id,
                identity: identity,
                location: location,
                name: name,
                size: size,
                modified: modified,
                title: title,
                artist: artist,
                album: album,
                durationMs: durationMs,
                metadataError: metadataError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SongsTable, Song>(table),
                  $$SongsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({songLocationsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (songLocationsRefs) db.songLocations,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (songLocationsRefs)
                    await $_getPrefetchedDataByColumns<
                      Song,
                      $SongsTable,
                      SongLocation,
                      $SongLocationsTable
                    >(
                      currentTable: table,
                      referencedTable: $$SongsTableReferences
                          ._songLocationsRefsTable(db),
                      managerFromTypedResult: (p0) => $$SongsTableReferences(
                        db,
                        table,
                        p0,
                      ).songLocationsRefs,
                      currentColumn: 'id',
                      referencedColumn: 'song_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SongsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $SongsTable,
      Song,
      $$SongsTableFilterComposer,
      $$SongsTableOrderingComposer,
      $$SongsTableAnnotationComposer,
      $$SongsTableCreateCompanionBuilder,
      $$SongsTableUpdateCompanionBuilder,
      (Song, $$SongsTableReferences),
      Song,
      PrefetchHooks Function({bool songLocationsRefs})
    >;
typedef $$LibraryRootsTableCreateCompanionBuilder =
    LibraryRootsCompanion Function({
      required String location,
      Value<bool> accessible,
      Value<String> status,
      Value<int?> scannedAt,
      Value<int> rowid,
    });
typedef $$LibraryRootsTableUpdateCompanionBuilder =
    LibraryRootsCompanion Function({
      Value<String> location,
      Value<bool> accessible,
      Value<String> status,
      Value<int?> scannedAt,
      Value<int> rowid,
    });

final class $$LibraryRootsTableReferences
    extends BaseReferences<_$LibraryDatabase, $LibraryRootsTable, LibraryRoot> {
  $$LibraryRootsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SongLocationsTable, List<SongLocation>>
  _songLocationsRefsTable(_$LibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.songLocations,
        aliasName: 'library_roots__location__song_locations__root',
      );

  $$SongLocationsTableProcessedTableManager get songLocationsRefs {
    final manager = $$SongLocationsTableTableManager($_db, $_db.songLocations)
        .filter(
          (f) => f.root.location.sqlEquals($_itemColumn<String>('location')!),
        );

    final cache = $_typedResult.readTableOrNull(_songLocationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LibraryRootsTableFilterComposer
    extends Composer<_$LibraryDatabase, $LibraryRootsTable> {
  $$LibraryRootsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get accessible => $composableBuilder(
    column: $table.accessible,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scannedAt => $composableBuilder(
    column: $table.scannedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> songLocationsRefs(
    Expression<bool> Function($$SongLocationsTableFilterComposer f) f,
  ) {
    final $$SongLocationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.location,
      referencedTable: $db.songLocations,
      getReferencedColumn: (t) => t.root,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongLocationsTableFilterComposer(
            $db: $db,
            $table: $db.songLocations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LibraryRootsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $LibraryRootsTable> {
  $$LibraryRootsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get accessible => $composableBuilder(
    column: $table.accessible,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scannedAt => $composableBuilder(
    column: $table.scannedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LibraryRootsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $LibraryRootsTable> {
  $$LibraryRootsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<bool> get accessible => $composableBuilder(
    column: $table.accessible,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get scannedAt =>
      $composableBuilder(column: $table.scannedAt, builder: (column) => column);

  Expression<T> songLocationsRefs<T extends Object>(
    Expression<T> Function($$SongLocationsTableAnnotationComposer a) f,
  ) {
    final $$SongLocationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.location,
      referencedTable: $db.songLocations,
      getReferencedColumn: (t) => t.root,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongLocationsTableAnnotationComposer(
            $db: $db,
            $table: $db.songLocations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LibraryRootsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $LibraryRootsTable,
          LibraryRoot,
          $$LibraryRootsTableFilterComposer,
          $$LibraryRootsTableOrderingComposer,
          $$LibraryRootsTableAnnotationComposer,
          $$LibraryRootsTableCreateCompanionBuilder,
          $$LibraryRootsTableUpdateCompanionBuilder,
          (LibraryRoot, $$LibraryRootsTableReferences),
          LibraryRoot,
          PrefetchHooks Function({bool songLocationsRefs})
        > {
  $$LibraryRootsTableTableManager(
    _$LibraryDatabase db,
    $LibraryRootsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryRootsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LibraryRootsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LibraryRootsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> location = const Value.absent(),
                Value<bool> accessible = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> scannedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryRootsCompanion(
                location: location,
                accessible: accessible,
                status: status,
                scannedAt: scannedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String location,
                Value<bool> accessible = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> scannedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryRootsCompanion.insert(
                location: location,
                accessible: accessible,
                status: status,
                scannedAt: scannedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LibraryRootsTable, LibraryRoot>(table),
                  $$LibraryRootsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({songLocationsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (songLocationsRefs) db.songLocations,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (songLocationsRefs)
                    await $_getPrefetchedDataByColumns<
                      LibraryRoot,
                      $LibraryRootsTable,
                      SongLocation,
                      $SongLocationsTable
                    >(
                      currentTable: table,
                      referencedTable: $$LibraryRootsTableReferences
                          ._songLocationsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$LibraryRootsTableReferences(
                            db,
                            table,
                            p0,
                          ).songLocationsRefs,
                      currentColumn: 'location',
                      referencedColumn: 'root',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$LibraryRootsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $LibraryRootsTable,
      LibraryRoot,
      $$LibraryRootsTableFilterComposer,
      $$LibraryRootsTableOrderingComposer,
      $$LibraryRootsTableAnnotationComposer,
      $$LibraryRootsTableCreateCompanionBuilder,
      $$LibraryRootsTableUpdateCompanionBuilder,
      (LibraryRoot, $$LibraryRootsTableReferences),
      LibraryRoot,
      PrefetchHooks Function({bool songLocationsRefs})
    >;
typedef $$SongLocationsTableCreateCompanionBuilder =
    SongLocationsCompanion Function({
      required String songId,
      required String root,
      required String location,
      required String relativePath,
      Value<bool> available,
      Value<int> rowid,
    });
typedef $$SongLocationsTableUpdateCompanionBuilder =
    SongLocationsCompanion Function({
      Value<String> songId,
      Value<String> root,
      Value<String> location,
      Value<String> relativePath,
      Value<bool> available,
      Value<int> rowid,
    });

final class $$SongLocationsTableReferences
    extends
        BaseReferences<_$LibraryDatabase, $SongLocationsTable, SongLocation> {
  $$SongLocationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SongsTable _songIdTable(_$LibraryDatabase db) =>
      db.songs.createAlias('song_locations__song_id__songs__id');

  $$SongsTableProcessedTableManager get songId {
    final $_column = $_itemColumn<String>('song_id')!;

    final manager = $$SongsTableTableManager(
      $_db,
      $_db.songs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_songIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $LibraryRootsTable _rootTable(_$LibraryDatabase db) => db.libraryRoots
      .createAlias('song_locations__root__library_roots__location');

  $$LibraryRootsTableProcessedTableManager get root {
    final $_column = $_itemColumn<String>('root')!;

    final manager = $$LibraryRootsTableTableManager(
      $_db,
      $_db.libraryRoots,
    ).filter((f) => f.location.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_rootTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SongLocationsTableFilterComposer
    extends Composer<_$LibraryDatabase, $SongLocationsTable> {
  $$SongLocationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get available => $composableBuilder(
    column: $table.available,
    builder: (column) => ColumnFilters(column),
  );

  $$SongsTableFilterComposer get songId {
    final $$SongsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.songId,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableFilterComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LibraryRootsTableFilterComposer get root {
    final $$LibraryRootsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.root,
      referencedTable: $db.libraryRoots,
      getReferencedColumn: (t) => t.location,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LibraryRootsTableFilterComposer(
            $db: $db,
            $table: $db.libraryRoots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SongLocationsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $SongLocationsTable> {
  $$SongLocationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get available => $composableBuilder(
    column: $table.available,
    builder: (column) => ColumnOrderings(column),
  );

  $$SongsTableOrderingComposer get songId {
    final $$SongsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.songId,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableOrderingComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LibraryRootsTableOrderingComposer get root {
    final $$LibraryRootsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.root,
      referencedTable: $db.libraryRoots,
      getReferencedColumn: (t) => t.location,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LibraryRootsTableOrderingComposer(
            $db: $db,
            $table: $db.libraryRoots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SongLocationsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $SongLocationsTable> {
  $$SongLocationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get available =>
      $composableBuilder(column: $table.available, builder: (column) => column);

  $$SongsTableAnnotationComposer get songId {
    final $$SongsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.songId,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableAnnotationComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LibraryRootsTableAnnotationComposer get root {
    final $$LibraryRootsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.root,
      referencedTable: $db.libraryRoots,
      getReferencedColumn: (t) => t.location,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LibraryRootsTableAnnotationComposer(
            $db: $db,
            $table: $db.libraryRoots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SongLocationsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $SongLocationsTable,
          SongLocation,
          $$SongLocationsTableFilterComposer,
          $$SongLocationsTableOrderingComposer,
          $$SongLocationsTableAnnotationComposer,
          $$SongLocationsTableCreateCompanionBuilder,
          $$SongLocationsTableUpdateCompanionBuilder,
          (SongLocation, $$SongLocationsTableReferences),
          SongLocation,
          PrefetchHooks Function({bool songId, bool root})
        > {
  $$SongLocationsTableTableManager(
    _$LibraryDatabase db,
    $SongLocationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SongLocationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SongLocationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SongLocationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> songId = const Value.absent(),
                Value<String> root = const Value.absent(),
                Value<String> location = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<bool> available = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SongLocationsCompanion(
                songId: songId,
                root: root,
                location: location,
                relativePath: relativePath,
                available: available,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String songId,
                required String root,
                required String location,
                required String relativePath,
                Value<bool> available = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SongLocationsCompanion.insert(
                songId: songId,
                root: root,
                location: location,
                relativePath: relativePath,
                available: available,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SongLocationsTable, SongLocation>(table),
                  $$SongLocationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({songId = false, root = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (songId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.songId,
                        referencedTable: $$SongLocationsTableReferences
                            ._songIdTable(db),
                        referencedColumn: $$SongLocationsTableReferences
                            ._songIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (root) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.root,
                        referencedTable: $$SongLocationsTableReferences
                            ._rootTable(db),
                        referencedColumn: $$SongLocationsTableReferences
                            ._rootTable(db)
                            .location,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SongLocationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $SongLocationsTable,
      SongLocation,
      $$SongLocationsTableFilterComposer,
      $$SongLocationsTableOrderingComposer,
      $$SongLocationsTableAnnotationComposer,
      $$SongLocationsTableCreateCompanionBuilder,
      $$SongLocationsTableUpdateCompanionBuilder,
      (SongLocation, $$SongLocationsTableReferences),
      SongLocation,
      PrefetchHooks Function({bool songId, bool root})
    >;

class $LibraryDatabaseManager {
  final _$LibraryDatabase _db;
  $LibraryDatabaseManager(this._db);
  $$SongsTableTableManager get songs =>
      $$SongsTableTableManager(_db, _db.songs);
  $$LibraryRootsTableTableManager get libraryRoots =>
      $$LibraryRootsTableTableManager(_db, _db.libraryRoots);
  $$SongLocationsTableTableManager get songLocations =>
      $$SongLocationsTableTableManager(_db, _db.songLocations);
}
