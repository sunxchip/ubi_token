// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TripSessionsTable extends TripSessions
    with TableInfo<$TripSessionsTable, TripSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TripSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<int> startTime = GeneratedColumn<int>(
    'start_time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeMeta = const VerificationMeta(
    'endTime',
  );
  @override
  late final GeneratedColumn<int> endTime = GeneratedColumn<int>(
    'end_time',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _distanceKmMeta = const VerificationMeta(
    'distanceKm',
  );
  @override
  late final GeneratedColumn<double> distanceKm = GeneratedColumn<double>(
    'distance_km',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _finalScoreMeta = const VerificationMeta(
    'finalScore',
  );
  @override
  late final GeneratedColumn<int> finalScore = GeneratedColumn<int>(
    'final_score',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(100),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    startTime,
    endTime,
    distanceKm,
    finalScore,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trip_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<TripSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(
        _endTimeMeta,
        endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta),
      );
    }
    if (data.containsKey('distance_km')) {
      context.handle(
        _distanceKmMeta,
        distanceKm.isAcceptableOrUnknown(data['distance_km']!, _distanceKmMeta),
      );
    }
    if (data.containsKey('final_score')) {
      context.handle(
        _finalScoreMeta,
        finalScore.isAcceptableOrUnknown(data['final_score']!, _finalScoreMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TripSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TripSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      startTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_time'],
      )!,
      endTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_time'],
      ),
      distanceKm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance_km'],
      )!,
      finalScore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}final_score'],
      )!,
    );
  }

  @override
  $TripSessionsTable createAlias(String alias) {
    return $TripSessionsTable(attachedDatabase, alias);
  }
}

class TripSession extends DataClass implements Insertable<TripSession> {
  final int id;
  final String sessionId;
  final int startTime;
  final int? endTime;
  final double distanceKm;
  final int finalScore;
  const TripSession({
    required this.id,
    required this.sessionId,
    required this.startTime,
    this.endTime,
    required this.distanceKm,
    required this.finalScore,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['start_time'] = Variable<int>(startTime);
    if (!nullToAbsent || endTime != null) {
      map['end_time'] = Variable<int>(endTime);
    }
    map['distance_km'] = Variable<double>(distanceKm);
    map['final_score'] = Variable<int>(finalScore);
    return map;
  }

  TripSessionsCompanion toCompanion(bool nullToAbsent) {
    return TripSessionsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      startTime: Value(startTime),
      endTime: endTime == null && nullToAbsent
          ? const Value.absent()
          : Value(endTime),
      distanceKm: Value(distanceKm),
      finalScore: Value(finalScore),
    );
  }

  factory TripSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TripSession(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      startTime: serializer.fromJson<int>(json['startTime']),
      endTime: serializer.fromJson<int?>(json['endTime']),
      distanceKm: serializer.fromJson<double>(json['distanceKm']),
      finalScore: serializer.fromJson<int>(json['finalScore']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'startTime': serializer.toJson<int>(startTime),
      'endTime': serializer.toJson<int?>(endTime),
      'distanceKm': serializer.toJson<double>(distanceKm),
      'finalScore': serializer.toJson<int>(finalScore),
    };
  }

