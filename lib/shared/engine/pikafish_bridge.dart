import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';

import '../../features/board/model/move.dart';
import '../engine_view_model.dart' show AnalysisResult;

/// Pikafish UCI 引擎桥（二期）。
///
/// 通过 `dart:io` 的 [Process] 启动 Pikafish 二进制，按 UCI 协议通信。
///
/// 主要功能：
/// - 启动和关闭引擎进程
/// - 发送 UCI 命令
/// - 解析引擎输出
/// - 局面分析和最佳走法计算
class PikafishBridge {
  static final _logger = Logger('PikafishBridge');
  
  Process? _process;
  final StreamController<String> _outputController = StreamController<String>.broadcast();
  final StreamController<String> _errorController = StreamController<String>.broadcast();
  
  bool _isReady = false;
  bool _isAnalyzing = false;
  String? _currentPosition;
  
  // 解析相关
  final List<String> _infoLines = [];
  final Map<String, int> _scores = {}; // PV 编号 -> 评分
  final Map<int, List<String>> _pvMoves = {}; // PV 编号 -> 走法列表
  int _currentDepth = 0;
  int _currentMultipv = 1;
  int _bestMoveScore = 0;
  String? _bestMove;
  
  // 计时器
  DateTime? _analysisStartTime;
  Timer? _timeoutTimer;

  /// 获取输出流。
  Stream<String> get output => _outputController.stream;

  /// 获取错误流。
  Stream<String> get errors => _errorController.stream;

  /// 是否已就绪。
  bool get isReady => _isReady;

  /// 是否正在分析。
  bool get isAnalyzing => _isAnalyzing;

  /// 启动引擎。
  Future<bool> start(String binaryPath) async {
    try {
      _logger.info('Starting Pikafish engine from: $binaryPath');
      
      _process = await Process.start(
        binaryPath,
        [],
        mode: ProcessStartMode.normal,
      );

      // 监听标准输出
      _process!.stdout.transform(utf8.decoder).listen(_handleOutput);
      
      // 监听标准错误
      _process!.stderr.transform(utf8.decoder).listen(_handleError);
      
      // 监听进程退出
      _process!.exitCode.then((code) {
        _logger.info('Pikafish process exited with code: $code');
        _isReady = false;
        _isAnalyzing = false;
        _outputController.close();
        _errorController.close();
      });

      // 发送 UCI 命令
      await sendCommand('uci');
      
      // 等待 uuciok 响应（最多 5 秒）
      await _waitForReady(const Duration(seconds: 5));
      
      // 发送 isready 命令
      await sendCommand('isready');
      
      _isReady = true;
      _logger.info('Pikafish engine started successfully');
      return true;
    } catch (e, stack) {
      _logger.severe('Failed to start Pikafish engine', e, stack);
      return false;
    }
  }

  /// 关闭引擎。
  Future<void> shutdown() async {
    if (_process != null) {
      try {
        await sendCommand('quit');
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        _logger.warning('Error sending quit command: $e');
      }
      
      _process?.kill();
      _process = null;
      _isReady = false;
      _isAnalyzing = false;
    }
  }

  /// 设置局面。
  Future<void> setPosition(String fen, {List<String>? moves}) async {
    _currentPosition = fen;
    
    if (moves != null && moves.isNotEmpty) {
      await sendCommand('position fen $fen moves ${moves.join(" ")}');
    } else {
      await sendCommand('position fen $fen');
    }
  }

  /// 分析局面。
  Future<AnalysisResult> analyze(String fen, {
    int depth = 18,
    int multipv = 1,
    Duration? timeLimit,
  }) async {
    if (!_isReady) {
      throw StateError('Engine not ready');
    }

    _isAnalyzing = true;
    _currentDepth = depth;
    _currentMultipv = multipv;
    _analysisStartTime = DateTime.now();
    _infoLines.clear();
    _scores.clear();
    _pvMoves.clear();

    // 设置分析超时
    _timeoutTimer?.cancel();
    if (timeLimit != null) {
      _timeoutTimer = Timer(timeLimit, () {
        _isAnalyzing = false;
      });
    }

    try {
      await setPosition(fen);
      await sendCommand('go depth $depth multipv $multipv');
      
      // 等待分析完成
      await _waitForAnalysisComplete();
      
      return _buildAnalysisResult();
    } finally {
      _isAnalyzing = false;
      _timeoutTimer?.cancel();
    }
  }

  /// 获取最佳走法。
  Future<String> bestMove(String fen, {int depth = 15, Duration? timeLimit}) async {
    if (!_isReady) {
      throw StateError('Engine not ready');
    }

    _isAnalyzing = true;
    _bestMove = null;
    _bestMoveScore = 0;
    _infoLines.clear();
    _analysisStartTime = DateTime.now();

    _timeoutTimer?.cancel();
    if (timeLimit != null) {
      _timeoutTimer = Timer(timeLimit, () {
        _isAnalyzing = false;
      });
    }

    try {
      await setPosition(fen);
      await sendCommand('go depth $depth');
      
      // 等待 bestmove
      await _waitForBestMove();
      
      if (_bestMove == null) {
        throw StateError('No best move returned');
      }
      
      return _bestMove!;
    } finally {
      _isAnalyzing = false;
      _timeoutTimer?.cancel();
    }
  }

  /// 停止当前计算。
  Future<void> stop() async {
    if (_isAnalyzing) {
      await sendCommand('stop');
      _isAnalyzing = false;
    }
  }

