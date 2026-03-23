import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'riderlink_secure.db');
    return await openDatabase(
      path,
      password: "secure_password_replace_in_prod", // In prod, use secure storage to manage key
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE UserMedicalProfile(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        blood_group TEXT,
        emergency_contact TEXT,
        allergies TEXT
      )
    ''');
  }

  Future<int> insertProfile(Map<String, dynamic> row) async {
    Database db = await database;
    return await db.insert('UserMedicalProfile', row);
  }

  Future<Map<String, dynamic>?> getProfile() async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query('UserMedicalProfile');
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }
}