  TripSession copyWith({
    int? id,
    String? sessionId,
    int? startTime,
    Value<int?> endTime = const Value.absent(),
    double? distanceKm,
    int? finalScore,
  }) => TripSession(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    startTime: startTime ?? this.startTime,
    endTime: endTime.present ? endTime.value : this.endTime,
    distanceKm: distanceKm ?? this.distanceKm,
    finalScore: finalScore ?? this.finalScore,
  );
  TripSession copyWithCompanion(TripSessionsCompanion data) {
    return TripSession(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      distanceKm: data.distanceKm.present
          ? data.distanceKm.value
          : this.distanceKm,
      finalScore: data.finalScore.present
          ? data.finalScore.value
          : this.finalScore,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TripSession(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('distanceKm: $distanceKm, ')
          ..write('finalScore: $finalScore')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, sessionId, startTime, endTime, distanceKm, finalScore);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TripSession &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.distanceKm == this.distanceKm &&
          other.finalScore == this.finalScore);
}

class TripSessionsCompanion extends UpdateCompanion<TripSession> {
  final Value<int> id;
  final Value<String> sessionId;
  final Value<int> startTime;
  final Value<int?> endTime;
  final Value<double> distanceKm;
  final Value<int> finalScore;
  const TripSessionsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.distanceKm = const Value.absent(),
    this.finalScore = const Value.absent(),
  });
  TripSessionsCompanion.insert({
    this.id = const Value.absent(),
    required String sessionId,
    required int startTime,
    this.endTime = const Value.absent(),
    this.distanceKm = const Value.absent(),
    this.finalScore = const Value.absent(),
  }) : sessionId = Value(sessionId),
       startTime = Value(startTime);
  static Insertable<TripSession> custom({
    Expression<int>? id,
    Expression<String>? sessionId,
    Expression<int>? startTime,
    Expression<int>? endTime,
    Expression<double>? distanceKm,
    Expression<int>? finalScore,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (distanceKm != null) 'distance_km': distanceKm,
      if (finalScore != null) 'final_score': finalScore,
    });
  }

  TripSessionsCompanion copyWith({
    Value<int>? id,
    Value<String>? sessionId,
    Value<int>? startTime,
    Value<int?>? endTime,
    Value<double>? distanceKm,
    Value<int>? finalScore,
  }) {
    return TripSessionsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      distanceKm: distanceKm ?? this.distanceKm,
      finalScore: finalScore ?? this.finalScore,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<int>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<int>(endTime.value);
    }
    if (distanceKm.present) {
      map['distance_km'] = Variable<double>(distanceKm.value);
    }
    if (finalScore.present) {
      map['final_score'] = Variable<int>(finalScore.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TripSessionsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('distanceKm: $distanceKm, ')
          ..write('finalScore: $finalScore')
          ..write(')'))
        .toString();
  }
}

class $DriveEventsTable extends DriveEvents
    with TableInfo<$DriveEventsTable, DriveEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DriveEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<double> value = GeneratedColumn<double>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    type,
    timestamp,
    latitude,
    longitude,
    value,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drive_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<DriveEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DriveEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DriveEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}type'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $DriveEventsTable createAlias(String alias) {
    return $DriveEventsTable(attachedDatabase, alias);
  }
}

class DriveEvent extends DataClass implements Insertable<DriveEvent> {
  final int id;
  final String sessionId;
  final int type;
  final int timestamp;
  final double latitude;
  final double longitude;
  final double value;
  const DriveEvent({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.value,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['type'] = Variable<int>(type);
    map['timestamp'] = Variable<int>(timestamp);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['value'] = Variable<double>(value);
    return map;
  }

  DriveEventsCompanion toCompanion(bool nullToAbsent) {
    return DriveEventsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      type: Value(type),
      timestamp: Value(timestamp),
      latitude: Value(latitude),
      longitude: Value(longitude),
      value: Value(value),
    );
  }

  factory DriveEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DriveEvent(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      type: serializer.fromJson<int>(json['type']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      value: serializer.fromJson<double>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'type': serializer.toJson<int>(type),
      'timestamp': serializer.toJson<int>(timestamp),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'value': serializer.toJson<double>(value),
    };
  }

