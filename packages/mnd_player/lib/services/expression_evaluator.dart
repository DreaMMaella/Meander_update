import 'dart:math' as math;
import 'package:expressions/expressions.dart';

class ExpressionEvaluatorService {
  static final Map<String, dynamic> _availableFunctions = {
    'abs': (num v) => v.abs(),
    'round': (num v, [num digits = 0]) {
      if (digits == 0) return v.round();
      final mul = math.pow(10, digits.toInt());
      return (v * mul).roundToDouble() / mul;
    },
    'ceil': (num v) => v.ceil(),
    'floor': (num v) => v.floor(),
    'sqrt': (num v) => math.sqrt(v),
    'pow': (num x, num exponent) => math.pow(x, exponent),
    'sin': (num v) => math.sin(v),
    'cos': (num v) => math.cos(v),
    'tan': (num v) => math.tan(v),
    'min': (num a, num b) => math.min(a, b),
    'max': (num a, num b) => math.max(a, b),
    'random': (num minVal, num maxVal) {
      if (minVal > maxVal) {
        final temp = minVal;
        minVal = maxVal;
        maxVal = temp;
      }
      if (minVal is int && maxVal is int) {
        return minVal + math.Random().nextInt(maxVal - minVal + 1);
      } else {
        return minVal + math.Random().nextDouble() * (maxVal - minVal);
      }
    },
    'contains': (String str, String pattern) => str.contains(pattern),
    'length': (String str) => str.length,
  };

  dynamic _cleanNumericResult(dynamic value) {
    if (value is! double) return value;
    if (!value.isFinite || value == 0.0) return value;

    double cleaned = value;
    try {
      double rounded = (value * 1e10).roundToDouble() / 1e10;
      if ((value - rounded).abs() < 1e-11) {
        cleaned = rounded;
      }
    } catch (_) {}

    if (cleaned == cleaned.truncateToDouble()) {
      return cleaned.toInt();
    }
    return cleaned;
  }

  dynamic evaluate(dynamic inputValue, Map<String, dynamic> variables) {
    if (inputValue is! String) return _cleanNumericResult(inputValue);
    String expressionString = inputValue.trim();

    if (expressionString.isEmpty) return null;
    final lower = expressionString.toLowerCase();
    if (lower == 'null') return null;
    if (lower == 'true') return true;
    if (lower == 'false') return false;

    if (variables.containsKey(expressionString)) {
      return _cleanNumericResult(variables[expressionString]);
    }

    String processedExpression = expressionString.replaceAllMapped(
      RegExp(r'\{([^}]+)\}'),
      (match) {
        final varName = match.group(1)?.trim();
        if (varName == null) return match.group(0)!;

        final value = variables[varName];

        if (value == null) return 'null';
        if (value is num) return value.toString();
        if (value is bool) return value.toString();

        return "'${value.toString().replaceAll("'", "\\'")}'";
      },
    );

    try {
      final expression = Expression.parse(processedExpression);
      const evaluator = ExpressionEvaluator();
      final context = <String, dynamic>{..._availableFunctions, ...variables};

      final result = evaluator.eval(expression, context);
      return _cleanNumericResult(result);
    } catch (e) {
      if (!RegExp(r'[+\-*/%()=<>]').hasMatch(processedExpression)) {
        if (!processedExpression.startsWith("'") &&
            !processedExpression.startsWith('"') &&
            !RegExp(r'^\d').hasMatch(processedExpression)) {
          return null;
        }
        if ((processedExpression.startsWith("'") &&
                processedExpression.endsWith("'")) ||
            (processedExpression.startsWith('"') &&
                processedExpression.endsWith('"'))) {
          return processedExpression.substring(
            1,
            processedExpression.length - 1,
          );
        }
      }
      return null;
    }
  }
}
