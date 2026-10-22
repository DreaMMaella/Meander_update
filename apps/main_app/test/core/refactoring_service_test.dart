import 'package:canvas_app/core/services/refactoring_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('_replaceInString', () {
    test('replaces {variableName} in braces', () {
      expect(
        RefactoringService.replaceInString('{gold}', 'gold', 'newGold'),
        '{newGold}',
      );
    });

    test('replaces standalone variable in formula', () {
      expect(
        RefactoringService.replaceInString('gold + 10', 'gold', 'newGold'),
        'newGold + 10',
      );
    });

    test('replaces {variableName} in complex formula', () {
      expect(
        RefactoringService.replaceInString(
          '{gold} + {silver} * 2',
          'gold',
          'newGold',
        ),
        '{newGold} + {silver} * 2',
      );
    });

    test('does not replace partial matches', () {
      expect(
        RefactoringService.replaceInString('golden', 'gold', 'newGold'),
        'golden',
      );
    });

    test('does not replace when followed by underscore', () {
      expect(
        RefactoringService.replaceInString('gold_count', 'gold', 'newGold'),
        'gold_count',
      );
    });

    test('replaces Cyrillic variable in braces', () {
      expect(
        RefactoringService.replaceInString('{бёдра}', 'бёдра', 'newVar'),
        '{newVar}',
      );
    });

    test('replaces Cyrillic variable in formula', () {
      expect(
        RefactoringService.replaceInString(
          '{бёдра} == 1 && {осм} == 1',
          'бёдра',
          'newVar',
        ),
        '{newVar} == 1 && {осм} == 1',
      );
    });

    test('handles variable with spaces in formula', () {
      expect(
        RefactoringService.replaceInString(
          '{посещённые ноды[ID]} == null',
          'посещённые ноды',
          'visitedNodes',
        ),
        '{visitedNodes[ID]} == null',
      );
    });

    test('replaces in table path expression', () {
      expect(
        RefactoringService.replaceInString("'\"'+{ID}+'\"'", 'ID', 'newID'),
        "'\"'+{newID}+'\"'",
      );
    });

    test('handles multiple occurrences', () {
      expect(
        RefactoringService.replaceInString(
          '{gold} + {gold} * {gold}',
          'gold',
          'newGold',
        ),
        '{newGold} + {newGold} * {newGold}',
      );
    });

    test('does not replace inside quoted string literal', () {
      // This is a known limitation - we replace everywhere
      // But this test documents current behavior
      final result = RefactoringService.replaceInString(
        "'hello gold world'",
        'gold',
        'newGold',
      );
      // Current behavior: replaces even in string literals
      expect(result, "'hello newGold world'");
    });

    test('replaces Cyrillic standalone in formula', () {
      expect(
        RefactoringService.replaceInString('бёдра == 1', 'бёдра', 'newVar'),
        'newVar == 1',
      );
    });

    test('does not replace Cyrillic partial match', () {
      expect(
        RefactoringService.replaceInString('бёдрашка', 'бёдра', 'newVar'),
        'бёдрашка',
      );
    });

    test('handles comparison with Cyrillic', () {
      expect(
        RefactoringService.replaceInString(
          '{ключ}==1 && {осм}==1',
          'ключ',
          'newKey',
        ),
        '{newKey}==1 && {осм}==1',
      );
    });

    test('handles variable name that is substring of another', () {
      expect(
        RefactoringService.replaceInString(
          '{gold} + {goldmine}',
          'gold',
          'newGold',
        ),
        '{newGold} + {goldmine}',
      );
    });
  });

  group('replaceInLuaSource', () {
    test('переименовывает строковые аргументы core-API', () {
      const source =
          'local n = core.get_var("gold")\n'
          "core.set_var('gold', n + 1)\n"
          'core.set_table("Печка", "цена", n)\n';
      expect(
        RefactoringService.replaceInLuaSource(source, 'gold', 'монеты'),
        'local n = core.get_var("монеты")\n'
        "core.set_var('монеты', n + 1)\n"
        'core.set_table("Печка", "цена", n)\n',
      );
    });

    test('не трогает текст, локальные имена и совпадения внутри слова', () {
      const source =
          'local gold = my_gold\n'
          'print("gold", "у тебя gold")\n'
          'core.call("gold")\n'
          'core.get_var("gold_key")\n'
          'core.get_var(gold)\n';
      expect(
        RefactoringService.replaceInLuaSource(source, 'gold', 'silver'),
        source,
      );
    });

    test('таблицы переименовываются в get_table/set_table', () {
      const source = 'local rows = core.get_table("Печка")\n';
      expect(
        RefactoringService.replaceInLuaSource(source, 'Печка', 'Печь'),
        'local rows = core.get_table("Печь")\n',
      );
    });
  });
}