  DriveEvent copyWith({
    int? id,
    String? sessionId,
    int? type,
    int? timestamp,
    double? latitude,
    double? longitude,
    double? value,
  }) => DriveEvent(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    type: type ?? this.type,
    timestamp: timestamp ?? this.timestamp,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    value: value ?? this.value,
  );
  DriveEvent copyWithCompanion(DriveEventsCompanion data) {
    return DriveEvent(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      type: data.type.present ? data.type.value : this.type,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DriveEvent(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('type: $type, ')
          ..write('timestamp: $timestamp, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, sessionId, type, timestamp, latitude, longitude, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DriveEvent &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.type == this.type &&
          other.timestamp == this.timestamp &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.value == this.value);
}

class DriveEventsCompanion extends UpdateCompanion<DriveEvent> {
  final Value<int> id;
  final Value<String> sessionId;
  final Value<int> type;
  final Value<int> timestamp;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<double> value;
  const DriveEventsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.type = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.value = const Value.absent(),
  });
  DriveEventsCompanion.insert({
    this.id = const Value.absent(),
    required String sessionId,
    required int type,
    required int timestamp,
    required double latitude,
    required double longitude,
    required double value,
  }) : sessionId = Value(sessionId),
       type = Value(type),
       timestamp = Value(timestamp),
       latitude = Value(latitude),
       longitude = Value(longitude),
       value = Value(value);
  static Insertable<DriveEvent> custom({
    Expression<int>? id,
    Expression<String>? sessionId,
    Expression<int>? type,
    Expression<int>? timestamp,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? value,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (type != null) 'type': type,
      if (timestamp != null) 'timestamp': timestamp,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (value != null) 'value': value,
    });
  }

