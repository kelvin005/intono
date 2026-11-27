import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../scales/grader.dart';
import '../scales/grading_config.dart';
import '../scales/scale.dart';
import 'practice_db.dart';
import 'practice_stats.dart';

/// A stored session, as the history and results screens read it.
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.instrument,
    required this.scaleId,
    required this.scorePercent,
    required this.totals,
  });

  final String id;
  final DateTime startedAt, endedAt;
  final String instrument;
  final String scaleId;
  final double scorePercent;
  final Totals totals;
}

/// The practice history on the phone (ADR 0015). Every graded note of a run is stored; the session totals and `note_stats` are caches
/// of them, rebuilt by [rebuildCaches]. Plain SQL against the tables of [PracticeDb], so nothing here depends on generated names. No
/// audio, extra notes or frames are ever written.
class PracticeStore {
  PracticeStore(this.db, {DateTime Function()? clock, math.Random? random})
      : _clock = clock ?? DateTime.now,
        _random = random ?? math.Random.secure();

  final PracticeDb db;
  final DateTime Function() _clock;
  final math.Random _random;

  /// Stores a finished run in one transaction and returns its session id. A run with no played note is not stored (nothing was
  /// practised); then the result is null.
  Future<String?> saveRun(
    ScaleResult r, {
    required DateTime startedAt,
    required DateTime endedAt,
    double a4Hz = 440,
    String tuning = 'equal',
    String instrument = 'violin',
  }) async {
    if (r.notes.every((g) => g.played == null)) return null;
    final id = uuidV7(_clock(), _random);
    final notes = storedNotesOf(r);
    await db.transaction(() async {
      final t = totalsOf(notes);
      await db.customInsert(
        'INSERT INTO sessions (id, started_at, ended_at, mode, instrument, a4_hz, tuning, scale_id, score_percent, green, yellow, '
        'red, missed, note_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable.withString(id),
          Variable.withInt(startedAt.toUtc().millisecondsSinceEpoch),
          Variable.withInt(endedAt.toUtc().millisecondsSinceEpoch),
          Variable.withString('scale'),
          Variable.withString(instrument),
          Variable.withReal(a4Hz),
          Variable.withString(tuning),
          Variable.withString(r.scale.id),
          Variable.withReal(t.scorePercent),
          Variable.withInt(t.green),
          Variable.withInt(t.yellow),
          Variable.withInt(t.red),
          Variable.withInt(t.missed),
          Variable.withInt(t.noteCount),
        ],
      );
      for (final n in notes) {
        await _insertNote(id, n);
      }
      await _writeStats(id, notes);
    });
    return id;
  }

  Future<void> _insertNote(String sessionId, StoredNote n) => db.customInsert(
        'INSERT INTO graded_notes (session_id, idx, midi_note, string, finger, placement, grade, cents, t_start, t_end) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable.withString(sessionId),
          Variable.withInt(n.idx),
          Variable.withInt(n.midiNote),
          Variable.withString(n.string),
          Variable.withInt(n.finger),
          Variable<String>(n.placement),
          Variable.withString(n.grade.name),
          Variable<double>(n.cents),
          Variable<double>(n.tStart),
          Variable<double>(n.tEnd),
        ],
      );

  Future<void> _writeStats(String sessionId, List<StoredNote> notes) async {
    await db.customStatement('DELETE FROM note_stats WHERE session_id = ?', [sessionId]);
    for (final s in noteStatsOf(notes)) {
      await db.customInsert(
        'INSERT INTO note_stats (session_id, midi_note, string, finger, placement, count, green, yellow, red, missed, mean_cents, '
        'mean_abs_cents, std_cents, total_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable.withString(sessionId),
          Variable.withInt(s.midiNote),
          Variable.withString(s.string),
          Variable.withInt(s.finger),
          Variable.withString(s.placement),
          Variable.withInt(s.count),
          Variable.withInt(s.green),
          Variable.withInt(s.yellow),
          Variable.withInt(s.red),
          Variable.withInt(s.missed),
          Variable<double>(s.meanCents),
          Variable<double>(s.meanAbsCents),
          Variable<double>(s.stdCents),
          Variable.withReal(s.totalMs),
        ],
      );
    }
  }

  /// The graded notes of one session, in scale order.
  Future<List<StoredNote>> gradedNotes(String sessionId) async {
    final rows = await db.customSelect(
      'SELECT idx, midi_note, string, finger, placement, grade, cents, t_start, t_end FROM graded_notes WHERE session_id = ? '
      'ORDER BY idx',
      variables: [Variable.withString(sessionId)],
    ).get();
    return [
      for (final r in rows)
        StoredNote(
          idx: r.read<int>('idx'),
          midiNote: r.read<int>('midi_note'),
          string: r.read<String>('string'),
          finger: r.read<int>('finger'),
          placement: r.readNullable<String>('placement'),
          grade: Grade.values.byName(r.read<String>('grade')),
          cents: r.readNullable<double>('cents'),
          tStart: r.readNullable<double>('t_start'),
          tEnd: r.readNullable<double>('t_end'),
        )
    ];
  }

  /// Every session, newest first.
  Future<List<SessionSummary>> sessions() async {
    final rows = await db.customSelect(
      'SELECT id, started_at, ended_at, instrument, scale_id, score_percent, green, yellow, red, missed, note_count FROM sessions '
      'ORDER BY started_at DESC, id DESC',
    ).get();
    DateTime t(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return [
      for (final r in rows)
        SessionSummary(
          id: r.read<String>('id'),
          startedAt: t(r.read<int>('started_at')),
          endedAt: t(r.read<int>('ended_at')),
          instrument: r.read<String>('instrument'),
          scaleId: r.read<String>('scale_id'),
          scorePercent: r.read<double>('score_percent'),
          totals: Totals(r.read<int>('green'), r.read<int>('yellow'), r.read<int>('red'), r.read<int>('missed'),
              r.read<int>('note_count')),
        )
    ];
  }

  /// The `note_stats` rows of one session (the cache).
  Future<List<NoteStat>> noteStats(String sessionId) => _stats('WHERE session_id = ?', [Variable.withString(sessionId)]);

  Future<List<NoteStat>> _stats(String where, List<Variable> vars) async {
    final rows = await db.customSelect(
      'SELECT midi_note, string, finger, placement, count, green, yellow, red, missed, mean_cents, mean_abs_cents, std_cents, '
      'total_ms FROM note_stats $where ORDER BY rowid',
      variables: vars,
    ).get();
    return [
      for (final r in rows)
        NoteStat(
          midiNote: r.read<int>('midi_note'),
          string: r.read<String>('string'),
          finger: r.read<int>('finger'),
          placement: r.read<String>('placement'),
          count: r.read<int>('count'),
          green: r.read<int>('green'),
          yellow: r.read<int>('yellow'),
          red: r.read<int>('red'),
          missed: r.read<int>('missed'),
          meanCents: r.readNullable<double>('mean_cents'),
          meanAbsCents: r.readNullable<double>('mean_abs_cents'),
          stdCents: r.readNullable<double>('std_cents'),
          totalMs: r.read<double>('total_ms'),
        )
    ];
  }

  /// Per (string, finger, placement) across every session, for the finger-level heatmap; [instrument] filters (v1: violin only).
  Future<List<FingerStat>> fingerStats({String instrument = 'violin'}) async => combineFingerStats(await _stats(
        'WHERE session_id IN (SELECT id FROM sessions WHERE instrument = ?)',
        [Variable.withString(instrument)],
      ));

  /// Rebuilds every cache from the stored graded notes (ADR 0015 decision 4): re-grades with [cfg], re-maps string, finger and
  /// placement from [library]'s current scale data, and rewrites the session totals and `note_stats`. One transaction.
  Future<void> rebuildCaches(GradingConfig cfg, ScaleLibrary library) async {
    await db.transaction(() async {
      final ss = await db.customSelect('SELECT id, scale_id FROM sessions').get();
      for (final s in ss) {
        final id = s.read<String>('id');
        final notes = regrade(await gradedNotes(id), cfg, library.byId(s.read<String>('scale_id')));
        await db.customStatement('DELETE FROM graded_notes WHERE session_id = ?', [id]);
        for (final n in notes) {
          await _insertNote(id, n);
        }
        final t = totalsOf(notes);
        await db.customStatement(
          'UPDATE sessions SET score_percent = ?, green = ?, yellow = ?, red = ?, missed = ?, note_count = ? WHERE id = ?',
          [t.scorePercent, t.green, t.yellow, t.red, t.missed, t.noteCount, id],
        );
        await _writeStats(id, notes);
      }
    });
  }

  /// "Clear history" (ADR 0015 decision 9): every session, graded note and statistic, in one transaction, then VACUUM so the deleted
  /// pages leave the file. Settings are kept. The confirmation dialog is the caller's.
  Future<void> clearHistory() async {
    await db.transaction(() async {
      await db.customStatement('DELETE FROM note_stats');
      await db.customStatement('DELETE FROM graded_notes');
      await db.customStatement('DELETE FROM sessions');
    });
    await db.customStatement('VACUUM');
  }

  Future<String?> setting(String key) async {
    final r = await db.customSelect('SELECT value FROM settings WHERE key = ?', variables: [Variable.withString(key)]).getSingleOrNull();
    return r?.read<String>('value');
  }

  Future<void> setSetting(String key, String value) => db.customStatement(
        'INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at',
        [key, value, _clock().toUtc().millisecondsSinceEpoch],
      );

  Future<void> close() => db.close();
}
