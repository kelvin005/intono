// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'practice_db.dart';

// ignore_for_file: type=lint
class $SessionsTable extends Sessions with TableInfo<$SessionsTable, Session> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<int> endedAt = GeneratedColumn<int>(
    'ended_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _instrumentMeta = const VerificationMeta(
    'instrument',
  );
  @override
  late final GeneratedColumn<String> instrument = GeneratedColumn<String>(
    'instrument',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('violin'),
  );
  static const VerificationMeta _a4HzMeta = const VerificationMeta('a4Hz');
  @override
  late final GeneratedColumn<double> a4Hz = GeneratedColumn<double>(
    'a4_hz',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tuningMeta = const VerificationMeta('tuning');
  @override
  late final GeneratedColumn<String> tuning = GeneratedColumn<String>(
    'tuning',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scaleIdMeta = const VerificationMeta(
    'scaleId',
  );
  @override
  late final GeneratedColumn<String> scaleId = GeneratedColumn<String>(
    'scale_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scorePercentMeta = const VerificationMeta(
    'scorePercent',
  );
  @override
  late final GeneratedColumn<double> scorePercent = GeneratedColumn<double>(
    'score_percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _greenMeta = const VerificationMeta('green');
  @override
  late final GeneratedColumn<int> green = GeneratedColumn<int>(
    'green',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yellowMeta = const VerificationMeta('yellow');
  @override
  late final GeneratedColumn<int> yellow = GeneratedColumn<int>(
    'yellow',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _redMeta = const VerificationMeta('red');
  @override
  late final GeneratedColumn<int> red = GeneratedColumn<int>(
    'red',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _missedMeta = const VerificationMeta('missed');
  @override
  late final GeneratedColumn<int> missed = GeneratedColumn<int>(
    'missed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteCountMeta = const VerificationMeta(
    'noteCount',
  );
  @override
  late final GeneratedColumn<int> noteCount = GeneratedColumn<int>(
    'note_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    startedAt,
    endedAt,
    mode,
    instrument,
    a4Hz,
    tuning,
    scaleId,
    scorePercent,
    green,
    yellow,
    red,
    missed,
    noteCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Session> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_endedAtMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('instrument')) {
      context.handle(
        _instrumentMeta,
        instrument.isAcceptableOrUnknown(data['instrument']!, _instrumentMeta),
      );
    }
    if (data.containsKey('a4_hz')) {
      context.handle(
        _a4HzMeta,
        a4Hz.isAcceptableOrUnknown(data['a4_hz']!, _a4HzMeta),
      );
    } else if (isInserting) {
      context.missing(_a4HzMeta);
    }
    if (data.containsKey('tuning')) {
      context.handle(
        _tuningMeta,
        tuning.isAcceptableOrUnknown(data['tuning']!, _tuningMeta),
      );
    } else if (isInserting) {
      context.missing(_tuningMeta);
    }
    if (data.containsKey('scale_id')) {
      context.handle(
        _scaleIdMeta,
        scaleId.isAcceptableOrUnknown(data['scale_id']!, _scaleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_scaleIdMeta);
    }
    if (data.containsKey('score_percent')) {
      context.handle(
        _scorePercentMeta,
        scorePercent.isAcceptableOrUnknown(
          data['score_percent']!,
          _scorePercentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scorePercentMeta);
    }
    if (data.containsKey('green')) {
      context.handle(
        _greenMeta,
        green.isAcceptableOrUnknown(data['green']!, _greenMeta),
      );
    } else if (isInserting) {
      context.missing(_greenMeta);
    }
    if (data.containsKey('yellow')) {
      context.handle(
        _yellowMeta,
        yellow.isAcceptableOrUnknown(data['yellow']!, _yellowMeta),
      );
    } else if (isInserting) {
      context.missing(_yellowMeta);
    }
    if (data.containsKey('red')) {
      context.handle(
        _redMeta,
        red.isAcceptableOrUnknown(data['red']!, _redMeta),
      );
    } else if (isInserting) {
      context.missing(_redMeta);
    }
    if (data.containsKey('missed')) {
      context.handle(
        _missedMeta,
        missed.isAcceptableOrUnknown(data['missed']!, _missedMeta),
      );
    } else if (isInserting) {
      context.missing(_missedMeta);
    }
    if (data.containsKey('note_count')) {
      context.handle(
        _noteCountMeta,
        noteCount.isAcceptableOrUnknown(data['note_count']!, _noteCountMeta),
      );
    } else if (isInserting) {
      context.missing(_noteCountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Session map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Session(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_at'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      instrument: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}instrument'],
      )!,
      a4Hz: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}a4_hz'],
      )!,
      tuning: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tuning'],
      )!,
      scaleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scale_id'],
      )!,
      scorePercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}score_percent'],
      )!,
      green: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}green'],
      )!,
      yellow: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}yellow'],
      )!,
      red: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}red'],
      )!,
      missed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}missed'],
      )!,
      noteCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}note_count'],
      )!,
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class Session extends DataClass implements Insertable<Session> {
  final String id;
  final int startedAt;
  final int endedAt;
  final String mode;
  final String instrument;
  final double a4Hz;
  final String tuning;
  final String scaleId;
  final double scorePercent;
  final int green;
  final int yellow;
  final int red;
  final int missed;
  final int noteCount;
  const Session({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.mode,
    required this.instrument,
    required this.a4Hz,
    required this.tuning,
    required this.scaleId,
    required this.scorePercent,
    required this.green,
    required this.yellow,
    required this.red,
    required this.missed,
    required this.noteCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['started_at'] = Variable<int>(startedAt);
    map['ended_at'] = Variable<int>(endedAt);
    map['mode'] = Variable<String>(mode);
    map['instrument'] = Variable<String>(instrument);
    map['a4_hz'] = Variable<double>(a4Hz);
    map['tuning'] = Variable<String>(tuning);
    map['scale_id'] = Variable<String>(scaleId);
    map['score_percent'] = Variable<double>(scorePercent);
    map['green'] = Variable<int>(green);
    map['yellow'] = Variable<int>(yellow);
    map['red'] = Variable<int>(red);
    map['missed'] = Variable<int>(missed);
    map['note_count'] = Variable<int>(noteCount);
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      startedAt: Value(startedAt),
      endedAt: Value(endedAt),
      mode: Value(mode),
      instrument: Value(instrument),
      a4Hz: Value(a4Hz),
      tuning: Value(tuning),
      scaleId: Value(scaleId),
      scorePercent: Value(scorePercent),
      green: Value(green),
      yellow: Value(yellow),
      red: Value(red),
      missed: Value(missed),
      noteCount: Value(noteCount),
    );
  }

  factory Session.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Session(
      id: serializer.fromJson<String>(json['id']),
      startedAt: serializer.fromJson<int>(json['startedAt']),
      endedAt: serializer.fromJson<int>(json['endedAt']),
      mode: serializer.fromJson<String>(json['mode']),
      instrument: serializer.fromJson<String>(json['instrument']),
      a4Hz: serializer.fromJson<double>(json['a4Hz']),
      tuning: serializer.fromJson<String>(json['tuning']),
      scaleId: serializer.fromJson<String>(json['scaleId']),
      scorePercent: serializer.fromJson<double>(json['scorePercent']),
      green: serializer.fromJson<int>(json['green']),
      yellow: serializer.fromJson<int>(json['yellow']),
      red: serializer.fromJson<int>(json['red']),
      missed: serializer.fromJson<int>(json['missed']),
      noteCount: serializer.fromJson<int>(json['noteCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'startedAt': serializer.toJson<int>(startedAt),
      'endedAt': serializer.toJson<int>(endedAt),
      'mode': serializer.toJson<String>(mode),
      'instrument': serializer.toJson<String>(instrument),
      'a4Hz': serializer.toJson<double>(a4Hz),
      'tuning': serializer.toJson<String>(tuning),
      'scaleId': serializer.toJson<String>(scaleId),
      'scorePercent': serializer.toJson<double>(scorePercent),
      'green': serializer.toJson<int>(green),
      'yellow': serializer.toJson<int>(yellow),
      'red': serializer.toJson<int>(red),
      'missed': serializer.toJson<int>(missed),
      'noteCount': serializer.toJson<int>(noteCount),
    };
  }

  Session copyWith({
    String? id,
    int? startedAt,
    int? endedAt,
    String? mode,
    String? instrument,
    double? a4Hz,
    String? tuning,
    String? scaleId,
    double? scorePercent,
    int? green,
    int? yellow,
    int? red,
    int? missed,
    int? noteCount,
  }) => Session(
    id: id ?? this.id,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    mode: mode ?? this.mode,
    instrument: instrument ?? this.instrument,
    a4Hz: a4Hz ?? this.a4Hz,
    tuning: tuning ?? this.tuning,
    scaleId: scaleId ?? this.scaleId,
    scorePercent: scorePercent ?? this.scorePercent,
    green: green ?? this.green,
    yellow: yellow ?? this.yellow,
    red: red ?? this.red,
    missed: missed ?? this.missed,
    noteCount: noteCount ?? this.noteCount,
  );
  Session copyWithCompanion(SessionsCompanion data) {
    return Session(
      id: data.id.present ? data.id.value : this.id,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      mode: data.mode.present ? data.mode.value : this.mode,
      instrument: data.instrument.present
          ? data.instrument.value
          : this.instrument,
      a4Hz: data.a4Hz.present ? data.a4Hz.value : this.a4Hz,
      tuning: data.tuning.present ? data.tuning.value : this.tuning,
      scaleId: data.scaleId.present ? data.scaleId.value : this.scaleId,
      scorePercent: data.scorePercent.present
          ? data.scorePercent.value
          : this.scorePercent,
      green: data.green.present ? data.green.value : this.green,
      yellow: data.yellow.present ? data.yellow.value : this.yellow,
      red: data.red.present ? data.red.value : this.red,
      missed: data.missed.present ? data.missed.value : this.missed,
      noteCount: data.noteCount.present ? data.noteCount.value : this.noteCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Session(')
          ..write('id: $id, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('mode: $mode, ')
          ..write('instrument: $instrument, ')
          ..write('a4Hz: $a4Hz, ')
          ..write('tuning: $tuning, ')
          ..write('scaleId: $scaleId, ')
          ..write('scorePercent: $scorePercent, ')
          ..write('green: $green, ')
          ..write('yellow: $yellow, ')
          ..write('red: $red, ')
          ..write('missed: $missed, ')
          ..write('noteCount: $noteCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    startedAt,
    endedAt,
    mode,
    instrument,
    a4Hz,
    tuning,
    scaleId,
    scorePercent,
    green,
    yellow,
    red,
    missed,
    noteCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Session &&
          other.id == this.id &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.mode == this.mode &&
          other.instrument == this.instrument &&
          other.a4Hz == this.a4Hz &&
          other.tuning == this.tuning &&
          other.scaleId == this.scaleId &&
          other.scorePercent == this.scorePercent &&
          other.green == this.green &&
          other.yellow == this.yellow &&
          other.red == this.red &&
          other.missed == this.missed &&
          other.noteCount == this.noteCount);
}

class SessionsCompanion extends UpdateCompanion<Session> {
  final Value<String> id;
  final Value<int> startedAt;
  final Value<int> endedAt;
  final Value<String> mode;
  final Value<String> instrument;
  final Value<double> a4Hz;
  final Value<String> tuning;
  final Value<String> scaleId;
  final Value<double> scorePercent;
  final Value<int> green;
  final Value<int> yellow;
  final Value<int> red;
  final Value<int> missed;
  final Value<int> noteCount;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.mode = const Value.absent(),
    this.instrument = const Value.absent(),
    this.a4Hz = const Value.absent(),
    this.tuning = const Value.absent(),
    this.scaleId = const Value.absent(),
    this.scorePercent = const Value.absent(),
    this.green = const Value.absent(),
    this.yellow = const Value.absent(),
    this.red = const Value.absent(),
    this.missed = const Value.absent(),
    this.noteCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    required int startedAt,
    required int endedAt,
    required String mode,
    this.instrument = const Value.absent(),
    required double a4Hz,
    required String tuning,
    required String scaleId,
    required double scorePercent,
    required int green,
    required int yellow,
    required int red,
    required int missed,
    required int noteCount,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       startedAt = Value(startedAt),
       endedAt = Value(endedAt),
       mode = Value(mode),
       a4Hz = Value(a4Hz),
       tuning = Value(tuning),
       scaleId = Value(scaleId),
       scorePercent = Value(scorePercent),
       green = Value(green),
       yellow = Value(yellow),
       red = Value(red),
       missed = Value(missed),
       noteCount = Value(noteCount);
  static Insertable<Session> custom({
    Expression<String>? id,
    Expression<int>? startedAt,
    Expression<int>? endedAt,
    Expression<String>? mode,
    Expression<String>? instrument,
    Expression<double>? a4Hz,
    Expression<String>? tuning,
    Expression<String>? scaleId,
    Expression<double>? scorePercent,
    Expression<int>? green,
    Expression<int>? yellow,
    Expression<int>? red,
    Expression<int>? missed,
    Expression<int>? noteCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (mode != null) 'mode': mode,
      if (instrument != null) 'instrument': instrument,
      if (a4Hz != null) 'a4_hz': a4Hz,
      if (tuning != null) 'tuning': tuning,
      if (scaleId != null) 'scale_id': scaleId,
      if (scorePercent != null) 'score_percent': scorePercent,
      if (green != null) 'green': green,
      if (yellow != null) 'yellow': yellow,
      if (red != null) 'red': red,
      if (missed != null) 'missed': missed,
      if (noteCount != null) 'note_count': noteCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? id,
    Value<int>? startedAt,
    Value<int>? endedAt,
    Value<String>? mode,
    Value<String>? instrument,
    Value<double>? a4Hz,
    Value<String>? tuning,
    Value<String>? scaleId,
    Value<double>? scorePercent,
    Value<int>? green,
    Value<int>? yellow,
    Value<int>? red,
    Value<int>? missed,
    Value<int>? noteCount,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      id: id ?? this.id,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      mode: mode ?? this.mode,
      instrument: instrument ?? this.instrument,
      a4Hz: a4Hz ?? this.a4Hz,
      tuning: tuning ?? this.tuning,
      scaleId: scaleId ?? this.scaleId,
      scorePercent: scorePercent ?? this.scorePercent,
      green: green ?? this.green,
      yellow: yellow ?? this.yellow,
      red: red ?? this.red,
      missed: missed ?? this.missed,
      noteCount: noteCount ?? this.noteCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<int>(endedAt.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (instrument.present) {
      map['instrument'] = Variable<String>(instrument.value);
    }
    if (a4Hz.present) {
      map['a4_hz'] = Variable<double>(a4Hz.value);
    }
    if (tuning.present) {
      map['tuning'] = Variable<String>(tuning.value);
    }
    if (scaleId.present) {
      map['scale_id'] = Variable<String>(scaleId.value);
    }
    if (scorePercent.present) {
      map['score_percent'] = Variable<double>(scorePercent.value);
    }
    if (green.present) {
      map['green'] = Variable<int>(green.value);
    }
    if (yellow.present) {
      map['yellow'] = Variable<int>(yellow.value);
    }
    if (red.present) {
      map['red'] = Variable<int>(red.value);
    }
    if (missed.present) {
      map['missed'] = Variable<int>(missed.value);
    }
    if (noteCount.present) {
      map['note_count'] = Variable<int>(noteCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('mode: $mode, ')
          ..write('instrument: $instrument, ')
          ..write('a4Hz: $a4Hz, ')
          ..write('tuning: $tuning, ')
          ..write('scaleId: $scaleId, ')
          ..write('scorePercent: $scorePercent, ')
          ..write('green: $green, ')
          ..write('yellow: $yellow, ')
          ..write('red: $red, ')
          ..write('missed: $missed, ')
          ..write('noteCount: $noteCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GradedNotesTable extends GradedNotes
    with TableInfo<$GradedNotesTable, GradedNoteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GradedNotesTable(this.attachedDatabase, [this._alias]);
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
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _idxMeta = const VerificationMeta('idx');
  @override
  late final GeneratedColumn<int> idx = GeneratedColumn<int>(
    'idx',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _midiNoteMeta = const VerificationMeta(
    'midiNote',
  );
  @override
  late final GeneratedColumn<int> midiNote = GeneratedColumn<int>(
    'midi_note',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stringMeta = const VerificationMeta('string');
  @override
  late final GeneratedColumn<String> string = GeneratedColumn<String>(
    'string',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerMeta = const VerificationMeta('finger');
  @override
  late final GeneratedColumn<int> finger = GeneratedColumn<int>(
    'finger',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _placementMeta = const VerificationMeta(
    'placement',
  );
  @override
  late final GeneratedColumn<String> placement = GeneratedColumn<String>(
    'placement',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gradeMeta = const VerificationMeta('grade');
  @override
  late final GeneratedColumn<String> grade = GeneratedColumn<String>(
    'grade',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _centsMeta = const VerificationMeta('cents');
  @override
  late final GeneratedColumn<double> cents = GeneratedColumn<double>(
    'cents',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tStartMeta = const VerificationMeta('tStart');
  @override
  late final GeneratedColumn<double> tStart = GeneratedColumn<double>(
    't_start',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tEndMeta = const VerificationMeta('tEnd');
  @override
  late final GeneratedColumn<double> tEnd = GeneratedColumn<double>(
    't_end',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    idx,
    midiNote,
    string,
    finger,
    placement,
    grade,
    cents,
    tStart,
    tEnd,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graded_notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<GradedNoteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('idx')) {
      context.handle(
        _idxMeta,
        idx.isAcceptableOrUnknown(data['idx']!, _idxMeta),
      );
    } else if (isInserting) {
      context.missing(_idxMeta);
    }
    if (data.containsKey('midi_note')) {
      context.handle(
        _midiNoteMeta,
        midiNote.isAcceptableOrUnknown(data['midi_note']!, _midiNoteMeta),
      );
    } else if (isInserting) {
      context.missing(_midiNoteMeta);
    }
    if (data.containsKey('string')) {
      context.handle(
        _stringMeta,
        string.isAcceptableOrUnknown(data['string']!, _stringMeta),
      );
    } else if (isInserting) {
      context.missing(_stringMeta);
    }
    if (data.containsKey('finger')) {
      context.handle(
        _fingerMeta,
        finger.isAcceptableOrUnknown(data['finger']!, _fingerMeta),
      );
    } else if (isInserting) {
      context.missing(_fingerMeta);
    }
    if (data.containsKey('placement')) {
      context.handle(
        _placementMeta,
        placement.isAcceptableOrUnknown(data['placement']!, _placementMeta),
      );
    }
    if (data.containsKey('grade')) {
      context.handle(
        _gradeMeta,
        grade.isAcceptableOrUnknown(data['grade']!, _gradeMeta),
      );
    } else if (isInserting) {
      context.missing(_gradeMeta);
    }
    if (data.containsKey('cents')) {
      context.handle(
        _centsMeta,
        cents.isAcceptableOrUnknown(data['cents']!, _centsMeta),
      );
    }
    if (data.containsKey('t_start')) {
      context.handle(
        _tStartMeta,
        tStart.isAcceptableOrUnknown(data['t_start']!, _tStartMeta),
      );
    }
    if (data.containsKey('t_end')) {
      context.handle(
        _tEndMeta,
        tEnd.isAcceptableOrUnknown(data['t_end']!, _tEndMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, idx};
  @override
  GradedNoteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GradedNoteRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      idx: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}idx'],
      )!,
      midiNote: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}midi_note'],
      )!,
      string: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}string'],
      )!,
      finger: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}finger'],
      )!,
      placement: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}placement'],
      ),
      grade: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}grade'],
      )!,
      cents: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cents'],
      ),
      tStart: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}t_start'],
      ),
      tEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}t_end'],
      ),
    );
  }

  @override
  $GradedNotesTable createAlias(String alias) {
    return $GradedNotesTable(attachedDatabase, alias);
  }
}

class GradedNoteRow extends DataClass implements Insertable<GradedNoteRow> {
  final String sessionId;
  final int idx;
  final int midiNote;
  final String string;
  final int finger;
  final String? placement;
  final String grade;
  final double? cents;
  final double? tStart;
  final double? tEnd;
  const GradedNoteRow({
    required this.sessionId,
    required this.idx,
    required this.midiNote,
    required this.string,
    required this.finger,
    this.placement,
    required this.grade,
    this.cents,
    this.tStart,
    this.tEnd,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['idx'] = Variable<int>(idx);
    map['midi_note'] = Variable<int>(midiNote);
    map['string'] = Variable<String>(string);
    map['finger'] = Variable<int>(finger);
    if (!nullToAbsent || placement != null) {
      map['placement'] = Variable<String>(placement);
    }
    map['grade'] = Variable<String>(grade);
    if (!nullToAbsent || cents != null) {
      map['cents'] = Variable<double>(cents);
    }
    if (!nullToAbsent || tStart != null) {
      map['t_start'] = Variable<double>(tStart);
    }
    if (!nullToAbsent || tEnd != null) {
      map['t_end'] = Variable<double>(tEnd);
    }
    return map;
  }

  GradedNotesCompanion toCompanion(bool nullToAbsent) {
    return GradedNotesCompanion(
      sessionId: Value(sessionId),
      idx: Value(idx),
      midiNote: Value(midiNote),
      string: Value(string),
      finger: Value(finger),
      placement: placement == null && nullToAbsent
          ? const Value.absent()
          : Value(placement),
      grade: Value(grade),
      cents: cents == null && nullToAbsent
          ? const Value.absent()
          : Value(cents),
      tStart: tStart == null && nullToAbsent
          ? const Value.absent()
          : Value(tStart),
      tEnd: tEnd == null && nullToAbsent ? const Value.absent() : Value(tEnd),
    );
  }

  factory GradedNoteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GradedNoteRow(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      idx: serializer.fromJson<int>(json['idx']),
      midiNote: serializer.fromJson<int>(json['midiNote']),
      string: serializer.fromJson<String>(json['string']),
      finger: serializer.fromJson<int>(json['finger']),
      placement: serializer.fromJson<String?>(json['placement']),
      grade: serializer.fromJson<String>(json['grade']),
      cents: serializer.fromJson<double?>(json['cents']),
      tStart: serializer.fromJson<double?>(json['tStart']),
      tEnd: serializer.fromJson<double?>(json['tEnd']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'idx': serializer.toJson<int>(idx),
      'midiNote': serializer.toJson<int>(midiNote),
      'string': serializer.toJson<String>(string),
      'finger': serializer.toJson<int>(finger),
      'placement': serializer.toJson<String?>(placement),
      'grade': serializer.toJson<String>(grade),
      'cents': serializer.toJson<double?>(cents),
      'tStart': serializer.toJson<double?>(tStart),
      'tEnd': serializer.toJson<double?>(tEnd),
    };
  }

  GradedNoteRow copyWith({
    String? sessionId,
    int? idx,
    int? midiNote,
    String? string,
    int? finger,
    Value<String?> placement = const Value.absent(),
    String? grade,
    Value<double?> cents = const Value.absent(),
    Value<double?> tStart = const Value.absent(),
    Value<double?> tEnd = const Value.absent(),
  }) => GradedNoteRow(
    sessionId: sessionId ?? this.sessionId,
    idx: idx ?? this.idx,
    midiNote: midiNote ?? this.midiNote,
    string: string ?? this.string,
    finger: finger ?? this.finger,
    placement: placement.present ? placement.value : this.placement,
    grade: grade ?? this.grade,
    cents: cents.present ? cents.value : this.cents,
    tStart: tStart.present ? tStart.value : this.tStart,
    tEnd: tEnd.present ? tEnd.value : this.tEnd,
  );
  GradedNoteRow copyWithCompanion(GradedNotesCompanion data) {
    return GradedNoteRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      idx: data.idx.present ? data.idx.value : this.idx,
      midiNote: data.midiNote.present ? data.midiNote.value : this.midiNote,
      string: data.string.present ? data.string.value : this.string,
      finger: data.finger.present ? data.finger.value : this.finger,
      placement: data.placement.present ? data.placement.value : this.placement,
      grade: data.grade.present ? data.grade.value : this.grade,
      cents: data.cents.present ? data.cents.value : this.cents,
      tStart: data.tStart.present ? data.tStart.value : this.tStart,
      tEnd: data.tEnd.present ? data.tEnd.value : this.tEnd,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GradedNoteRow(')
          ..write('sessionId: $sessionId, ')
          ..write('idx: $idx, ')
          ..write('midiNote: $midiNote, ')
          ..write('string: $string, ')
          ..write('finger: $finger, ')
          ..write('placement: $placement, ')
          ..write('grade: $grade, ')
          ..write('cents: $cents, ')
          ..write('tStart: $tStart, ')
          ..write('tEnd: $tEnd')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    idx,
    midiNote,
    string,
    finger,
    placement,
    grade,
    cents,
    tStart,
    tEnd,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GradedNoteRow &&
          other.sessionId == this.sessionId &&
          other.idx == this.idx &&
          other.midiNote == this.midiNote &&
          other.string == this.string &&
          other.finger == this.finger &&
          other.placement == this.placement &&
          other.grade == this.grade &&
          other.cents == this.cents &&
          other.tStart == this.tStart &&
          other.tEnd == this.tEnd);
}

class GradedNotesCompanion extends UpdateCompanion<GradedNoteRow> {
  final Value<String> sessionId;
  final Value<int> idx;
  final Value<int> midiNote;
  final Value<String> string;
  final Value<int> finger;
  final Value<String?> placement;
  final Value<String> grade;
  final Value<double?> cents;
  final Value<double?> tStart;
  final Value<double?> tEnd;
  final Value<int> rowid;
  const GradedNotesCompanion({
    this.sessionId = const Value.absent(),
    this.idx = const Value.absent(),
    this.midiNote = const Value.absent(),
    this.string = const Value.absent(),
    this.finger = const Value.absent(),
    this.placement = const Value.absent(),
    this.grade = const Value.absent(),
    this.cents = const Value.absent(),
    this.tStart = const Value.absent(),
    this.tEnd = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GradedNotesCompanion.insert({
    required String sessionId,
    required int idx,
    required int midiNote,
    required String string,
    required int finger,
    this.placement = const Value.absent(),
    required String grade,
    this.cents = const Value.absent(),
    this.tStart = const Value.absent(),
    this.tEnd = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       idx = Value(idx),
       midiNote = Value(midiNote),
       string = Value(string),
       finger = Value(finger),
       grade = Value(grade);
  static Insertable<GradedNoteRow> custom({
    Expression<String>? sessionId,
    Expression<int>? idx,
    Expression<int>? midiNote,
    Expression<String>? string,
    Expression<int>? finger,
    Expression<String>? placement,
    Expression<String>? grade,
    Expression<double>? cents,
    Expression<double>? tStart,
    Expression<double>? tEnd,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (idx != null) 'idx': idx,
      if (midiNote != null) 'midi_note': midiNote,
      if (string != null) 'string': string,
      if (finger != null) 'finger': finger,
      if (placement != null) 'placement': placement,
      if (grade != null) 'grade': grade,
      if (cents != null) 'cents': cents,
      if (tStart != null) 't_start': tStart,
      if (tEnd != null) 't_end': tEnd,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GradedNotesCompanion copyWith({
    Value<String>? sessionId,
    Value<int>? idx,
    Value<int>? midiNote,
    Value<String>? string,
    Value<int>? finger,
    Value<String?>? placement,
    Value<String>? grade,
    Value<double?>? cents,
    Value<double?>? tStart,
    Value<double?>? tEnd,
    Value<int>? rowid,
  }) {
    return GradedNotesCompanion(
      sessionId: sessionId ?? this.sessionId,
      idx: idx ?? this.idx,
      midiNote: midiNote ?? this.midiNote,
      string: string ?? this.string,
      finger: finger ?? this.finger,
      placement: placement ?? this.placement,
      grade: grade ?? this.grade,
      cents: cents ?? this.cents,
      tStart: tStart ?? this.tStart,
      tEnd: tEnd ?? this.tEnd,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (idx.present) {
      map['idx'] = Variable<int>(idx.value);
    }
    if (midiNote.present) {
      map['midi_note'] = Variable<int>(midiNote.value);
    }
    if (string.present) {
      map['string'] = Variable<String>(string.value);
    }
    if (finger.present) {
      map['finger'] = Variable<int>(finger.value);
    }
    if (placement.present) {
      map['placement'] = Variable<String>(placement.value);
    }
    if (grade.present) {
      map['grade'] = Variable<String>(grade.value);
    }
    if (cents.present) {
      map['cents'] = Variable<double>(cents.value);
    }
    if (tStart.present) {
      map['t_start'] = Variable<double>(tStart.value);
    }
    if (tEnd.present) {
      map['t_end'] = Variable<double>(tEnd.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GradedNotesCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('idx: $idx, ')
          ..write('midiNote: $midiNote, ')
          ..write('string: $string, ')
          ..write('finger: $finger, ')
          ..write('placement: $placement, ')
          ..write('grade: $grade, ')
          ..write('cents: $cents, ')
          ..write('tStart: $tStart, ')
          ..write('tEnd: $tEnd, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteStatsTable extends NoteStats
    with TableInfo<$NoteStatsTable, NoteStatRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteStatsTable(this.attachedDatabase, [this._alias]);
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
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _midiNoteMeta = const VerificationMeta(
    'midiNote',
  );
  @override
  late final GeneratedColumn<int> midiNote = GeneratedColumn<int>(
    'midi_note',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stringMeta = const VerificationMeta('string');
  @override
  late final GeneratedColumn<String> string = GeneratedColumn<String>(
    'string',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerMeta = const VerificationMeta('finger');
  @override
  late final GeneratedColumn<int> finger = GeneratedColumn<int>(
    'finger',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _placementMeta = const VerificationMeta(
    'placement',
  );
  @override
  late final GeneratedColumn<String> placement = GeneratedColumn<String>(
    'placement',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
    'count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _greenMeta = const VerificationMeta('green');
  @override
  late final GeneratedColumn<int> green = GeneratedColumn<int>(
    'green',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yellowMeta = const VerificationMeta('yellow');
  @override
  late final GeneratedColumn<int> yellow = GeneratedColumn<int>(
    'yellow',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _redMeta = const VerificationMeta('red');
  @override
  late final GeneratedColumn<int> red = GeneratedColumn<int>(
    'red',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _missedMeta = const VerificationMeta('missed');
  @override
  late final GeneratedColumn<int> missed = GeneratedColumn<int>(
    'missed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _meanCentsMeta = const VerificationMeta(
    'meanCents',
  );
  @override
  late final GeneratedColumn<double> meanCents = GeneratedColumn<double>(
    'mean_cents',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _meanAbsCentsMeta = const VerificationMeta(
    'meanAbsCents',
  );
  @override
  late final GeneratedColumn<double> meanAbsCents = GeneratedColumn<double>(
    'mean_abs_cents',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stdCentsMeta = const VerificationMeta(
    'stdCents',
  );
  @override
  late final GeneratedColumn<double> stdCents = GeneratedColumn<double>(
    'std_cents',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalMsMeta = const VerificationMeta(
    'totalMs',
  );
  @override
  late final GeneratedColumn<double> totalMs = GeneratedColumn<double>(
    'total_ms',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    midiNote,
    string,
    finger,
    placement,
    count,
    green,
    yellow,
    red,
    missed,
    meanCents,
    meanAbsCents,
    stdCents,
    totalMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_stats';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteStatRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('midi_note')) {
      context.handle(
        _midiNoteMeta,
        midiNote.isAcceptableOrUnknown(data['midi_note']!, _midiNoteMeta),
      );
    } else if (isInserting) {
      context.missing(_midiNoteMeta);
    }
    if (data.containsKey('string')) {
      context.handle(
        _stringMeta,
        string.isAcceptableOrUnknown(data['string']!, _stringMeta),
      );
    } else if (isInserting) {
      context.missing(_stringMeta);
    }
    if (data.containsKey('finger')) {
      context.handle(
        _fingerMeta,
        finger.isAcceptableOrUnknown(data['finger']!, _fingerMeta),
      );
    } else if (isInserting) {
      context.missing(_fingerMeta);
    }
    if (data.containsKey('placement')) {
      context.handle(
        _placementMeta,
        placement.isAcceptableOrUnknown(data['placement']!, _placementMeta),
      );
    } else if (isInserting) {
      context.missing(_placementMeta);
    }
    if (data.containsKey('count')) {
      context.handle(
        _countMeta,
        count.isAcceptableOrUnknown(data['count']!, _countMeta),
      );
    } else if (isInserting) {
      context.missing(_countMeta);
    }
    if (data.containsKey('green')) {
      context.handle(
        _greenMeta,
        green.isAcceptableOrUnknown(data['green']!, _greenMeta),
      );
    } else if (isInserting) {
      context.missing(_greenMeta);
    }
    if (data.containsKey('yellow')) {
      context.handle(
        _yellowMeta,
        yellow.isAcceptableOrUnknown(data['yellow']!, _yellowMeta),
      );
    } else if (isInserting) {
      context.missing(_yellowMeta);
    }
    if (data.containsKey('red')) {
      context.handle(
        _redMeta,
        red.isAcceptableOrUnknown(data['red']!, _redMeta),
      );
    } else if (isInserting) {
      context.missing(_redMeta);
    }
    if (data.containsKey('missed')) {
      context.handle(
        _missedMeta,
        missed.isAcceptableOrUnknown(data['missed']!, _missedMeta),
      );
    } else if (isInserting) {
      context.missing(_missedMeta);
    }
    if (data.containsKey('mean_cents')) {
      context.handle(
        _meanCentsMeta,
        meanCents.isAcceptableOrUnknown(data['mean_cents']!, _meanCentsMeta),
      );
    }
    if (data.containsKey('mean_abs_cents')) {
      context.handle(
        _meanAbsCentsMeta,
        meanAbsCents.isAcceptableOrUnknown(
          data['mean_abs_cents']!,
          _meanAbsCentsMeta,
        ),
      );
    }
    if (data.containsKey('std_cents')) {
      context.handle(
        _stdCentsMeta,
        stdCents.isAcceptableOrUnknown(data['std_cents']!, _stdCentsMeta),
      );
    }
    if (data.containsKey('total_ms')) {
      context.handle(
        _totalMsMeta,
        totalMs.isAcceptableOrUnknown(data['total_ms']!, _totalMsMeta),
      );
    } else if (isInserting) {
      context.missing(_totalMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    sessionId,
    midiNote,
    string,
    finger,
    placement,
  };
  @override
  NoteStatRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteStatRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      midiNote: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}midi_note'],
      )!,
      string: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}string'],
      )!,
      finger: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}finger'],
      )!,
      placement: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}placement'],
      )!,
      count: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count'],
      )!,
      green: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}green'],
      )!,
      yellow: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}yellow'],
      )!,
      red: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}red'],
      )!,
      missed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}missed'],
      )!,
      meanCents: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}mean_cents'],
      ),
      meanAbsCents: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}mean_abs_cents'],
      ),
      stdCents: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}std_cents'],
      ),
      totalMs: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_ms'],
      )!,
    );
  }

  @override
  $NoteStatsTable createAlias(String alias) {
    return $NoteStatsTable(attachedDatabase, alias);
  }
}