  DriveEventsCompanion copyWith({
    Value<int>? id,
    Value<String>? sessionId,
    Value<int>? type,
    Value<int>? timestamp,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<double>? value,
  }) {
    return DriveEventsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      value: value ?? this.value,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (value.present) {
      map['value'] = Variable<double>(value.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DriveEventsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('type: $type, ')
          ..write('timestamp: $timestamp, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TripSessionsTable tripSessions = $TripSessionsTable(this);
  late final $DriveEventsTable driveEvents = $DriveEventsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tripSessions,
    driveEvents,
  ];
}

typedef $$TripSessionsTableCreateCompanionBuilder =
    TripSessionsCompanion Function({
      Value<int> id,
      required String sessionId,
      required int startTime,
      Value<int?> endTime,
      Value<double> distanceKm,
      Value<int> finalScore,
    });
typedef $$TripSessionsTableUpdateCompanionBuilder =
    TripSessionsCompanion Function({
      Value<int> id,
      Value<String> sessionId,
      Value<int> startTime,
      Value<int?> endTime,
      Value<double> distanceKm,
      Value<int> finalScore,
    });

class $$TripSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $TripSessionsTable> {
  $$TripSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distanceKm => $composableBuilder(
    column: $table.distanceKm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get finalScore => $composableBuilder(
    column: $table.finalScore,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TripSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TripSessionsTable> {
  $$TripSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distanceKm => $composableBuilder(
    column: $table.distanceKm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get finalScore => $composableBuilder(
    column: $table.finalScore,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TripSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TripSessionsTable> {
  $$TripSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<int> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<double> get distanceKm => $composableBuilder(
    column: $table.distanceKm,
    builder: (column) => column,
  );

  GeneratedColumn<int> get finalScore => $composableBuilder(
    column: $table.finalScore,
    builder: (column) => column,
  );
}

class $$TripSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TripSessionsTable,
          TripSession,
          $$TripSessionsTableFilterComposer,
          $$TripSessionsTableOrderingComposer,
          $$TripSessionsTableAnnotationComposer,
          $$TripSessionsTableCreateCompanionBuilder,
          $$TripSessionsTableUpdateCompanionBuilder,
          (
            TripSession,
            BaseReferences<_$AppDatabase, $TripSessionsTable, TripSession>,
          ),
          TripSession,
          PrefetchHooks Function()
        > {
  $$TripSessionsTableTableManager(_$AppDatabase db, $TripSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TripSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TripSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TripSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> startTime = const Value.absent(),
                Value<int?> endTime = const Value.absent(),
                Value<double> distanceKm = const Value.absent(),
                Value<int> finalScore = const Value.absent(),
              }) => TripSessionsCompanion(
                id: id,
                sessionId: sessionId,
                startTime: startTime,
                endTime: endTime,
                distanceKm: distanceKm,
                finalScore: finalScore,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sessionId,
                required int startTime,
                Value<int?> endTime = const Value.absent(),
                Value<double> distanceKm = const Value.absent(),
                Value<int> finalScore = const Value.absent(),
              }) => TripSessionsCompanion.insert(
                id: id,
                sessionId: sessionId,
                startTime: startTime,
                endTime: endTime,
                distanceKm: distanceKm,
                finalScore: finalScore,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TripSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TripSessionsTable,
      TripSession,
      $$TripSessionsTableFilterComposer,
      $$TripSessionsTableOrderingComposer,
      $$TripSessionsTableAnnotationComposer,
      $$TripSessionsTableCreateCompanionBuilder,
      $$TripSessionsTableUpdateCompanionBuilder,
      (
        TripSession,
        BaseReferences<_$AppDatabase, $TripSessionsTable, TripSession>,
      ),
      TripSession,
      PrefetchHooks Function()
    >;
typedef $$DriveEventsTableCreateCompanionBuilder =
    DriveEventsCompanion Function({
      Value<int> id,
      required String sessionId,
      required int type,
      required int timestamp,
      required double latitude,
      required double longitude,
      required double value,
    });
typedef $$DriveEventsTableUpdateCompanionBuilder =
    DriveEventsCompanion Function({
      Value<int> id,
      Value<String> sessionId,
      Value<int> type,
      Value<int> timestamp,
      Value<double> latitude,
      Value<double> longitude,
      Value<double> value,
    });

class $$DriveEventsTableFilterComposer
    extends Composer<_$AppDatabase, $DriveEventsTable> {
  $$DriveEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DriveEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $DriveEventsTable> {
  $$DriveEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DriveEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DriveEventsTable> {
  $$DriveEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$DriveEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DriveEventsTable,
          DriveEvent,
          $$DriveEventsTableFilterComposer,
          $$DriveEventsTableOrderingComposer,
          $$DriveEventsTableAnnotationComposer,
          $$DriveEventsTableCreateCompanionBuilder,
          $$DriveEventsTableUpdateCompanionBuilder,
          (
            DriveEvent,
            BaseReferences<_$AppDatabase, $DriveEventsTable, DriveEvent>,
          ),
          DriveEvent,
          PrefetchHooks Function()
        > {
  $$DriveEventsTableTableManager(_$AppDatabase db, $DriveEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DriveEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DriveEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DriveEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<double> value = const Value.absent(),
              }) => DriveEventsCompanion(
                id: id,
                sessionId: sessionId,
                type: type,
                timestamp: timestamp,
                latitude: latitude,
                longitude: longitude,
                value: value,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sessionId,
                required int type,
                required int timestamp,
                required double latitude,
                required double longitude,
                required double value,
              }) => DriveEventsCompanion.insert(
                id: id,
                sessionId: sessionId,
                type: type,
                timestamp: timestamp,
                latitude: latitude,
                longitude: longitude,
                value: value,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DriveEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DriveEventsTable,
      DriveEvent,
      $$DriveEventsTableFilterComposer,
      $$DriveEventsTableOrderingComposer,
      $$DriveEventsTableAnnotationComposer,
      $$DriveEventsTableCreateCompanionBuilder,
      $$DriveEventsTableUpdateCompanionBuilder,
      (
        DriveEvent,
        BaseReferences<_$AppDatabase, $DriveEventsTable, DriveEvent>,
      ),
      DriveEvent,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TripSessionsTableTableManager get tripSessions =>
      $$TripSessionsTableTableManager(_db, _db.tripSessions);
  $$DriveEventsTableTableManager get driveEvents =>
      $$DriveEventsTableTableManager(_db, _db.driveEvents);
}
