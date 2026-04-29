import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'riderlink_secure.db');

    // Derive a per-install encryption key stored in SharedPreferences.
    // This is not as strong as Android Keystore but is far better than a
    // hardcoded string committed to source control. The key is generated once
    // on first launch and persisted — the database can only be opened on the
    // same device installation.
    final prefs = await SharedPreferences.getInstance();
    String? dbKey = prefs.getString('_db_enc_key');
    if (dbKey == null) {
      // Generate a random 32-character alphanumeric key on first launch
      const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final rng = Random.secure();
      dbKey = List.generate(32, (_) => chars[rng.nextInt(chars.length)]).join();
      await prefs.setString('_db_enc_key', dbKey);
    }

    return await openDatabase(
      path,
      password: dbKey,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE riders(
            id INTEGER PRIMARY KEY,
            name TEXT,
            last_seen INTEGER,
            latitude REAL,
            longitude REAL
          )
        ''');
        
        await db.execute('''
          CREATE TABLE messages(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender_id INTEGER,
            content TEXT,
            timestamp INTEGER,
            is_sent_by_me INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE trips(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_time INTEGER,
            end_time INTEGER,
            distance_km REAL,
            max_lean_angle REAL,
            top_speed REAL
          )
        ''');
        
        await db.execute('''
          CREATE TABLE route_points(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            trip_id INTEGER,
            latitude REAL,
            longitude REAL,
            timestamp INTEGER,
            FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
          )
        ''');
      },
    );
  }

  Future<void> insertRider(int id, double lat, double lng) async {
    final db = await database;
    await db.insert(
      'riders',
      {
        'id': id,
        'latitude': lat, 
        'longitude': lng,
        'last_seen': DateTime.now().millisecondsSinceEpoch
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  Future<void> insertMessage(int senderId, String content, bool isSentByMe) async {
      final db = await database;
      await db.insert('messages', {
          'sender_id': senderId,
          'content': content,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_sent_by_me': isSentByMe ? 1 : 0
      });
  }

  Future<int> insertTrip(int startTime) async {
    final db = await database;
    return await db.insert('trips', {
      'start_time': startTime,
      'end_time': 0,
      'distance_km': 0.0,
      'max_lean_angle': 0.0,
      'top_speed': 0.0
    });
  }

  Future<void> updateTripEnd(int tripId, int endTime, double maxLean) async {
    final db = await database;
    await db.update('trips', {
      'end_time': endTime,
      'max_lean_angle': maxLean
    }, where: 'id = ?', whereArgs: [tripId]);
  }

  Future<void> insertRoutePoint(int tripId, double lat, double lng) async {
    final db = await database;
    await db.insert('route_points', {
      'trip_id': tripId,
      'latitude': lat,
      'longitude': lng,
      'timestamp': DateTime.now().millisecondsSinceEpoch
    });
  }
}

