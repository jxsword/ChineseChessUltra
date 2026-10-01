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
    this.mode,
    required this.fen,
    required this.moves,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;

  /// 归属模式（GameMode.name）；旧库迁移前的一期数据为 'legacy'。
  final String? mode;
  final String fen;

  /// 走法历史，每条记录为 [fromCol, fromRow, toCol, toRow]。
  final List<List<int>> moves;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'mode': mode,
        'fen': fen,
        'moves': moves,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory SavedGame.fromRow(Row row) => SavedGame(
        id: row['id'] as int,
        mode: row['mode'] as String?,
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
/// 表结构遵循 srs.md 中 §5.2（二期增加 mode 列以按模式分存）：
/// ```sql
/// CREATE TABLE saved_games (
///   id INTEGER PRIMARY KEY AUTOINCREMENT,
///   mode TEXT,
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
    return GameDao.fromDatabase(db);
  }

  /// 在给定数据库上建表并执行迁移（供测试注入内存库）。
  factory GameDao.fromDatabase(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS saved_games (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        mode TEXT,
        fen TEXT NOT NULL,
        move_stack_json TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    _migrateV1(db);
    return GameDao._(db);
  }

  /// 一期建表无 mode 列：补列并把老数据标记为 'legacy'，
  /// 使其不会被任何 GameMode 的查询读到（视为作废）。
  static void _migrateV1(Database db) {
    final cols = db.select('PRAGMA table_info(saved_games)');
    final hasMode = cols.any((row) => row['name'] == 'mode');
    if (!hasMode) {
      db.execute(
        "ALTER TABLE saved_games ADD COLUMN mode TEXT NOT NULL DEFAULT 'legacy'",
      );
    }
  }

  /// 用于测试：在内存库上创建。
  factory GameDao.inMemory() {
    final db = sqlite3.openInMemory();
    return GameDao.fromDatabase(db);
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
      SELECT id, mode, fen, move_stack_json, created_at, updated_at
      FROM saved_games
      ORDER BY datetime(updated_at) DESC
      LIMIT 1
    ''');
    final row = rs.firstOrNull;
    return row == null ? null : SavedGame.fromRow(row);
  }

  /// 按模式保存或更新：每个 [mode] 只保留最近一局。
  ///
  /// 已有该模式的记录时更新，否则插入。返回写入后的 id。
  int upsertForMode({
    required String mode,
    required String fen,
    required List<List<int>> moves,
  }) {
    final json = jsonEncode(moves);
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = _db.select(
      'SELECT id FROM saved_games WHERE mode = ? LIMIT 1',
      [mode],
    );
    if (existing.isEmpty) {
      _db.execute(
        'INSERT INTO saved_games(mode, fen, move_stack_json, updated_at) VALUES (?, ?, ?, ?)',
        [mode, fen, json, now],
      );
      final rs = _db.select('SELECT last_insert_rowid() AS id');
      return rs.first['id'] as int;
    }
    final id = existing.first['id'] as int;
    _db.execute(
      'UPDATE saved_games SET fen = ?, move_stack_json = ?, updated_at = ? WHERE id = ?',
      [fen, json, now, id],
    );
    return id;
  }

  /// 取指定模式的最近一局（legacy 数据不属于任何模式，查不到）。
  SavedGame? latestForMode(String mode) {
    final rs = _db.select('''
      SELECT id, mode, fen, move_stack_json, created_at, updated_at
      FROM saved_games
      WHERE mode = ?
      ORDER BY datetime(updated_at) DESC
      LIMIT 1
    ''', [mode]);
    final row = rs.firstOrNull;
    return row == null ? null : SavedGame.fromRow(row);
  }

  /// 删除指定模式的存档。
  void deleteForMode(String mode) {
    _db.execute('DELETE FROM saved_games WHERE mode = ?', [mode]);
  }

  /// 取所有记录（按更新时间倒序）。
  List<SavedGame> all() {
    final rs = _db.select('''
      SELECT id, mode, fen, move_stack_json, created_at, updated_at
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
