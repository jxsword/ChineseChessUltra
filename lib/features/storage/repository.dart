import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/model/fen.dart';
import '../board/model/move.dart';
import 'game_dao.dart';
import 'game_mode.dart';

/// 仓储层：包装 [GameDao]，提供对局保存/恢复的业务语义。
///
/// 屏蔽 SQL 细节，向上层只暴露 [SavedGame] 域对象与走法历史。
class GameRepository {
  GameRepository(this._dao);

  final GameDao _dao;

  /// 保存当前局面（含完整走法历史）到 [mode] 的存档桶。
  ///
  /// 每个模式只保留最近一局：已有该模式存档时覆盖更新。
  /// 返回写入后的对局 id。
  int saveGame({
    required GameMode mode,
    required String fen,
    required List<Move> moves,
  }) {
    final serialized = moves
        .map((m) => <int>[m.from.col, m.from.row, m.to.col, m.to.row])
        .toList();
    return _dao.upsertForMode(mode: mode.name, fen: fen, moves: serialized);
  }

  /// 读取 [mode] 模式的最近一局（用于进入模式时自动恢复）。
  SavedGame? loadLatest(GameMode mode) => _dao.latestForMode(mode.name);

  /// 删除 [mode] 模式的存档。
  void deleteForMode(GameMode mode) => _dao.deleteForMode(mode.name);

  /// 列出全部历史。
  List<SavedGame> listAll() => _dao.all();

  /// 删除指定 id。
  void delete(int id) => _dao.delete(id);

  /// 清空历史。
  void clear() => _dao.clear();

  void dispose() => _dao.dispose();
}

/// 是否为合法 FEN 的封装（仓储对外校验入口）。
bool isValidFen(String fen) => Fen.isValid(fen);

/// 全局 Provider：异步打开数据库。
final gameDaoProvider = FutureProvider<GameDao>((ref) async {
  final dao = await GameDao.open();
  ref.onDispose(dao.dispose);
  return dao;
});

/// 全局 Provider：基于 [gameDaoProvider] 提供 [GameRepository]。
final gameRepositoryProvider = FutureProvider<GameRepository>((ref) async {
  final dao = await ref.watch(gameDaoProvider.future);
  final repo = GameRepository(dao);
  ref.onDispose(repo.dispose);
  return repo;
});
