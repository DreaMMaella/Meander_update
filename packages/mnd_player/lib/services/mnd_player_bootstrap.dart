import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/services/expression_evaluator.dart';
import 'package:mnd_player/utils/file_storage.dart';

class MndPlayerBootstrap {
  static void initialize({bool debugLogs = false}) {
    ScriptExecutor.configure(
      expressionEngine: _AppExpressionEngine(),
      assetStore: _AppAssetStore(),
      debugLogsEnabled: debugLogs,
    );
  }
}

class _AppExpressionEngine implements ScriptExpressionEngine {
  final _evaluator = ExpressionEvaluatorService();

  @override
  dynamic evaluate(String expression, Map<String, dynamic> context) {
    return _evaluator.evaluate(expression, context);
  }
}

class _AppAssetStore implements ScriptAssetStore {
  @override
  Future<bool> exists(String path) => FileStorage.exists(path);

  @override
  Future<Map<String, dynamic>> readJson(String path) =>
      FileStorage.readJsonFile(path);
}
