// Пикер нод нельзя открыть в тупик.
//
// `NodeSelectionScreen` — это и список нод, и выбор одной из них. Экран
// открывают из восьми мест, и у каждого места есть ровно два честных
// варианта: есть нода, от которой отталкиваемся (`currentNodeId`), или
// человек вправе создать ноду прямо здесь (`allowCreate: true`). Третьего не
// дано: без обоих аргументов новичок в свежем квесте попадает в пустой
// список, откуда один выход — догадаться вернуться в редактор.
//
// Исторически два места в редакторе модалок обходили это `currentNodeId: ''`
// — пустая строка вместо идентификатора разблокировала кнопку создания, но
// враньём ломала и текст пустого состояния («нет других нод» там, где нод
// нет вовсе). Теперь для этого есть `allowCreate`.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ (проверено): вернуть `currentNodeId: ''` в
// modal_editor_screen — падает тест про пустую строку; снять `allowCreate`
// с блока «Перейти к ноде» — падает тест про два честных варианта.
//
// Не покрыто: что аргументы доходят до виджета — за это отвечают виджет-тесты
// в start_node_picker_creation_test.dart; здесь проверяются только места
// вызова, потому что новый вызов в тупик попадает именно здесь.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final callSites = _collectCallSites();

  test('скан нашёл все места вызова пикера нод', () {
    // Тест не должен молча превратиться в «проверено ноль мест», если
    // поменяется имя экрана или способ вызова.
    expect(
      callSites,
      hasLength(greaterThanOrEqualTo(8)),
      reason:
          'скан по lib/ нашёл слишком мало вызовов NodeSelectionScreen: '
          '${callSites.map((s) => s.where).toList()}',
    );
  });

  test('пикер нод не обманывают пустой строкой вместо текущей ноды', () {
    for (final site in callSites) {
      expect(
        site.args,
        isNot(contains("currentNodeId: ''")),
        reason:
            '${site.where}: пустая строка в currentNodeId — это костыль, '
            'чтобы разблокировать создание; для этого есть allowCreate',
      );
    }
  });

  test('каждый пикер нод либо знает текущую ноду, либо умеет создавать', () {
    for (final site in callSites) {
      final knowsCurrentNode = site.args.contains('currentNodeId:');
      final canCreate = site.args.contains('allowCreate: true');
      expect(
        knowsCurrentNode || canCreate,
        isTrue,
        reason:
            '${site.where}: пикер открыт без currentNodeId и без '
            'allowCreate — в свежем квесте это тупик без кнопки',
      );
    }
  });
}

class _CallSite {
  _CallSite({required this.where, required this.args});

  final String where;
  final String args;
}

List<_CallSite> _collectCallSites() {
  final sites = <_CallSite>[];
  final pattern = RegExp(r'NodeSelectionScreen\(');
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = entity.readAsStringSync();
    for (final match in pattern.allMatches(source)) {
      final args = _balancedArguments(
        source,
        source.substring(match.start).indexOf('(') + match.start,
      );
      // Объявление самого экрана: `this.currentNodeId` вместо значения.
      if (args.contains('this.')) continue;
      final line = source.substring(0, match.start).split('\n').length;
      sites.add(_CallSite(where: '${entity.path}:$line', args: args));
    }
  }
  return sites;
}

/// Аргументы вызова — от открывающей скобки до парной закрывающей.
String _balancedArguments(String source, int openParen) {
  var depth = 0;
  for (var i = openParen; i < source.length; i++) {
    if (source[i] == '(') {
      depth++;
    } else if (source[i] == ')') {
      depth--;
      if (depth == 0) return source.substring(openParen, i + 1);
    }
  }
  return source.substring(openParen);
}
