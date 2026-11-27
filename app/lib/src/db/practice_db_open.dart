import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'practice_db.dart';

/// The database file name (ADR 0015 decision 5).
const practiceDbFileName = 'intono.sqlite';

/// Where the practice database lives (ADR 0015 decision 5). iOS: Application Support, which iCloud backs up. Android: the app's
/// `databases/` directory (beside `files/`, which path_provider returns), named in the backup rules (res/xml).
Future<File> practiceDbFile() async {
  final support = await getApplicationSupportDirectory();
  final dir = Platform.isAndroid ? Directory(p.join(support.parent.path, 'databases')) : support;
  await dir.create(recursive: true);
  return File(p.join(dir.path, practiceDbFileName));
}

/// Opens the database on drift's background isolate, so the UI thread never waits on disk (ADR 0015 decision 6).
Future<PracticeDb> openPracticeDb() async => PracticeDb(NativeDatabase.createInBackground(await practiceDbFile()));
