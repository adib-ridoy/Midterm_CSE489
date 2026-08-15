import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/landmark.dart';

class DBHelper {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'landmarks.db');
    _db = await openDatabase(path, version: 1, onCreate: _onCreate);
    return _db!;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE landmarks(
        id INTEGER PRIMARY KEY,
        title TEXT,
        lat REAL,
        lon REAL,
        image TEXT,
        score REAL,
        visit_count INTEGER,
        avg_distance REAL,
        deleted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE visits(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        landmark_id INTEGER,
        visit_time TEXT,
        distance REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE queued_visits(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        landmark_id INTEGER,
        user_lat REAL,
        user_lon REAL,
        job_id INTEGER,
        status TEXT DEFAULT 'queued'
      )
    ''');
  }

  static Future<void> upsertLandmarks(List<Landmark> items) async {
    final db = await database;
    final deletedRows = await db.query(
      'landmarks',
      columns: ['id'],
      where: 'deleted = 1',
    );
    final deletedIds = deletedRows.map((r) => r['id']).whereType<int>().toSet();

    final batch = db.batch();
    for (final l in items) {
      batch.insert('landmarks', {
        'id': l.id,
        'title': l.title,
        'lat': l.lat,
        'lon': l.lon,
        'image': l.image,
        'score': l.score,
        'visit_count': l.visitCount,
        'avg_distance': l.avgDistance,
        // Keep locally soft-deleted rows hidden across server refreshes.
        'deleted': deletedIds.contains(l.id) ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<Set<int>> getDeletedLandmarkIds() async {
    final db = await database;
    final rows = await db.query(
      'landmarks',
      columns: ['id'],
      where: 'deleted = 1',
    );
    return rows.map((r) => r['id']).whereType<int>().toSet();
  }

  static Future<List<Landmark>> getCachedLandmarks() async {
    final db = await database;
    final rows = await db.query('landmarks', where: 'deleted = 0');
    return rows.map((r) => Landmark.fromJson(r)).toList();
  }

  static Future<List<Landmark>> getDeletedLandmarks() async {
    final db = await database;
    final rows = await db.query(
      'landmarks',
      where: 'deleted = 1',
      orderBy: 'id DESC',
    );
    return rows.map((r) => Landmark.fromJson(r)).toList();
  }

  static Future<void> softDeleteLandmark(int id) async {
    final db = await database;
    await db.update(
      'landmarks',
      {'deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> restoreLandmark(int id) async {
    final db = await database;
    await db.update(
      'landmarks',
      {'deleted': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> insertVisit(
    int landmarkId,
    String visitTime,
    double distance,
  ) async {
    final db = await database;
    await db.insert('visits', {
      'landmark_id': landmarkId,
      'visit_time': visitTime,
      'distance': distance,
    });
  }

  static Future<List<Landmark>> getQueuedCreates() async {
    final db = await database;
    final rows = await db.query('landmarks', where: 'id < 0');
    return rows.map((r) => Landmark.fromJson(r)).toList();
  }

  static Future<void> replaceTempLandmark(int tempId, Landmark newL) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('landmarks', where: 'id = ?', whereArgs: [tempId]);
      await txn.insert('landmarks', {
        'id': newL.id,
        'title': newL.title,
        'lat': newL.lat,
        'lon': newL.lon,
        'image': newL.image,
        'score': newL.score,
        'visit_count': newL.visitCount,
        'avg_distance': newL.avgDistance,
        'deleted': 0,
      });
    });
  }

  static Future<int> enqueueVisit(
    int landmarkId,
    double userLat,
    double userLon,
  ) async {
    final db = await database;
    final id = await db.insert('queued_visits', {
      'landmark_id': landmarkId,
      'user_lat': userLat,
      'user_lon': userLon,
      'status': 'queued',
    });
    return id;
  }

  static Future<List<Map<String, dynamic>>> getQueuedVisits() async {
    final db = await database;
    return await db.query('queued_visits', where: "status != 'done'");
  }

  static Future<void> updateQueuedVisitJob(int id, int jobId) async {
    final db = await database;
    await db.update(
      'queued_visits',
      {'job_id': jobId, 'status': 'pending'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> markQueuedVisitDone(int id) async {
    final db = await database;
    await db.update(
      'queued_visits',
      {'status': 'done'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<List<Map<String, dynamic>>> getVisitHistory() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT v.id, v.landmark_id, l.title as landmark_title, v.visit_time, v.distance
      FROM visits v
      LEFT JOIN landmarks l ON v.landmark_id = l.id
      ORDER BY v.visit_time DESC
    ''');
    return rows;
  }

  static Future<Landmark?> getLandmarkById(int id) async {
    final db = await database;
    final rows = await db.query(
      'landmarks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Landmark.fromJson(rows.first);
  }

  static Future<String?> getLatestVisitTime() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT visit_time FROM visits ORDER BY visit_time DESC LIMIT 1',
    );
    if (rows.isEmpty) return null;
    return rows.first['visit_time'] as String?;
  }
}
