import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// 持久化的对局记录。
class SavedGame {
  SavedGame({
    this.id,
    required this.fen,
    required this.moves,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String fen;

  /// 走法历史，每条记录为 [fromCol, fromRow, toCol, toRow]。
  final List<List<int>> moves;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fen': fen,
        'moves': moves,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory SavedGame.fromRow(Row row) => SavedGame(
        id: row['id'] as int,
        fen: row['fen'] as String,
        moves: (jsonDecode(row['move_stack_json'] as String) as List)
            .map((e) => (e as List).map((v) => v as int).toList())
            .toList(),
        createdAt:
            DateTime.tryParse(row['created_at'] as String? ?? '')?.toUtc(),
        updatedAt:
            DateTime.tryParse(row['updated_at'] as String? ?? '')?.toUtc(),
      );
}

/// SQLite 数据访问对象。
///
/// 包装 sqlite3 直接执行 SQL；避免引入代码生成（drift）以让项目开箱可运行。
/// 表结构遵循 srs.md 中 §5.2：
/// ```sql
/// CREATE TABLE saved_games (
///   id INTEGER PRIMARY KEY AUTOINCREMENT,
///   fen TEXT NOT NULL,
///   move_stack_json TEXT NOT NULL,
///   created_at TEXT DEFAULT CURRENT_TIMESTAMP,
///   updated_at TEXT DEFAULT CURRENT_TIMESTAMP
/// );
/// ```
class GameDao {
  GameDao._(this._db);

  final Database _db;

  /// 打开/创建数据库文件（按平台存放到 ApplicationDocuments）。
  static Future<GameDao> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'chinese_chess_ultra.sqlite'));
    final db = sqlite3.open(file.path);
    db.execute('''
      CREATE TABLE IF NOT EXISTS saved_games (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fen TEXT NOT NULL,
        move_stack_json TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    return GameDao._(db);
  }

  /// 用于测试：在内存库上创建。
  factory GameDao.inMemory() {
    final db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE IF NOT EXISTS saved_games (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fen TEXT NOT NULL,
        move_stack_json TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    return GameDao._(db);
  }

  /// 保存或更新一条对局。
  ///
  /// 传 [id] 时为更新，否则插入新记录。返回写入后的 id。
  int upsert({
    int? id,
    required String fen,
    required List<List<int>> moves,
  }) {
    final json = jsonEncode(moves);
    final now = DateTime.now().toUtc().toIso8601String();
    if (id == null) {
      _db.execute(
        'INSERT INTO saved_games(fen, move_stack_json, updated_at) VALUES (?, ?, ?)',
        [fen, json, now],
      );
      final rs = _db.select('SELECT last_insert_rowid() AS id');
      return rs.first['id'] as int;
    } else {
      _db.execute(
        'UPDATE saved_games SET fen = ?, move_stack_json = ?, updated_at = ? WHERE id = ?',
        [fen, json, now, id],
      );
      return id;
    }
  }

  /// 取最近一条记录（按更新时间倒序）。
  SavedGame? latest() {
    final rs = _db.select('''
      SELECT id, fen, move_stack_json, created_at, updated_at
      FROM saved_games
      ORDER BY datetime(updated_at) DESC
      LIMIT 1
    ''');
    final row = rs.firstOrNull;
    return row == null ? null : SavedGame.fromRow(row);
  }

  /// 取所有记录（按更新时间倒序）。
  List<SavedGame> all() {
    final rs = _db.select('''
      SELECT id, fen, move_stack_json, created_at, updated_at
      FROM saved_games
      ORDER BY datetime(updated_at) DESC
    ''');
    return rs.map(SavedGame.fromRow).toList();
  }

  /// 按 id 删除。
  void delete(int id) {
    _db.execute('DELETE FROM saved_games WHERE id = ?', [id]);
  }

  /// 清空全部（用于"新游戏"前清理历史快照）。
  void clear() {
    _db.execute('DELETE FROM saved_games');
  }

  void dispose() {
    _db.dispose();
  }
}