class NoteStatRow extends DataClass implements Insertable<NoteStatRow> {
  final String sessionId;
  final int midiNote;
  final String string;
  final int finger;
  final String placement;
  final int count;
  final int green;
  final int yellow;
  final int red;
  final int missed;
  final double? meanCents;
  final double? meanAbsCents;
  final double? stdCents;
  final double totalMs;
  const NoteStatRow({
    required this.sessionId,
    required this.midiNote,
    required this.string,
    required this.finger,
    required this.placement,
    required this.count,
    required this.green,
    required this.yellow,
    required this.red,
    required this.missed,
    this.meanCents,
    this.meanAbsCents,
    this.stdCents,
    required this.totalMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['midi_note'] = Variable<int>(midiNote);
    map['string'] = Variable<String>(string);
    map['finger'] = Variable<int>(finger);
    map['placement'] = Variable<String>(placement);
    map['count'] = Variable<int>(count);
    map['green'] = Variable<int>(green);
    map['yellow'] = Variable<int>(yellow);
    map['red'] = Variable<int>(red);
    map['missed'] = Variable<int>(missed);
    if (!nullToAbsent || meanCents != null) {
      map['mean_cents'] = Variable<double>(meanCents);
    }
    if (!nullToAbsent || meanAbsCents != null) {
      map['mean_abs_cents'] = Variable<double>(meanAbsCents);
    }
    if (!nullToAbsent || stdCents != null) {
      map['std_cents'] = Variable<double>(stdCents);
    }
    map['total_ms'] = Variable<double>(totalMs);
    return map;
  }

  NoteStatsCompanion toCompanion(bool nullToAbsent) {
    return NoteStatsCompanion(
      sessionId: Value(sessionId),
      midiNote: Value(midiNote),
      string: Value(string),
      finger: Value(finger),
      placement: Value(placement),
      count: Value(count),
      green: Value(green),
      yellow: Value(yellow),
      red: Value(red),
      missed: Value(missed),
      meanCents: meanCents == null && nullToAbsent
          ? const Value.absent()
          : Value(meanCents),
      meanAbsCents: meanAbsCents == null && nullToAbsent
          ? const Value.absent()
          : Value(meanAbsCents),
      stdCents: stdCents == null && nullToAbsent
          ? const Value.absent()
          : Value(stdCents),
      totalMs: Value(totalMs),
    );
  }

  factory NoteStatRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteStatRow(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      midiNote: serializer.fromJson<int>(json['midiNote']),
      string: serializer.fromJson<String>(json['string']),
      finger: serializer.fromJson<int>(json['finger']),
      placement: serializer.fromJson<String>(json['placement']),
      count: serializer.fromJson<int>(json['count']),
      green: serializer.fromJson<int>(json['green']),
      yellow: serializer.fromJson<int>(json['yellow']),
      red: serializer.fromJson<int>(json['red']),
      missed: serializer.fromJson<int>(json['missed']),
      meanCents: serializer.fromJson<double?>(json['meanCents']),
      meanAbsCents: serializer.fromJson<double?>(json['meanAbsCents']),
      stdCents: serializer.fromJson<double?>(json['stdCents']),
      totalMs: serializer.fromJson<double>(json['totalMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'midiNote': serializer.toJson<int>(midiNote),
      'string': serializer.toJson<String>(string),
      'finger': serializer.toJson<int>(finger),
      'placement': serializer.toJson<String>(placement),
      'count': serializer.toJson<int>(count),
      'green': serializer.toJson<int>(green),
      'yellow': serializer.toJson<int>(yellow),
      'red': serializer.toJson<int>(red),
      'missed': serializer.toJson<int>(missed),
      'meanCents': serializer.toJson<double?>(meanCents),
      'meanAbsCents': serializer.toJson<double?>(meanAbsCents),
      'stdCents': serializer.toJson<double?>(stdCents),
      'totalMs': serializer.toJson<double>(totalMs),
    };
  }

  NoteStatRow copyWith({
    String? sessionId,
    int? midiNote,
    String? string,
    int? finger,
    String? placement,
    int? count,
    int? green,
    int? yellow,
    int? red,
    int? missed,
    Value<double?> meanCents = const Value.absent(),
    Value<double?> meanAbsCents = const Value.absent(),
    Value<double?> stdCents = const Value.absent(),
    double? totalMs,
  }) => NoteStatRow(
    sessionId: sessionId ?? this.sessionId,
    midiNote: midiNote ?? this.midiNote,
    string: string ?? this.string,
    finger: finger ?? this.finger,
    placement: placement ?? this.placement,
    count: count ?? this.count,
    green: green ?? this.green,
    yellow: yellow ?? this.yellow,
    red: red ?? this.red,
    missed: missed ?? this.missed,
    meanCents: meanCents.present ? meanCents.value : this.meanCents,
    meanAbsCents: meanAbsCents.present ? meanAbsCents.value : this.meanAbsCents,
    stdCents: stdCents.present ? stdCents.value : this.stdCents,
    totalMs: totalMs ?? this.totalMs,
  );
  NoteStatRow copyWithCompanion(NoteStatsCompanion data) {
    return NoteStatRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      midiNote: data.midiNote.present ? data.midiNote.value : this.midiNote,
      string: data.string.present ? data.string.value : this.string,
      finger: data.finger.present ? data.finger.value : this.finger,
      placement: data.placement.present ? data.placement.value : this.placement,
      count: data.count.present ? data.count.value : this.count,
      green: data.green.present ? data.green.value : this.green,
      yellow: data.yellow.present ? data.yellow.value : this.yellow,
      red: data.red.present ? data.red.value : this.red,
      missed: data.missed.present ? data.missed.value : this.missed,
      meanCents: data.meanCents.present ? data.meanCents.value : this.meanCents,
      meanAbsCents: data.meanAbsCents.present
          ? data.meanAbsCents.value
          : this.meanAbsCents,
      stdCents: data.stdCents.present ? data.stdCents.value : this.stdCents,
      totalMs: data.totalMs.present ? data.totalMs.value : this.totalMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteStatRow(')
          ..write('sessionId: $sessionId, ')
          ..write('midiNote: $midiNote, ')
          ..write('string: $string, ')
          ..write('finger: $finger, ')
          ..write('placement: $placement, ')
          ..write('count: $count, ')
          ..write('green: $green, ')
          ..write('yellow: $yellow, ')
          ..write('red: $red, ')
          ..write('missed: $missed, ')
          ..write('meanCents: $meanCents, ')
          ..write('meanAbsCents: $meanAbsCents, ')
          ..write('stdCents: $stdCents, ')
          ..write('totalMs: $totalMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    midiNote,
    string,
    finger,
    placement,
    count,
    green,
    yellow,
    red,
    missed,
    meanCents,
    meanAbsCents,
    stdCents,
    totalMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteStatRow &&
          other.sessionId == this.sessionId &&
          other.midiNote == this.midiNote &&
          other.string == this.string &&
          other.finger == this.finger &&
          other.placement == this.placement &&
          other.count == this.count &&
          other.green == this.green &&
          other.yellow == this.yellow &&
          other.red == this.red &&
          other.missed == this.missed &&
          other.meanCents == this.meanCents &&
          other.meanAbsCents == this.meanAbsCents &&
          other.stdCents == this.stdCents &&
          other.totalMs == this.totalMs);
}

class NoteStatsCompanion extends UpdateCompanion<NoteStatRow> {
  final Value<String> sessionId;
  final Value<int> midiNote;
  final Value<String> string;
  final Value<int> finger;
  final Value<String> placement;
  final Value<int> count;
  final Value<int> green;
  final Value<int> yellow;
  final Value<int> red;
  final Value<int> missed;
  final Value<double?> meanCents;
  final Value<double?> meanAbsCents;
  final Value<double?> stdCents;
  final Value<double> totalMs;
  final Value<int> rowid;
  const NoteStatsCompanion({
    this.sessionId = const Value.absent(),
    this.midiNote = const Value.absent(),
    this.string = const Value.absent(),
    this.finger = const Value.absent(),
    this.placement = const Value.absent(),
    this.count = const Value.absent(),
    this.green = const Value.absent(),
    this.yellow = const Value.absent(),
    this.red = const Value.absent(),
    this.missed = const Value.absent(),
    this.meanCents = const Value.absent(),
    this.meanAbsCents = const Value.absent(),
    this.stdCents = const Value.absent(),
    this.totalMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteStatsCompanion.insert({
    required String sessionId,
    required int midiNote,
    required String string,
    required int finger,
    required String placement,
    required int count,
    required int green,
    required int yellow,
    required int red,
    required int missed,
    this.meanCents = const Value.absent(),
    this.meanAbsCents = const Value.absent(),
    this.stdCents = const Value.absent(),
    required double totalMs,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       midiNote = Value(midiNote),
       string = Value(string),
       finger = Value(finger),
       placement = Value(placement),
       count = Value(count),
       green = Value(green),
       yellow = Value(yellow),
       red = Value(red),
       missed = Value(missed),
       totalMs = Value(totalMs);
  static Insertable<NoteStatRow> custom({
    Expression<String>? sessionId,
    Expression<int>? midiNote,
    Expression<String>? string,
    Expression<int>? finger,
    Expression<String>? placement,
    Expression<int>? count,
    Expression<int>? green,
    Expression<int>? yellow,
    Expression<int>? red,
    Expression<int>? missed,
    Expression<double>? meanCents,
    Expression<double>? meanAbsCents,
    Expression<double>? stdCents,
    Expression<double>? totalMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (midiNote != null) 'midi_note': midiNote,
      if (string != null) 'string': string,
      if (finger != null) 'finger': finger,
      if (placement != null) 'placement': placement,
      if (count != null) 'count': count,
      if (green != null) 'green': green,
      if (yellow != null) 'yellow': yellow,
      if (red != null) 'red': red,
      if (missed != null) 'missed': missed,
      if (meanCents != null) 'mean_cents': meanCents,
      if (meanAbsCents != null) 'mean_abs_cents': meanAbsCents,
      if (stdCents != null) 'std_cents': stdCents,
      if (totalMs != null) 'total_ms': totalMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteStatsCompanion copyWith({
    Value<String>? sessionId,
    Value<int>? midiNote,
    Value<String>? string,
    Value<int>? finger,
    Value<String>? placement,
    Value<int>? count,
    Value<int>? green,
    Value<int>? yellow,
    Value<int>? red,
    Value<int>? missed,
    Value<double?>? meanCents,
    Value<double?>? meanAbsCents,
    Value<double?>? stdCents,
    Value<double>? totalMs,
    Value<int>? rowid,
  }) {
    return NoteStatsCompanion(
      sessionId: sessionId ?? this.sessionId,
      midiNote: midiNote ?? this.midiNote,
      string: string ?? this.string,
      finger: finger ?? this.finger,
      placement: placement ?? this.placement,
      count: count ?? this.count,
      green: green ?? this.green,
      yellow: yellow ?? this.yellow,
      red: red ?? this.red,
      missed: missed ?? this.missed,
      meanCents: meanCents ?? this.meanCents,
      meanAbsCents: meanAbsCents ?? this.meanAbsCents,
      stdCents: stdCents ?? this.stdCents,
      totalMs: totalMs ?? this.totalMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (midiNote.present) {
      map['midi_note'] = Variable<int>(midiNote.value);
    }
    if (string.present) {
      map['string'] = Variable<String>(string.value);
    }
    if (finger.present) {
      map['finger'] = Variable<int>(finger.value);
    }
    if (placement.present) {
      map['placement'] = Variable<String>(placement.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (green.present) {
      map['green'] = Variable<int>(green.value);
    }
    if (yellow.present) {
      map['yellow'] = Variable<int>(yellow.value);
    }
    if (red.present) {
      map['red'] = Variable<int>(red.value);
    }
    if (missed.present) {
      map['missed'] = Variable<int>(missed.value);
    }
    if (meanCents.present) {
      map['mean_cents'] = Variable<double>(meanCents.value);
    }
    if (meanAbsCents.present) {
      map['mean_abs_cents'] = Variable<double>(meanAbsCents.value);
    }
    if (stdCents.present) {
      map['std_cents'] = Variable<double>(stdCents.value);
    }
    if (totalMs.present) {
      map['total_ms'] = Variable<double>(totalMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteStatsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('midiNote: $midiNote, ')
          ..write('string: $string, ')
          ..write('finger: $finger, ')
          ..write('placement: $placement, ')
          ..write('count: $count, ')
          ..write('green: $green, ')
          ..write('yellow: $yellow, ')
          ..write('red: $red, ')
          ..write('missed: $missed, ')
          ..write('meanCents: $meanCents, ')
          ..write('meanAbsCents: $meanAbsCents, ')
          ..write('stdCents: $stdCents, ')
          ..write('totalMs: $totalMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  final int updatedAt;
  const Setting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  Setting copyWith({String? key, String? value, int? updatedAt}) => Setting(
    key: key ?? this.key,
    value: value ?? this.value,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$PracticeDb extends GeneratedDatabase {
  _$PracticeDb(QueryExecutor e) : super(e);
  $PracticeDbManager get managers => $PracticeDbManager(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $GradedNotesTable gradedNotes = $GradedNotesTable(this);
  late final $NoteStatsTable noteStats = $NoteStatsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sessions,
    gradedNotes,
    noteStats,
    settings,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('graded_notes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('note_stats', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$SessionsTableCreateCompanionBuilder = SessionsCompanion Function({
  required String id,
  required int startedAt,
  required int endedAt,
  required String mode,
  Value<String> instrument,
  required double a4Hz,
  required String tuning,
  required String scaleId,
  required double scorePercent,
  required int green,
  required int yellow,
  required int red,
  required int missed,
  required int noteCount,
  Value<int> rowid,
});
typedef $$SessionsTableUpdateCompanionBuilder = SessionsCompanion Function({
  Value<String> id,
  Value<int> startedAt,
  Value<int> endedAt,
  Value<String> mode,
  Value<String> instrument,
  Value<double> a4Hz,
  Value<String> tuning,
  Value<String> scaleId,
  Value<double> scorePercent,
  Value<int> green,
  Value<int> yellow,
  Value<int> red,
  Value<int> missed,
  Value<int> noteCount,
  Value<int> rowid,
});

final class $$SessionsTableReferences
    extends BaseReferences<_$PracticeDb, $SessionsTable, Session> {
  $$SessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$GradedNotesTable, List<GradedNoteRow>>
  _gradedNotesRefsTable(_$PracticeDb db) => MultiTypedResultKey.fromTable(
    db.gradedNotes,
    aliasName: 'sessions__id__graded_notes__session_id',
  );

  $$GradedNotesTableProcessedTableManager get gradedNotesRefs {
    final manager = $$GradedNotesTableTableManager(
      $_db,
      $_db.gradedNotes,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_gradedNotesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$NoteStatsTable, List<NoteStatRow>>
  _noteStatsRefsTable(_$PracticeDb db) => MultiTypedResultKey.fromTable(
    db.noteStats,
    aliasName: 'sessions__id__note_stats__session_id',
  );

  $$NoteStatsTableProcessedTableManager get noteStatsRefs {
    final manager = $$NoteStatsTableTableManager(
      $_db,
      $_db.noteStats,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_noteStatsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SessionsTableFilterComposer
    extends Composer<_$PracticeDb, $SessionsTable> {
  $$SessionsTableFilterComposer({
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

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get instrument => $composableBuilder(
    column: $table.instrument,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get a4Hz => $composableBuilder(
    column: $table.a4Hz,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tuning => $composableBuilder(
    column: $table.tuning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scaleId => $composableBuilder(
    column: $table.scaleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get scorePercent => $composableBuilder(
    column: $table.scorePercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get green => $composableBuilder(
    column: $table.green,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get yellow => $composableBuilder(
    column: $table.yellow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get red => $composableBuilder(
    column: $table.red,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get missed => $composableBuilder(
    column: $table.missed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get noteCount => $composableBuilder(
    column: $table.noteCount,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> gradedNotesRefs(
    Expression<bool> Function($$GradedNotesTableFilterComposer f) f,
  ) {
    final $$GradedNotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gradedNotes,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GradedNotesTableFilterComposer(
            $db: $db,
            $table: $db.gradedNotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> noteStatsRefs(
    Expression<bool> Function($$NoteStatsTableFilterComposer f) f,
  ) {
    final $$NoteStatsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteStats,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteStatsTableFilterComposer(
            $db: $db,
            $table: $db.noteStats,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableOrderingComposer
    extends Composer<_$PracticeDb, $SessionsTable> {
  $$SessionsTableOrderingComposer({
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

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get instrument => $composableBuilder(
    column: $table.instrument,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get a4Hz => $composableBuilder(
    column: $table.a4Hz,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tuning => $composableBuilder(
    column: $table.tuning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scaleId => $composableBuilder(
    column: $table.scaleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get scorePercent => $composableBuilder(
    column: $table.scorePercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get green => $composableBuilder(
    column: $table.green,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get yellow => $composableBuilder(
    column: $table.yellow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get red => $composableBuilder(
    column: $table.red,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get missed => $composableBuilder(
    column: $table.missed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get noteCount => $composableBuilder(
    column: $table.noteCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$PracticeDb, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get instrument => $composableBuilder(
    column: $table.instrument,
    builder: (column) => column,
  );

  GeneratedColumn<double> get a4Hz =>
      $composableBuilder(column: $table.a4Hz, builder: (column) => column);

  GeneratedColumn<String> get tuning =>
      $composableBuilder(column: $table.tuning, builder: (column) => column);

  GeneratedColumn<String> get scaleId =>
      $composableBuilder(column: $table.scaleId, builder: (column) => column);

  GeneratedColumn<double> get scorePercent => $composableBuilder(
    column: $table.scorePercent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get green =>
      $composableBuilder(column: $table.green, builder: (column) => column);

  GeneratedColumn<int> get yellow =>
      $composableBuilder(column: $table.yellow, builder: (column) => column);

  GeneratedColumn<int> get red =>
      $composableBuilder(column: $table.red, builder: (column) => column);

  GeneratedColumn<int> get missed =>
      $composableBuilder(column: $table.missed, builder: (column) => column);

  GeneratedColumn<int> get noteCount =>
      $composableBuilder(column: $table.noteCount, builder: (column) => column);

  Expression<T> gradedNotesRefs<T extends Object>(
    Expression<T> Function($$GradedNotesTableAnnotationComposer a) f,
  ) {
    final $$GradedNotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gradedNotes,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GradedNotesTableAnnotationComposer(
            $db: $db,
            $table: $db.gradedNotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> noteStatsRefs<T extends Object>(
    Expression<T> Function($$NoteStatsTableAnnotationComposer a) f,
  ) {
    final $$NoteStatsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteStats,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteStatsTableAnnotationComposer(
            $db: $db,
            $table: $db.noteStats,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$PracticeDb,
          $SessionsTable,
          Session,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (Session, $$SessionsTableReferences),
          Session,
          PrefetchHooks Function({bool gradedNotesRefs, bool noteStatsRefs})
        > {
  $$SessionsTableTableManager(_$PracticeDb db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> startedAt = const Value.absent(),
                Value<int> endedAt = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String> instrument = const Value.absent(),
                Value<double> a4Hz = const Value.absent(),
                Value<String> tuning = const Value.absent(),
                Value<String> scaleId = const Value.absent(),
                Value<double> scorePercent = const Value.absent(),
                Value<int> green = const Value.absent(),
                Value<int> yellow = const Value.absent(),
                Value<int> red = const Value.absent(),
                Value<int> missed = const Value.absent(),
                Value<int> noteCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                id: id,
                startedAt: startedAt,
                endedAt: endedAt,
                mode: mode,
                instrument: instrument,
                a4Hz: a4Hz,
                tuning: tuning,
                scaleId: scaleId,
                scorePercent: scorePercent,
                green: green,
                yellow: yellow,
                red: red,
                missed: missed,
                noteCount: noteCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int startedAt,
                required int endedAt,
                required String mode,
                Value<String> instrument = const Value.absent(),
                required double a4Hz,
                required String tuning,
                required String scaleId,
                required double scorePercent,
                required int green,
                required int yellow,
                required int red,
                required int missed,
                required int noteCount,
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                id: id,
                startedAt: startedAt,
                endedAt: endedAt,
                mode: mode,
                instrument: instrument,
                a4Hz: a4Hz,
                tuning: tuning,
                scaleId: scaleId,
                scorePercent: scorePercent,
                green: green,
                yellow: yellow,
                red: red,
                missed: missed,
                noteCount: noteCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SessionsTable, Session>(table),
                  $$SessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({gradedNotesRefs = false, noteStatsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (gradedNotesRefs) db.gradedNotes,
                    if (noteStatsRefs) db.noteStats,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (gradedNotesRefs)
                        await $_getPrefetchedDataByColumns<
                          Session,
                          $SessionsTable,
                          GradedNoteRow,
                          $GradedNotesTable
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._gradedNotesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).gradedNotesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'session_id',
                          typedResults: items,
                        ),
                      if (noteStatsRefs)
                        await $_getPrefetchedDataByColumns<
                          Session,
                          $SessionsTable,
                          NoteStatRow,
                          $NoteStatsTable
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._noteStatsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).noteStatsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'session_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$PracticeDb,
      $SessionsTable,
      Session,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (Session, $$SessionsTableReferences),
      Session,
      PrefetchHooks Function({bool gradedNotesRefs, bool noteStatsRefs})
    >;
typedef $$GradedNotesTableCreateCompanionBuilder =
    GradedNotesCompanion Function({
      required String sessionId,
      required int idx,
      required int midiNote,
      required String string,
      required int finger,
      Value<String?> placement,
      required String grade,
      Value<double?> cents,
      Value<double?> tStart,
      Value<double?> tEnd,
      Value<int> rowid,
    });
typedef $$GradedNotesTableUpdateCompanionBuilder =
    GradedNotesCompanion Function({
      Value<String> sessionId,
      Value<int> idx,
      Value<int> midiNote,
      Value<String> string,
      Value<int> finger,
      Value<String?> placement,
      Value<String> grade,
      Value<double?> cents,
      Value<double?> tStart,
      Value<double?> tEnd,
      Value<int> rowid,
    });

final class $$GradedNotesTableReferences
    extends BaseReferences<_$PracticeDb, $GradedNotesTable, GradedNoteRow> {
  $$GradedNotesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SessionsTable _sessionIdTable(_$PracticeDb db) =>
      db.sessions.createAlias('graded_notes__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GradedNotesTableFilterComposer
    extends Composer<_$PracticeDb, $GradedNotesTable> {
  $$GradedNotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get idx => $composableBuilder(
    column: $table.idx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get midiNote => $composableBuilder(
    column: $table.midiNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get string => $composableBuilder(
    column: $table.string,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get finger => $composableBuilder(
    column: $table.finger,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get placement => $composableBuilder(
    column: $table.placement,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get grade => $composableBuilder(
    column: $table.grade,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cents => $composableBuilder(
    column: $table.cents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get tStart => $composableBuilder(
    column: $table.tStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get tEnd => $composableBuilder(
    column: $table.tEnd,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GradedNotesTableOrderingComposer
    extends Composer<_$PracticeDb, $GradedNotesTable> {
  $$GradedNotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get idx => $composableBuilder(
    column: $table.idx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get midiNote => $composableBuilder(
    column: $table.midiNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get string => $composableBuilder(
    column: $table.string,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get finger => $composableBuilder(
    column: $table.finger,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get placement => $composableBuilder(
    column: $table.placement,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get grade => $composableBuilder(
    column: $table.grade,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cents => $composableBuilder(
    column: $table.cents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get tStart => $composableBuilder(
    column: $table.tStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get tEnd => $composableBuilder(
    column: $table.tEnd,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GradedNotesTableAnnotationComposer
    extends Composer<_$PracticeDb, $GradedNotesTable> {
  $$GradedNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get idx =>
      $composableBuilder(column: $table.idx, builder: (column) => column);

  GeneratedColumn<int> get midiNote =>
      $composableBuilder(column: $table.midiNote, builder: (column) => column);

  GeneratedColumn<String> get string =>
      $composableBuilder(column: $table.string, builder: (column) => column);

  GeneratedColumn<int> get finger =>
      $composableBuilder(column: $table.finger, builder: (column) => column);

  GeneratedColumn<String> get placement =>
      $composableBuilder(column: $table.placement, builder: (column) => column);

  GeneratedColumn<String> get grade =>
      $composableBuilder(column: $table.grade, builder: (column) => column);

  GeneratedColumn<double> get cents =>
      $composableBuilder(column: $table.cents, builder: (column) => column);

  GeneratedColumn<double> get tStart =>
      $composableBuilder(column: $table.tStart, builder: (column) => column);

  GeneratedColumn<double> get tEnd =>
      $composableBuilder(column: $table.tEnd, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GradedNotesTableTableManager
    extends
        RootTableManager<
          _$PracticeDb,
          $GradedNotesTable,
          GradedNoteRow,
          $$GradedNotesTableFilterComposer,
          $$GradedNotesTableOrderingComposer,
          $$GradedNotesTableAnnotationComposer,
          $$GradedNotesTableCreateCompanionBuilder,
          $$GradedNotesTableUpdateCompanionBuilder,
          (GradedNoteRow, $$GradedNotesTableReferences),
          GradedNoteRow,
          PrefetchHooks Function({bool sessionId})
        > {
  $$GradedNotesTableTableManager(_$PracticeDb db, $GradedNotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GradedNotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GradedNotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GradedNotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<int> idx = const Value.absent(),
                Value<int> midiNote = const Value.absent(),
                Value<String> string = const Value.absent(),
                Value<int> finger = const Value.absent(),
                Value<String?> placement = const Value.absent(),
                Value<String> grade = const Value.absent(),
                Value<double?> cents = const Value.absent(),
                Value<double?> tStart = const Value.absent(),
                Value<double?> tEnd = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GradedNotesCompanion(
                sessionId: sessionId,
                idx: idx,
                midiNote: midiNote,
                string: string,
                finger: finger,
                placement: placement,
                grade: grade,
                cents: cents,
                tStart: tStart,
                tEnd: tEnd,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required int idx,
                required int midiNote,
                required String string,
                required int finger,
                Value<String?> placement = const Value.absent(),
                required String grade,
                Value<double?> cents = const Value.absent(),
                Value<double?> tStart = const Value.absent(),
                Value<double?> tEnd = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GradedNotesCompanion.insert(
                sessionId: sessionId,
                idx: idx,
                midiNote: midiNote,
                string: string,
                finger: finger,
                placement: placement,
                grade: grade,
                cents: cents,
                tStart: tStart,
                tEnd: tEnd,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GradedNotesTable, GradedNoteRow>(table),
                  $$GradedNotesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
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
                    if (sessionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.sessionId,
                        referencedTable: $$GradedNotesTableReferences
                            ._sessionIdTable(db),
                        referencedColumn: $$GradedNotesTableReferences
                            ._sessionIdTable(db)
                            .id,
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

typedef $$GradedNotesTableProcessedTableManager =
    ProcessedTableManager<
      _$PracticeDb,
      $GradedNotesTable,
      GradedNoteRow,
      $$GradedNotesTableFilterComposer,
      $$GradedNotesTableOrderingComposer,
      $$GradedNotesTableAnnotationComposer,
      $$GradedNotesTableCreateCompanionBuilder,
      $$GradedNotesTableUpdateCompanionBuilder,
      (GradedNoteRow, $$GradedNotesTableReferences),
      GradedNoteRow,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$NoteStatsTableCreateCompanionBuilder = NoteStatsCompanion Function({
  required String sessionId,
  required int midiNote,
  required String string,
  required int finger,
  required String placement,
  required int count,
  required int green,
  required int yellow,
  required int red,
  required int missed,
  Value<double?> meanCents,
  Value<double?> meanAbsCents,
  Value<double?> stdCents,
  required double totalMs,
  Value<int> rowid,
});
typedef $$NoteStatsTableUpdateCompanionBuilder = NoteStatsCompanion Function({
  Value<String> sessionId,
  Value<int> midiNote,
  Value<String> string,
  Value<int> finger,
  Value<String> placement,
  Value<int> count,
  Value<int> green,
  Value<int> yellow,
  Value<int> red,
  Value<int> missed,
  Value<double?> meanCents,
  Value<double?> meanAbsCents,
  Value<double?> stdCents,
  Value<double> totalMs,
  Value<int> rowid,
});

final class $$NoteStatsTableReferences
    extends BaseReferences<_$PracticeDb, $NoteStatsTable, NoteStatRow> {
  $$NoteStatsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SessionsTable _sessionIdTable(_$PracticeDb db) =>
      db.sessions.createAlias('note_stats__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$NoteStatsTableFilterComposer
    extends Composer<_$PracticeDb, $NoteStatsTable> {
  $$NoteStatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get midiNote => $composableBuilder(
    column: $table.midiNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get string => $composableBuilder(
    column: $table.string,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get finger => $composableBuilder(
    column: $table.finger,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get placement => $composableBuilder(
    column: $table.placement,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get green => $composableBuilder(
    column: $table.green,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get yellow => $composableBuilder(
    column: $table.yellow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get red => $composableBuilder(
    column: $table.red,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get missed => $composableBuilder(
    column: $table.missed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get meanCents => $composableBuilder(
    column: $table.meanCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get meanAbsCents => $composableBuilder(
    column: $table.meanAbsCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get stdCents => $composableBuilder(
    column: $table.stdCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalMs => $composableBuilder(
    column: $table.totalMs,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteStatsTableOrderingComposer
    extends Composer<_$PracticeDb, $NoteStatsTable> {
  $$NoteStatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get midiNote => $composableBuilder(
    column: $table.midiNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get string => $composableBuilder(
    column: $table.string,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get finger => $composableBuilder(
    column: $table.finger,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get placement => $composableBuilder(
    column: $table.placement,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get green => $composableBuilder(
    column: $table.green,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get yellow => $composableBuilder(
    column: $table.yellow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get red => $composableBuilder(
    column: $table.red,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get missed => $composableBuilder(
    column: $table.missed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get meanCents => $composableBuilder(
    column: $table.meanCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get meanAbsCents => $composableBuilder(
    column: $table.meanAbsCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get stdCents => $composableBuilder(
    column: $table.stdCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalMs => $composableBuilder(
    column: $table.totalMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteStatsTableAnnotationComposer
    extends Composer<_$PracticeDb, $NoteStatsTable> {
  $$NoteStatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get midiNote =>
      $composableBuilder(column: $table.midiNote, builder: (column) => column);

  GeneratedColumn<String> get string =>
      $composableBuilder(column: $table.string, builder: (column) => column);

  GeneratedColumn<int> get finger =>
      $composableBuilder(column: $table.finger, builder: (column) => column);

  GeneratedColumn<String> get placement =>
      $composableBuilder(column: $table.placement, builder: (column) => column);

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);

  GeneratedColumn<int> get green =>
      $composableBuilder(column: $table.green, builder: (column) => column);

  GeneratedColumn<int> get yellow =>
      $composableBuilder(column: $table.yellow, builder: (column) => column);

  GeneratedColumn<int> get red =>
      $composableBuilder(column: $table.red, builder: (column) => column);

  GeneratedColumn<int> get missed =>
      $composableBuilder(column: $table.missed, builder: (column) => column);

  GeneratedColumn<double> get meanCents =>
      $composableBuilder(column: $table.meanCents, builder: (column) => column);

  GeneratedColumn<double> get meanAbsCents => $composableBuilder(
    column: $table.meanAbsCents,
    builder: (column) => column,
  );

  GeneratedColumn<double> get stdCents =>
      $composableBuilder(column: $table.stdCents, builder: (column) => column);

  GeneratedColumn<double> get totalMs =>
      $composableBuilder(column: $table.totalMs, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteStatsTableTableManager
    extends
        RootTableManager<
          _$PracticeDb,
          $NoteStatsTable,
          NoteStatRow,
          $$NoteStatsTableFilterComposer,
          $$NoteStatsTableOrderingComposer,
          $$NoteStatsTableAnnotationComposer,
          $$NoteStatsTableCreateCompanionBuilder,
          $$NoteStatsTableUpdateCompanionBuilder,
          (NoteStatRow, $$NoteStatsTableReferences),
          NoteStatRow,
          PrefetchHooks Function({bool sessionId})
        > {
  $$NoteStatsTableTableManager(_$PracticeDb db, $NoteStatsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteStatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteStatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteStatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<int> midiNote = const Value.absent(),
                Value<String> string = const Value.absent(),
                Value<int> finger = const Value.absent(),
                Value<String> placement = const Value.absent(),
                Value<int> count = const Value.absent(),
                Value<int> green = const Value.absent(),
                Value<int> yellow = const Value.absent(),
                Value<int> red = const Value.absent(),
                Value<int> missed = const Value.absent(),
                Value<double?> meanCents = const Value.absent(),
                Value<double?> meanAbsCents = const Value.absent(),
                Value<double?> stdCents = const Value.absent(),
                Value<double> totalMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteStatsCompanion(
                sessionId: sessionId,
                midiNote: midiNote,
                string: string,
                finger: finger,
                placement: placement,
                count: count,
                green: green,
                yellow: yellow,
                red: red,
                missed: missed,
                meanCents: meanCents,
                meanAbsCents: meanAbsCents,
                stdCents: stdCents,
                totalMs: totalMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required int midiNote,
                required String string,
                required int finger,
                required String placement,
                required int count,
                required int green,
                required int yellow,
                required int red,
                required int missed,
                Value<double?> meanCents = const Value.absent(),
                Value<double?> meanAbsCents = const Value.absent(),
                Value<double?> stdCents = const Value.absent(),
                required double totalMs,
                Value<int> rowid = const Value.absent(),
              }) => NoteStatsCompanion.insert(
                sessionId: sessionId,
                midiNote: midiNote,
                string: string,
                finger: finger,
                placement: placement,
                count: count,
                green: green,
                yellow: yellow,
                red: red,
                missed: missed,
                meanCents: meanCents,
                meanAbsCents: meanAbsCents,
                stdCents: stdCents,
                totalMs: totalMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NoteStatsTable, NoteStatRow>(table),
                  $$NoteStatsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
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
                    if (sessionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.sessionId,
                        referencedTable: $$NoteStatsTableReferences
                            ._sessionIdTable(db),
                        referencedColumn: $$NoteStatsTableReferences
                            ._sessionIdTable(db)
                            .id,
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

typedef $$NoteStatsTableProcessedTableManager =
    ProcessedTableManager<
      _$PracticeDb,
      $NoteStatsTable,
      NoteStatRow,
      $$NoteStatsTableFilterComposer,
      $$NoteStatsTableOrderingComposer,
      $$NoteStatsTableAnnotationComposer,
      $$NoteStatsTableCreateCompanionBuilder,
      $$NoteStatsTableUpdateCompanionBuilder,
      (NoteStatRow, $$NoteStatsTableReferences),
      NoteStatRow,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$PracticeDb, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$PracticeDb, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$PracticeDb, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$PracticeDb,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$PracticeDb, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$PracticeDb db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, Setting>(table),
                  BaseReferences<_$PracticeDb, $SettingsTable, Setting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$PracticeDb,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$PracticeDb, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;

class $PracticeDbManager {
  final _$PracticeDb _db;
  $PracticeDbManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$GradedNotesTableTableManager get gradedNotes =>
      $$GradedNotesTableTableManager(_db, _db.gradedNotes);
  $$NoteStatsTableTableManager get noteStats =>
      $$NoteStatsTableTableManager(_db, _db.noteStats);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
