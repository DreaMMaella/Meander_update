import 'package:mnd_player/services/expression_evaluator.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_core/contracts/script_engine_dependencies.dart';
import 'package:mnd_core/engine/script_executor.dart';

class MeanderCoreBootstrap {
  static void initialize({bool debugLogs = false}) {
    ScriptExecutor.configure(
      expressionEngine: _AppExpressionEngine(),
      assetStore: _AppAssetStore(),
      debugLogsEnabled: debugLogs,
    );
  }
}

class _AppExpressionEngine implements ScriptExpressionEngine {
  @override
  dynamic evaluate(String expression, Map<String, dynamic> context) {
    final evaluator = ExpressionEvaluatorService();
    return evaluator.evaluate(expression, context);
  }
}

class _AppAssetStore implements ScriptAssetStore {
  @override
  Future<bool> exists(String path) => FileStorage.exists(path);

  @override
  Future<Map<String, dynamic>> readJson(String path) =>
      FileStorage.readJsonFile(path);
}
