/// 全局常量。
class AppConstants {
  const AppConstants._();

  /// 应用名称。
  static const String appName = '中国象棋 Ultra';

  /// 棋盘列数。
  static const int boardCols = 9;

  /// 棋盘行数。
  static const int boardRows = 10;

  /// 棋子直径与单元格边长的比例。
  static const double pieceRatio = 0.86;

  /// 默认窗口尺寸（Windows）。
  static const double defaultWindowWidth = 1100;
  static const double defaultWindowHeight = 760;

  /// 数据库文件名。
  static const String dbFileName = 'chinese_chess_ultra.sqlite';
}

/// 颜色与画笔常量（避免硬编码）。
class AppColors {
  const AppColors._();

  static const int boardBackground = 0xFFF3D9A6; // 棋盘木色
  static const int boardLine = 0xFF8A6A3F; // 棋盘线条（深棕色）
  static const int riverText = 0xFF8A6A3F;
  static const int pieceRed = 0xFFB71C1C;
  static const int pieceBlack = 0xFF212121;
  static const int pieceFaceRed = 0xFFFBEFD0;
  static const int pieceFaceBlack = 0xFFFBEFD0;
  static const int selected = 0x6A1565C0;
  static const int legalHint = 0x6A2E7D32;
  static const int lastMove = 0x55F9A825;
}
