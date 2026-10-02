import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/game_dao.dart';
import '../storage/repository.dart' show gameDaoProvider;
import 'game_record.dart';

/// 棋谱库仓储：包装 [GameDao] 的 game_records 表操作。
class RecordRepository {
  RecordRepository(this._dao);

  final GameDao _dao;

  /// 保存棋谱（新记录插入，带 id 的更新），返回写入后的 id。
  int save(GameRecord record) {
    if (record.id == null) return _dao.insertRecord(record);
    _dao.updateRecord(record);
    return record.id!;
  }

  List<GameRecord> listAll() => _dao.allRecords();

  GameRecord? byId(int id) => _dao.recordById(id);

  void delete(int id) => _dao.deleteRecord(id);
}

/// 全局 Provider：与对局存档共用同一个数据库。
final recordRepositoryProvider = FutureProvider<RecordRepository>((ref) async {
  final dao = await ref.watch(gameDaoProvider.future);
  return RecordRepository(dao);
});