  /// 发送命令。
  Future<void> sendCommand(String command) async {
    if (_process == null) {
      throw StateError('Engine not started');
    }
    
    _logger.fine('Sending command: $command');
    _process!.stdin.writeln(command);
  }

  /// 设置引擎选项。
  Future<void> setOption(String name, String value) async {
    await sendCommand('setoption name $name value $value');
  }

  /// 处理输出。
  void _handleOutput(String line) {
    _logger.fine('Engine output: $line');
    _outputController.add(line);
    
    _parseOutput(line);
  }

  /// 处理错误。
  void _handleError(String line) {
    _logger.warning('Engine error: $line');
    _errorController.add(line);
  }

  /// 解析输出。
  void _parseOutput(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      
      if (part == 'uciok') {
        _isReady = true;
        break;
      }
      
      if (part == 'readyok') {
        break;
      }
      
      if (part == 'bestmove') {
        if (i + 1 < parts.length) {
          _bestMove = parts[i + 1];
        }
        _isAnalyzing = false;
        break;
      }
      
      if (part == 'info') {
        _parseInfoLine(parts);
        break;
      }
    }
  }

  /// 解析 info 行。
  void _parseInfoLine(List<String> parts) {
    int multipv = 0;
    int score = 0;
    int depth = 0;
    List<String> pv = [];
    
    for (int i = 1; i < parts.length; i++) {
      final part = parts[i];
      
      if (part == 'multipv' && i + 1 < parts.length) {
        multipv = int.tryParse(parts[i + 1]) ?? 0;
        i++;
      } else if (part == 'depth' && i + 1 < parts.length) {
        depth = int.tryParse(parts[i + 1]) ?? 0;
        i++;
      } else if (part == 'score') {
        if (i + 2 < parts.length) {
          final scoreType = parts[i + 1];
          score = int.tryParse(parts[i + 2]) ?? 0;
          
          // UCI 评分转换：mate 表示将杀，cp 表示 centipawn
          if (scoreType == 'mate') {
            // 将杀步数
            score = score > 0 ? 30000 - score : -30000 - score;
          }
          i += 2;
        }
      } else if (part == 'pv') {
        // 提取 PV 走法
        pv = parts.sublist(i + 1);
        break;
      }
    }
    
    if (multipv > 0) {
      _scores[multipv.toString()] = score;
      if (depth > 0) {
        _currentDepth = depth;
      }
      _pvMoves[multipv] = pv;
    } else if (depth > 0 && score != 0) {
      // 单 PV 模式
      _scores['1'] = score;
      _currentDepth = depth;
      _pvMoves[1] = pv;
    }
    
    _infoLines.add(parts.join(' '));
  }

  /// 构建分析结果。
  AnalysisResult _buildAnalysisResult() {
    final pvList = <List<String>>[];
    final scoreList = <int>[];
    
    // 收集所有 PV 线
    for (int i = 1; i <= _currentMultipv; i++) {
      final pv = _pvMoves[i] ?? [];
      final score = _scores[i.toString()] ?? 0;
      
      pvList.add(pv);
      scoreList.add(score);
    }
    
    final elapsedMs = _analysisStartTime != null 
        ? DateTime.now().difference(_analysisStartTime!).inMilliseconds 
        : 0;
    
    return AnalysisResult(
      pvMoves: pvList,
      scores: scoreList,
      depth: _currentDepth,
      elapsedMs: elapsedMs,
    );
  }

  /// 等待引擎就绪。
  Future<void> _waitForReady(Duration timeout) async {
    final completer = Completer<void>();
    
    StreamSubscription? subscription;
    Timer? timeoutTimer;
    
    subscription = output.listen((line) {
      if (line.contains('uciok')) {
        timeoutTimer?.cancel();
        subscription?.cancel();
        completer.complete();
      }
    });
    
    timeoutTimer = Timer(timeout, () {
      subscription?.cancel();
      completer.completeError(TimeoutException('Engine ready timeout'));
    });
    
    return completer.future;
  }

  /// 等待分析完成。
  Future<void> _waitForAnalysisComplete() async {
    final completer = Completer<void>();
    
    StreamSubscription? subscription;
    Timer? timeoutTimer;
    
    subscription = output.listen((line) {
      if (line.contains('bestmove')) {
        timeoutTimer?.cancel();
        subscription?.cancel();
        completer.complete();
      }
    });
    
    // 设置超时（根据深度动态计算）
    final timeout = Duration(milliseconds: _currentDepth * 1000);
    timeoutTimer = Timer(timeout, () {
      subscription?.cancel();
      _logger.warning('Analysis timeout after $timeout');
      completer.complete(); // 超时也视为完成，返回当前结果
    });
    
    return completer.future;
  }

  /// 等待最佳走法。
  Future<void> _waitForBestMove() async {
    final completer = Completer<void>();
    
    StreamSubscription? subscription;
    Timer? timeoutTimer;
    
    subscription = output.listen((line) {
      if (line.contains('bestmove')) {
        timeoutTimer?.cancel();
        subscription?.cancel();
        completer.complete();
      }
    });
    
    // 设置超时
    final timeout = Duration(milliseconds: _currentDepth * 1000);
    timeoutTimer = Timer(timeout, () {
      subscription?.cancel();
      _logger.warning('Best move timeout after $timeout');
      completer.completeError(TimeoutException('Best move timeout'));
    });
    
    return completer.future;
  }
}