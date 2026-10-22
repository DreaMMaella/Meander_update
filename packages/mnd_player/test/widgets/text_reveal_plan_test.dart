import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_player/widgets/shared/text_reveal_plan.dart';

/// Снимает служебный markdown, чтобы проверить: сколько «видимого» текста
/// реально осталось в префиксе. Если разрезать исходник по сырым символам,
/// здесь останутся обрывки тегов — ровно тот дефект, который ловит план.
String _visibleOnly(String prefix) => prefix
    .replaceAll(
      RegExp(
        r'\[color=#[0-9A-Fa-f]{6,8}\]|\[/color\]|\[font=[^\]]+\]|\[/font\]',
      ),
      '',
    )
    .replaceAll(RegExp(r'\*\*|__|~~|`|\*|_'), '');

void main() {
  group('TextRevealPlan', () {
    test('обычный текст печатается посимвольно', () {
      final plan = TextRevealPlan.of('Привет');
      expect(plan.totalVisible, 6);
      expect(plan.prefixFor(3), 'При');
      // Последний кадр — ровно то, что автор написал.
      expect(plan.prefixFor(plan.totalVisible), 'Привет');
      expect(plan.prefixFor(0), '');
    });

    test('эмодзи из нескольких кодовых точек не рвётся', () {
      const family = '👨‍👩‍👧';
      final plan = TextRevealPlan.of('a${family}b');
      expect(plan.totalVisible, 3);
      expect(plan.prefixFor(1), 'a');
      expect(plan.prefixFor(2), 'a$family');
      expect(plan.prefixFor(3), 'a${family}b');
    });

    test('жирный никогда не показывает звёздочки', () {
      const source = '**жирный**';
      const plain = 'жирный';
      final plan = TextRevealPlan.of(source);
      expect(plan.totalVisible, plain.length);
      for (var v = 0; v <= plan.totalVisible; v++) {
        final prefix = plan.prefixFor(v);
        expect(_visibleOnly(prefix), plain.substring(0, v), reason: prefix);
        // Открытая конструкция закрыта: чётное число маркеров.
        expect(prefix.split('**').length % 2, 1, reason: prefix);
      }
      expect(plan.prefixFor(3), '**жир**');
      expect(plan.prefixFor(plan.totalVisible), source);

      // Негативный контроль: наивный разрез по символам показал бы синтаксис.
      expect(source.substring(0, 3), '**ж');
    });

    test('тег цвета всегда парный', () {
      const source = '[color=#FF0000]красный[/color]';
      const plain = 'красный';
      final plan = TextRevealPlan.of(source);
      expect(plan.totalVisible, plain.length);
      for (var v = 0; v <= plan.totalVisible; v++) {
        final prefix = plan.prefixFor(v);
        expect(
          '[color='.allMatches(prefix).length,
          '[/color]'.allMatches(prefix).length,
          reason: prefix,
        );
        expect(_visibleOnly(prefix), plain.substring(0, v), reason: prefix);
      }
      expect(plan.prefixFor(2), '[color=#FF0000]кр[/color]');
      expect(plan.prefixFor(plan.totalVisible), source);

      // Негативный контроль: оборванный тег — это и есть старый дефект.
      expect(source.substring(0, 12), '[color=#FF00');
    });

    test('адрес ссылки не виден, label печатается', () {
      const source = '[текст](node://n1)';
      final plan = TextRevealPlan.of(source);
      expect(plan.totalVisible, 5);
      expect(plan.prefixFor(0), '');
      expect(plan.prefixFor(2), '[те](node://n1)');
      expect(plan.prefixFor(plan.totalVisible), source);
      for (var v = 1; v < plan.totalVisible; v++) {
        expect(
          plan.prefixFor(v),
          contains('(node://n1)'),
          reason: 'префикс должен оставаться валидной ссылкой',
        );
      }
    });

    test('акцент в середине строки ведёт себя как в начале', () {
      // Якорь `^` в шаблонах работал лишь на первой строке: matchAsPrefix
      // вызывает их на любой позиции. Этот случай ловит возврат к `^`.
      const source = 'обычный **жир** текст';
      const plain = 'обычный жир текст';
      final plan = TextRevealPlan.of(source);
      expect(plan.totalVisible, plain.length);
      for (var v = 0; v <= plan.totalVisible; v++) {
        final prefix = plan.prefixFor(v);
        expect(_visibleOnly(prefix), plain.substring(0, v), reason: prefix);
        expect(prefix.split('**').length % 2, 1, reason: prefix);
      }
      expect(plan.prefixFor(9), 'обычный **ж**');
    });

    test('маркеры строк не печатаются отдельно от содержимого', () {
      const source = '- раз\n- два';
      final plan = TextRevealPlan.of(source);
      expect(plan.totalVisible, 6);
      for (var v = 1; v <= plan.totalVisible; v++) {
        expect(
          plan.prefixFor(v),
          startsWith('- '),
          reason: 'голый дефис выглядел бы как текст',
        );
      }
      expect(plan.prefixFor(3), '- раз');
      expect(plan.prefixFor(4), '- раз\n- д');
      expect(plan.prefixFor(plan.totalVisible), source);
    });

    test('одиночная звёздочка остаётся текстом', () {
      const source = '2*3 равно 6';
      final plan = TextRevealPlan.of(source);
      // Пары у `*` нет — значит это символ, и он считается видимым.
      expect(plan.totalVisible, source.length);
      expect(plan.prefixFor(3), '2*3');
    });

    test('блок кода закрыт, пока код не набран', () {
      const source = '```\ncode\n```';
      final plan = TextRevealPlan.of(source);
      for (var v = 0; v <= plan.totalVisible; v++) {
        final prefix = plan.prefixFor(v);
        expect(
          '```'.allMatches(prefix).length % 2,
          isNot(1),
          reason: 'Открытая без закрытия выборка кода: $prefix',
        );
      }
      expect(plan.prefixFor(1), '```\nc```');
      expect(plan.prefixFor(plan.totalVisible), source);
    });

    test('пустой текст не ломает план', () {
      final plan = TextRevealPlan.of('');
      expect(plan.totalVisible, 0);
      expect(plan.prefixFor(0), '');
      expect(plan.visibleAt(0.5), 0);
    });

    test('доля прогресса переводится в целые символы', () {
      final plan = TextRevealPlan.of('1234567890');
      expect(plan.visibleAt(0), 0);
      expect(plan.visibleAt(0.5), 5);
      expect(plan.visibleAt(1), 10);
    });
  });
}
